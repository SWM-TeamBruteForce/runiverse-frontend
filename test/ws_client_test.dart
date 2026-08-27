import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket 연결 — **끊겼을 때 무엇을 하는가.**
///
/// 진짜 소켓을 열지 않는다. `WsClient`가 채널 만드는 함수를 인자로 받아서,
/// 여기서는 손으로 여닫는 가짜를 끼운다.
void main() {
  /// 테스트가 마음대로 여닫는 가짜 채널.
  ///
  /// `WebSocketChannel`을 상속하는 대신 필요한 것만 흉내 낸다 —
  /// 진짜를 상속하면 쓰지도 않는 멤버를 잔뜩 채워야 한다.
  late _FakeChannel channel;
  late WsClient client;

  /// 몇 번째 연결인가. 재연결이 실제로 일어났는지 세는 데 쓴다.
  late int connectCalls;

  /// 핸드셰이크에 실려 나간 토큰들. 갱신된 토큰을 쓰는지 보는 데 쓴다.
  late List<String> sentTokens;

  /// 갱신을 몇 번 불렀나. **한 번을 넘으면 안 된다.**
  late int refreshCalls;

  /// `n`번째 연결부터 이 상태코드로 거절한다. 비면 전부 성공한다.
  late List<int?> handshakeStatuses;

  WsClient makeClient({
    Duration healthCheck = const Duration(seconds: 30),
    List<int?> statuses = const [],
    String? refreshedToken = 'fresh',
  }) {
    connectCalls = 0;
    refreshCalls = 0;
    sentTokens = [];
    handshakeStatuses = List.of(statuses);

    return WsClient(
      url: 'ws://example.test/ws',
      token: ({bool refresh = false}) async {
        if (refresh) {
          refreshCalls++;
          return refreshedToken;
        }
        return 'token';
      },
      healthCheckInterval: healthCheck,
      connect: (url, token) {
        sentTokens.add(token);
        final status = connectCalls < handshakeStatuses.length
            ? handshakeStatuses[connectCalls]
            : null;
        connectCalls++;
        channel = _FakeChannel(handshakeStatus: status);
        return channel;
      },
    );
  }

  setUp(() => client = makeClient());
  tearDown(() => client.dispose());

  group('연결', () {
    test('열면 연결된다', () async {
      await client.open();

      expect(client.state, WsConnectionState.connected);
      expect(connectCalls, 1);
    });

    test('이미 붙어 있으면 다시 열지 않는다', () async {
      await client.open();
      await client.open();

      expect(connectCalls, 1);
    });

    test('스스로 닫으면 재연결하지 않는다', () async {
      await client.open();

      await client.close();
      // 재연결이 걸렸다면 이 사이에 붙었을 것이다.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.state, WsConnectionState.disconnected);
      expect(connectCalls, 1);
    });
  });

  group('재연결', () {
    test('끊기면 다시 붙는다', () async {
      await client.open();

      channel.closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.state, WsConnectionState.reconnecting);

      // 첫 재시도는 1초 뒤다.
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(connectCalls, 2);
      expect(client.state, WsConnectionState.connected);
    });

    test('⚠️ 4001을 받으면 재연결하지 않는다', () async {
      // 다른 기기에서 접속했다는 뜻이다. 여기서 다시 붙으면 저쪽을 끊고,
      // 저쪽이 또 붙어 이쪽을 끊는 무한 루프가 된다.
      await client.open();

      channel.closeFromServer(code: 4001);
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(client.state, WsConnectionState.closed);
      expect(connectCalls, 1);
    });
  });

  group('핸드셰이크 401', () {
    test('⚠️ 갱신한 토큰으로 곧바로 다시 붙는다', () async {
      // 갱신하지 않으면 죽은 토큰으로 30초마다 영원히 두드리게 된다.
      client = makeClient(statuses: [401]);

      await client.open();
      // backoff를 기다리지 않는다. 사용자는 카운트다운 앞에 서 있다.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.state, WsConnectionState.connected);
      expect(refreshCalls, 1);
      expect(sentTokens, ['token', 'fresh'], reason: '갱신된 토큰을 써야 한다');
    });

    test('⚠️ 갱신하고도 401이면 멈춘다', () async {
      // 토큰 문제가 아니라 계정 문제다. 계속하면 갱신 API만 두드린다.
      client = makeClient(statuses: [401, 401]);

      await client.open();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(client.state, WsConnectionState.closed);
      expect(refreshCalls, 1, reason: '갱신은 한 번뿐이어야 한다');
      expect(connectCalls, 2);
    });

    test('⚠️ 갱신이 실패하면 붙지 않는다', () async {
      // 재로그인 말고는 방법이 없다. 재연결로 시간을 끌지 않는다.
      client = makeClient(statuses: [401], refreshedToken: null);

      await client.open();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(client.state, WsConnectionState.closed);
      expect(connectCalls, 1, reason: '토큰 없이 소켓을 열면 안 된다');
    });

    test('401이 아닌 실패는 갱신하지 않고 backoff로 간다', () async {
      // 500이나 네트워크 오류에 갱신을 부르면 멀쩡한 토큰을 회전시킨다.
      client = makeClient(statuses: [503]);

      await client.open();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(refreshCalls, 0);
      expect(client.state, WsConnectionState.reconnecting);
    });

    test('⚠️ 다시 붙을 때 토큰을 새로 물어본다', () async {
      // 30분을 달리면 처음 받은 토큰이 재연결 시점에는 죽어 있을 수 있다.
      await client.open();

      channel.closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(sentTokens, hasLength(2), reason: '한 번 받아 들고 있으면 안 된다');
    });
  });

  group('메시지', () {
    test('보낸 봉투가 그대로 나간다', () async {
      await client.open();

      client.send(const WsMessage('RUNNING_START', {'runningRoomId': 7}));

      expect(channel.sent, hasLength(1));
      expect(channel.sent.single, contains('"event":"RUNNING_START"'));
      expect(channel.sent.single, contains('"runningRoomId":7'));
    });

    test('끊겨 있으면 보내지 않는다', () {
      // 큐에 쌓지 않는다. 재전송 책임은 위 계층에 있다.
      client.send(const WsMessage('RUNNING_START'));

      expect(client.state, WsConnectionState.disconnected);
    });

    test('받은 봉투가 올라온다', () async {
      await client.open();
      final received = <WsMessage>[];
      client.messages.listen(received.add);

      channel.emit('{"event":"ERROR","data":{"code":"ROOM_NOT_FOUND"}}');
      await Future<void>.delayed(Duration.zero);

      expect(received.single.event, 'ERROR');
      expect(received.single.data['code'], 'ROOM_NOT_FOUND');
    });

    test('⚠️ HEALTH_CHECKED는 위로 올리지 않는다', () async {
      // 연결 유지의 부산물이다. 위 계층이 알 이유가 없다.
      await client.open();
      final received = <WsMessage>[];
      client.messages.listen(received.add);

      channel.emit('{"event":"HEALTH_CHECKED","data":{}}');
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test('깨진 메시지를 받아도 죽지 않는다', () async {
      await client.open();
      final received = <WsMessage>[];
      client.messages.listen(received.add);

      channel.emit('이건 JSON이 아니다');
      channel.emit('{"data":{}}'); // event가 없다
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      expect(client.state, WsConnectionState.connected);
    });
  });

  group('헬스체크', () {
    test('주기마다 보낸다', () async {
      client = makeClient(healthCheck: const Duration(milliseconds: 50));
      await client.open();

      await Future<void>.delayed(const Duration(milliseconds: 170));

      // 세 번쯤 나갔어야 한다. 정확한 수는 스케줄러에 달려 있어 하한만 본다.
      expect(channel.sent.length, greaterThanOrEqualTo(2));
      expect(channel.sent.first, contains('"event":"HEALTH_CHECK"'));
    });

    test('끊기면 멈춘다', () async {
      client = makeClient(healthCheck: const Duration(milliseconds: 50));
      await client.open();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final before = channel.sent.length;

      await client.close();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(channel.sent.length, before);
    });
  });
}

/// 손으로 여닫는 가짜 채널.
class _FakeChannel implements WebSocketChannel {
  _FakeChannel({this.handshakeStatus});

  /// 핸드셰이크를 이 상태코드로 거절한다. `null`이면 성공한다.
  ///
  /// 진짜 서버가 401을 줄 때와 **같은 모양**으로 실패시킨다 —
  /// `WebSocketChannelException`이 `dart:io`의 `WebSocketException`을 감싸고,
  /// 상태코드는 그 안의 `httpStatusCode`에 있다.
  final int? handshakeStatus;

  final _incoming = StreamController<dynamic>.broadcast();
  final _sink = _FakeSink();

  /// 이 채널로 나간 문자열들.
  List<String> get sent => _sink.sent;

  @override
  Future<void> get ready {
    final status = handshakeStatus;
    if (status == null) return Future<void>.value();
    return Future<void>.error(
      WebSocketChannelException.from(
        WebSocketException('not upgraded', status),
      ),
    );
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => _closeCode;
  int? _closeCode;

  /// 서버가 보낸 척한다.
  void emit(String raw) => _incoming.add(raw);

  /// 서버가 끊은 척한다.
  void closeFromServer({int code = 1006}) {
    _closeCode = code;
    _incoming.close();
  }

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
