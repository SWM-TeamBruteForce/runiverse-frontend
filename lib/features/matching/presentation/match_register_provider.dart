import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => HttpMatchRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// 매칭 등록 화면(S08)이 들고 있는 것.
class MatchRegisterState {
  const MatchRegisterState({
    this.slots = const [],
    this.selected,
    this.distance,
    this.loading = false,
    this.submitting = false,
    this.failure,
    this.cooldownUntil,
  });

  final List<MatchSlot> slots;

  /// 고른 시간대. `null`이면 아직 고르지 않았다.
  final MatchSlot? selected;

  /// 고른 거리. `null`이면 아직 고르지 않았다.
  final TargetDistance? distance;

  /// 시간대 목록을 받아오는 중.
  final bool loading;

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
    bool? loading,
    bool? submitting,
    MatchFailure? failure,
    DateTime? cooldownUntil,
  }) => MatchRegisterState(
    slots: slots ?? this.slots,
    selected: selected ?? this.selected,
    distance: distance ?? this.distance,
    loading: loading ?? this.loading,
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

  /// 시간대 목록을 받아온다. 화면에 들어올 때와 마감 경합 뒤에 부른다.
  ///
  /// **고른 시간대가 목록에서 사라지거나 잠기면 선택을 푼다.** 남겨두면
  /// 마감된 슬롯으로 등록을 눌러 같은 409를 다시 맞는다.
  Future<void> loadSlots() async {
    state = state.copyWith(loading: true);
    try {
      final slots = await ref
          .read(matchRepositoryProvider)
          .fetchSlots(distance: state.distance);

      final picked = state.selected;
      final stillOpen =
          picked != null &&
          slots.any((slot) => slot.raw == picked.raw && slot.selectable);

      state = MatchRegisterState(
        slots: slots,
        selected: stillOpen ? picked : null,
        distance: state.distance,
      );
    } on MatchException catch (error) {
      debugPrint('[match] 시간대를 읽지 못했다 · ${error.failure.name}');
      state = state.copyWith(loading: false, failure: error.failure);
    }
  }

  void selectSlot(MatchSlot slot) {
    state = state.copyWith(selected: slot, failure: null);
  }

  /// 거리를 고른다. **대기 인원 집계가 거리별이라 목록을 다시 받는다** —
  /// 10km를 고른 사람에게 3km 대기자 수를 보여주면 사회적 증거가 거짓이 된다.
  void selectDistance(TargetDistance distance) {
    state = state.copyWith(distance: distance, failure: null);
    unawaited(loadSlots());
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
      state = state.copyWith(submitting: false);
      return roomId;
    } on MatchException catch (error) {
      state = state.copyWith(
        submitting: false,
        failure: error.failure,
        cooldownUntil: error.cooldownUntil,
      );
      // 마감 경합이면 목록이 이미 낡았다. 바로 다시 받는다.
      if (error.failure == MatchFailure.slotClosed) unawaited(loadSlots());
      return null;
    }
  }

  /// 스낵바를 띄운 뒤 부른다. 같은 실패로 두 번 알리지 않는다.
  void clearFailure() {
    if (state.failure == null) return;
    state = state.copyWith(failure: null);
  }
}
