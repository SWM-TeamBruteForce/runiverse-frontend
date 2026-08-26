import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 지금 연결이 어떤 상태인가.
enum WsConnectionState {
  /// 아직 붙지 않았거나 스스로 끊었다.
  disconnected,

  connecting,

  connected,

  /// 끊겼고 다시 붙는 중이다. 화면은 이 상태에서 "연결이 불안정해요"를 보인다.
  reconnecting,

  /// **다시 붙지 않는다.** 다른 기기에서 접속했거나(4001) 인증이 죽었다.
  closed,
}

/// WebSocket 연결 하나를 돌본다.
///
/// **내용을 모른다.** 봉투를 보내고 받을 뿐이라 러닝·매칭 어느 쪽에도 묶이지 않는다.
/// 러닝 계약은 `WsRunningChannel`이 이 위에 얹는다.
///
/// ## 하는 일 셋
///
/// 1. 연결과 인증 — 핸드셰이크에 `Authorization` 헤더를 싣는다
/// 2. 재연결 — 끊기면 backoff로 다시 붙는다
/// 3. 헬스체크 — 주기적으로 `HEALTH_CHECK`를 보내 유휴로 끊기는 것을 막는다
///
/// ## ⚠️ close code 4001은 재연결하지 않는다
///
/// 서버는 **같은 사용자의 마지막 연결만 유지**한다. 다른 기기에서 접속하면
/// 이쪽을 `4001`로 닫는다. 여기서 다시 붙으면 저쪽을 끊고, 저쪽이 또 붙어
/// 이쪽을 끊는 **무한 루프**가 된다. 명세도 재연결하지 말라고 못박았다.
class WsClient {
  WsClient({
    required this.url,
    required this.accessToken,
    this.healthCheckInterval = const Duration(seconds: 30),
    this.connect = _connectIo,
  });

  /// `wss://host/api/v1/ws/running`
  final String url;

  /// 핸드셰이크에서 **한 번만** 검증된다. 연결 중 만료돼도 끊기지 않는다.
  final String accessToken;

  /// 얼마나 자주 `HEALTH_CHECK`를 보내나.
  ///
  /// ⚠️ **서버 유휴 종료 시간보다 짧아야 한다.** 그 값이 운영 설정이라
  /// 앱이 알 수 없다 — 서버와 맞춰야 하는 상수다.
  final Duration healthCheckInterval;

  /// 채널을 만드는 법. **테스트에서 갈아 끼운다.**
  ///
  /// 진짜 소켓을 열지 않고도 재연결·헬스체크를 검증하기 위해 함수로 받는다.
  final WebSocketChannel Function(String url, String accessToken) connect;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _healthCheck;
  Timer? _retry;

  /// 연속 실패 횟수. backoff 간격을 정한다.
  var _attempt = 0;

  /// 스스로 끊었는가. `true`면 재연결하지 않는다.
  var _closedByUs = false;

  final _messages = StreamController<WsMessage>.broadcast();
  final _states = StreamController<WsConnectionState>.broadcast();

  var _state = WsConnectionState.disconnected;

  /// 서버가 보낸 봉투. **`HEALTH_CHECKED`는 걸러서 내보내지 않는다** —
  /// 연결 유지의 부산물이라 위 계층이 알 이유가 없다.
  Stream<WsMessage> get messages => _messages.stream;

  Stream<WsConnectionState> get states => _states.stream;

  WsConnectionState get state => _state;

  bool get isConnected => _state == WsConnectionState.connected;

  /// 붙는다. 이미 붙어 있으면 아무것도 하지 않는다.
  Future<void> open() async {
    if (_state == WsConnectionState.connected ||
        _state == WsConnectionState.connecting) {
      return;
    }
    _closedByUs = false;
    await _attach();
  }

