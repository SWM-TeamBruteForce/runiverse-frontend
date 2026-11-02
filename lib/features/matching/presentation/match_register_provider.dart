import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/slot_board.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';

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
    ref.watch(tokenRefresherProvider),
  ),
);

/// 매칭 등록 화면(S08)이 들고 있는 것.
///
/// ## ⚠️ 판은 한 번 받고 바뀌지 않는다
///
/// 2026-10-26까지는 조회가 거리를 필수로 받아, 거리를 고를 때마다 목록이 새로
/// 왔다. 그래서 **거리를 바꾸는 왕복 내내 새 거리 이름에 옛 거리 숫자가 붙는**
/// 틈이 있었고, 그 틈을 막는 절차(목록 비우기·고른 시간 갈아 끼우기)가 상태의
/// 절반이었다. 지금은 숫자가 한 판에서 같이 오므로 그 틈이 **구조적으로 없다.**
class MatchRegisterState {
  const MatchRegisterState({
    this.board,
    this.time,
    this.meters,
    this.submitting = false,
    this.failure,
    this.cooldownUntil,
    this.loadingSlots = false,
    this.loadFailure,
  });

  /// 받아 둔 거리 × 시간의 판. `null`이면 아직 못 받았다.
  final SlotBoard? board;

  /// 고른 시간대. `null`이면 아직 고르지 않았다.
  final SlotTime? time;

  /// 고른 거리(m). `null`이면 아직 고르지 않았다.
  ///
  /// ⚠️ **`TargetDistance`가 아니다.** 선택지는 응답이 정한다 — 서버가 7km를
  /// 추가하면 enum에 없어서 신청할 수 없게 된다.
  final int? meters;

  /// 신청을 보내는 중. **CTA를 잠그는 데 쓴다** — 두 번 누르면 중복 신청이 된다.
  final bool submitting;

  final MatchFailure? failure;

  /// [MatchFailure.cooldown]일 때만 담긴다.
  final DateTime? cooldownUntil;

  /// 판을 받는 중이다. 그동안 시간 선택기를 잠근다.
  final bool loadingSlots;

  /// ⚠️ **[failure]와 따로 둔다.** 저쪽은 화면이 스낵바를 띄운 뒤 곧바로
  /// 지우는데, 조회 실패는 **선택기 자리에 머물러야** 한다 — 잠긴 이유와
  /// 다시 시도할 길이 거기 있다.
  final SlotLoadFailure? loadFailure;

  /// 시간을 고를 수 있는가.
  ///
  /// ⚠️ **"판이 비지 않았다"로는 부족하다.** 전부 마감인 응답(22시 이후)이
  /// 오면 판은 차 있는데 고를 것이 없다. 그때 선택기를 열어 두면 시트에
  /// `마감`만 늘어서고 등록 버튼은 영영 잠긴 채라 고장난 화면으로 읽힌다.
  ///
  /// ⚠️ **거리를 묻지 않는다.** 전에는 거리를 고른 뒤라야 참이었다 — 조회가
  /// 거리별이어서 그 전에는 보여줄 숫자가 없었다. 지금은 시트의 숫자가
  /// 거리와 무관한 합계라 거리를 고르기 전에도 열어도 된다(설계 5-3).
  bool get slotsReady =>
      !loadingSlots && loadFailure == null && openTimes.isNotEmpty;

  /// 아직 들어갈 수 있는 시각.
  List<SlotTime> get openTimes => [
    for (final t in board?.times ?? const <SlotTime>[])
      if (t.selectable) t,
  ];

  /// 고른 시각 × 고른 거리의 칸. 둘 중 하나라도 안 골랐으면 `null`이다.
  MatchSlotPick? get picked {
    final raw = time?.raw;
    final meters = this.meters;
    if (raw == null || meters == null) return null;
    final slot = board?.at(raw: raw, meters: meters);
    if (slot == null) return null;
    return MatchSlotPick(raw: raw, meters: meters, slot: slot);
  }

  /// 등록 버튼에 붙는 숫자. **고른 조건의 수다.**
  ///
  /// ⚠️ **시간 시트의 숫자와 다르다.** 시트는 모든 거리를 더한 합계를 그리고
  /// (`SlotTime.waitingTotal`), 여기는 고른 거리 하나의 수다. 거리를 고르면
  /// 숫자가 좁혀지는 것이 그래서 정상이다.
  ///
  /// ⚠️ **없는 조합은 `0`이 아니라 `null`이다.** 0으로 뭉개면 고를 수 없는
  /// 자리를 `0명 대기`로 그려, 신청할 수 있는 것처럼 말하게 된다.
  int? get pickedWaiting => picked?.slot.waitingCount;

