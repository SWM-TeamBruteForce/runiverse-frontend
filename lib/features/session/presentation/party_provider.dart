import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/domain/combo_milestone.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

final partyProvider = NotifierProvider<PartyController, PartyBoard>(
  PartyController.new,
);

/// 함께 뛰는 사람들의 현재 상태.
///
/// ## 명단과 수치가 다른 곳에서 온다
///
/// **명단**(이름·사진)은 `RUNNING_STARTED` 스냅샷이 실어 오고,
/// **수치**(거리·페이스·콤보)는 러닝 채널이 10초마다 밀어 준다.
/// 둘을 `userId`로 맞춘다.
///
/// 한동안 서버가 그 ack의 `data`를 비워 보내서 명단을 대기방에서 들고 들어왔다
/// (`devlog/2026-09-16-버그수정-러닝-파티원-표시정보.md`). 지금은 스냅샷이
/// 채워져 오고, [setRoster]는 스냅샷이 오기 전 구간을 메우는 용도로만 남았다.
///
/// ## ⚠️ 솔로 러닝에도 통지가 온다
///
/// 예전 주석은 "같이 뛰는 사람이 없으니 명단도 통지도 비어 있다"고 적혀 있었는데
/// **틀렸다.** 서버는 1인 러닝에서도 10초마다 **내 진행**을 보낸다
/// (2026-10-06 에뮬레이터 확인). 그것을 여기서 걸러내므로, 화면은 여전히
/// [PartyBoard.rows]가 비었는지만 보면 된다 — 솔로인지 매칭인지 따로 묻지 않는다.
class PartyController extends Notifier<PartyBoard> {
  StreamSubscription<RunProgress>? _progress;
  StreamSubscription<RunCombo>? _combos;
  StreamSubscription<RunSnapshot>? _snapshots;

  @override
  PartyBoard build() {
    // ⚠️ 화면이 소유하면 러닝 중에 탭을 옮기는 사이 통지를 놓친다.
    ref.keepAlive();

    // 채널이 생기고 사라지는 것을 따라간다. 러닝을 시작할 때 만들어지므로
    // 여기서 한 번 잡아두면 그 뒤 통지가 이어진다.
    ref.listen(
      runningConnectionProvider.select((state) => state.room),
      (_, room) => _bind(),
    );
    ref.onDispose(_unbind);

    // ⚠️ **첫 build에서도 붙는다.** 위의 `listen`은 방이 *바뀔 때*만 부른다.
    //
    // 복구 경로(앱 재시작)는 스플래시가 `openMatched`로 방을 먼저 열고 러닝
    // 화면을 뒤에 띄운다. 그래서 이 provider를 처음 읽는 시점에 방이 이미 있는
    // 경우가 있고, 그러면 바뀌는 일이 없어 영영 구독하지 않는다 — 통지는
    // 채널까지 오는데 보드가 비어 파티원이 한 명도 안 보인다(2026-09-18 실주행).
    // 둘 중 어느 쪽이 먼저인지는 경합이라, 여기서 한 번 더 확인한다.
    final opened = ref.read(runningConnectionProvider.notifier).channel;
    if (opened != null) _subscribe(opened);

    // 내 거리도 보드에 넣는다. 내 레인이 파티원과 같은 규칙(기준값 이상 앞서야
    // 자리 교체)으로 섞이려면 보드가 내 거리를 알아야 한다 — 화면에서 매번
    // 끼워 넣으면 그 기억이 화면 밖에 남지 않아 경계에서 줄이 튄다.
    ref.listen(runSessionControllerProvider.select(_myDistanceOf), (_, meters) {
      // ⚠️ 솔로는 섞을 줄이 없다. 매초 새 보드를 만들어 화면을 다시 그리지 않는다.
      if (state.roster.isEmpty && state.progress.isEmpty) return;
      if (meters == state.myDistanceMeters) return;
      state = state.withMyDistance(meters);
    });

    return const PartyBoard();
  }

  static int _myDistanceOf(RunSessionState state) => switch (state) {
    RunRunning(:final metrics) ||
    RunPaused(:final metrics) => metrics.distanceMeters.round(),
    _ => 0,
  };

  void _bind() {
    _unbind();
    final channel = ref.read(runningConnectionProvider.notifier).channel;

    // ⚠️ 채널이 없어졌다 = 러닝이 끝났다. **여기서 비운다.**
    //
    // 연결 쪽에서 비우게 하면 순환이 된다 — 파티가 연결을 듣고 있는데 연결이
    // 파티를 읽으면 Riverpod이 `CircularDependencyError`로 막는다. 끝났다는
    // 사실은 어차피 이 구독으로 전해지므로 판단도 여기서 한다.
    if (channel == null) {
      state = const PartyBoard();
      return;
    }

    _subscribe(channel);
  }

