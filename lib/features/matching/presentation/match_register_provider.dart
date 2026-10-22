import 'dart:async';

import 'package:flutter/foundation.dart';
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
  /// ⚠️ **거리를 고른 뒤라야 참이다.** 진입 조회(`probeToday`)는 아무 거리로
  /// 물어 "오늘 뭐가 남았나"만 보는 것이라, 그 숫자를 시트에 그리면 3km
  /// 대기자를 10km 고를 사람에게 보여주게 된다.
  bool get slotsReady =>
      distance != null &&
      !loadingSlots &&
      loadFailure == null &&
      slots.any((slot) => slot.selectable);

  /// 이 거리의 모든 시각을 더한 대기 인원.
  ///
  /// 등록 버튼 위 줄이 쓴다 — "이 거리에 사람이 이만큼 있다"를 먼저 알리고,
  /// 어느 시각인지는 시트가 답한다.
  /// ⚠️ **마감된 시각은 세지 않는다.** 세면 전부 마감인 날 "7명이 기다려요"와
  /// "신청할 수 있는 시간이 없어요"가 같은 화면에 서고 버튼은 잠긴 채다 —
  /// 고장난 화면으로 읽힌다. 들어갈 수 없는 자리의 사람은 권유가 될 수 없다.
  int get waitingTotal => slots.fold(
    0,
    (sum, slot) => slot.selectable ? sum + slot.waitingCount : sum,
  );

  /// 아직 들어갈 수 있는 시간대.
  List<MatchSlot> get openSlots => [
    for (final slot in slots)
      if (slot.selectable) slot,
  ];

  /// **오늘은 더 고를 것이 없다.** 받아 봤는데 전부 마감이다.
  ///
  /// ⚠️ **"목록이 비었다"와 가른다.** 거리를 고르기 전에도 목록은 비어 있고,
  /// 조회가 실패해도 비운다. 그 둘을 마감으로 읽으면 화면에 들어오자마자,
  /// 또는 서버가 흔들릴 때마다 사람을 홈으로 쫓아낸다.
  bool get closedForToday =>
      !loadingSlots &&
      loadFailure == null &&
      slots.isNotEmpty &&
      openSlots.isEmpty;

  /// 마감이 **임박했다.** 남은 시간대를 미리 알린다.
  ///
  /// ## ⚠️ 시계로 재지 않는다
  ///
  /// 마감이 "시작 10분 전"이라는 건 운영값이다. 앱이 그 숫자를 가지면 설정이
  /// 바뀌는 날 조용히 어긋난다 — 운영에서 아홉 칸이 하루 종일 마감으로 떴던
  /// 사고가 그 계산 때문이었다. 대신 **서버가 준 `selectable`이 몇 개
  /// 남았는지**로 가른다. 판정 주체가 계속 서버다.
  ///
  /// ⚠️ 전부 마감이면 거짓이다 — 그때는 [closedForToday]가 팝업으로 맡는다.
  /// 둘을 겹쳐 띄우면 "곧 마감"과 "이미 마감"이 같은 화면에 선다.
  bool get closingSoon =>
      openSlots.isNotEmpty && openSlots.length <= closingSoonThreshold;

  /// 임박으로 보는 경계. 운영값(18:00~22:00 · 30분)에서 마지막 한 시간쯤이다.
  static const closingSoonThreshold = 2;

  /// 등록할 수 있는가. **둘 다 골라야 열린다.**
  bool get canSubmit => selected != null && distance != null && !submitting;

  /// "안 바꾼다"를 뜻하는 표식.
  ///
  /// ## ⚠️ 이게 없으면 상태를 생성자로 직접 세우게 된다
  ///
  /// `null`을 "안 바꾼다"로 읽으면 **비울 수가 없다.** 그래서 선택을 푸는
  /// 자리마다 생성자를 직접 썼고, 그때마다 **옮기는 것을 빠뜨린 필드가 조용히
  /// 초기화됐다** — 신청 중에 거리를 바꾸면 `submitting`이 풀려 같은 신청이
  /// 두 번 나가던 것이 그 결과다.
  static const _keep = Object();

  MatchRegisterState copyWith({
    List<MatchSlot>? slots,
    Object? selected = _keep,
    TargetDistance? distance,
    bool? submitting,
    Object? failure = _keep,
    Object? cooldownUntil = _keep,
    bool? loadingSlots,
    Object? loadFailure = _keep,
  }) => MatchRegisterState(
    slots: slots ?? this.slots,
    selected: identical(selected, _keep)
        ? this.selected
        : selected as MatchSlot?,
    distance: distance ?? this.distance,
    submitting: submitting ?? this.submitting,
    loadingSlots: loadingSlots ?? this.loadingSlots,
    loadFailure: identical(loadFailure, _keep)
        ? this.loadFailure
        : loadFailure as SlotLoadFailure?,
    failure: identical(failure, _keep)
        ? this.failure
        : failure as MatchFailure?,
    cooldownUntil: identical(cooldownUntil, _keep)
        ? this.cooldownUntil
        : cooldownUntil as DateTime?,
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

  /// 화면에 들어올 때 **오늘 뭐가 남았는지**만 본다.
  ///
  /// ## ⚠️ 거리를 안 골랐는데 어떻게 묻나
  ///
  /// 조회는 거리를 필수로 받는다. 그런데 **시각 목록과 `selectable`은 거리와
  /// 무관하다** — 명세가 `slots`를 "그날의 신청 가능 시각"이라 적고, 거리별로
  /// 달라지는 것은 `waitingCount` 하나다. 그래서 아무 거리로 한 번 묻는다.
  ///
  /// ⚠️ **받은 숫자는 쓰지 않는다.** 어느 거리의 수인지 말할 수 없어서다.
  /// [MatchRegisterState.slotsReady]가 거리를 요구하므로 시트도 안 열리고,
  /// 등록 버튼 위 줄도 거리가 있어야 선다. 쓰는 것은 **마감 여부뿐**이다.
  ///
  /// ⚠️ 서버가 거리별로 다른 시각 목록을 주기 시작하면 이 전제가 깨진다.
  /// 그때는 마감 판정만 틀리고(거리를 고르면 곧 바로잡힌다) 숫자는 여전히
  /// 안전하다 — 애초에 안 쓰기 때문이다.
  /// ## ⚠️ 들어올 때마다 상태를 비우고 시작한다
  ///
  /// 이 상태는 화면을 나가도 죽지 않는다. 남겨두면 **지난번에 누른 거리가
  /// 기본값처럼** 선택돼 있고, 그 거리의 낡은 숫자가 그대로 선다. 더 나쁜 것은
  /// 마감 팝업이다 — 화면은 [MatchRegisterState.closedForToday]가 **바뀔 때**
  /// 여는데, 지난번 판정이 남아 있으면 바뀌는 것이 없어 **영영 안 뜬다.**
  /// 한 번 보고 홈에 갔다 돌아온 사람이 잠긴 화면 앞에 이유도 모르고 선다.
  Future<void> probeToday() {
    state = const MatchRegisterState();
    return _loadSlots(++_loadToken, TargetDistance.values.first);
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
    // ⚠️ **옛 목록을 버리고 시작한다.** 들고 있으면 왕복 한 번 내내 새 거리
    // 이름에 **옛 거리 숫자**가 붙는다 — "현재 10km에 7명"인데 7은 3km의
    // 합계다. 설계가 "가장 나쁜 실패"로 꼽은 것이 그것이다.
    // ⚠️ **고른 시간은 남긴다.** `_applySlots`가 새 목록의 같은 `raw`로 갈아
    // 끼운다(설계 6절). 여기서 비우면 거리만 바꿔도 시간을 다시 골라야 한다.
    state = state.copyWith(
      slots: const [],
      distance: distance,
      failure: null,
      loadFailure: null,
      loadingSlots: true,
    );
    await _loadSlots(++_loadToken, distance);
  }

  /// 보낸 조회에 매기는 번호.
  ///
  /// ## ⚠️ 거리만으로는 경합을 못 가른다
  ///
  /// 처음에는 `state.distance != distance`로 걸렀는데, **같은 거리를 다시
  /// 누르는 것이 정식 동작**(실패 복구)이라 그 경우 둘이 같아 통과한다.
  /// 늦게 온 실패가 먼저 성공한 목록을 지워서, 목록이 제대로 왔는데도
  /// "불러오지 못했어요"로 잠겼다. `다시 시도`는 연타하기 가장 쉬운 버튼이다.
  var _loadToken = 0;

  /// 거리 하나의 슬롯을 받아 상태에 심는다. **마지막으로 보낸 조회만 쓴다.**
  Future<void> _loadSlots(int token, TargetDistance distance) async {
    try {
      final slots = await ref
          .read(matchRepositoryProvider)
          .slots(distance: distance);
      if (!ref.mounted || token != _loadToken) return;
      _applySlots(slots);
    } on SlotLoadException catch (error) {
      if (!ref.mounted || token != _loadToken) return;
      _failSlots(error.failure);
    } on Object catch (error) {
      // ⚠️ **예상 밖의 예외도 받는다.** 플랫폼 채널 실패 같은 것을 흘려보내면
      // 화면이 "불러오는 중"에 영영 갇히고 `다시 시도` 버튼조차 안 붙는다.
      // 매칭 신청이 통째로 불가능해지면서 빠져나올 길이 없다.
      debugPrint('[match] 슬롯 조회가 예상 밖으로 죽었다 · $error');
      if (!ref.mounted || token != _loadToken) return;
      _failSlots(SlotLoadFailure.network);
    }
  }

  /// 조회가 실패했다. **목록도 비운다** — 남겨두면 잠긴 선택기 뒤에 옛 거리의
  /// 숫자가 그대로 서 있다.
  void _failSlots(SlotLoadFailure failure) {
    state = state.copyWith(
      slots: const [],
      selected: null,
      loadingSlots: false,
      loadFailure: failure,
    );
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

    // ⚠️ **`copyWith`를 쓴다.** 생성자로 세우면 여기 안 적은 필드가 조용히
    // 초기화된다 — `submitting`이 그렇게 풀려서, 신청이 날아가는 중에 거리를
    // 바꾸면 CTA가 다시 열리고 같은 신청이 두 번 나갔다.
    state = state.copyWith(
      slots: slots,
      selected: fresh,
      loadingSlots: false,
      loadFailure: null,
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
        unawaited(_reloadAfterClosed(distance));
      }
      return null;
    }
  }

  /// 409 뒤에 목록을 다시 받는다.
  ///
  /// ⚠️ **실패 문구를 다시 세우지 않는다.** 화면은 `failure`가 차는 것을 보고
  /// 스낵바를 띄운 뒤 곧바로 지운다. 여기서 되살리면 **사라졌던 스낵바가 다시
  /// 나타나고** 4초 타이머가 처음부터 돈다. 알릴 일은 이미 끝났다.
  Future<void> _reloadAfterClosed(TargetDistance distance) async {
    try {
      final slots = await ref
          .read(matchRepositoryProvider)
          .slots(distance: distance);
      if (!ref.mounted || state.distance != distance) return;
      _applySlots(slots);
    } on Object {
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