  /// 봉투를 보낸다. 끊겨 있으면 **조용히 버린다.**
  ///
  /// 큐에 쌓지 않는 이유는, 좌표를 다시 보내는 책임이 위 계층에 있어서다 —
  /// 재연결하면 로컬 트랙을 처음부터 다시 보낸다(명세). 여기서도 쌓아두면
  /// 같은 좌표가 두 경로로 나간다.
  void send(WsMessage message) {
    final channel = _channel;
    if (channel == null || !isConnected) return;
    channel.sink.add(message.encode());
  }

  /// 스스로 끊는다. **재연결하지 않는다.**
  Future<void> close() async {
    _closedByUs = true;
    _retry?.cancel();
    await _detach();
    _moveTo(WsConnectionState.disconnected);
  }

  /// 다 쓰고 버린다. 이 객체는 다시 쓰지 못한다.
  Future<void> dispose() async {
    await close();
    await _messages.close();
    await _states.close();
  }

  // ── 안쪽 ──────────────────────────────────────────────────

  Future<void> _attach() async {
    _moveTo(
      _attempt == 0
          ? WsConnectionState.connecting
          : WsConnectionState.reconnecting,
    );

    try {
      final channel = connect(url, accessToken);
      _channel = channel;

      // ⚠️ **`ready`를 기다린다.** 기다리지 않으면 핸드셰이크가 실패해도
      // "연결됨"으로 잘못 알린다 — 401이 그렇게 조용히 묻힌다.
      await channel.ready;

      _subscription = channel.stream.listen(
        _onData,
        onError: (Object error) => _onDone(error),
        onDone: () => _onDone(channel.closeCode),
        cancelOnError: false,
      );

      _attempt = 0;
      _moveTo(WsConnectionState.connected);
      _startHealthCheck();
    } on Object catch (error) {
      // 핸드셰이크 실패. 401도 여기로 온다.
      _onDone(error);
    }
  }

  void _onData(dynamic raw) {
    final message = WsMessage.decode(raw);
    if (message == null) {
      debugPrint('[ws] 해석하지 못한 메시지를 버렸다');
      return;
    }
    // 연결 유지의 부산물이다. 위로 올리지 않는다.
    if (message.event == WsEvents.healthChecked) return;
    _messages.add(message);
  }

  /// 연결이 끝났다. 스스로 끊은 게 아니면 다시 붙는다.
  void _onDone(Object? reason) {
    _healthCheck?.cancel();
    final code = _channel?.closeCode;
    _channel = null;
    _subscription?.cancel();
    _subscription = null;

    if (_closedByUs) return;

    // ⚠️ 다른 기기에서 접속했다. 다시 붙으면 서로 끊는 루프가 된다.
    if (code == _duplicateConnection) {
      debugPrint('[ws] 다른 기기에서 접속했다. 재연결하지 않는다');
      _moveTo(WsConnectionState.closed);
      return;
    }

    debugPrint('[ws] 끊겼다 · code=${code ?? '-'} · $reason');
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _moveTo(WsConnectionState.reconnecting);

    // 1 · 2 · 4 · 8 … 최대 30초. 서버가 죽었을 때 초당 두드리지 않는다.
    final seconds = _attempt >= 5 ? 30 : 1 << _attempt;
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), () {
      if (!_closedByUs) _attach();
    });
  }

  void _startHealthCheck() {
    _healthCheck?.cancel();
    _healthCheck = Timer.periodic(healthCheckInterval, (_) {
      send(const WsMessage(WsEvents.healthCheck));
    });
  }

  Future<void> _detach() async {
    _healthCheck?.cancel();
    _healthCheck = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _moveTo(WsConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// 서버가 중복 연결을 끊을 때 쓰는 close code.
  static const _duplicateConnection = 4001;

  /// 진짜 소켓을 연다.
  ///
  /// `IOWebSocketChannel`을 쓰는 이유는 **핸드셰이크에 헤더를 실을 수 있어서**다.
  /// `WebSocketChannel.connect`는 헤더를 받지 않아 `Authorization`을 넣지 못한다.
  static WebSocketChannel _connectIo(String url, String accessToken) {
    return IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}