  /// 채널의 두 스트림을 듣는다. **여기서는 `state`를 건드리지 않는다** —
  /// `build` 중에 부르는 길이 있어서다.
  void _subscribe(RunningChannel channel) {
    // ⚠️ **이름과 사진은 여기서만 온다.** 진행·콤보 통지는 사람을 `userId`로만
    // 가리키므로, 이것을 놓치면 러닝 내내 "함께 달리는 사람"으로만 보인다.
    _snapshots = channel.snapshots.listen(_apply);

    _progress = channel.progress.listen((update) async {
      // ⚠️ **내 진행은 버린다.**
      //
      // 2026-10-06 에뮬레이터 1인 러닝에서 확인했다 — `201 /running-rooms/solo`,
      // `시작 확인 · 1명` 인데 서버가 10초마다 **내 진행**을 보낸다. 코드
      // 주석은 반대로("서버는 본인 진행을 보내지 않는다") 적혀 있었다.
      //
      // 거르지 않으면 **자기가 파티원으로 뜬다** — 점이 2개에서 3개가 되고
      // `파티원 비교` 장에 내가 남처럼 선다.
      //
      // ⚠️ **내 진행도 버리지 않는다**(1.1.0 가이드 1.2). 비교 화면은 나를
      // 포함한 모두를 서버 거리로 줄 세운다 — 나만 로컬 값으로 매 초 움직이면
      // 간격이 어긋나 보이고, 서버 거리로 판정하는 콤보와도 따로 논다.
      //
      // ⚠️ **보드가 내 번호를 모르면 내가 파티원으로 선다.** `myUserId` 는
      // 명단(스냅샷)이 와야 채워지는데 진행 통지가 먼저 올 수 있다. 서버가
      // 무엇을 먼저 보내든 상관없도록 **로그인할 때 받아 둔 내 번호**를
      // 먼저 세운다.
      final me = await _myUserId();
      var next = state;
      if (me != null && next.myUserId != me) {
        next = next.withRoster(next.roster, myUserId: me);
      }

      // 받은 시각을 여기서 찍는다. 채널은 시계를 모르는 편이 테스트하기 쉽다.
      state = next.withProgress(update.stamped(DateTime.now()));
    });
    _combos = channel.combos.listen((update) {
      final before = state.combos;
      state = state.withCombos(update);
      final now = state.combos;

      // ⚠️ **한 통지에 한 번만 울린다.** 끊김 · 눈금 · 틱이 겹칠 수 있는데
      // 연달아 떨리면 무슨 뜻인지 알 수 없다. 순서는 끊김 → 눈금 → 틱이다.
      //
      // 풀린 것은 달리는 사람이 할 일이 있다는 신호고(붙어야 한다), 눈금은
      // 칭찬이다. 둘 중 하나만 울린다면 끊김이다.
      //
      // ⚠️ 빈 배열은 **전원 해제**다(WS No 9). 목록에서 빠지는 것이 곧
      // 끊김이고 별도의 종료 통지는 없다.
      if (before.keys.any((userId) => !now.containsKey(userId))) {
        unawaited(HapticFeedback.mediumImpact());
        return;
      }

      final headcount = state.comboHeadcount;

      // 눈금은 **상대마다 따로** 본다 — "동일한 콤보 건"이 기준이다. 가장
      // 높은 하나로 묶으면 뒤에 붙은 사람의 눈금이 영영 안 울린다.
      if (now.entries.any(
        (entry) => comboMilestonePassed(
          before: before[entry.key]?.comboCount ?? 0,
          after: entry.value.comboCount,
        ),
      )) {
        unawaited(_comboMilestoneHaptic(headcount));
        return;
      }

      // ⚠️ **오른 상대가 있을 때만 울린다.** 명세상 같은 관계를 두고 양쪽
      // 배치가 각각 통지를 만들 수 있다 — 값이 같으면 화면이 안 바뀌므로
      // 진동도 없어야 한다.
      //
      // 처음 붙은 상대는 `before`에 없다. `comboCount`가 0으로 오므로 `-1`과
      // 견줘야 "올랐다"가 된다.
      if (now.entries.any(
        (entry) =>
            entry.value.comboCount > (before[entry.key]?.comboCount ?? -1),
      )) {
        unawaited(_comboTickHaptic(headcount));
      }
    });
  }

