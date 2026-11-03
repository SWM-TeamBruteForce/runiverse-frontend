import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// [WatchChannel.send] 의 결과.
enum WatchSendResult {
  /// 가까이 연결된 워치가 없다. 워치 앱이 없는 폰도 여기다.
  noWatch,

  /// 연결된 워치를 묻거나 보내다가 실패했다.
  failed,

  /// 보내기 요청이 넘어갔다. **워치가 받았다는 뜻은 아니다** — 못 받은 메시지는
  /// 워치가 3초 감시와 `WATCH_SYNC` 로 다시 맞춘다.
  sent;

  /// `WatchBridge.kt` 가 준 값에서 되살린다. 모르는 값이면 [failed].
  static WatchSendResult fromWire(Object? value) => switch (value) {
    'NO_WATCH' => WatchSendResult.noWatch,
    'SENT' => WatchSendResult.sent,
    _ => WatchSendResult.failed,
  };
}

/// [WatchChannel.launchApp] 의 결과.
enum WatchLaunchResult {
  /// 가까이 연결된 워치가 없다. 워치 앱이 없는 폰도 여기다.
  noWatch,

  /// [WatchChannel.messages] 구독 전이거나 받기 등록이 아직 안 끝났다.
  /// 켜자마자 워치가 보내는 `WATCH_SYNC` 를 놓치므로 켜지 않았다.
  notListening,

  /// 연결된 워치를 묻거나 실행 요청을 넘기다가 실패했다. 워치에 우리 앱이 없을
  /// 때도 여기다.
  failed,

  /// 실행 요청이 넘어갔다. **화면이 떴다는 뜻은 아니다.**
  launched;

  /// `WatchBridge.kt` 가 준 값에서 되살린다. 모르는 값이면 [failed].
  static WatchLaunchResult fromWire(Object? value) => switch (value) {
    'NO_WATCH' => WatchLaunchResult.noWatch,
    'NOT_LISTENING' => WatchLaunchResult.notListening,
    'LAUNCHED' => WatchLaunchResult.launched,
    _ => WatchLaunchResult.failed,
  };
}

/// 워치가 보낸 메시지 하나. 서버 WebSocket과 같은 봉투다.
class WatchMessage {
  const WatchMessage({required this.event, required this.data});

  final String event;
  final Map<String, dynamic> data;
}

/// 폰 ↔ 워치 통로. 안드로이드는 `WatchBridge.kt` 가 갤럭시워치와 잇는다.
///
/// 메시지 종류와 보내는 규칙은 워치 레포 `docs/phone-communication.md` 가
/// 정본이다. 이 클래스는 봉투를 싸고 푸는 일만 한다.
///
/// ## ⚠️ 아직 안드로이드만 있다
///
/// iOS(애플워치)는 같은 채널 이름으로 나중에 붙인다. 그 전에 iOS에서 부르면
/// [MissingPluginException] 이 난다.
class WatchChannel {
  const WatchChannel();

  static const _method = MethodChannel('watch');
  static const _events = EventChannel('watch/messages');

  /// 워치가 보낸 메시지. 첫 구독 때 받기를 등록하고 마지막 구독이 끝나면 푼다.
  ///
  /// 해석하지 못한 메시지는 버린다 — 다음 상태가 곧 다시 온다.
  ///
  /// 받기 등록이 실패하면 [PlatformException](`LISTEN_FAILED`)이 흐른다.
  /// 워치 앱이 없는 폰은 실패가 아니라 아무것도 오지 않는다(워치가 보이면 다시 등록한다).
  Stream<WatchMessage> get messages => _messages;

  // ⚠️ 스트림은 하나만 만든다. `receiveBroadcastStream()`을 부를 때마다 채널의
  // 받는 쪽이 새 스트림으로 바뀐다 — 두 곳에서 따로 만들면 먼저 구독한 쪽이
  // 아무것도 못 받고, 한쪽이 구독을 끊으면 다른 쪽까지 끊긴다.
  static final Stream<WatchMessage> _messages = _events
      .receiveBroadcastStream()
      .expand((raw) {
        final message = _decode(raw);
        return message == null ? const <WatchMessage>[] : [message];
      });

  /// 워치에 메시지를 보낸다.
  ///
  /// [data] 에는 JSON으로 바꿀 수 있는 값만 넣는다. `DateTime` 같은 것이 섞이면
  /// [JsonUnsupportedObjectError] 가 난다.
  Future<WatchSendResult> send(String event, Map<String, Object?> data) async {
    final body = jsonEncode({'event': event, 'data': data});
    final result = await _method.invokeMethod<String>('send', body);
    return WatchSendResult.fromWire(result);
  }

  /// 워치 앱을 켠다.
  ///
  /// 먼저 [messages] 를 구독해 둬야 한다 — 켜자마자 워치가 보내는
  /// `WATCH_SYNC` 를 놓치지 않기 위해서다. 등록이 끝나기를 기다리지 않고
  /// [WatchLaunchResult.notListening] 을 돌려준다.
  Future<WatchLaunchResult> launchApp() async {
    final result = await _method.invokeMethod<String>('launchApp');
    return WatchLaunchResult.fromWire(result);
  }

  static WatchMessage? _decode(Object? raw) {
    final message = _tryDecode(raw);
    if (message == null) debugPrint('[watch] 해석하지 못한 메시지를 버렸다');
    return message;
  }

  static WatchMessage? _tryDecode(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final event = decoded['event'];
      if (event is! String || event.isEmpty) return null;
      final data = decoded['data'];
      return WatchMessage(
        event: event,
        data: data is Map<String, dynamic> ? data : const {},
      );
    } on FormatException {
      return null;
    }
  }
}
