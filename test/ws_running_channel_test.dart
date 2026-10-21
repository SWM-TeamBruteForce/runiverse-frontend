import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/data/ws_running_channel.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 러닝 계약 — **봉투 위에 얹은 규칙이 맞게 도는가.**
///
/// `WsClient`는 봉투만 알고 러닝을 모른다. 러닝 쪽 규칙(시작 재전송, 종료
/// 확인, 세션 없음 복구)은 전부 이 클래스에 있어서 여기서만 검증된다.
///
/// 진짜 소켓을 열지 않는다. `WsClient`가 채널 만드는 함수를 받으므로 가짜를
/// 끼우고, **인코딩까지 진짜 경로로** 돌린다.
void main() {
  const roomId = 42;

  late _FakeChannel socket;
  late WsClient client;
  late WsRunningChannel channel;

  setUp(() {
    client = WsClient(
      url: 'ws://example.test/ws',
      token: ({bool refresh = false}) async => 'token',
      healthCheckInterval: const Duration(hours: 1),
      connect: (url, token) => socket = _FakeChannel(),
    );
    channel = WsRunningChannel(
      client,
      // 15초를 실제로 기다릴 수 없다.
      finishAckTimeout: const Duration(milliseconds: 80),
    );
  });

  tearDown(() => channel.close());

  /// 소켓으로 나간 봉투들의 `event`만.
  List<String> sentEvents() => [
    for (final raw in socket.sent) jsonDecode(raw)['event'] as String,
  ];

  /// 마지막으로 나간 봉투의 `data`.
  Map<String, dynamic> lastData() =>
      (jsonDecode(socket.sent.last) as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

  /// 서버가 보낸 척한다.
  Future<void> receive(String event, [Map<String, dynamic> data = const {}]) {
    socket.emit(jsonEncode({'event': event, 'data': data}));
    return Future<void>.delayed(Duration.zero);
  }

  group('시작', () {
    test('붙으면 RUNNING_START를 보낸다', () async {
      await channel.start(roomId);

      expect(sentEvents(), ['RUNNING_START']);
      expect(lastData()['runningRoomId'], roomId);
    });
  });

  /// 시작 확인이 싣고 오는 번호 — 1.1.1 2절.
  ///
  /// ## ⚠️ 스냅샷과 **따로** 흘려야 한다
  ///
  /// `RunSnapshot.of`는 `runningRoomId`를 못 읽으면 통째로 `null`이다. 명세의
  /// 재연결 payload가 아직 확정되지 않아 몸통이 **번호만 담고 올 수 있는데**,
  /// 둘을 한 길로 묶으면 그때 번호가 조용히 함께 사라진다.
  ///
  /// 사라지면 러닝 중 재설치한 앱이 1번부터 매기고, 그 좌표는 전부 버려지거나
  /// `PAUSE_SEGMENT_DECREASED`로 배치째 거부된다.
  group('시작 확인의 번호', () {
    test('스냅샷과 함께 올라온다', () async {
      await channel.start(roomId);
      final numbers = channel.serverNumbers.first;
      final snapshots = channel.snapshots.first;

      await receive('RUNNING_STARTED', {
        'runningRoomId': roomId,
        'players': <Object>[],
        'nextSequence': 120,
        'pauseSegment': 2,
      });

      expect((await numbers).nextSequence, 120);
      expect((await numbers).pauseSegment, 2);
      expect((await snapshots).runningRoomId, roomId);
    });

    test('⚠️ 스냅샷을 못 읽어도 번호는 올라온다', () async {
      await channel.start(roomId);
      final numbers = channel.serverNumbers.first;
      var sawSnapshot = false;
      channel.snapshots.listen((_) => sawSnapshot = true);

      // 방 번호가 없다. 스냅샷은 통째로 버려진다.
      await receive('RUNNING_STARTED', {
        'nextSequence': 120,
        'pauseSegment': 2,
      });

      expect((await numbers).nextSequence, 120);
      expect(sawSnapshot, isFalse, reason: '스냅샷이 올라오면 이 테스트가 무의미하다');
    });

    test('몸통이 비어 있으면 0이 올라온다', () async {
      // 0은 로컬 번호를 그대로 남긴다. 조용히 아무것도 안 하는 것이 맞다.
      await channel.start(roomId);
      final numbers = channel.serverNumbers.first;

      await receive('RUNNING_STARTED');

      expect(await numbers, RunNumbers.serverZero);
    });
  });

  group('종료', () {
    test('RUNNING_FINISH를 보낸다', () async {
      await channel.start(roomId);

      unawaited(channel.finish());
      await Future<void>.delayed(Duration.zero);

      expect(sentEvents().last, 'RUNNING_FINISH');
      expect(lastData()['forced'], isFalse);
    });

    test('forced를 실어 보낸다', () async {
      await channel.start(roomId);

      unawaited(channel.finish(forced: true));
      await Future<void>.delayed(Duration.zero);

      expect(lastData()['forced'], isTrue);
    });

    test('⚠️ 방 번호를 싣지 않는다', () async {
      // 명세가 그렇게 정했다. RUNNING_START가 정한 방을 끝낸다.
      await channel.start(roomId);

      unawaited(channel.finish());
      await Future<void>.delayed(Duration.zero);

      expect(lastData().containsKey('runningRoomId'), isFalse);
    });

    test('RUNNING_FINISHED를 받으면 확정이다', () async {
      await channel.start(roomId);

      final finishing = channel.finish();
      await receive('RUNNING_FINISHED');

      expect(await finishing, isA<FinishConfirmed>());
    });

    test('⚠️ 확인이 안 오면 기다리다 포기한다', () async {
      // 여기서 매달리면 소켓이 영영 안 닫힌다.
      await channel.start(roomId);

      expect(await channel.finish(), isA<FinishUnconfirmed>());
    });

    test('⚠️ 끊겨 있으면 기다리지 않는다', () async {
      // 보내지도 못했으니 ack가 올 리 없다.
      expect(await channel.finish(), isA<FinishUnconfirmed>());
    });

    group('⚠️ 서버가 스스로 끝낸 경우 — 1.1.0 가이드 3.1', () {
      // ⚠️ **요청 없이도 `RUNNING_FINISHED` 가 온다.** 1.1.0부터 목표 도달
      // 자동 종료는 서버의 몫이다 — 앱은 로컬 거리가 목표를 넘어도 보내지
      // 않는다. 기다리는 쪽이 없으니 **스트림으로 알리지 않으면 아무도
      // 모르고**, 러닝이 끝났는데 화면이 영영 남는다.

      test('요청하지 않았는데 오면 스트림으로 알린다', () async {
        await channel.start(roomId);
        final seen = <void>[];
        channel.finished.listen(seen.add);

        await receive('RUNNING_FINISHED');
        await Future<void>.delayed(Duration.zero);

        expect(seen, hasLength(1));
      });

      test('⚠️ 내가 요청한 종료는 스트림으로 새지 않는다', () async {
        // 한 번의 종료가 **두 길로** 처리되면 트랙을 두 번 지운다.
        await channel.start(roomId);
        final seen = <void>[];
        channel.finished.listen(seen.add);

        final finishing = channel.finish();
        await receive('RUNNING_FINISHED');
        await finishing;
        await Future<void>.delayed(Duration.zero);

        expect(seen, isEmpty);
      });
    });

    group('⚠️ RUNNING_GOAL_PENDING — 1.1.0', () {
      // ⚠️ **이것이 종료가 아니다.** 서버가 확정한 거리가 목표에 모자라다는
      // 뜻이고 러닝은 그대로 간다. `bool` 이던 시절에는 이 답을 표현할 자리가
      // 없어 **"못 받았다"와 같아졌다** — 둘은 정반대로 다뤄야 한다.

      test('남은 거리를 싣고 온다', () async {
        await channel.start(roomId);

        final finishing = channel.finish();
        await receive('RUNNING_GOAL_PENDING', {'remainingMeters': 40});

        final outcome = await finishing;
        expect(outcome, isA<FinishGoalPending>());
        expect((outcome as FinishGoalPending).remainingMeters, 40);
      });

      test('⚠️ 확정과 섞이지 않는다', () async {
        // 보류를 확정으로 읽으면 **로컬 트랙을 지운다.** 되돌릴 수 없다.
        await channel.start(roomId);

        final finishing = channel.finish();
        await receive('RUNNING_GOAL_PENDING', {'remainingMeters': 40});

        expect(await finishing, isNot(isA<FinishConfirmed>()));
      });

      test('⚠️ 남은 거리를 못 읽어도 보류는 보류다', () async {
        // 0 으로 떨어지지만 **확정으로 넘어가지 않는다.** 숫자 하나 때문에
        // 러닝을 끝내 버리는 것이 훨씬 나쁘다.
        await channel.start(roomId);

        final finishing = channel.finish();
        await receive('RUNNING_GOAL_PENDING', {'remainingMeters': null});

        expect(await finishing, isA<FinishGoalPending>());
      });
    });
  });

  group('세션이 없다는 오류', () {
    test('⚠️ RUNNING_NOT_STARTED를 받으면 RUNNING_START를 다시 보낸다', () async {
      // 다시 알리지 않으면 그 뒤 좌표가 전부 같은 오류로 거절되는데,
      // 좌표에는 ack가 없어 앱은 아무것도 모른 채 계속 보낸다.
      await channel.start(roomId);
      socket.sent.clear();

      await receive('ERROR', {
        'code': 'RUNNING_NOT_STARTED',
        'sourceType': 'RUNNING_LOCATION_UPDATE',
      });

      expect(sentEvents(), ['RUNNING_START']);
    });

    test('⚠️ 서버 장애에는 여기서 다시 보내지 않는다', () async {
      // 앱이 이길 수 없는 실패다. 곧바로 다시 보내면 같은 답이 오고, 답마다
      // 다시 보내면 스스로 증폭한다. 간격과 상태 확인이 필요해서 연결을
      // 가진 쪽이 맡는다(`running_connection_provider._restartLater`).
      await channel.start(roomId);
      socket.sent.clear();

      await receive('ERROR', {'code': 'RUNNING_SESSION_UNAVAILABLE'});

      expect(sentEvents(), isEmpty);
    });

    test('⚠️ 방 상태가 어긋나도 여기서 다시 보내지 않는다', () async {
      await channel.start(roomId);
      socket.sent.clear();

      await receive('ERROR', {'code': 'INVALID_ROOM_STATE'});

      expect(sentEvents(), isEmpty);
    });

    test('⚠️ 좌표 저장 실패에는 다시 보내지 않는다', () async {
      // 러닝은 계속된다. 여기서 재시작하면 멀쩡한 세션을 흔든다.
      await channel.start(roomId);
      socket.sent.clear();

      await receive('ERROR', {'code': 'RUNNING_TRACK_UNAVAILABLE'});

      expect(sentEvents(), isEmpty);
    });

    test('오류는 위로 올라간다', () async {
      await channel.start(roomId);
      final seen = <WsErrorCode>[];
      channel.errors.listen(seen.add);

      await receive('ERROR', {'code': 'ROOM_NOT_FOUND'});

      expect(seen, [WsErrorCode.roomNotFound]);
    });
  });

  group('모르는 이벤트', () {
    test('받아도 죽지 않는다', () async {
      // 서버가 메시지를 늘려도 러닝이 멈추면 안 된다.
      await channel.start(roomId);

      await receive('훗날_생길_이벤트');

      expect(channel.state, WsConnectionState.connected);
    });
  });
}

/// 손으로 여닫는 가짜 소켓.
class _FakeChannel implements WebSocketChannel {
  final _incoming = StreamController<dynamic>.broadcast();
  final _sink = _FakeSink();

  List<String> get sent => _sink.sent;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => null;

  void emit(String raw) => _incoming.add(raw);

  @override
  Object? noSuchMethod(Invocation invocation) => null;
}

class _FakeSink implements WebSocketSink {
  final sent = <String>[];

  @override
  void add(dynamic data) => sent.add(data as String);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Object? noSuchMethod(Invocation invocation) => null;
}