  /// 콤보가 한 칸 올랐다는 틱. **이어지고 있다는 신호라 가장 약하다.**
  ///
  /// 10초마다 울리는 자리다. 여기가 세면 달리는 내내 떨리는 것으로 느껴진다.
  Future<void> _comboTickHaptic(int headcount) => switch (headcount) {
    <= 2 => HapticFeedback.selectionClick(),
    3 => HapticFeedback.lightImpact(),
    _ => HapticFeedback.mediumImpact(),
  };

  /// 눈금을 알리는 진동. **크고 길게.**
  ///
  /// ⚠️ **길이를 지정할 수 없다.** `HapticFeedback`에는 세기 네 단계뿐이라,
  /// 짧은 틈으로 연달아 쳐서 한 번의 긴 진동처럼 뭉치게 한다. 진짜 길이가
  /// 필요하면 `vibration` 패키지를 들여야 하는데 아직 승인 전이다.
  Future<void> _comboMilestoneHaptic(int headcount) async {
    final feel = headcount <= 2
        ? HapticFeedback.mediumImpact
        : HapticFeedback.heavyImpact;
    final times = headcount <= 3 ? 2 : 3;
    for (var turn = 0; turn < times; turn++) {
      if (turn > 0) await Future<void>.delayed(_comboHapticGap);
      await feel();
    }
  }

  /// 눈금을 연달아 칠 때 사이의 틈.
  ///
  /// ⚠️ **뭉쳐야 한다.** 90ms 로 뒀을 때는 또렷이 끊어져 "여러 번"으로
  /// 세였는데, 눈금은 **한 번 크고 길게**가 목적이라 짧아야 한다.
  static const _comboHapticGap = Duration(milliseconds: 50);

  /// 로그인할 때 받아 둔 내 번호. **서버가 알려주기를 기다리지 않는다.**
  ///
  /// 한 번 읽고 들고 있는다 — 통지가 10초마다 오는데 그때마다 저장소를 열 이유가
  /// 없다. 로그아웃하면 이 provider 도 함께 사라진다.
  String? _me;

  Future<String?> _myUserId() async =>
      _me ??= (await ref.read(tokenStoreProvider).read()).userId;

  /// 스냅샷 하나를 보드에 통째로 얹는다. 최초 진입과 재연결이 같은 길이다.
  Future<void> _apply(RunSnapshot snapshot) async {
    // 명단에는 나도 들어 있다. 나를 가려내야 내 줄이 파티원으로 또 뜨지 않는다.
    final me = await _myUserId();
    if (me == null) return;

    // 서버가 아는 내 누적 거리로 바닥을 메운다. 앱을 껐다 켜면 로컬이 0부터라
    // 화면만 0.00km가 된다. 이미 우리가 잰 것이 있으면 세션이 알아서 무시한다.
    final session = ref.read(runSessionControllerProvider.notifier);
    final mine = snapshot.myDistanceOf(me);
    if (mine != null) session.seedDistance(mine);

    // ⚠️ 경과 시간도 같이 맞춘다. 복구는 상태 조회의 **예약 시각**으로 재기
    // 시작하는데, 솔로 방은 만들어진 순간이 시작이라 그 값과 갈린다.
    // 스냅샷의 시작 시각이 유일하게 정확하다.
    final startedAt = snapshot.startedAt;
    if (startedAt != null) session.seedStartedAt(startedAt);

    final at = DateTime.now();
    var next = state.withRoster(snapshot.roster, myUserId: me);
    for (final progress in snapshot.progressOf(me)) {
      next = next.withProgress(progress.stamped(at));
    }
    // ⚠️ 시작 직후에는 **빈 목록**이 온다. 아직 아무와도 이어지지 않아서다 —
    // 못 읽은 것과 다르다. 그대로 얹으면 콤보가 없는 상태로 바르게 그려진다.
    state = next.withCombos(snapshot.combos);
  }

  void _unbind() {
    _snapshots?.cancel();
    _snapshots = null;
    _progress?.cancel();
    _progress = null;
    _combos?.cancel();
    _combos = null;
  }

  /// 대기방에서 들고 온 명단을 넣는다. **러닝을 시작할 때 한 번.**
  ///
  /// [myUserId]는 명단에서 나를 가려내는 열쇠다 — 방 전원 명단에는 나도 있다.
  void setRoster(List<PartyMember> members, {required String myUserId}) {
    state = state.withRoster(members, myUserId: myUserId);
  }

  /// 손으로 비운다. 평소에는 [_bind]가 알아서 한다.
  void clear() {
    _unbind();
    state = const PartyBoard();
  }
}
