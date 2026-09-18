import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/match_stream.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 매칭 스트림을 **언제 붙이고 언제 끊는가.**
///
/// 활성 신청이 없는데 열면 서버가 404로 거절하고, 붙어야 할 때 안 붙으면
/// 확정 통지를 영영 못 받아 출발 시각을 지나친다. 그 판정이 여기 있다.
void main() {
  final startAt = DateTime(2026, 9, 15, 19);

  RoomInfo room(RoomStatus status, {int players = 2}) => RoomInfo(
    runningRoomId: 125,
    status: status,
    scheduledStartAt: startAt,
    players: [
      for (var i = 0; i < players; i++)
        RoomPlayer(userId: 'u-$i', nickname: '러너$i', isDeleted: false),
    ],
  );

  /// 컨테이너와 가짜 스트림을 함께 만든다.
  ({
    ProviderContainer container,
    FakeMatchStream stream,
    FakeUserStatusRepository statuses,
  })
  build() {
    final stream = FakeMatchStream();
    final statuses = FakeUserStatusRepository();
    final container = ProviderContainer(
      overrides: [
        matchStreamProvider.overrideWithValue(stream),
        userStatusRepositoryProvider.overrideWithValue(statuses),
      ],
    );
    addTearDown(container.dispose);
    // provider를 세워야 유저 상태를 지켜보기 시작한다.
    container.read(matchRoomProvider);
    return (container: container, stream: stream, statuses: statuses);
  }

  group('언제 붙는가', () {
    test('처음에는 붙지 않는다', () {
      final app = build();

      expect(app.stream.connects, 0);
    });

    test('⚠️ 이미 대기 중인 상태로 앱을 켜도 붙는다', () async {
      // 상태는 스플래시가 읽고 이 provider는 그 뒤에 생긴다. 변화만 들으면
      // 이미 지나간 값을 영영 못 봐서, 켤 때마다 대기 중인 매칭에 안 붙는다.
      final stream = FakeMatchStream();
      final statuses = FakeUserStatusRepository(
        status: UserStatusWaiting(
          runningRoomId: 125,
          scheduledStartAt: startAt,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          matchStreamProvider.overrideWithValue(stream),
          userStatusRepositoryProvider.overrideWithValue(statuses),
        ],
      );
      addTearDown(container.dispose);

      // provider를 세우기 **전에** 상태를 읽어 둔다 — 실제 진입 순서다.
      await container.read(userStatusProvider.notifier).refresh();
      container.read(matchRoomProvider);
      await Future<void>.delayed(Duration.zero);

      expect(stream.connects, 1);
    });

    test('⚠️ 매칭 대기면 붙는다', () async {
      // 안 붙으면 확정 통지를 못 받아 출발 시각을 지나친다.
      final app = build();
      app.statuses.status = UserStatusWaiting(
        runningRoomId: 125,
        scheduledStartAt: startAt,
      );

      await app.container.read(userStatusProvider.notifier).refresh();
      // 붙는 판정은 한 틱 미뤄진다(`build()` 중 state 변경을 피한다).
      await Future<void>.delayed(Duration.zero);

      expect(app.stream.connects, 1);
    });

    test('매칭 확정도 붙는다', () async {
      final app = build();
      app.statuses.status = UserStatusReady(
        runningRoomId: 125,
        isSolo: false,
        scheduledStartAt: startAt,
      );

      await app.container.read(userStatusProvider.notifier).refresh();
      // 붙는 판정은 한 틱 미뤄진다(`build()` 중 state 변경을 피한다).
      await Future<void>.delayed(Duration.zero);

      expect(app.stream.connects, 1);
    });

    test('⚠️ 솔로 준비 중에는 붙지 않는다', () async {
      // 솔로는 SSE를 쓰지 않는다. 맞출 상대가 없어 모집 단계가 없다.
      final app = build();
      app.statuses.status = UserStatusReady(
        runningRoomId: 125,
        isSolo: true,
        scheduledStartAt: startAt,
      );

      await app.container.read(userStatusProvider.notifier).refresh();
      // 붙는 판정은 한 틱 미뤄진다(`build()` 중 state 변경을 피한다).
      await Future<void>.delayed(Duration.zero);

      expect(app.stream.connects, 0);
    });

    test('러닝 중에는 붙지 않는다', () async {
      // 그 구간은 WebSocket이 맡는다.
      final app = build();
      app.statuses.status = UserStatusRunning(
        runningRoomId: 125,
        isSolo: false,
        scheduledStartAt: startAt,
      );

      await app.container.read(userStatusProvider.notifier).refresh();
      // 붙는 판정은 한 틱 미뤄진다(`build()` 중 state 변경을 피한다).
      await Future<void>.delayed(Duration.zero);

      expect(app.stream.connects, 0);
    });

    test('두 번 붙지 않는다', () async {
      // 포그라운드 복귀마다 상태를 다시 읽는다. 그때마다 새로 붙으면 안 된다.
      final app = build();
      app.statuses.status = UserStatusWaiting(
        runningRoomId: 125,
        scheduledStartAt: startAt,
      );

      await app.container.read(userStatusProvider.notifier).refresh();
      await app.container.read(userStatusProvider.notifier).refresh();
      // 붙는 판정은 한 틱 미뤄진다(`build()` 중 state 변경을 피한다).
      await Future<void>.delayed(Duration.zero);

      expect(app.stream.connects, 1);
    });

    test('⚠️ 상태를 못 읽어도 살아 있는 연결을 버리지 않는다', () async {
      // 조회 한 번 실패했다고 끊으면 그사이의 확정 통지를 놓친다.
      final app = build();
      app.statuses.status = UserStatusWaiting(
        runningRoomId: 125,
        scheduledStartAt: startAt,
      );
      await app.container.read(userStatusProvider.notifier).refresh();

      app.statuses.failure = UserStatusFailure.network;
      await app.container.read(userStatusProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);

      expect(app.stream.closes, 0);
    });

    test('쉬는 중이 되면 끊는다', () async {
      final app = build();
      app.statuses.status = UserStatusWaiting(
        runningRoomId: 125,
        scheduledStartAt: startAt,
      );
      await app.container.read(userStatusProvider.notifier).refresh();

      app.statuses.status = const UserStatusIdle();
      await app.container.read(userStatusProvider.notifier).refresh();
      // 끊기는 것은 비동기다. 기다리지 않으면 아직 0이다.
      await Future<void>.delayed(Duration.zero);

      expect(app.stream.closes, greaterThanOrEqualTo(1));
      expect(app.container.read(matchRoomProvider).room, isNull);
    });
  });

  group('나가기', () {
    // 누를 수 있는 곳이 둘이다 — 모집 중에는 홈 히어로, 확정 뒤에는 로비.
    // 순서가 한 곳에 있어야 한쪽만 고쳐지는 일이 없다.
    ({
      ProviderContainer container,
      FakeMatchStream stream,
      FakeMatchRepository matches,
    })
    buildWithRepo({MatchFailure? cancelFailure}) {
      final stream = FakeMatchStream();
      final matches = FakeMatchRepository(cancelFailure: cancelFailure);
      final container = ProviderContainer(
        overrides: [
          matchStreamProvider.overrideWithValue(stream),
          matchRepositoryProvider.overrideWithValue(matches),
          // 나가기가 남겨 둔 방 번호를 지운다. 진짜는 플랫폼 채널을 탄다.
          matchRoomStoreProvider.overrideWithValue(InMemoryMatchRoomStore()),
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(matchRoomProvider);
      return (container: container, stream: stream, matches: matches);
    }

    test('취소를 보내고 스트림을 닫고 방을 비운다', () async {
      final app = buildWithRepo();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);
      app.stream.emit(MatchRoomUpdated(room(RoomStatus.matching)));
      await Future<void>.delayed(Duration.zero);

      final left = await app.container.read(matchRoomProvider.notifier).leave();

      expect(left, isTrue);
      expect(app.matches.cancelCalls, 1);
      expect(app.stream.closes, greaterThanOrEqualTo(1));
      expect(app.container.read(matchRoomProvider).room, isNull);
    });

    test('⚠️ 취소할 것이 없다는 답은 실패가 아니다', () async {
      // 다른 기기에서 먼저 나갔거나 서버가 방을 닫은 뒤다 — 이미 원하던 상태다.
      final app = buildWithRepo(cancelFailure: MatchFailure.nothingToCancel);

      final left = await app.container.read(matchRoomProvider.notifier).leave();

      expect(left, isTrue);
      expect(app.container.read(matchRoomProvider).room, isNull);
    });

    test('⚠️ 진짜 실패하면 방을 비우지 않는다', () async {
      // 서버는 아직 이 사람을 참가자로 알고 있다. 화면에서 지우면 나간 줄 안다.
      final app = buildWithRepo(cancelFailure: MatchFailure.network);
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);
      app.stream.emit(MatchRoomUpdated(room(RoomStatus.matched)));
      await Future<void>.delayed(Duration.zero);

      final left = await app.container.read(matchRoomProvider.notifier).leave();

      expect(left, isFalse);
      expect(app.container.read(matchRoomProvider).room, isNotNull);
    });
  });

  group('이벤트를 받는다', () {
    test('갱신은 방을 다시 그린다', () async {
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(MatchRoomUpdated(room(RoomStatus.matching)));
      await Future<void>.delayed(Duration.zero);

      expect(
        app.container.read(matchRoomProvider).room?.status,
        RoomStatus.matching,
      );
    });

    test('⚠️ 확정 연출은 상태 전이로 판정한다', () async {
      // 연동 가이드가 "SSE에 연결하면 MATCH_STARTED를 전송한다"고 정했다 —
      // 이벤트 종류로 판정하면 앱을 켤 때마다 다시 축하하게 된다.
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      // 연결 직후 스냅샷. 아직 모집 중이니 축하할 것이 없다.
      app.stream.emit(MatchStarted(room(RoomStatus.matching)));
      await Future<void>.delayed(Duration.zero);
      expect(app.container.read(matchRoomProvider).justMatched, isFalse);

      // 모집 중 → 확정으로 넘어간 그 순간이다.
      app.stream.emit(MatchRoomUpdated(room(RoomStatus.matched)));
      await Future<void>.delayed(Duration.zero);
      expect(app.container.read(matchRoomProvider).justMatched, isTrue);
    });

    test('⚠️ 확정된 방으로 다시 붙어도 축하하지 않는다', () async {
      // 재연결 스냅샷은 같은 MATCHED를 실어 온다. 전이가 아니므로 조용하다.
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(MatchStarted(room(RoomStatus.matched)));
      await Future<void>.delayed(Duration.zero);
      app.container.read(matchRoomProvider.notifier).consumeMatched();

      app.stream.emit(MatchStarted(room(RoomStatus.matched)));
      await Future<void>.delayed(Duration.zero);

      expect(app.container.read(matchRoomProvider).justMatched, isFalse);
    });

    test('연출을 띄우고 나면 내려간다', () async {
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(MatchStarted(room(RoomStatus.matched)));
      await Future<void>.delayed(Duration.zero);
      app.container.read(matchRoomProvider.notifier).consumeMatched();

      expect(app.container.read(matchRoomProvider).justMatched, isFalse);
      // 방은 그대로 남는다 — 연출만 끝난 것이다.
      expect(app.container.read(matchRoomProvider).room, isNotNull);
    });

    test('⚠️ 취소된 방은 들고 있지 않는다', () async {
      // 참가자가 모두 빠진 방이다. 남겨두면 갈 수 없는 대기실이 남는다.
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(MatchRoomUpdated(room(RoomStatus.matching)));
      await Future<void>.delayed(Duration.zero);
      app.stream.emit(MatchRoomUpdated(room(RoomStatus.cancelled)));
      await Future<void>.delayed(Duration.zero);

      expect(app.container.read(matchRoomProvider).room, isNull);
      expect(app.stream.closes, greaterThanOrEqualTo(1));
    });

    test('⚠️ 끝난 방은 현재 방으로 삼지 않고 연결도 끊지 않는다', () async {
      // 2026-09-18: 새 방에 신청했는데 스냅샷으로 두 시간 전에 끝낸 방이 왔다.
      // 그것을 현재 방으로 저장하니 홈이 "매칭 없음"으로 보였고, 재신청은
      // 409로 막혀 빠져나갈 길이 없었다. 그때도 상태 조회는 확정을 줬다.
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(MatchRoomUpdated(room(RoomStatus.finished)));
      await Future<void>.delayed(Duration.zero);

      expect(app.container.read(matchRoomProvider).room, isNull);
      // ⚠️ 끊으면 상태가 확정이라 곧바로 다시 붙고 같은 것을 또 받는다.
      expect(app.stream.closes, 0);
    });

    test('⚠️ 끝난 방이 와도 들고 있던 방을 지우지 않는다', () async {
      // 살아 있는 방을 보고 있는데 옛 방의 마지막 상태가 끼어들 수 있다.
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(MatchRoomUpdated(room(RoomStatus.matched)));
      await Future<void>.delayed(Duration.zero);
      app.stream.emit(MatchRoomUpdated(room(RoomStatus.finished)));
      await Future<void>.delayed(Duration.zero);

      expect(
        app.container.read(matchRoomProvider).room?.status,
        RoomStatus.matched,
      );
    });

    test('시작 통지를 들고 있는다', () async {
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(
        RunningReady(
          runningRoomId: 125,
          scheduledStartAt: startAt,
          startsInMs: 10000,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(app.container.read(matchRoomProvider).ready?.startsInMs, 10000);
    });

    test('⚠️ 끊겨도 방 정보는 남는다', () async {
      // 잠깐 끊겼다고 대기방을 비우면 사람이 홈으로 튕긴다.
      final app = build();
      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(MatchRoomUpdated(room(RoomStatus.matched)));
      await Future<void>.delayed(Duration.zero);
      app.stream.breakDown();
      await Future<void>.delayed(Duration.zero);

      final state = app.container.read(matchRoomProvider);
      expect(state.room, isNotNull);
      expect(state.connected, isFalse);
      expect(state.failure, MatchStreamFailure.network);
    });

    test('활성 신청이 없다고 거절당하면 그 이유가 남는다', () async {
      final app = build();
      app.stream.failure = MatchStreamFailure.noActiveMatch;

      app.container.read(matchRoomProvider.notifier).connect();
      await Future<void>.delayed(Duration.zero);

      expect(
        app.container.read(matchRoomProvider).failure,
        MatchStreamFailure.noActiveMatch,
      );
    });
  });
}
