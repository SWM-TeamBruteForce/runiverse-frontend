import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';

/// [WsClient] 위에 러닝 계약을 얹는다.
///
/// **아래(`WsClient`)는 봉투만 알고, 위(화면)는 러닝만 안다.** 이 클래스가 둘을 잇는다.
///
/// ## 재연결하면 `RUNNING_START`를 다시 보낸다
///
/// 서버는 최초 진입과 재연결을 같은 메시지로 받고 **멱등하게** 처리한다.
/// 끊겼다 붙을 때마다 다시 보내지 않으면, 서버는 이 사용자의 WS 세션을
/// 새로 등록하지 못한다.
class WsRunningChannel implements RunningChannel {
  WsRunningChannel(this._client) {
    _messages = _client.messages.listen(_onMessage);
    _connections = _client.states.listen(_onState);
  }

  final WsClient _client;

  late final StreamSubscription<WsMessage> _messages;
  late final StreamSubscription<WsConnectionState> _connections;

  final _errors = StreamController<WsErrorCode>.broadcast();

  /// 어느 방에서 달리는가. 재연결 때 `RUNNING_START`를 다시 보내려면 필요하다.
  int? _roomId;

  /// 방금 연결된 것이 재연결인가. 첫 연결에서는 [start]가 직접 보낸다.
  var _wasConnected = false;

  @override
  Stream<WsConnectionState> get states => _client.states;

  @override
  WsConnectionState get state => _client.state;

  @override
  Stream<WsErrorCode> get errors => _errors.stream;

  @override
  Future<void> start(int runningRoomId) async {
    _roomId = runningRoomId;
    await _client.open();
    _sendStart();
  }

  @override
  Future<void> close() async {
    _roomId = null;
    _wasConnected = false;
    await _messages.cancel();
    await _connections.cancel();
    await _errors.close();
    await _client.dispose();
  }

  // ── 안쪽 ──────────────────────────────────────────────────

  void _sendStart() {
    final roomId = _roomId;
    if (roomId == null) return;
    _client.send(WsMessage(WsEvents.runningStart, {'runningRoomId': roomId}));
  }

  void _onState(WsConnectionState state) {
    if (state != WsConnectionState.connected) {
      // 끊겼다. 다음에 붙으면 그것은 재연결이다.
      if (state == WsConnectionState.reconnecting) _wasConnected = true;
      return;
    }
    // ⚠️ **재연결이면 `RUNNING_START`를 다시 보낸다.** 첫 연결은 [start]가
    // 이미 보냈으므로 두 번 보내지 않는다.
    if (_wasConnected) {
      _wasConnected = false;
      _sendStart();
    }
  }

  void _onMessage(WsMessage message) {
    switch (message.event) {
      case WsEvents.runningStarted:
        // ack다. 지금은 `data`가 비어 있어 확인할 것이 없다.
        debugPrint('[running] 시작 확인');

      case WsEvents.error:
        final code = WsErrorCode.fromWire(message.data['code']);
        // ⚠️ **연결을 끊지 않는다.** 명세가 "오류를 보낸 뒤 연결은 유지한다"고
        // 정했다. 여기서 끊으면 좌표 하나가 잘못됐을 때 러닝 전체가 죽는다.
        debugPrint('[running] 서버 거절 · $code');
        if (!_errors.isClosed) _errors.add(code);

      default:
        // 아직 다루지 않는 이벤트. 서버가 늘려도 앱이 죽지 않아야 한다.
        debugPrint('[running] 다루지 않는 이벤트 · ${message.event}');
    }
  }
}
