import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
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

/// 매칭 등록 화면(S08)이 들고 있는 것.
class MatchRegisterState {
  const MatchRegisterState({
    this.slots = const [],
    this.selected,
    this.distance,
    this.submitting = false,
    this.failure,
    this.cooldownUntil,
    this.loadingSlots = false,
    this.loadFailure,
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

  /// 슬롯 목록을 받는 중이다. 그동안 시간 선택기를 잠근다.
  final bool loadingSlots;

  /// ⚠️ **[failure]와 따로 둔다.** 저쪽은 화면이 스낵바를 띄운 뒤 곧바로
  /// 지우는데, 조회 실패는 **선택기 자리에 머물러야** 한다 — 잠긴 이유와
  /// 다시 시도할 길이 거기 있다.
  final SlotLoadFailure? loadFailure;

  /// 시간을 고를 수 있는가.
  ///
  /// ⚠️ **"목록이 비지 않았다"로는 부족하다.** 전부 마감인 응답(22시 이후)이
  /// 오면 목록은 차 있는데 고를 것이 없다. 그때 선택기를 열어 두면 시트에
  /// `마감`만 늘어서고 등록 버튼은 영영 잠긴 채라 고장난 화면으로 읽힌다.
  bool get slotsReady =>
      !loadingSlots &&
      loadFailure == null &&
      slots.any((slot) => slot.selectable);

  /// 이 거리의 모든 시각을 더한 대기 인원.
  ///
  /// 등록 버튼 위 줄이 쓴다 — "이 거리에 사람이 이만큼 있다"를 먼저 알리고,
  /// 어느 시각인지는 시트가 답한다.
  int get waitingTotal => slots.fold(0, (sum, slot) => sum + slot.waitingCount);

  /// 등록할 수 있는가. **둘 다 골라야 열린다.**
  bool get canSubmit => selected != null && distance != null && !submitting;

  MatchRegisterState copyWith({
    List<MatchSlot>? slots,
    MatchSlot? selected,
    TargetDistance? distance,
    bool? submitting,
    MatchFailure? failure,
    DateTime? cooldownUntil,
    bool? loadingSlots,
    SlotLoadFailure? loadFailure,
  }) => MatchRegisterState(
    slots: slots ?? this.slots,
    selected: selected ?? this.selected,
    distance: distance ?? this.distance,
    submitting: submitting ?? this.submitting,
    loadingSlots: loadingSlots ?? this.loadingSlots,
    // ⚠️ [failure]와 같은 이유로 `??`를 쓰지 않는다 — 지울 수 있어야 한다.
    loadFailure: loadFailure,
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

  void selectSlot(MatchSlot slot) {
    state = state.copyWith(selected: slot, failure: null);
  }

  /// 거리를 고르고 **그 거리의 슬롯을 받는다**(명세 No 16).
  ///
  /// ## ⚠️ 목록이 거리에 딸려 있다
  ///
  /// 10km를 고른 사람에게 3km 대기자 수를 보여주면 사회적 증거가 거짓이 된다.
  /// 그래서 거리가 바뀔 때마다 다시 받는다. **같은 거리를 다시 눌러도** 받는다
  /// — 조회가 실패한 사람에게 `다시 시도` 말고 다른 길도 열어 두는 것이다.
  ///
  /// 캐시하지 않는다. 갱신 주기가 없어서 화면에 오래 머문 사람은 어차피 낡은
  /// 숫자를 보는데, 거리를 다시 고르는 **행동까지** 캐시로 묶으면 고의로
  /// 확인하려는 사람에게도 낡은 숫자를 준다.
  Future<void> selectDistance(TargetDistance distance) async {
    state = state.copyWith(
      distance: distance,
      failure: null,
      loadingSlots: true,
    );
    await _loadSlots(distance);
  }

  /// 거리 하나의 슬롯을 받아 상태에 심는다.
  Future<void> _loadSlots(TargetDistance distance) async {
    try {
      final slots = await ref
          .read(matchRepositoryProvider)
          .slots(distance: distance);
      // ⚠️ **늦게 온 답이 나중 거리를 덮지 않게 한다.** 칩을 연타하면 요청이
      // 겹치는데, 먼저 보낸 것이 늦게 오면 칩은 10km인데 숫자는 3km가 된다.
      if (!ref.mounted || state.distance != distance) return;
      _applySlots(slots);
    } on SlotLoadException catch (error) {
      if (!ref.mounted || state.distance != distance) return;
      // 고를 것이 없으니 목록도 비운다 — 남겨두면 잠긴 선택기 뒤에 옛 거리의
      // 숫자가 그대로 서 있다.
      state = MatchRegisterState(
        distance: distance,
        loadFailure: error.failure,
      );
    }
  }

  /// 받은 목록을 심고 고른 시간을 맞춘다.
  ///
  /// ⚠️ **고른 시간을 새 목록의 같은 `raw`로 갈아 끼운다.** 옛 객체를 그대로
  /// 두면 `waitingCount`와 `selectable`이 **옛 거리의 값**으로 남는다.
  /// 없거나 잠겼으면 선택을 푼다 — 남겨두면 마감된 슬롯으로 등록을 눌러 같은
  /// 409를 다시 맞는다.
  void _applySlots(List<MatchSlot> slots) {
    final picked = state.selected;
    MatchSlot? fresh;
    if (picked != null) {
      for (final slot in slots) {
        if (slot.raw == picked.raw && slot.selectable) {
          fresh = slot;
          break;
        }
      }
    }

    // `copyWith`는 선택을 비울 수 없어 직접 세운다.
    state = MatchRegisterState(
      slots: slots,
      selected: fresh,
      distance: state.distance,
      cooldownUntil: state.cooldownUntil,
    );
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
      unawaited(
        ref.read(analyticsProvider).matchApply(distanceMeters: distance.meters),
      );

      state = state.copyWith(submitting: false);
      return roomId;
    } on MatchException catch (error) {
      state = state.copyWith(
        submitting: false,
        failure: error.failure,
        cooldownUntil: error.cooldownUntil,
      );
      // 마감 경합이다. 서버가 준 `selectable`은 **받은 시점의 사진**이라,
      // 화면을 열어 둔 사이 마감(시작 10분 전)이 지날 수 있다.
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
        // ⚠️ **목록을 다시 받는다.** 앱이 만들던 시절에는 같은 값이 돌아와
        // 부를 이유가 없었지만, 이제 서버가 주므로 **그사이 마감된 다른
        // 시각들도 함께** 잠긴 채로 온다.
        //
        // 기다리지 않는다 — 실패를 이미 화면에 알렸고, 목록은 늦게 와도 된다.
        unawaited(_reloadAfterClosed(distance, error.failure));
      }
      return null;
    }
  }

  /// 409 뒤에 목록을 다시 받는다. **실패 문구는 지우지 않는다** — 화면이
  /// 아직 그것을 띄우기 전일 수 있다.
  Future<void> _reloadAfterClosed(
    TargetDistance distance,
    MatchFailure failure,
  ) async {
    try {
      final slots = await ref
          .read(matchRepositoryProvider)
          .slots(distance: distance);
      if (!ref.mounted || state.distance != distance) return;
      _applySlots(slots);
      state = state.copyWith(failure: failure);
    } on SlotLoadException {
      // 다시 받지 못했다. **지금 화면을 건드리지 않는다** — 잠근 슬롯과
      // 409 문구가 이미 서 있고, 그것을 조회 실패로 덮으면 왜 신청이
      // 거절됐는지 알 수 없어진다.
    }
  }

  /// 스낵바를 띄운 뒤 부른다. 같은 실패로 두 번 알리지 않는다.
  void clearFailure() {
    if (state.failure == null) return;
    state = state.copyWith(failure: null);
  }
}
