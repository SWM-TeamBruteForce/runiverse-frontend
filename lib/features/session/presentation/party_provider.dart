import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
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

    return const PartyBoard();
  }

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
    _combos = channel.combos.listen(
      (update) => state = state.withCombos(update),
    );
  }

  void _unbind() {
    _progress?.cancel();
    _progress = null;
    _combos?.cancel();
    _combos = null;
  }

  /// 대기방에서 들고 온 명단을 넣는다. **러닝을 시작할 때 한 번.**
  void setRoster(List<PartyMember> members) {
    state = state.withRoster(members);
  }

  /// 손으로 비운다. 평소에는 [_bind]가 알아서 한다.
  void clear() {
    _unbind();
    state = const PartyBoard();
  }
}
