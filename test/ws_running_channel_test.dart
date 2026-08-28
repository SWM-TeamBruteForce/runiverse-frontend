import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/data/ws_running_channel.dart';
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

    test('RUNNING_FINISHED를 받으면 true다', () async {
      await channel.start(roomId);

      final finishing = channel.finish();
      await receive('RUNNING_FINISHED');

      expect(await finishing, isTrue);
    });

    test('⚠️ 확인이 안 오면 기다리다 false다', () async {
      // 여기서 매달리면 소켓이 영영 안 닫힌다.
      await channel.start(roomId);

      expect(await channel.finish(), isFalse);
    });

    test('⚠️ 끊겨 있으면 기다리지 않고 false다', () async {
      // 보내지도 못했으니 ack가 올 리 없다.
      expect(await channel.finish(), isFalse);
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

    test('RUNNING_SESSION_UNAVAILABLE도 다시 보낸다', () async {
      await channel.start(roomId);
      socket.sent.clear();

      await receive('ERROR', {'code': 'RUNNING_SESSION_UNAVAILABLE'});

      expect(sentEvents(), ['RUNNING_START']);
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
