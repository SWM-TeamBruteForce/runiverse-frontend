import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 신청해 둔 방 번호를 남기는 곳.
///
/// ⚠️ 위젯 테스트는 이것도 override해야 한다. `InMemoryMatchRoomStore`를 넣는다.
final matchRoomStoreProvider = Provider<MatchRoomStore>(
  (ref) => SecureMatchRoomStore(),
);

final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => HttpMatchRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// 지금의 **한국 벽시계.**
///
/// 시간대 목록을 앱이 이 값으로 만들기 때문에, 고정하지 않으면 테스트가 돌아가는
/// 시각에 따라 결과가 달라진다 — 밤 10시 이후에는 고를 수 있는 슬롯이 하나도
/// 없어진다. 테스트는 이것을 갈아끼워 시각을 못 박는다.
final matchClockProvider = Provider<DateTime Function()>(
  (ref) => KstTime.nowWall,
);

/// 매칭 등록 화면(S08)이 들고 있는 것.
class MatchRegisterState {
  const MatchRegisterState({
    this.slots = const [],
    this.selected,
    this.distance,
    this.submitting = false,
    this.failure,
    this.cooldownUntil,
  });

  final List<MatchSlot> slots;

  /// 고른 시간대. `null`이면 아직 고르지 않았다.
  final MatchSlot? selected;

  /// 고른 거리. `null`이면 아직 고르지 않았다.
  final TargetDistance? distance;

  /// 신청을 보내는 중. **CTA를 잠그는 데 쓴다** — 두 번 누르면 중복 신청이 된다.
  final bool submitting;

  final MatchFailure? failure;

  /// [MatchFailure.cooldown]일 때만 담긴다.
  final DateTime? cooldownUntil;

  /// 등록할 수 있는가. **둘 다 골라야 열린다.**
  bool get canSubmit => selected != null && distance != null && !submitting;

  MatchRegisterState copyWith({
    List<MatchSlot>? slots,
    MatchSlot? selected,
    TargetDistance? distance,
    bool? submitting,
    MatchFailure? failure,
    DateTime? cooldownUntil,
  }) => MatchRegisterState(
    slots: slots ?? this.slots,
    selected: selected ?? this.selected,
    distance: distance ?? this.distance,
    submitting: submitting ?? this.submitting,
    // ⚠️ `??`를 쓰지 않는다. 실패를 **지울** 수 있어야 한다 — 그러지 않으면
    // 한 번 실패한 뒤로 스낵바가 영영 다시 뜬다.
    failure: failure,
    cooldownUntil: cooldownUntil,
  );
}

final matchRegisterProvider =
    NotifierProvider<MatchRegisterController, MatchRegisterState>(
      MatchRegisterController.new,
    );

/// 시간대를 읽고 매칭을 신청한다.
class MatchRegisterController extends Notifier<MatchRegisterState> {
  @override
  MatchRegisterState build() => const MatchRegisterState();

  /// 시간대 목록을 갖춘다. 화면에 들어올 때 부른다.
  ///
  /// ## ⚠️ 서버에 묻지 않는다
  ///
  /// 대기 인원 조회(`GET /running-matches/slots`, 14번)는 MVP 범위 밖이고 아직
  /// 구현되어 있지 않다. 신청은 `POST /running-matches`만으로 되므로 목록은
  /// **명세가 고정한 규칙으로 앱이 만든다** — 18:00~22:00, 30분 간격.
  ///
  /// 잃는 것은 대기 인원 하나뿐이고, 그것은 `null`로 남아 화면에서 빠진다.
  ///
  /// **고른 시간대가 잠기면 선택을 푼다.** 남겨두면 마감된 슬롯으로 등록을
  /// 눌러 같은 409를 다시 맞는다.
  void loadSlots() {
    final slots = MatchSlot.todayRange(nowWall: ref.read(matchClockProvider)());

    final picked = state.selected;
    final stillOpen =
        picked != null &&
        slots.any((slot) => slot.raw == picked.raw && slot.selectable);

    state = MatchRegisterState(
      slots: slots,
      selected: stillOpen ? picked : null,
      distance: state.distance,
    );
  }

  void selectSlot(MatchSlot slot) {
    state = state.copyWith(selected: slot, failure: null);
  }

  /// 거리를 고른다.
  ///
  /// 목록을 다시 만들지 않는다 — 시간대는 거리와 무관하고, 대기 인원은 어차피
  /// 비어 있다. 대기 인원 조회가 들어오면 그때 거리별로 다시 받아야 한다:
  /// 10km를 고른 사람에게 3km 대기자 수를 보여주면 사회적 증거가 거짓이 된다.
  void selectDistance(TargetDistance distance) {
    state = state.copyWith(distance: distance, failure: null);
  }

  /// 신청한다. 성공하면 배정된 방 번호를, 실패하면 `null`을 돌려준다.
  ///
  /// ⚠️ **실패해도 다시 보내지 않는다.** 네트워크가 끊긴 경우 신청됐는지
  /// 알 수 없어, 재시도가 곧 중복 신청이 된다.
  Future<int?> submit() async {
    final slot = state.selected;
    final distance = state.distance;
    if (slot == null || distance == null || state.submitting) return null;

    state = state.copyWith(submitting: true, failure: null);
    try {
      final roomId = await ref
          .read(matchRepositoryProvider)
          .apply(slotRaw: slot.raw, distance: distance);

      // 가이드가 요구하는 것 — 신청·러닝·결과 조회가 같은 방 번호 하나로
      // 이어진다. 메모리에만 두면 앱이 죽는 순간 그 고리가 끊긴다.
      await ref.read(matchRoomStoreProvider).save(roomId);

      state = state.copyWith(submitting: false);
      return roomId;
    } on MatchException catch (error) {
      state = state.copyWith(
        submitting: false,
        failure: error.failure,
        cooldownUntil: error.cooldownUntil,
      );
      // 마감 경합이다. **그 슬롯만 잠근다** — 목록을 다시 받아도 앱이 만든
      // 것이면 같은 값이 돌아와 무한히 같은 409를 맞는다.
      if (error.failure == MatchFailure.slotClosed) {
        // ⚠️ 고른 것도 함께 푼다. 잠근 슬롯을 고른 채로 두면 CTA가 열려 있어
        // 같은 409를 다시 맞는다. `copyWith`는 선택을 비울 수 없어 직접 세운다.
        state = MatchRegisterState(
          slots: [
            for (final s in state.slots) s.raw == slot.raw ? s.closed() : s,
          ],
          distance: state.distance,
          failure: error.failure,
        );
      }
      return null;
    }
  }

  /// 스낵바를 띄운 뒤 부른다. 같은 실패로 두 번 알리지 않는다.
  void clearFailure() {
    if (state.failure == null) return;
    state = state.copyWith(failure: null);
  }
}
