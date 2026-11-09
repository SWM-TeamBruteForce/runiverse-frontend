import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/watch_version_store.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/core/watch/watch_channel.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/app_update/presentation/watch_version_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/watch_photo_maker.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_control_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/watch_link_provider.dart';

/// 폰이 **언제** 워치에 보내는가. 규칙은 워치 레포
/// `docs/phone-communication.md` 「보내는 규칙 — 폰」이다.
///
/// 워치는 받은 것만 그린다. 보내야 할 때 안 보내면 워치가 멈춰 보이고, 화면이
/// 꺼진 동안 보내면 배터리만 쓴다.
void main() {
  const metrics = RunMetrics(
    distanceMeters: 1200,
    elapsed: Duration(minutes: 7),
  );
  const room = RunningRoom(812, targetDistanceMeters: 5000, isMatched: true);

  late _Watch watch;
  late _Session session;
  late _Connection connection;
  late _Party party;
  late _Auth auth;
  late _Photos photos;

  /// 세션·연결을 부른 순서.
  late List<String> calls;

  /// 방 번호 → 서버 기록 조회. 테스트가 끝낼 때를 정한다.
  late Map<int, Completer<RunDetail>> details;

  /// 서버의 워치 기준. 남겨 둔 값이 없을 때 받으러 간다.
  late FakeAppVersionRepository versions;

  /// 워치 SYNC 가 싣는 버전. 남겨 둔 기준(1.2.0)과 같다.
  const watchVersion = '1.2.0';

  ProviderContainer start({
    bool withWatch = true,
    BodyProfileStore? body,
    WatchVersionStore? watchVersions,
  }) {
    watch = _Watch();
    photos = _Photos();
    details = {};
    calls = [];
    versions = FakeAppVersionRepository()
      ..watchMinimum = const AppVersion(1, 2, 0);
    final container = ProviderContainer.test(
      overrides: [
        appVersionRepositoryProvider.overrideWithValue(versions),
        watchVersionStoreProvider.overrideWithValue(
          watchVersions ?? InMemoryWatchVersionStore(const AppVersion(1, 2, 0)),
        ),
        watchChannelProvider.overrideWithValue(withWatch ? watch : null),
        watchPhotoMakerProvider.overrideWithValue(photos),
        runSessionControllerProvider.overrideWith(() => _Session(calls)),
        runningConnectionProvider.overrideWith(() => _Connection(calls)),
        partyProvider.overrideWith(_Party.new),
        authControllerProvider.overrideWith(_Auth.new),
        runDetailProvider.overrideWith(
          (ref, roomId) => (details[roomId] ??= Completer<RunDetail>()).future,
        ),
        bodyProfileStoreProvider.overrideWithValue(
          body ?? InMemoryBodyProfileStore(),
        ),
        runClockProvider.overrideWithValue(() => DateTime(2026, 11, 4, 9)),
      ],
    );
    session = container.read(runSessionControllerProvider.notifier) as _Session;
    connection =
        container.read(runningConnectionProvider.notifier) as _Connection;
    party = container.read(partyProvider.notifier) as _Party;
    auth = container.read(authControllerProvider.notifier) as _Auth;
    container.read(watchLinkProvider.notifier).start();
    return container;
  }

  Map<String, Object?> runOf(Map<String, Object?> state) =>
      state['run']! as Map<String, Object?>;

  Object? secondsOf(Map<String, Object?> state) =>
      (runOf(state)['me']! as Map<String, Object?>)['elapsedSeconds'];

  /// 러닝 시계가 [seconds] 초를 적은 상태.
  RunRunning runningAt(int seconds) => RunRunning(
    RunMetrics(distanceMeters: 1200, elapsed: Duration(seconds: seconds)),
  );

  testWidgets('러닝이 시작되면 워치 앱을 한 번 켜고 상태를 바로 보낸다', (tester) async {
    start();

    session.set(const RunRunning(metrics));
    // 1초 티커가 상태를 다시 세워도 단계는 그대로다.
    session.set(const RunRunning(metrics));
    await tester.pump();

    expect(watch.launches, 1);
    expect(watch.states, hasLength(1));
    expect(watch.states.single['statusVersion'], 1);
  });

  testWidgets('워치 화면이 켜져 있을 때만 러닝 시간이 바뀔 때마다 보낸다', (tester) async {
    start();
    session.set(runningAt(420));
    // 화면이 꺼져 있으면 시작 한 번뿐이다.
    session.set(runningAt(421));
    await tester.pump(const Duration(seconds: 3));
    expect(watch.states, hasLength(1));

    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();
    // 켜졌다는 알림을 받으면 바로 한 번 보낸다.
    expect(watch.states, hasLength(2));

    // 달리는 중엔 1초 타이머로 따로 읽지 않는다. 폰 화면 시간이 바뀔 때 보낸다.
    await tester.pump(const Duration(seconds: 3));
    expect(watch.states, hasLength(2));
    for (final second in [422, 423, 424]) {
      session.set(runningAt(second));
      await tester.pump();
    }
    expect(
      [for (final state in watch.states.skip(2)) secondsOf(state)],
      [422, 423, 424],
    );

    // 좌표로 같은 초가 다시 적히면 보내지 않는다.
    session.set(runningAt(424));
    await tester.pump();
    expect(watch.states, hasLength(5));

    // 15초 동안 알림이 없으면 꺼진 것으로 보고 멈춘다.
    await tester.pump(const Duration(seconds: 15));
    session.set(runningAt(440));
    await tester.pump();
    expect(watch.states, hasLength(5));
  });

  testWidgets('화면 신호가 10초마다 오면 1초 전송이 이어진다', (tester) async {
    start();
    // 달리는 중엔 시간이 바뀔 때 보내 1초 전송은 일시정지로 본다.
    session.set(const RunRunning(metrics));
    session.set(const RunPaused(metrics));
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump(const Duration(seconds: 10));

    // 첫 신호에서 15초가 지났어도, 두 번째 신호로 창이 늘어나 계속 보낸다.
    final before = watch.states.length;
    await tester.pump(const Duration(seconds: 3));
    expect(watch.states, hasLength(before + 3));

    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': false});
    await tester.pump();
  });

  testWidgets('일시정지 중에도 1초마다 보내고 끝나면 멈춘다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    session.set(const RunPaused(metrics));
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();

    final paused = watch.states.length;
    await tester.pump(const Duration(seconds: 2));
    expect(watch.states, hasLength(paused + 2));

    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    await tester.pump();
    final finished = watch.states.length;
    await tester.pump(const Duration(seconds: 2));
    expect(watch.states, hasLength(finished));

    // 화면이 다시 켜지면 놓친 결과를 되찾게 한 번 보낸다.
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();
    expect(watch.states, hasLength(finished + 1));
    expect(runOf(watch.states.last)['status'], 'FINISHED');

    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': false});
    await tester.pump();
  });

  testWidgets('서버 연결 상태를 그대로 싣는다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    session.set(const RunRunning(metrics));
    expect(runOf(watch.states.last)['isServerConnected'], isTrue);

    connection.set(
      connection.current.copyWith(connection: WsConnectionState.disconnected),
    );
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();
    expect(runOf(watch.states.last)['isServerConnected'], isFalse);

    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': false});
    await tester.pump();
  });

  testWidgets('러닝을 다시 시작하면 워치 앱도 다시 켠다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    session.set(const RunIdle());
    session.set(const RunPreparing(hasFix: true));
    session.set(const RunRunning(metrics));
    await tester.pump();

    expect(watch.launches, 2);
  });

  testWidgets('꺼졌다는 알림을 받으면 바로 멈춘다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();

    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': false});
    await tester.pump();
    final stopped = watch.states.length;
    await tester.pump(const Duration(seconds: 3));

    expect(watch.states, hasLength(stopped));
  });

  testWidgets('일시정지는 화면이 꺼져 있어도 바로 보내고 번호를 올린다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    session.set(const RunPaused(metrics));
    session.set(const RunRunning(metrics));
    await tester.pump();

    expect(
      [for (final state in watch.states) runOf(state)['status']],
      ['RUNNING', 'PAUSED', 'RUNNING'],
    );
    expect(
      [for (final state in watch.states) state['statusVersion']],
      [1, 2, 3],
    );
    // 보낼 때마다 오른다. 워치는 지난 번호를 버린다.
    expect(
      [for (final state in watch.states) state['stateSequence']],
      [1, 2, 3],
    );
  });

  testWidgets('종료가 확정될 때 종료 중에서 결과로 바로 간다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    session.set(const RunRunning(metrics));

    // 종료를 보냈다.
    connection.set(connection.current.copyWith(settling: true));
    // 확정을 받아 소켓을 닫는다 — 상태가 한 번 통째로 비워진다.
    connection.set(const RunningConnectionState());
    connection.set(
      const RunningConnectionState(room: room, finishedRoomId: 812),
    );
    // 그다음에 `RunControlController` 가 세션을 접는다.
    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    await tester.pump();

    // ⚠️ 사이에 달리는 중으로 돌아가면 워치가 종료 버튼을 다시 연다.
    expect(
      [for (final state in watch.states) runOf(state)['status']],
      ['RUNNING', 'RUNNING', 'FINISHED'],
    );
    expect(
      [for (final state in watch.states) runOf(state)['finish']],
      [
        null,
        {'stage': 'FINISHING'},
        null,
      ],
    );
    // 서버 기록을 받는 동안은 결과를 비운다 — 폰 요약이 `--` 를 띄운다.
    expect(runOf(watch.states.last)['result'], isNull);
    expect(runOf(watch.states.last)['runningRoomId'], 812);

    // 서버 기록이 오면 화면이 꺼져 있어도 바로 그 숫자로 보낸다.
    details[812]!.complete(
      RunDetail(
        runningRoomId: 812,
        distanceMeters: 1190,
        duration: const Duration(minutes: 6, seconds: 50),
        averagePace: const Duration(minutes: 5, seconds: 44),
        rawSplits: const [],
        players: const [
          RunPlayerResult(
            userId: 'me',
            nickname: '나',
            isMe: true,
            duration: Duration(minutes: 6, seconds: 50),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(runOf(watch.states.last)['result'], {
      'isServerConfirmed': true,
      'totalDistanceMeters': 1190,
      'averagePaceSecondsPerKm': 344,
      'elapsedSeconds': 410,
    });
  });

  testWidgets('서버 기록을 못 받으면 폰이 잰 숫자로 보낸다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(room: room, finishedRoomId: 812),
    );
    session.set(const RunRunning(metrics));
    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    await tester.pump();

    details[812]!.completeError(Exception('조회 실패'));
    await tester.pump();

    // 다시 시도를 기다리지 않고 첫 실패에서 바로 폰 숫자로 간다 — 폰 요약과 같다.
    final result = runOf(watch.states.last)['result']! as Map;
    expect(result['isServerConfirmed'], isFalse);
    expect(result['totalDistanceMeters'], 1200);
    expect(result['elapsedSeconds'], 420);

    // 실패한 조회를 Riverpod 이 몇 번 더 시도한다. 그 시계를 다 흘려보낸다.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('서버 기록에 내 기록이 없으면 폰이 잰 숫자로 보낸다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(room: room, finishedRoomId: 812),
    );
    session.set(const RunRunning(metrics));
    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    await tester.pump();

    // 너무 짧게 달려 조회는 성공해도 내 수치가 비어 온다.
    details[812]!.complete(
      RunDetail(
        runningRoomId: 812,
        distanceMeters: 0,
        duration: Duration.zero,
        rawSplits: const [],
        players: const [
          RunPlayerResult(userId: 'me', nickname: '나', isMe: true),
        ],
      ),
    );
    await tester.pump();

    final result = runOf(watch.states.last)['result']! as Map;
    expect(result['isServerConfirmed'], isFalse);
    expect(result['totalDistanceMeters'], 1200);
  });

  testWidgets('종료 확인을 못 받으면 서버 기록을 부르지 않고 폰 숫자로 보낸다', (tester) async {
    start();
    // 확인을 못 받아 연결이 비워졌다. 끝낸 방 표시가 없다.
    connection.set(const RunningConnectionState(room: room));
    session.set(const RunRunning(metrics));
    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    await tester.pump();

    expect(details, isEmpty);
    final result = runOf(watch.states.last)['result']! as Map;
    expect(result['isServerConfirmed'], isFalse);
  });

  testWidgets('폰에서 요약을 닫으면 화면이 꺼져 있어도 바로 러닝 없음을 보낸다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    final version = watch.states.last['statusVersion']! as int;

    // 워치 결과 화면도 같이 닫힌다.
    session.set(const RunIdle());
    await tester.pump();

    expect(watch.states.last['run'], isNull);
    expect(watch.states.last['statusVersion'], version + 1);
  });

  testWidgets('서버가 끝낸 러닝도 바로 러닝 없음을 보낸다', (tester) async {
    start();
    session.set(const RunRunning(metrics));

    // 서버 종료·강퇴는 요약 없이 홈으로 간다.
    session.set(const RunIdle());
    await tester.pump();

    expect(watch.states.last['run'], isNull);
  });

  testWidgets('러닝 중에 방이 세워지면 화면이 꺼져 있어도 바로 다시 보낸다', (tester) async {
    start();
    // 출발은 방을 기다리지 않는다. 첫 상태엔 방 번호·목표가 없다.
    session.set(const RunRunning(metrics));
    await tester.pump();
    expect(runOf(watch.states.last)['runningRoomId'], isNull);
    final version = watch.states.last['statusVersion'];

    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    await tester.pump();

    expect(watch.states, hasLength(2));
    expect(runOf(watch.states.last)['runningRoomId'], 812);
    expect(runOf(watch.states.last)['targetDistanceMeters'], 5000);
    // 단계가 바뀐 것은 아니다. 번호를 올리면 누른 명령이 거절된다.
    expect(watch.states.last['statusVersion'], version);

    // 같은 방으로 연결 상태만 바뀌면 또 보내지 않는다.
    connection.set(const RunningConnectionState(room: room));
    await tester.pump();
    expect(watch.states, hasLength(2));
  });

  testWidgets('구간 거부로 끝내려다 확인을 못 받으면 종료 중을 푼다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    session.set(const RunRunning(metrics));

    connection.set(
      connection.current.copyWith(settling: true, trackRejected: true),
    );
    await tester.pump();
    expect(runOf(watch.states.last)['finish'], {'stage': 'FINISHING'});

    // 답을 못 받아 정리한다 — 상태가 비워졌다가 방과 거부 표시만 되돌아온다.
    connection.set(const RunningConnectionState());
    connection.set(
      const RunningConnectionState(room: room, trackRejected: true),
    );
    await tester.pump();

    // 폰 러닝 화면은 달리는 중으로 남는다. 워치도 같게 돌아간다.
    expect(runOf(watch.states.last)['status'], 'RUNNING');
    expect(runOf(watch.states.last)['finish'], isNull);
  });

  testWidgets('구간 거부로 끝내다 확인을 받으면 결과로 간다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    session.set(const RunRunning(metrics));
    connection.set(
      connection.current.copyWith(settling: true, trackRejected: true),
    );

    connection.set(const RunningConnectionState());
    connection.set(
      const RunningConnectionState(
        room: room,
        trackRejected: true,
        finishedRoomId: 812,
      ),
    );
    await tester.pump();

    // 확인을 받았으면 세션이 곧 끝난다. 그 사이 달리는 중으로 돌아가지 않는다.
    expect(runOf(watch.states.last)['finish'], {'stage': 'FINISHING'});
  });

  testWidgets('종료 확인을 못 받아도 결과까지 종료 중을 유지한다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    session.set(const RunRunning(metrics));
    connection.set(connection.current.copyWith(settling: true));
    // 답을 못 받아 정리한다 — 방만 되돌아오고 끝낸 방 표시는 없다.
    connection.set(const RunningConnectionState());
    connection.set(const RunningConnectionState(room: room));
    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    await tester.pump();

    expect(
      [for (final state in watch.states) runOf(state)['finish']],
      [
        null,
        {'stage': 'FINISHING'},
        null,
      ],
    );
    expect(runOf(watch.states.last)['status'], 'FINISHED');
  });

  testWidgets('종료가 보류되면 러닝이 이어진다고 알린다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    session.set(const RunRunning(metrics));

    connection.set(connection.current.copyWith(settling: true));
    // 거리가 모자라다는 답이다. 방과 소켓은 그대로다.
    connection.set(connection.current.copyWith(settling: false));
    await tester.pump();

    final last = watch.states.last;
    expect(runOf(last)['finish'], isNull);
    expect(runOf(last)['status'], 'RUNNING');
    expect(last['statusVersion'], 3);
  });

  testWidgets('SYNC 를 받으면 같은 syncId 로 SYNCED 를 보낸다', (tester) async {
    start();

    watch.receive('WATCH_SYNC', {
      'syncId': 's-1',
      'watchVersion': watchVersion,
    });
    await tester.pump();

    final (event, data) = watch.sent.single;
    expect(event, 'WATCH_SYNCED');
    expect(data['syncId'], 's-1');
    expect(data['run'], isNull);
    expect(data['photos'], isEmpty);
  });

  testWidgets('SYNCED 에 저장된 생일을 싣는다', (tester) async {
    final body = InMemoryBodyProfileStore();
    await body.save(birthday: DateTime(1998, 3, 7));
    final container = start(body: body);
    // 앱은 스플래시에서 미리 읽어 둔다.
    container.read(bodyProfileProvider);
    await tester.pump();

    watch.receive('WATCH_SYNC', {
      'syncId': 's-1',
      'watchVersion': watchVersion,
    });
    await tester.pump();

    expect(watch.sent.single.$2['birthday'], '1998-03-07');
  });

  group('파티원 사진', () {
    const kong = 'https://s3/kong.jpg?X-Amz-Signature=1';
    const roster = [
      PartyMember(
        userId: 'me',
        nickname: '나',
        profileImageUrl: 'https://s3/me.jpg',
      ),
      PartyMember(userId: 'u-1', nickname: '콩나물', profileImageUrl: kong),
      // 사진을 올린 적이 없다.
      PartyMember(userId: 'u-2', nickname: '두부'),
    ];
    final board = const PartyBoard().withRoster(roster, myUserId: 'me');

    Future<List<Object?>> syncedPhotos(
      WidgetTester tester,
      String syncId,
    ) async {
      watch.receive('WATCH_SYNC', {
        'syncId': syncId,
        'watchVersion': watchVersion,
      });
      await tester.pump();
      final (event, data) = watch.sent.last;
      expect(event, 'WATCH_SYNCED');
      return data['photos']! as List<Object?>;
    }

    testWidgets('카운트다운에서 미리 만든 사진을 싣고 내 사진은 안 만든다', (tester) async {
      final container = start();
      container
          .read(watchLinkProvider.notifier)
          .prefetchPhotos(roster, myUserId: 'me');
      await tester.pump();
      // 명단이 들어오기 전에 받았다.
      expect(photos.asked, [kong]);
      // 대기실은 미리 받은 직후 위치를 열며 준비 단계로 간다. 여기서 지우면 안 된다.
      session.set(const RunPreparing());
      party.set(board);
      session.set(const RunRunning(metrics));

      final photo = {'userId': 'u-1', 'jpegBase64': 'jpeg:$kong'};
      expect(await syncedPhotos(tester, 's-1'), [photo]);
      // 워치는 SYNCED 마다 사진을 통째로 바꾼다. 다음 답에도 다 실어야 한다.
      expect(await syncedPhotos(tester, 's-2'), [photo]);
      // 명단이 들어와도 만든 사람은 다시 받지 않는다.
      expect(photos.asked, [kong]);
    });

    testWidgets('카운트다운 없이 이어 뛰면 명단이 올 때 만든다', (tester) async {
      start();
      session.set(const RunRunning(metrics));
      party.set(board);
      await tester.pump();

      expect(await syncedPhotos(tester, 's-1'), [
        {'userId': 'u-1', 'jpegBase64': 'jpeg:$kong'},
      ]);
    });

    testWidgets('못 만든 사람은 빼고 보내고 다음 SYNCED 부터 싣는다', (tester) async {
      start();
      photos.failing.add(kong);
      session.set(const RunRunning(metrics));
      party.set(board);
      await tester.pump();

      expect(await syncedPhotos(tester, 's-1'), isEmpty);
      expect(await syncedPhotos(tester, 's-2'), [
        {'userId': 'u-1', 'jpegBase64': 'jpeg:$kong'},
      ]);
    });

    testWidgets('러닝을 마치고 돌아오면 사진을 비운다', (tester) async {
      start();
      session.set(const RunRunning(metrics));
      party.set(board);
      await tester.pump();

      session.set(const RunIdle());
      party.set(const PartyBoard());
      await tester.pump();

      expect(await syncedPhotos(tester, 's-1'), isEmpty);
      // 다음 러닝은 새 주소로 다시 만든다.
      party.set(board);
      await tester.pump();
      expect(photos.asked, [kong, kong]);
    });

    testWidgets('비운 뒤에 끝난 지난 러닝의 받기는 담지 않는다', (tester) async {
      start();
      photos.holding.add(kong);
      session.set(const RunRunning(metrics));
      party.set(board);
      await tester.pump();

      session.set(const RunIdle());
      party.set(const PartyBoard());
      await tester.pump();
      photos.held[kong]!.complete('jpeg:지난 러닝');
      await tester.pump();

      // 다음 러닝 명단이 오면 다시 받는다 — 지난 받기가 자리를 차지하지 않는다.
      party.set(board);
      await tester.pump();
      expect(await syncedPhotos(tester, 's-1'), [
        {'userId': 'u-1', 'jpegBase64': 'jpeg:$kong'},
      ]);
      expect(photos.asked, [kong, kong]);
    });

    testWidgets('지난 러닝의 받기가 끝나도 이번 러닝의 받는 중 표시는 남는다', (tester) async {
      start();
      photos.holding.add(kong);
      session.set(const RunRunning(metrics));
      party.set(board);
      await tester.pump();
      final previous = photos.held[kong]!;

      session.set(const RunIdle());
      party.set(const PartyBoard());
      photos.holding.add(kong);
      party.set(board);
      await tester.pump();
      previous.complete('jpeg:지난 러닝');
      await tester.pump();

      // 이번 러닝 받기가 아직 진행 중이라 SYNC 가 같은 사진을 또 받지 않는다.
      watch.receive('WATCH_SYNC', {
        'syncId': 's-1',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expect(photos.asked, [kong, kong]);
      photos.held[kong]!.complete('jpeg:$kong');
    });

    testWidgets('통로가 없으면(테스트·iOS) 사진을 만들지 않는다', (tester) async {
      final container = start(withWatch: false);
      container
          .read(watchLinkProvider.notifier)
          .prefetchPhotos(roster, myUserId: 'me');
      party.set(board);
      await tester.pump();

      expect(photos.asked, isEmpty);
    });
  });

  testWidgets('syncId 가 없는 SYNC 에는 답하지 않는다', (tester) async {
    start();

    // 돌려줄 syncId 가 없으면 워치가 그 답을 못 읽는다.
    watch.receive('WATCH_SYNC', {});
    await tester.pump();

    expect(watch.sent, isEmpty);
  });

  group('워치 버전', () {
    void expectSyncRejected(String syncId) {
      final (event, data) = watch.sent.single;
      expect(event, 'ERROR');
      expect(data['code'], 'WATCH_UPDATE_REQUIRED');
      expect(data['sourceType'], 'WATCH_SYNC');
      expect(data['requestId'], syncId);
    }

    testWidgets('최소 버전보다 낮으면 SYNCED 대신 거절한다', (tester) async {
      start();

      watch.receive('WATCH_SYNC', {'syncId': 's-1', 'watchVersion': '1.1.9'});
      await tester.pump();

      expectSyncRejected('s-1');
    });

    testWidgets('버전이 없거나 형식이 틀리면 거절한다', (tester) async {
      start();

      watch.receive('WATCH_SYNC', {'syncId': 's-1'});
      await tester.pump();
      expectSyncRejected('s-1');

      watch.sent.clear();
      watch.receive('WATCH_SYNC', {'syncId': 's-2', 'watchVersion': '1.2'});
      await tester.pump();
      expectSyncRejected('s-2');

      // 문자열이 아니어도 거절한다 — 던지면 답이 안 나간다.
      watch.sent.clear();
      watch.receive('WATCH_SYNC', {'syncId': 's-3', 'watchVersion': 120});
      await tester.pump();
      expectSyncRejected('s-3');
    });

    testWidgets('⚠️ 기준을 읽는 사이 이번 러닝에서 통과했으면 늦은 답도 거절하지 않는다', (tester) async {
      final store = _HeldWatchVersionStore();
      final container = start(watchVersions: store);
      session.set(const RunRunning(metrics));
      await tester.pump();

      // 첫 SYNC 는 남겨 둔 값을 읽느라 기다린다.
      watch.receive('WATCH_SYNC', {
        'syncId': 's-1',
        'watchVersion': watchVersion,
      });
      await tester.pump();

      // 그사이 서버 값이 와서 다음 SYNC 가 통과한다.
      final versionsOf = container.read(watchVersionProvider.notifier);
      await versionsOf.refresh();
      watch.receive('WATCH_SYNC', {
        'syncId': 's-2',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expect(watch.sent.last.$1, 'WATCH_SYNCED');

      // 기준이 올라간 뒤에 첫 읽기가 끝난다.
      versions.watchMinimum = const AppVersion(1, 3, 0);
      await versionsOf.refresh();
      store.held.complete(const AppVersion(1, 2, 0));
      await tester.pump();

      expect(watch.errors, isEmpty);
      expect(watch.sent.last.$1, 'WATCH_SYNCED');
      expect(watch.sent.last.$2['syncId'], 's-1');
    });

    testWidgets('남겨 둔 기준으로 서버에 묻지 않고 바로 답한다', (tester) async {
      start();

      watch.receive('WATCH_SYNC', {'syncId': 's-1', 'watchVersion': '1.3.0'});
      await tester.pump();

      expect(watch.sent.single.$1, 'WATCH_SYNCED');
      expect(versions.watchFetchCount, 0);
    });

    testWidgets('⚠️ 기준을 모르면 답하지 않고 받으러 간다', (tester) async {
      final store = InMemoryWatchVersionStore();
      start(watchVersions: store);

      watch.receive('WATCH_SYNC', {'syncId': 's-1', 'watchVersion': '1.1.0'});
      await tester.pump();
      // 모른다고 거절하면 업데이트할 필요 없는 워치가 업데이트 화면에 갇힌다.
      expect(watch.sent, isEmpty);
      expect(versions.watchFetchCount, 1);
      expect(await store.minimum(), const AppVersion(1, 2, 0));

      // 워치가 3초 뒤 다시 보낸 SYNC 는 받아 둔 기준으로 판정한다.
      watch.receive('WATCH_SYNC', {'syncId': 's-2', 'watchVersion': '1.1.0'});
      await tester.pump();
      expectSyncRejected('s-2');
    });

    testWidgets('기준을 못 받으면 계속 답하지 않는다', (tester) async {
      start(watchVersions: InMemoryWatchVersionStore());
      versions.watchFailure = Exception('offline');

      watch.receive('WATCH_SYNC', {
        'syncId': 's-1',
        'watchVersion': watchVersion,
      });
      await tester.pump();

      expect(watch.sent, isEmpty);
    });

    testWidgets('러닝 중 통과한 워치는 기준이 올라가도 러닝이 끝날 때까지 막지 않는다', (tester) async {
      final container = start();
      session.set(const RunRunning(metrics));
      await tester.pump();

      watch.receive('WATCH_SYNC', {
        'syncId': 's-1',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expect(watch.sent.last.$1, 'WATCH_SYNCED');

      versions.watchMinimum = const AppVersion(1, 3, 0);
      await container.read(watchVersionProvider.notifier).refresh();

      watch.receive('WATCH_SYNC', {
        'syncId': 's-2',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expect(watch.sent.last.$1, 'WATCH_SYNCED');

      // 결과 화면까지가 그 러닝이다.
      session.set(
        RunFinished(
          metrics: metrics,
          startedAt: DateTime(2026, 11, 4, 8),
          endedAt: DateTime(2026, 11, 4, 9),
        ),
      );
      await tester.pump();
      watch.receive('WATCH_SYNC', {
        'syncId': 's-3',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expect(watch.sent.last.$1, 'WATCH_SYNCED');

      session.set(const RunIdle());
      await tester.pump();
      watch.sent.clear();
      watch.receive('WATCH_SYNC', {
        'syncId': 's-4',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expectSyncRejected('s-4');
    });

    testWidgets('러닝 밖에서 통과한 워치는 기준이 올라가면 막는다', (tester) async {
      final container = start();

      watch.receive('WATCH_SYNC', {
        'syncId': 's-1',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expect(watch.sent.single.$1, 'WATCH_SYNCED');

      versions.watchMinimum = const AppVersion(1, 3, 0);
      await container.read(watchVersionProvider.notifier).refresh();
      watch.sent.clear();

      watch.receive('WATCH_SYNC', {
        'syncId': 's-2',
        'watchVersion': watchVersion,
      });
      await tester.pump();
      expectSyncRejected('s-2');
    });
  });

  testWidgets('콤보가 오르거나 끊기면 화면이 꺼져 있어도 알린다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    final board = const PartyBoard()
        .withRoster(const [
          PartyMember(userId: 'me', nickname: '나'),
          PartyMember(userId: 'u-1', nickname: '콩나물'),
        ], myUserId: 'me')
        .withProgress(const RunProgress(userId: 'u-1', distanceMeters: 1210));

    party.set(board);
    party.set(
      board.withCombos(
        const RunCombo([
          ComboPeer(
            userId: 'u-1',
            gapMeters: 10,
            comboCount: 0,
            maxComboCount: 0,
          ),
        ]),
      ),
    );
    party.set(party.current.withCombos(const RunCombo([])));
    await tester.pump();

    expect([for (final data in watch.combos) data['kind']], ['TICK', 'BREAK']);
    expect(watch.combos.first['userId'], 'u-1');
    expect(watch.combos.first['eventId'], isNot(watch.combos.last['eventId']));
  });

  testWidgets('러닝이 끝나며 비워진 보드는 끊김이 아니다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    party.set(
      const PartyBoard()
          .withProgress(const RunProgress(userId: 'u-1', distanceMeters: 1210))
          .withCombos(
            const RunCombo([
              ComboPeer(
                userId: 'u-1',
                gapMeters: 10,
                comboCount: 4,
                maxComboCount: 4,
              ),
            ]),
          ),
    );
    final before = watch.combos.length;

    // 연결이 닫히면 `PartyController` 가 보드를 통째로 비운다.
    party.set(const PartyBoard());
    await tester.pump();

    expect(watch.combos, hasLength(before));
  });

  testWidgets('콤보만 얹힌 보드가 비워져도 끊김이 아니다', (tester) async {
    start();
    session.set(const RunRunning(metrics));
    // 복구 중이라 명단·진행보다 콤보가 먼저 보드에 얹혔다.
    party.set(
      const PartyBoard().withCombos(
        const RunCombo([
          ComboPeer(
            userId: 'u-1',
            gapMeters: 10,
            comboCount: 4,
            maxComboCount: 4,
          ),
        ]),
      ),
    );
    final before = watch.combos.length;

    // 그 상태에서 연결이 닫혀 `PartyController` 가 보드를 비운다.
    party.set(const PartyBoard());
    await tester.pump();

    expect(watch.combos, hasLength(before));
  });

  testWidgets('명단·진행보다 먼저 온 콤보도 알린다', (tester) async {
    start();
    session.set(const RunRunning(metrics));

    // 복구할 때는 콤보가 명단·진행보다 먼저 보드에 얹힌다.
    party.set(
      const PartyBoard().withCombos(
        const RunCombo([
          ComboPeer(
            userId: 'u-1',
            gapMeters: 10,
            comboCount: 7,
            maxComboCount: 7,
          ),
        ]),
      ),
    );
    await tester.pump();

    expect([for (final data in watch.combos) data['kind']], ['MILESTONE']);
  });

  testWidgets('다시 붙을 때 스냅샷으로 얹힌 콤보는 알리지 않는다', (tester) async {
    start();
    session.set(const RunRunning(metrics));

    // 스냅샷은 명단·진행·콤보를 한 번에 얹는다. 폰도 이때는 진동하지 않는다.
    party.set(
      const PartyBoard()
          .withRoster(const [
            PartyMember(userId: 'me', nickname: '나'),
            PartyMember(userId: 'u-1', nickname: '콩나물'),
          ], myUserId: 'me')
          .withProgress(const RunProgress(userId: 'u-1', distanceMeters: 1210))
          .withCombos(
            const RunCombo([
              ComboPeer(
                userId: 'u-1',
                gapMeters: 10,
                comboCount: 7,
                maxComboCount: 7,
              ),
            ]),
          ),
    );
    await tester.pump();

    expect(watch.combos, isEmpty);
  });

  testWidgets('종료 답을 기다리는 동안 생긴 콤보도 알린다', (tester) async {
    start();
    connection.set(
      const RunningConnectionState(
        room: room,
        connection: WsConnectionState.connected,
      ),
    );
    session.set(const RunRunning(metrics));
    final board = const PartyBoard()
        .withProgress(const RunProgress(userId: 'u-1', distanceMeters: 1210))
        .withCombos(
          const RunCombo([
            ComboPeer(
              userId: 'u-1',
              gapMeters: 10,
              comboCount: 4,
              maxComboCount: 4,
            ),
          ]),
        );
    party.set(board);
    final before = watch.combos.length;

    // 보류로 끝나면 러닝이 이어진다. 그사이 끊긴 것을 버리면 다시 올 길이 없다.
    connection.set(connection.current.copyWith(settling: true));
    party.set(board.withCombos(const RunCombo([])));
    await tester.pump();

    expect(
      [for (final data in watch.combos.skip(before)) data['kind']],
      ['BREAK'],
    );
  });

  testWidgets('새 방이 열리기 전에는 지난 러닝의 방을 싣지 않는다', (tester) async {
    start();
    // 지난 러닝을 끝내고 요약을 닫았다. 연결은 끝난 방을 그대로 들고 있다.
    connection.set(
      const RunningConnectionState(room: room, finishedRoomId: 812),
    );
    session.set(const RunRunning(metrics));
    session.set(
      RunFinished(
        metrics: metrics,
        startedAt: DateTime(2026, 11, 4, 8),
        endedAt: DateTime(2026, 11, 4, 9),
      ),
    );
    session.set(const RunIdle());

    // 새 솔로를 시작했는데 방이 카운트다운보다 늦다.
    session.set(const RunPreparing(hasFix: true));
    session.set(const RunRunning(metrics));
    await tester.pump();
    expect(runOf(watch.states.last)['runningRoomId'], isNull);
    expect(runOf(watch.states.last)['targetDistanceMeters'], isNull);

    // 새 방이 열리면 그 번호를 싣는다.
    connection.set(
      const RunningConnectionState(
        room: RunningRoom(813),
        connection: WsConnectionState.connected,
      ),
    );
    watch.receive('WATCH_SYNC', {
      'syncId': 's-2',
      'watchVersion': watchVersion,
    });
    await tester.pump();
    expect(runOf(watch.sent.last.$2)['runningRoomId'], 813);

    // 지난 러닝의 서버 기록 구독을 닫으며 Riverpod 이 걸어 둔 정리 타이머를 흘려보낸다.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('받을 준비가 안 돼 못 켰으면 1초 뒤 다시 켠다', (tester) async {
    start();
    // 폰 앱을 켤 때 워치에 닿지 못해, 러닝을 시작하는 순간에야 받기를 다시 건다.
    watch.launchResults.addAll([
      WatchLaunchResult.notListening,
      WatchLaunchResult.notListening,
    ]);

    session.set(const RunRunning(metrics));
    await tester.pump();
    expect(watch.launches, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(watch.launches, 3);

    // 켜기 요청이 나갔으면 더 하지 않는다.
    await tester.pump(const Duration(seconds: 5));
    expect(watch.launches, 3);
  });

  testWidgets('다시 켜기는 세 번까지만 한다', (tester) async {
    start();
    watch.launchResults.addAll(List.filled(10, WatchLaunchResult.notListening));

    session.set(const RunRunning(metrics));
    await tester.pump(const Duration(seconds: 10));

    expect(watch.launches, 4);
  });

  testWidgets('다시 켜기 전에 러닝이 끝났으면 켜지 않는다', (tester) async {
    start();
    watch.launchResults.add(WatchLaunchResult.notListening);

    session.set(const RunRunning(metrics));
    await tester.pump();
    session.set(const RunIdle());
    await tester.pump(const Duration(seconds: 3));

    expect(watch.launches, 1);
  });

  testWidgets('받기가 실패하면 5초 뒤 다시 듣는다', (tester) async {
    start();
    expect(watch.listens, 1);

    watch.failListening();
    await tester.pump(const Duration(seconds: 5));
    expect(watch.listens, 2);

    // 다시 들은 뒤로는 워치가 보낸 것을 받는다.
    watch.receive('WATCH_SYNC', {
      'syncId': 's-3',
      'watchVersion': watchVersion,
    });
    await tester.pump();
    expect(watch.sent.single.$1, 'WATCH_SYNCED');
  });

  testWidgets('다시 듣기 전에 켜기를 포기했으면 다시 들은 뒤 다시 켠다', (tester) async {
    start();
    // 받기가 실패한 직후 러닝을 시작해, 켜기가 다시 듣기(5초)보다 먼저 끝난다.
    watch.failListening();
    await tester.pump();
    watch.launchResults.addAll(List.filled(4, WatchLaunchResult.notListening));
    session.set(const RunRunning(metrics));

    await tester.pump(const Duration(seconds: 4));
    expect(watch.launches, 4);

    await tester.pump(const Duration(seconds: 1));
    expect(watch.listens, 2);
    expect(watch.launches, 5);
  });

  testWidgets('앞 전송이 안 끝났으면 그 초를 버리지 않고 끝나는 대로 최신 하나를 보낸다', (tester) async {
    start();
    session.set(runningAt(420));
    // 화면이 켜졌다는 알림에 답하는 요청이 끝내 답을 못 받는다.
    watch.holdNextSend = true;
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();
    final held = watch.states.length;

    // 답을 기다리는 동안 바뀐 시간은 미뤄 둔다.
    session.set(runningAt(421));
    session.set(runningAt(422));
    await tester.pump(const Duration(seconds: 1));
    expect(watch.states, hasLength(held));

    // 3초가 지나 실패로 보면 미뤄 둔 것 중 최신 하나만 보낸다.
    await tester.pump(const Duration(seconds: 3));
    expect(watch.states, hasLength(held + 1));
    expect(secondsOf(watch.states.last), 422);

    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': false});
    await tester.pump();
  });

  testWidgets('미뤄 둔 전송은 워치 화면이 꺼지면 버린다', (tester) async {
    start();
    session.set(runningAt(420));
    watch.holdNextSend = true;
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': true});
    await tester.pump();
    final held = watch.states.length;

    session.set(runningAt(421));
    watch.receive('WATCH_VISIBILITY_UPDATE', {'isVisible': false});
    await tester.pump();

    // 붙잡힌 전송이 3초 뒤 실패로 끝나도 화면이 꺼진 워치엔 더 보내지 않는다.
    await tester.pump(const Duration(seconds: 4));
    expect(watch.states, hasLength(held));
  });

  testWidgets('통로가 없으면(테스트·iOS) 러닝이 돌아도 오류 없이 지나간다', (tester) async {
    start(withWatch: false);

    session.set(const RunRunning(metrics));
    party.set(
      const PartyBoard().withCombos(
        const RunCombo([
          ComboPeer(
            userId: 'u-1',
            gapMeters: 10,
            comboCount: 1,
            maxComboCount: 1,
          ),
        ]),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });

  group('워치 명령', () {
    /// 방이 세워지고 달리는 중이다. 첫 상태가 워치로 나간다.
    ProviderContainer startRunning() {
      final container = start();
      connection.set(const RunningConnectionState(room: room));
      session.set(const RunRunning(metrics));
      return container;
    }

    /// 지금 워치가 본 값으로 만든 명령.
    Map<String, dynamic> command(
      String requestId, [
      Map<String, dynamic> extra = const {},
    ]) {
      final state = watch.states.last;
      final run = state['run'] as Map<String, Object?>?;
      return {
        'requestId': requestId,
        'phoneInstanceId': state['phoneInstanceId'],
        'runningRoomId': run?['runningRoomId'],
        'statusVersion': state['statusVersion'],
        ...extra,
      };
    }

    /// 워치 화면이 지나간 단계. 같은 단계가 이어지면 한 번만 센다.
    List<String> stages() {
      final seen = <String>[];
      for (final state in watch.states) {
        final run = state['run'] as Map<String, Object?>?;
        final finish = run?['finish'] as Map<String, Object?>?;
        final stage = (finish?['stage'] ?? run?['status'] ?? 'NONE') as String;
        if (seen.isEmpty || seen.last != stage) seen.add(stage);
      }
      return seen;
    }

    /// 거절됐고 워치 디코더가 읽을 수 있는 모양이다. 필드가 비면 통째로 버려진다.
    void expectRejected(String code, {String sourceType = 'WATCH_PAUSE'}) {
      final error = watch.errors.single;
      expect(error['code'], code);
      expect(error['message'], isA<String>());
      expect(error['sourceType'], sourceType);
      expect(error['requestId'], 'a');
    }

    testWidgets('일시정지를 받으면 멈추고 명령 번호를 실은 상태를 바로 보낸다', (tester) async {
      startRunning();
      final version = watch.states.last['statusVersion']! as int;

      watch.receive('WATCH_PAUSE', command('a'));
      await tester.pump();

      expect(session.current, isA<RunPaused>());
      expect(watch.states.last['statusVersion'], version + 1);
      expect(watch.states.last['lastRequestId'], 'a');
      expect(runOf(watch.states.last)['status'], 'PAUSED');
    });

    testWidgets('서버에 알리는 순서는 폰 버튼과 같다', (tester) async {
      startRunning();

      watch.receive('WATCH_PAUSE', command('a'));
      await tester.pump();
      watch.receive('WATCH_RESUME', command('b'));
      await tester.pump();

      expect(calls, [
        'session.pause',
        'connection.pause',
        'connection.resume',
        'session.resume',
      ]);
      expect(runOf(watch.states.last)['status'], 'RUNNING');
      expect(watch.states.last['lastRequestId'], 'b');
    });

    testWidgets('달리는 중에 재개가 오면 서버로 보내지 않고 답만 한다', (tester) async {
      startRunning();
      final sent = watch.states.length;
      final version = watch.states.last['statusVersion'];

      watch.receive('WATCH_RESUME', command('a'));
      await tester.pump();

      expect(calls, isEmpty);
      expect(watch.states, hasLength(sent + 1));
      expect(watch.states.last['statusVersion'], version);
      expect(watch.states.last['lastRequestId'], 'a');
    });

    testWidgets('같은 명령이 두 번 와도 한 번만 처리하고 상태로 다시 답한다', (tester) async {
      startRunning();
      final pause = command('a');

      watch.receive('WATCH_PAUSE', pause);
      await tester.pump();
      final sent = watch.states.length;
      watch.receive('WATCH_PAUSE', pause);
      await tester.pump();

      expect(calls, ['session.pause', 'connection.pause']);
      expect(watch.errors, isEmpty);
      expect(watch.states, hasLength(sent + 1));
      expect(watch.states.last['lastRequestId'], 'a');
    });

    testWidgets('requestId 가 없으면 답할 수 없어 무시한다', (tester) async {
      startRunning();
      final sent = watch.sent.length;

      watch.receive('WATCH_PAUSE', {'statusVersion': 1});
      await tester.pump();

      expect(session.current, isA<RunRunning>());
      expect(watch.sent, hasLength(sent));
    });

    group('거절', () {
      testWidgets('러닝이 없으면', (tester) async {
        startRunning();
        final pause = command('a');
        session.set(const RunIdle());

        watch.receive('WATCH_PAUSE', pause);
        await tester.pump();

        expectRejected('NO_RUN');
      });

      testWidgets('러닝이 끝났으면', (tester) async {
        startRunning();
        final finish = command('a', {'forced': false});
        session.set(
          RunFinished(
            metrics: metrics,
            startedAt: DateTime(2026, 11, 4, 8),
            endedAt: DateTime(2026, 11, 4, 9),
          ),
        );

        watch.receive('WATCH_FINISH', finish);
        await tester.pump();

        expectRejected('NO_RUN', sourceType: 'WATCH_FINISH');
        expect(connection.finishes, isEmpty);
      });

      testWidgets('로그인이 만료됐으면', (tester) async {
        startRunning();
        auth.set(const AuthSignedOut(returning: true));

        watch.receive('WATCH_PAUSE', command('a'));
        await tester.pump();

        expectRejected('NOT_RUN_OWNER');
        expect(session.current, isA<RunRunning>());
      });

      testWidgets('다른 계정이 로그인했으면', (tester) async {
        startRunning();
        auth.set(const AuthSignedIn('other', isOnboarded: true));

        watch.receive('WATCH_PAUSE', command('a'));
        await tester.pump();

        expectRejected('NOT_RUN_OWNER');
      });

      testWidgets('폰 앱이 다시 켜졌으면', (tester) async {
        startRunning();

        watch.receive(
          'WATCH_PAUSE',
          command('a', {'phoneInstanceId': 'before'}),
        );
        await tester.pump();

        expectRejected('OTHER_PHONE_INSTANCE');
      });

      testWidgets('누른 뒤 폰에서 먼저 눌렀으면', (tester) async {
        startRunning();
        final pause = command('a');
        session.set(const RunPaused(metrics));
        final sent = watch.states.length;

        watch.receive('WATCH_PAUSE', pause);
        await tester.pump();

        expectRejected('STALE_STATUS');
        expect(watch.states, hasLength(sent));
      });

      testWidgets('다른 방의 명령이면', (tester) async {
        startRunning();

        watch.receive('WATCH_PAUSE', command('a', {'runningRoomId': 1}));
        await tester.pump();

        expectRejected('OTHER_ROOM');
      });
    });

    testWidgets('같은 계정으로 다시 로그인하면 다시 받는다', (tester) async {
      startRunning();
      auth.set(const AuthSignedOut(returning: true));
      auth.set(const AuthSignedIn('me', isOnboarded: true));

      watch.receive('WATCH_PAUSE', command('a'));
      await tester.pump();

      expect(session.current, isA<RunPaused>());
    });

    testWidgets('다음 러닝을 다른 계정이 시작하면 그 계정의 명령을 받는다', (tester) async {
      startRunning();
      session.set(const RunIdle());
      auth.set(const AuthSignedIn('other', isOnboarded: true));
      session.set(const RunRunning(metrics));

      watch.receive('WATCH_PAUSE', command('a'));
      await tester.pump();

      expect(watch.errors, isEmpty);
      expect(session.current, isA<RunPaused>());
    });

    testWidgets('연결이 방을 비운 사이에도 이번 방의 명령을 받는다', (tester) async {
      startRunning();
      final pause = command('a');
      connection.set(const RunningConnectionState());

      watch.receive('WATCH_PAUSE', pause);
      await tester.pump();

      expect(watch.errors, isEmpty);
      expect(session.current, isA<RunPaused>());
    });

    testWidgets('명령의 방 번호가 없으면 방 비교만 건너뛴다', (tester) async {
      startRunning();

      watch.receive('WATCH_PAUSE', command('a', {'runningRoomId': null}));
      await tester.pump();

      expect(watch.errors, isEmpty);
      expect(session.current, isA<RunPaused>());
    });

    group('종료', () {
      testWidgets('첫 상태에 종료 중과 명령 번호를 싣고 번호는 한 번만 오른다', (tester) async {
        startRunning();
        final sent = watch.states.length;
        final version = watch.states.last['statusVersion']! as int;

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();

        expect(watch.states, hasLength(sent + 1));
        expect(runOf(watch.states.last)['finish'], {'stage': 'FINISHING'});
        expect(watch.states.last['lastRequestId'], 'a');
        expect(watch.states.last['statusVersion'], version + 1);
        expect(connection.finishes, [false]);
      });

      testWidgets('확정되면 달리는 중을 거치지 않고 받는 중으로 끝난다', (tester) async {
        startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        connection.answer(const FinishConfirmed());
        await tester.pump();

        expect(stages(), ['RUNNING', 'FINISHING', 'FINISHED']);
        final first = watch.states.firstWhere(
          (state) => runOf(state)['status'] == 'FINISHED',
        );
        expect(
          runOf(first)['result'],
          isNull,
          reason: '폰 값이 먼저 나가면 서버 기록이 오며 숫자가 바뀐다',
        );
      });

      testWidgets('답을 못 받으면 폰이 잰 값으로 끝난다', (tester) async {
        startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        connection.answer(const FinishUnconfirmed());
        await tester.pump();

        final result = runOf(watch.states.last)['result'];
        expect(result, containsPair('isServerConfirmed', false));
      });

      testWidgets('보류면 달리는 중을 거치지 않고 남은 거리를 싣는다', (tester) async {
        startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        connection.answer(const FinishGoalPending(420));
        await tester.pump();

        expect(stages(), ['RUNNING', 'FINISHING', 'GOAL_PENDING']);
        expect(runOf(watch.states.last)['finish'], {
          'stage': 'GOAL_PENDING',
          'remainingMeters': 420,
        });
        expect(session.current, isA<RunRunning>());
      });

      testWidgets('서버가 거절하면 달리는 중으로 돌아오고 ERROR 는 없다', (tester) async {
        startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        connection.answer(const FinishRejected(WsErrorCode.invalidRoomState));
        await tester.pump();

        expect(stages(), ['RUNNING', 'FINISHING', 'RUNNING']);
        expect(watch.errors, isEmpty);
      });

      testWidgets('정리가 던져도 끝낸다 — 워치가 종료 중에 갇히지 않는다', (tester) async {
        final container = startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        connection.failFinish();
        await tester.pump();

        expect(session.current, isA<RunFinished>());
        expect(container.read(runControlProvider).finishing, isFalse);
      });

      testWidgets('서버가 이미 끝내는 중이면 또 보내지 않고 답만 한다', (tester) async {
        startRunning();
        connection.set(connection.current.copyWith(settling: true));

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();

        expect(connection.finishes, isEmpty);
        expect(watch.states.last['lastRequestId'], 'a');
      });

      testWidgets('⚠️ 이전 러닝의 늦은 답은 새 러닝을 끝내지 않는다', (tester) async {
        final container = startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        session.set(const RunIdle());
        session.set(const RunRunning(metrics));
        connection.answer(const FinishUnconfirmed());
        await tester.pump();

        expect(session.current, isA<RunRunning>());
        expect(container.read(runControlProvider).finishing, isFalse);
      });

      testWidgets('⚠️ 이전 러닝의 늦은 실패도 새 러닝을 끝내지 않는다', (tester) async {
        startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        session.set(const RunIdle());
        session.set(const RunRunning(metrics));
        connection.failFinish();
        await tester.pump();

        expect(session.current, isA<RunRunning>());
      });

      testWidgets('답을 기다리는 동안 일시정지는 답만 한다', (tester) async {
        startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        watch.receive('WATCH_PAUSE', command('b'));
        await tester.pump();

        expect(calls, isEmpty);
        expect(watch.states.last['lastRequestId'], 'b');
      });

      testWidgets('⚠️ 서버가 끝내는 중이면 일시정지·재개는 답만 한다', (tester) async {
        startRunning();
        connection.set(connection.current.copyWith(settling: true));

        watch.receive('WATCH_PAUSE', command('a'));
        await tester.pump();

        expect(calls, isEmpty);
        expect(watch.states.last['lastRequestId'], 'a');

        session.set(const RunPaused(metrics));
        watch.receive('WATCH_RESUME', command('b'));
        await tester.pump();

        expect(calls, isEmpty);
        expect(session.current, isA<RunPaused>());
      });

      testWidgets('기다리는 사이 세션이 비워지면 상태를 더 쓰지 않는다', (tester) async {
        final container = startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        session.set(const RunIdle());
        connection.answer(const FinishRejected(WsErrorCode.invalidRoomState));
        await tester.pump();

        expect(container.read(runControlProvider).rejectedCode, isNull);
      });
    });

    group('forced', () {
      testWidgets('거리를 아는 동안은 워치가 정한 값을 쓴다', (tester) async {
        startRunning();

        watch.receive('WATCH_FINISH', command('a', {'forced': true}));
        await tester.pump();

        expect(connection.finishes, [true]);
      });

      testWidgets('복구 중이라 거리를 모르면 조기 종료로 보내지 않는다', (tester) async {
        startRunning();
        session.distanceUnknown = true;

        watch.receive('WATCH_FINISH', command('a', {'forced': true}));
        await tester.pump();

        expect(connection.finishes, [false]);
      });

      testWidgets('보류 중이면 폰 창의 종료하기처럼 true 로 보낸다', (tester) async {
        startRunning();
        session.distanceUnknown = true;
        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        connection.answer(const FinishGoalPending(420));
        await tester.pump();

        watch.receive('WATCH_FINISH', command('b', {'forced': false}));
        await tester.pump();

        expect(connection.finishes, [false, true]);
        expect(runOf(watch.states.last)['finish'], {'stage': 'FINISHING'});
      });
    });

    group('보류', () {
      /// 폰 버튼으로 끝내려다 보류된 상태까지 세운다.
      Future<ProviderContainer> pending(WidgetTester tester) async {
        final container = startRunning();
        unawaited(
          container.read(runControlProvider.notifier).finish(forced: false),
        );
        connection.answer(const FinishGoalPending(420));
        await tester.pump();
        return container;
      }

      testWidgets('폰 버튼으로 난 보류도 워치에 실린다', (tester) async {
        await pending(tester);

        expect(stages(), ['RUNNING', 'FINISHING', 'GOAL_PENDING']);
        expect(watch.states.last['lastRequestId'], isNull);
      });

      testWidgets('일시정지해도 보류를 싣고 번호가 오른다', (tester) async {
        await pending(tester);
        final version = watch.states.last['statusVersion']! as int;

        watch.receive('WATCH_PAUSE', command('a'));
        await tester.pump();

        final run = runOf(watch.states.last);
        expect(run['status'], 'PAUSED');
        expect(run['finish'], containsPair('stage', 'GOAL_PENDING'));
        expect(watch.states.last['statusVersion'], version + 1);
      });

      testWidgets('폰 창에서 계속 달리기를 고르면 거두고 번호가 오른다', (tester) async {
        final container = await pending(tester);
        final version = watch.states.last['statusVersion']! as int;

        container.read(runControlProvider.notifier).keepRunning();

        expect(runOf(watch.states.last)['finish'], isNull);
        expect(watch.states.last['statusVersion'], version + 1);
      });

      testWidgets('다시 종료해 답을 기다리는 동안 계속 달리기는 끼어들지 못한다', (tester) async {
        final container = await pending(tester);

        watch.receive('WATCH_FINISH', command('a', {'forced': false}));
        await tester.pump();
        container.read(runControlProvider.notifier).keepRunning();

        expect(container.read(runControlProvider).finishing, isTrue);
        expect(runOf(watch.states.last)['finish'], {'stage': 'FINISHING'});
      });

      testWidgets('다음 러닝에 남지 않는다', (tester) async {
        final container = await pending(tester);

        session.set(const RunIdle());
        session.set(const RunRunning(metrics));

        expect(container.read(runControlProvider).goalPendingMeters, isNull);
        expect(runOf(watch.states.last)['finish'], isNull);
      });
    });
  });
}

/// 남겨 둔 값 읽기를 [held] 가 끝날 때까지 잡아 둔다.
class _HeldWatchVersionStore implements WatchVersionStore {
  final held = Completer<AppVersion?>();

  @override
  Future<AppVersion?> minimum() => held.future;

  @override
  Future<void> rememberMinimum(AppVersion minimum) async {}
}

class _Watch implements WatchChannel {
  late final _incoming = StreamController<WatchMessage>.broadcast(
    onListen: () => listens++,
  );
  final sent = <(String, Map<String, Object?>)>[];
  var launches = 0;

  /// 받기를 몇 번 걸었나. 다시 구독하면 오른다.
  var listens = 0;

  /// 켜기마다 차례로 돌려줄 결과. 비면 [WatchLaunchResult.launched].
  final launchResults = <WatchLaunchResult>[];

  /// 참이면 다음 보내기 요청 하나에 끝내 답하지 않는다(Play 서비스가 알림을 안 줌).
  var holdNextSend = false;

  void receive(String event, Map<String, dynamic> data) =>
      _incoming.add(WatchMessage(event: event, data: data));

  /// 네이티브 받기 등록이 실패했다(`LISTEN_FAILED`).
  void failListening() => _incoming.addError(Exception('LISTEN_FAILED'));

  List<Map<String, Object?>> get states => [
    for (final (event, data) in sent)
      if (event == 'WATCH_STATE_UPDATED') data,
  ];

  List<Map<String, Object?>> get combos => [
    for (final (event, data) in sent)
      if (event == 'WATCH_COMBO_TRIGGERED') data,
  ];

  List<Map<String, Object?>> get errors => [
    for (final (event, data) in sent)
      if (event == 'ERROR') data,
  ];

  @override
  Stream<WatchMessage> get messages => _incoming.stream;

  @override
  Future<WatchSendResult> send(String event, Map<String, Object?> data) {
    // 진짜 통로처럼 JSON으로 바꿔 본다. 못 바꾸는 값이 섞이면 여기서 던진다.
    jsonEncode(data);
    sent.add((event, data));
    if (holdNextSend) {
      holdNextSend = false;
      return Completer<WatchSendResult>().future;
    }
    return Future.value(WatchSendResult.sent);
  }

  @override
  Future<WatchLaunchResult> launchApp() async {
    launches++;
    return launchResults.isEmpty
        ? WatchLaunchResult.launched
        : launchResults.removeAt(0);
  }
}

/// 주소를 그대로 담은 글자를 사진 대신 돌려준다.
class _Photos implements WatchPhotoMaker {
  /// 받으려 한 주소, 부른 순서대로.
  final asked = <String>[];

  /// 다음 한 번은 못 받는 주소.
  final failing = <String>{};

  /// 다음 한 번은 테스트가 끝낼 때까지 붙잡는 주소. 붙잡은 받기는 [held] 에 있다.
  final holding = <String>{};
  final held = <String, Completer<String>>{};

  @override
  Future<String> jpegBase64(String url) async {
    asked.add(url);
    if (failing.remove(url)) throw StateError('사진을 못 받았다');
    if (holding.remove(url)) return (held[url] = Completer<String>()).future;
    return 'jpeg:$url';
  }
}

class _Session extends RunSessionController {
  _Session(this.calls);

  final List<String> calls;

  /// 복구 중이라 거리를 모르는가.
  var distanceUnknown = false;

  @override
  RunSessionState build() => const RunIdle();

  RunSessionState get current => state;

  void set(RunSessionState next) => state = next;

  @override
  bool get awaitingDistanceSeed => distanceUnknown;

  @override
  void pause() {
    calls.add('session.pause');
    state = RunPaused((state as RunRunning).metrics);
  }

  @override
  void resume() {
    calls.add('session.resume');
    state = RunRunning((state as RunPaused).metrics);
  }

  @override
  void finish() {
    final metrics = switch (state) {
      RunRunning(:final metrics) || RunPaused(:final metrics) => metrics,
      _ => const RunMetrics(distanceMeters: 0, elapsed: Duration.zero),
    };
    state = RunFinished(
      metrics: metrics,
      startedAt: DateTime(2026, 11, 4, 8),
      endedAt: DateTime(2026, 11, 4, 9),
    );
  }
}

class _Connection extends RunningConnectionController {
  _Connection(this.calls);

  final List<String> calls;

  /// 보낸 종료의 `forced`.
  final finishes = <bool>[];

  Completer<FinishOutcome>? _answer;

  @override
  RunningConnectionState build() => const RunningConnectionState();

  RunningConnectionState get current => state;

  void set(RunningConnectionState next) => state = next;

  void answer(FinishOutcome outcome) => _answer!.complete(outcome);

  void failFinish() => _answer!.completeError(StateError('저장 실패'));

  @override
  Future<void> pause() async => calls.add('connection.pause');

  @override
  void resume() => calls.add('connection.resume');

  /// 진짜와 같은 순서로 상태를 바꾼다. 이어지면 `settling` 만 내리고, 끝나면 통째로
  /// 비웠다가 방을 되돌린다.
  @override
  Future<FinishOutcome> finish({bool forced = false}) async {
    finishes.add(forced);
    state = state.copyWith(settling: true);
    final answer = _answer = Completer<FinishOutcome>();
    final FinishOutcome outcome;
    try {
      outcome = await answer.future;
    } on Object {
      _clear(finished: false);
      rethrow;
    }
    if (outcome is FinishGoalPending || outcome is FinishRejected) {
      state = state.copyWith(settling: false);
    } else {
      _clear(finished: outcome is FinishConfirmed);
    }
    return outcome;
  }

  void _clear({required bool finished}) {
    final room = state.room;
    state = const RunningConnectionState();
    state = RunningConnectionState(
      room: room,
      finishedRoomId: finished ? room?.id : null,
    );
  }
}

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn('me', isOnboarded: true);

  void set(AuthState next) => state = next;
}

class _Party extends PartyController {
  @override
  PartyBoard build() => const PartyBoard();

  PartyBoard get current => state;

  void set(PartyBoard next) => state = next;
}