  /// **오늘은 더 고를 것이 없다.** 받아 봤는데 전부 마감이다.
  ///
  /// ⚠️ **"판이 없다"와 가른다.** 조회 전에도 판은 없고, 조회가 실패해도
  /// 비운다. 그 둘을 마감으로 읽으면 화면에 들어오자마자, 또는 서버가 흔들릴
  /// 때마다 사람을 홈으로 쫓아낸다.
  bool get closedForToday {
    final times = board?.times;
    return !loadingSlots &&
        loadFailure == null &&
        times != null &&
        times.isNotEmpty &&
        openTimes.isEmpty;
  }

  // ⚠️ **마감 임박 안내는 아직 없다.** 남은 슬롯 개수로 가늠하던 것을 뺐다 —
  // 서버 시각을 받는 API가 생기면 "지금 몇 시인가"로 제대로 판단한다.

  /// 등록할 수 있는가. **둘 다 골라야, 그 칸이 열려 있어야 열린다.**
  ///
  /// ⚠️ **칸의 `selectable`을 본다.** 시간 시트는 거리 중 하나라도 열려 있으면
  /// 여는데(설계 5-5), 그 시각에 **고른 거리만** 마감일 수 있다. 그걸 누르면
  /// 409를 맞는다.
  bool get canSubmit => !submitting && (picked?.slot.selectable ?? false);

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
    Object? board = _keep,
    Object? time = _keep,
    int? meters,
    bool? submitting,
    Object? failure = _keep,
    Object? cooldownUntil = _keep,
    bool? loadingSlots,
    Object? loadFailure = _keep,
  }) => MatchRegisterState(
    board: identical(board, _keep) ? this.board : board as SlotBoard?,
    time: identical(time, _keep) ? this.time : time as SlotTime?,
    meters: meters ?? this.meters,
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

/// 고른 시각 × 고른 거리 하나. 화면이 숫자와 잠금을 여기서 읽는다.
class MatchSlotPick {
  const MatchSlotPick({
    required this.raw,
    required this.meters,
    required this.slot,
  });

  /// 신청에 그대로 실리는 문자열.
  final String raw;

  /// 신청에 그대로 실리는 거리(m).
  final int meters;

  /// 그 칸의 대기 인원·선택 가능 여부.
  final MatchSlot slot;
}

final matchRegisterProvider =
    NotifierProvider<MatchRegisterController, MatchRegisterState>(
      MatchRegisterController.new,
    );

/// 판을 받고 매칭을 신청한다.
class MatchRegisterController extends Notifier<MatchRegisterState> {
  @override
  MatchRegisterState build() => const MatchRegisterState();

  /// 시간을 고른다. **서버를 부르지 않는다.**
  void selectTime(SlotTime time) {
    state = state.copyWith(time: time, failure: null);
  }

  /// 거리를 고른다. **서버를 부르지 않는다.**
  ///
  /// ⚠️ **고른 시간을 건드리지 않는다.** 전에는 거리마다 목록이 새로 와서
  /// 같은 `raw`를 찾아 갈아 끼워야 했다(`_applySlots`). 판이 바뀌지 않으므로
  /// 그 절차가 통째로 사라졌다 — 숫자는 `pickedWaiting`이 판에서 꺼낸다.
  void selectDistance(int meters) {
    state = state.copyWith(meters: meters, failure: null);
  }

  /// 화면에 들어올 때 **지난번 흔적을 지운다.**
  ///
  /// ## ⚠️ 이 상태는 화면을 나가도 죽지 않는다
  ///
  /// 남겨두면 지난번에 누른 거리가 **기본값처럼** 선택돼 있고, 몇 시간 전에
  /// 받은 대기 인원이 지금 것인 양 보인다.
  ///
  /// ⚠️ **여기서 서버를 부르지 않는다.** 부르는 것은 [load]다. 둘을 한 함수로
  /// 묶으면 초기화만 하고 싶을 때 왕복이 따라온다.
  void reset() {
    state = const MatchRegisterState();
    // 날아오던 답이 빈 화면에 내려앉지 않게 번호를 올린다.
    _loadToken++;
  }

  /// 오늘의 **모든 거리 × 모든 시간대**를 받는다(명세 No 16).
  ///
  /// ## ⚠️ 한 번이면 끝이다
  ///
  /// `probeToday`가 죽었다. 거리를 필수로 받던 시절에는 "거리를 안 골랐는데
  /// 어떻게 묻나"를 아무 거리로 한 번 물어 비켜 갔고, 받은 숫자는 어느 거리의
  /// 것인지 말할 수 없어 버렸다. 그 질문 자체가 사라졌다.
  ///
  /// 거리를 바꿀 때도 다시 묻지 않는다 — 받아 둔 판에서 꺼내 쓴다.
  Future<void> load() async {
    state = state.copyWith(
      loadingSlots: true,
      loadFailure: null,
      failure: null,
    );
    final token = ++_loadToken;
    try {
      final board = await ref.read(matchRepositoryProvider).slots();
      if (!ref.mounted || token != _loadToken) return;
      _applyBoard(board);
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

  /// 보낸 조회에 매기는 번호.
  ///
  /// ## ⚠️ 왕복이 하나로 줄어도 경합은 남는다
  ///
  /// 조회 실패 뒤 `다시 시도`는 연타하기 가장 쉬운 버튼이다. 늦게 온 실패가
  /// 먼저 온 성공을 덮으면, 판이 제대로 왔는데도 "불러오지 못했어요"로 잠긴다.
  var _loadToken = 0;

  /// 받은 판을 심는다.
  void _applyBoard(SlotBoard board) {
    // ⚠️ **`copyWith`를 쓴다.** 생성자로 세우면 여기 안 적은 필드가 조용히
    // 초기화된다 — `submitting`이 그렇게 풀려서, 신청이 날아가는 중에 판이
    // 다시 오면 CTA가 열리고 같은 신청이 두 번 나갔다.
    state = state.copyWith(
      board: board,
      loadingSlots: false,
      loadFailure: null,
    );
  }

  /// 조회가 실패했다. **판도 비운다** — 남겨두면 잠긴 선택기 뒤에 낡은 숫자가
  /// 그대로 서 있다.
  void _failSlots(SlotLoadFailure failure) {
    state = state.copyWith(
      board: null,
      time: null,
      loadingSlots: false,
      loadFailure: failure,
    );
  }

  /// 신청한다. 성공하면 배정된 방 번호를, 실패하면 `null`을 돌려준다.
  ///
  /// ⚠️ **실패해도 다시 보내지 않는다.** 네트워크가 끊긴 경우 신청됐는지
  /// 알 수 없어, 재시도가 곧 중복 신청이 된다.
  Future<int?> submit() async {
    final pick = state.picked;
    if (pick == null || state.submitting) return null;

    state = state.copyWith(submitting: true, failure: null);
    try {
      final roomId = await ref
          .read(matchRepositoryProvider)
          .apply(slotRaw: pick.raw, meters: pick.meters);

      // 가이드가 요구하는 것 — 신청·러닝·결과 조회가 같은 방 번호 하나로
      // 이어진다. 메모리에만 두면 앱이 죽는 순간 그 고리가 끊긴다.
      await ref.read(matchRoomStoreProvider).save(roomId);
      unawaited(
        ref.read(analyticsProvider).matchApply(distanceMeters: pick.meters),
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
        // ⚠️ 고른 시간을 푼다. 잠긴 자리를 고른 채로 두면 같은 409를 다시
        // 맞는다.
        //
        // ⚠️ **실패를 다시 세우지 않는다.** 위에서 이미 세웠고, 화면이 그것을
        // 보고 팝업을 띄운 뒤 지운다. 여기서 또 쓰면 **팝업이 두 번 열린다.**
        state = state.copyWith(time: null);
        // ⚠️ **판을 다시 받는다.** 한 줄만 잠그는 것보다 정확하다 — 그사이
        // 마감된 다른 시각도 함께 잠긴 채로 온다. 한 번에 다 받으므로 값도
        // 싸다(`MatchSlot.closed()`가 죽은 이유다).
        //
        // ⚠️ **기다린다.** 화면이 "오늘이 끝났나"로 팝업을 가르는데, 그 판정은
        // 이 답이 와야 선다. 안 기다리면 "그 시간만 마감" 팝업이 먼저 뜨고
        // 뒤이어 "오늘 마감" 팝업이 그 위에 겹친다.
        await _reloadAfterClosed();
      }
      return null;
    }
  }

  /// 409 뒤에 판을 다시 받는다.
  ///
  /// ⚠️ **실패 문구를 다시 세우지 않는다.** 화면은 `failure`가 차는 것을 보고
  /// 스낵바를 띄운 뒤 곧바로 지운다. 여기서 되살리면 **사라졌던 스낵바가 다시
  /// 나타나고** 4초 타이머가 처음부터 돈다. 알릴 일은 이미 끝났다.
  ///
  /// ⚠️ **[load]를 부르지 않는다.** 저쪽은 `loadingSlots`를 세워 선택기를
  /// 잠그고 `failure`를 지운다 — 방금 띄운 409 문구가 그 길로 사라진다.
  Future<void> _reloadAfterClosed() async {
    final token = ++_loadToken;
    try {
      final board = await ref.read(matchRepositoryProvider).slots();
      if (!ref.mounted || token != _loadToken) return;
      _applyBoard(board);
    } on Object {
      // 다시 받지 못했다. **지금 화면을 건드리지 않는다** — 409 문구가 이미
      // 서 있고, 그것을 조회 실패로 덮으면 왜 신청이 거절됐는지 알 수 없어진다.
    }
  }

  /// 스낵바를 띄운 뒤 부른다. 같은 실패로 두 번 알리지 않는다.
  void clearFailure() {
    if (state.failure == null) return;
    state = state.copyWith(failure: null);
  }
}
