import 'dart:convert';

/// WebSocket이 주고받는 봉투.
///
/// ```json
/// { "event": "...", "data": { ... } }
/// ```
///
/// ## ⚠️ 키는 `event`다
///
/// 2차 명세는 `type`이었다. **옛 문서를 보고 만들면 서버가 `MISSING_MESSAGE_TYPE`을
/// 돌려준다** — 이름만 보면 `type`이 맞는 것 같아서 더 헷갈린다.
///
/// ## 내용을 모른다
///
/// 이 클래스는 러닝도, 매칭도 모른다. 봉투만 다루므로 다른 채널이 생겨도 그대로 쓴다.
/// 어떤 `event`가 있고 `data`에 무엇이 드는지는 각 채널이 안다.
class WsMessage {
  const WsMessage(this.event, [this.data = const {}]);

  final String event;

  /// 비어 있을 수 있다. `HEALTH_CHECK`는 `data={}`다.
  final Map<String, dynamic> data;

  String encode() => jsonEncode({'event': event, 'data': data});

  /// 받은 문자열을 봉투로 되돌린다. **모양이 다르면 `null`.**
  ///
  /// 예외를 던지지 않는 이유는, 이상한 메시지 하나 때문에 연결을 끊을 이유가
  /// 없어서다. 서버도 같은 태도다 — `ERROR`를 보내고 연결은 유지한다.
  static WsMessage? decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final event = decoded['event'];
      if (event is! String || event.isEmpty) return null;
      final data = decoded['data'];
      return WsMessage(event, data is Map<String, dynamic> ? data : const {});
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'WsMessage($event)';
}

/// 서버와 주고받는 event 이름.
///
/// 문자열을 화면·저장소에 흩어 놓지 않는다. 오타는 컴파일러가 못 잡고,
/// 서버는 `UNSUPPORTED_MESSAGE_TYPE`으로만 답한다.
abstract final class WsEvents {
  // ── 공통 ────────────────────────────────────────────────────

  static const healthCheck = 'HEALTH_CHECK';
  static const healthChecked = 'HEALTH_CHECKED';

  /// 서버가 무언가 거절했다. **받아도 연결을 끊지 않는다.**
  static const error = 'ERROR';

  // ── 러닝 ────────────────────────────────────────────────────

  /// 연결 후 보내는 첫 메시지. 최초 진입과 재연결을 구분하지 않는다.
  static const runningStart = 'RUNNING_START';
  static const runningStarted = 'RUNNING_STARTED';

  /// 좌표 10초 배치. **ack가 없다.**
  static const runningLocationUpdate = 'RUNNING_LOCATION_UPDATE';

  static const runningPause = 'RUNNING_PAUSE';
  static const runningResume = 'RUNNING_RESUME';

  static const runningFinish = 'RUNNING_FINISH';
  static const runningFinished = 'RUNNING_FINISHED';
}

/// `ERROR`의 `code` 7종.
///
/// 지금은 어느 것이든 화면이 하는 일이 같지만(연결 유지, 로그), 나누어 두면
/// 나중에 "왜 안 되지"를 로그 없이 쫓지 않아도 된다.
enum WsErrorCode {
  malformedMessage,
  missingMessageType,
  unsupportedMessageType,
  invalidRequest,
  roomNotFound,
  notRoomPlayer,
  invalidRoomState,

  /// 명세에 없는 코드. 서버가 늘렸을 수 있다.
  unknown;

  static WsErrorCode fromWire(Object? value) => switch (value) {
    'MALFORMED_MESSAGE' => WsErrorCode.malformedMessage,
    'MISSING_MESSAGE_TYPE' => WsErrorCode.missingMessageType,
    'UNSUPPORTED_MESSAGE_TYPE' => WsErrorCode.unsupportedMessageType,
    'INVALID_REQUEST' => WsErrorCode.invalidRequest,
    'ROOM_NOT_FOUND' => WsErrorCode.roomNotFound,
    'NOT_ROOM_PLAYER' => WsErrorCode.notRoomPlayer,
    'INVALID_ROOM_STATE' => WsErrorCode.invalidRoomState,
    _ => WsErrorCode.unknown,
  };
}
