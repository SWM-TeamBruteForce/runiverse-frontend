import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 붙을 때마다 액세스 토큰을 주는 함수.
///
/// [refresh]가 `true`면 **갱신해서** 새 토큰을 준다. 못 주면 `null`이고,
/// 그때는 재로그인 말고는 방법이 없다.
///
/// 함수로 받는 이유는 [WsClient]가 인증을 몰라도 되게 하기 위해서다 —
/// 어디에 저장하고 어떻게 갱신하는지는 부르는 쪽이 안다.
typedef WsAccessToken = Future<String?> Function({bool refresh});

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
///
/// ## 핸드셰이크 401은 갱신하고 한 번만 다시 붙는다
///
/// 토큰이 만료된 채로 붙으면 서버가 `101`이 아니라 `401`로 답한다. 그것을
/// 여느 실패처럼 다루면 **같은 죽은 토큰으로 30초마다 영원히 두드리게 된다.**
/// 갱신해서 곧바로 한 번 다시 붙고, 그래도 401이면 [WsConnectionState.closed]로
/// 간다 — 그다음은 재로그인이다.
class WsClient {
  WsClient({
    required this.url,
    required this.token,
    this.healthCheckInterval = const Duration(seconds: 30),
    this.connect = _connectIo,
  });

  /// `wss://host/api/v1/ws/running`
  final String url;

  /// 붙을 때마다 액세스 토큰을 준다.
  ///
  /// 핸드셰이크에서 **한 번만** 검증된다. 연결 중 만료돼도 끊기지 않는다.
  /// 다만 **끊겨서 다시 붙을 때는 새로 물어본다** — 30분을 달리면 처음 받은
  /// 토큰이 그때는 죽어 있을 수 있다.
  final WsAccessToken token;

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

  /// 다음에 붙을 때 토큰을 갱신해서 받아야 하는가.
  var _needsFreshToken = false;

  /// 이번 연결 시도에서 이미 갱신을 써봤는가.
  ///
  /// **한 번뿐이다.** 갱신하고도 401이면 토큰 문제가 아니라 계정 문제다.
  /// 계속 시도하면 갱신 API만 두드리게 된다.
  var _refreshed = false;

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

  /// 봉투를 보낸다. **소켓에 넘겼으면 `true`.**
  ///
  /// 큐에 쌓지 않는 이유는, 좌표를 다시 보내는 책임이 위 계층에 있어서다 —
  /// 재연결하면 로컬 트랙을 겹쳐서 다시 보낸다. 여기서도 쌓아두면 같은
  /// 좌표가 두 경로로 나간다.
  ///
  /// ## ⚠️ `false`를 무시하면 좌표가 사라진다
  ///
  /// 끊겨 있으면 버리므로, 부르는 쪽이 그것을 모르고 "어디까지 보냈다"를
  /// 앞으로 옮기면 **그 구간이 영영 안 간다.** 서버는 그 자리를 직선으로 이어
  /// 거리를 짧게 계산하고, 사용자가 뛴 만큼 기록이 안 나온다.
  ///
  /// ## `true`가 "서버가 받았다"는 뜻은 아니다
  ///
  /// `RUNNING_LOCATION_UPDATE`에는 ack가 없다. 여기서 알 수 있는 것은
  /// **소켓에 넘겼다**까지다. TCP 위에 있어 연결이 살아 있는 동안 넘긴 것은
  /// 사실상 도착하지만, 끊기던 순간 날아가던 것은 유실될 수 있다 —
  /// 그래서 재연결 때 겹쳐서 다시 보낸다.
  bool send(WsMessage message) {
    final channel = _channel;
    if (channel == null || !isConnected) return false;
    channel.sink.add(message.encode());
    return true;
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

    // ⚠️ **붙을 때마다 새로 물어본다.** 한 번 받아 들고 있으면 30분짜리
    // 러닝 중에 재연결할 때 이미 죽은 토큰을 쓰게 된다.
    final accessToken = await token(refresh: _needsFreshToken);
    _needsFreshToken = false;

    if (accessToken == null) {
      // 줄 토큰이 없다. 재연결해도 같으므로 멈춘다.
      debugPrint('[ws] 토큰이 없다. 재연결하지 않는다');
      _moveTo(WsConnectionState.closed);
      return;
    }

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
      _refreshed = false;
      _moveTo(WsConnectionState.connected);
      _startHealthCheck();
    } on Object catch (error) {
      // 핸드셰이크 실패. 401도 여기로 온다.
      if (_isUnauthorized(error)) {
        await _onUnauthorized();
        return;
      }
      _onDone(error);
    }
  }

  /// 핸드셰이크가 401로 거절됐다.
  ///
  /// 갱신하고 **backoff 없이 곧바로** 다시 붙는다. 갱신은 왕복 한 번이고,
  /// 사용자는 출발 카운트다운 앞에서 기다리는 중이다.
  Future<void> _onUnauthorized() async {
    _channel = null;

    if (_refreshed) {
      debugPrint('[ws] 갱신하고도 401이다. 재로그인이 필요하다');
      _moveTo(WsConnectionState.closed);
      return;
    }

    debugPrint('[ws] 401 · 토큰을 갱신하고 다시 붙는다');
    _refreshed = true;
    _needsFreshToken = true;
    if (!_closedByUs) await _attach();
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

  /// 핸드셰이크가 401로 거절됐는가.
  ///
  /// ## ⚠️ 메시지를 문자열로 뒤지지 않는다
  ///
  /// `dart:io`의 [WebSocketException]이 **`httpStatusCode`를 필드로 들고 있다.**
  /// 메시지("...was not upgraded to websocket")를 파싱하면 SDK가 문구를 바꿀 때
  /// 조용히 망가진다.
  ///
  /// `ready`가 실패하면 `web_socket_channel`이 원본을
  /// [WebSocketChannelException]으로 감싸므로 `inner`를 한 겹 벗긴다.
  /// 감싸지 않는 경로도 있어 둘 다 받는다.
  static bool _isUnauthorized(Object error) {
    final inner = error is WebSocketChannelException ? error.inner : error;
    return inner is WebSocketException &&
        inner.httpStatusCode == HttpStatus.unauthorized;
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
