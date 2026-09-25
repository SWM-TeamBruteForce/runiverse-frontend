import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
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
/// ## 솔로 러닝에는 아무것도 오지 않는다
///
/// 같이 뛰는 사람이 없으니 명단도 통지도 비어 있다. 화면이 [PartyBoard.rows]가
/// 비었는지만 보면 된다 — 솔로인지 매칭인지 따로 묻지 않는다.
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

    _progress = channel.progress.listen(
      // 받은 시각을 여기서 찍는다. 채널은 시계를 모르는 편이 테스트하기 쉽다.
      (update) => state = state.withProgress(update.stamped(DateTime.now())),
    );
    _combos = channel.combos.listen((update) {
      final before = state.combos.keys.toSet();
      state = state.withCombos(update);
      // 콤보가 새로 이어지거나 끊긴 순간에만 한 번 울린다. 통지는 10초마다
      // 오는데 그때마다 울리면 달리는 내내 진동한다. 소리는 범위 밖이다.
      if (!before.containsAll(state.combos.keys) ||
          !state.combos.keys.toSet().containsAll(before)) {
        unawaited(HapticFeedback.mediumImpact());
      }
    });
  }

  /// 스냅샷 하나를 보드에 통째로 얹는다. 최초 진입과 재연결이 같은 길이다.
  Future<void> _apply(RunSnapshot snapshot) async {
    // 명단에는 나도 들어 있다. 나를 가려내야 내 줄이 파티원으로 또 뜨지 않는다.
    final me = (await ref.read(tokenStoreProvider).read()).userId;
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
