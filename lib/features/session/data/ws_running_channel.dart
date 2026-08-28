import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';

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
  WsRunningChannel(
    this._client, {
    this.finishAckTimeout = const Duration(seconds: 15),
  }) {
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

  /// `RUNNING_FINISHED`를 기다리는 쪽. 없으면 종료 중이 아니다.
  Completer<bool>? _finishing;

  /// 종료 확인을 얼마나 기다리나.
  ///
  /// 서버가 트랙으로 기록·splits·S3 업로드까지 만든 뒤에 답한다. 넉넉해야
  /// 하지만, 사용자가 요약 화면에서 이것이 끝나기를 기다리는 것은 아니라
  /// 화면이 막히지는 않는다.
  ///
  /// **테스트가 갈아 끼운다.** 15초를 실제로 기다리게 할 수 없다.
  final Duration finishAckTimeout;

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
  bool sendLocations(List<TrackPoint> points) {
    if (points.isEmpty) return true;
    return _client.send(
      WsMessage(WsEvents.runningLocationUpdate, {
        // ⚠️ **`runningRoomId`가 여기 없다.** 방 번호는 `RUNNING_START`에서
        // 한 번만 보내고, 서버가 WS 세션에서 알아낸다(설계 문서 6절).
        'locations': [for (final point in points) point.toJson()],
      }),
    );
  }

  @override
  Future<bool> finish({bool forced = false}) {
    // 소켓에 못 넘겼으면 ack가 올 리 없다. 기다리지 않는다.
    if (!_client.send(WsMessage(WsEvents.runningFinish, {'forced': forced}))) {
      return Future.value(false);
    }

    final waiting = Completer<bool>();
    _finishing = waiting;

    // ⚠️ **무한정 기다리지 않는다.** 사용자는 요약 화면 뒤에서 이것이 끝나기를
    // 기다리고 있고, ack가 안 오면 소켓이 영영 안 닫힌다. 못 받으면 트랙을
    // 남긴 채 끝낸다 — 지우는 것보다 남기는 쪽이 되돌릴 수 있다.
    return waiting.future.timeout(
      finishAckTimeout,
      onTimeout: () {
        debugPrint('[running] 종료 확인이 오지 않았다. 트랙을 남긴다');
        return false;
      },
    );
  }

  @override
  Future<void> close() async {
    _roomId = null;
    _wasConnected = false;
    // 기다리는 쪽이 남아 있으면 풀어 준다. 안 풀면 타임아웃까지 매달린다.
    if (_finishing?.isCompleted == false) _finishing!.complete(false);
    _finishing = null;
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

      case WsEvents.runningFinished:
        // 종료 확인이다. **이것이 로컬 트랙을 지워도 되는 유일한 근거다.**
        debugPrint('[running] 종료 확인');
        if (_finishing?.isCompleted == false) _finishing!.complete(true);

      case WsEvents.error:
        final code = WsErrorCode.fromWire(message.data['code']);
        // ⚠️ **연결을 끊지 않는다.** 명세가 "오류를 보낸 뒤 연결은 유지한다"고
        // 정했다. 여기서 끊으면 좌표 하나가 잘못됐을 때 러닝 전체가 죽는다.
        debugPrint('[running] 서버 거절 · $code · ${message.data['sourceType']}');

        // ⚠️ **서버에 이 사용자의 러닝 세션이 없다는 뜻이다.** 다시 알리지
        // 않으면 그 뒤 좌표가 전부 같은 오류로 거절된다 — 그런데 좌표에는
        // ack가 없어 앱은 아무것도 모른 채 계속 보낸다.
        if (code.needsRestart) {
          debugPrint('[running] 세션이 없다. RUNNING_START를 다시 보낸다');
          _sendStart();
        }

        if (!_errors.isClosed) _errors.add(code);

      default:
        // 아직 다루지 않는 이벤트. 서버가 늘려도 앱이 죽지 않아야 한다.
        debugPrint('[running] 다루지 않는 이벤트 · ${message.event}');
    }
  }
}
