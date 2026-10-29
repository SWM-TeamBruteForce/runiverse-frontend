import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/domain/invite_limits.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';

/// 초대 등록 화면이 보는 상태.
class InviteRegisterState {
  const InviteRegisterState({
    this.startAt,
    this.meters,
    this.submitting = false,
    this.failure,
    this.message,
  });

  /// 고른 시작 시각. **KST 벽시계 값이고 분 단위다.**
  final DateTime? startAt;

  /// 고른 거리(미터). 자유 입력이라 바로가기 셋에 없는 값일 수 있다.
  final int? meters;

  final bool submitting;
  final InviteFailure? failure;

  /// 서버가 준 문구. 있으면 그대로 보여 준다.
  final String? message;

  /// 지금 고를 수 있는 시각 범위. **`null`이면 오늘은 만들 수 없다.**
  ///
  /// ⚠️ 상태에 담지 않고 매번 계산한다 — 화면이 열려 있는 사이에 23:49를
  /// 넘길 수 있고, 그때 굳은 값을 들고 있으면 고를 수 없는 시각을 권한다.
  static ({DateTime from, DateTime to})? windowAt(DateTime nowKst) =>
      InviteLimits.window(nowKst: nowKst);

  /// 보낼 수 있는가.
  bool canSubmit({required DateTime nowKst}) {
    if (submitting) return false;
    final at = startAt;
    final distance = meters;
    if (at == null || distance == null) return false;
    if (!InviteLimits.allowsMeters(distance)) return false;

    final window = windowAt(nowKst);
    if (window == null) return false;
    return !at.isBefore(window.from) && !at.isAfter(window.to);
  }

  InviteRegisterState copyWith({
    DateTime? startAt,
    int? meters,
    bool? submitting,
    InviteFailure? failure,
    String? message,
  }) => InviteRegisterState(
    startAt: startAt ?? this.startAt,
    meters: meters ?? this.meters,
    submitting: submitting ?? this.submitting,
    // ⚠️ `??`를 쓰지 않는다. 실패를 **지울** 수 있어야 한다 — 스낵바로 알리고
    // 곧바로 비우는 자리다.
    failure: failure,
    message: message,
  );
}

final inviteRegisterProvider =
    NotifierProvider<InviteRegisterController, InviteRegisterState>(
      InviteRegisterController.new,
    );

/// 초대 방을 연다.
///
/// ## ⚠️ 앱이 `scheduledStartAt`을 **직접 만드는 유일한 자리다**
///
/// 매칭은 서버가 준 슬롯 문자열을 되돌려 보낸다(`match_slot.dart`가 "다시
/// 조립하지 않는다"고 못 박았다). 초대는 자유 입력이라 그럴 수 없다 — 그래서
/// 피커 바닥에 1분 여유를 두고([InviteLimits.pickerLeadMinutes]), 서버가
/// 거절하면 범위를 다시 안내한다.
class InviteRegisterController extends Notifier<InviteRegisterState> {
  @override
  InviteRegisterState build() => const InviteRegisterState();

  /// 시각을 고른다. **초는 버린다** — 서버가 분 단위를 받는다.
  void pickTime(DateTime at) {
    state = state.copyWith(
      startAt: DateTime(at.year, at.month, at.day, at.hour, at.minute),
    );
  }

  /// 거리를 고친다. 범위 밖 값도 상태에 들어온다 — 화면이 안내를 띄우고
  /// 버튼만 잠근다. 입력 중에 값을 되돌리면 지금 치는 숫자가 사라진다.
  void setMeters(int? meters) => state = state.copyWith(meters: meters);

  /// 방을 연다. 성공하면 방 번호를, 실패하면 `null`을 돌려준다.
  ///
  /// ⚠️ **실패해도 다시 보내지 않는다.** 네트워크가 끊긴 경우 방이 열렸는지
  /// 알 수 없어, 재시도가 곧 빈 방 두 개가 된다.
  Future<int?> submit({required DateTime nowKst}) async {
    if (!state.canSubmit(nowKst: nowKst)) return null;
    final at = state.startAt!;
    final meters = state.meters!;

    state = state.copyWith(submitting: true);
    try {
      final roomId = await ref
          .read(matchRepositoryProvider)
          .createInviteRoom(
            // 서버 표기로 적는다 — 오프셋 없는 KST, 초까지.
            scheduledStartAt: KstTime.format(at),
            meters: meters,
          );

      // 방 번호가 신청·러닝·결과 조회를 잇는 고리다. 메모리에만 두면 앱이
      // 죽는 순간 끊긴다 — 매칭 신청과 같은 판단이다.
      await ref.read(matchRoomStoreProvider).save(roomId);

      state = state.copyWith(submitting: false);
      return roomId;
    } on InviteException catch (error) {
      state = state.copyWith(
        submitting: false,
        failure: error.failure,
        message: error.message,
      );
      return null;
    }
  }

  /// 알린 실패를 지운다. 화면이 스낵바를 띄운 뒤 부른다.
  void clearFailure() => state = state.copyWith(submitting: state.submitting);
}
