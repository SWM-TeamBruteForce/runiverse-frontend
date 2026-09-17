import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

final partyProvider = NotifierProvider<PartyController, PartyBoard>(
  PartyController.new,
);

/// 함께 뛰는 사람들의 현재 상태.
///
/// ## 명단과 수치가 다른 곳에서 온다
///
/// **명단**(이름·사진)은 대기방에서 들고 들어오고, **수치**(거리·페이스·콤보)는
/// 러닝 채널이 10초마다 밀어 준다. 둘을 `userId`로 맞춘다.
///
/// 명세는 둘 다 `RUNNING_STARTED` 스냅샷에서 받으라고 하지만 서버가 그 ack의
/// `data`를 비워 보낸다. 그래서 명단만 따로 들고 온다
/// (`devlog/2026-09-16-버그수정-러닝-파티원-표시정보.md`).
///
/// ## 솔로 러닝에는 아무것도 오지 않는다
///
/// 같이 뛰는 사람이 없으니 명단도 통지도 비어 있다. 화면이 [PartyBoard.rows]가
/// 비었는지만 보면 된다 — 솔로인지 매칭인지 따로 묻지 않는다.
class PartyController extends Notifier<PartyBoard> {
  StreamSubscription<RunProgress>? _progress;
  StreamSubscription<RunCombo>? _combos;

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

    _progress = channel.progress.listen(
      (update) => state = state.withProgress(update),
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

  void _unbind() {
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
