import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:runiverse/features/notification/domain/push_messaging.dart';

/// Dart와 iOS `PushBridge.swift` 사이 통로. 채널 이름·메서드·답 값은 거기와 같다.
///
/// | 메서드 | 방향 | 뜻 |
/// |---|---|---|
/// | `willPresent` | iOS → Dart | 앱이 켜져 있을 때 OS가 띄우려는 알림. 답(`none`·`quiet`·`banner`)이 그대로 OS 표시 방식이 된다 |
/// | `clearChat` | Dart → iOS | 그 방(`thread-id`) 알림을 알림창에서 지운다 |
class IosPushChannel {
  const IosPushChannel();

  static const _channel = MethodChannel('push');

  /// [decide]가 정하기 전에 온 알림은 띄우지 않는다 — Swift 쪽이 답을 못 받으면
  /// 띄우지 않는 것으로 친다. 지금까지 iOS가 켜진 앱에서 하던 그대로다.
  void decideForeground(ForegroundAlert Function(ReceivedPush push) decide) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'willPresent') throw MissingPluginException();
      return decide(_receivedOf(call.arguments)).name;
    });
  }

  /// ⚠️ **던지지 않는다.** 채팅 화면이 기다리지 않고 부른다.
  Future<void> clearChat(String runningRoomId) async {
    try {
      await _channel.invokeMethod<void>('clearChat', runningRoomId);
    } on PlatformException catch (error) {
      debugPrint('[push] 채팅 알림을 지우지 못했다 · ${error.code}');
    }
  }

  /// Swift가 `data`(푸시 data 키만)·`title`·`body`를 싣는다.
  static ReceivedPush _receivedOf(Object? arguments) {
    final args = arguments is Map ? arguments : const {};
    final data = args['data'];
    final title = args['title'];
    final body = args['body'];
    return ReceivedPush(
      data: {
        if (data is Map)
          for (final MapEntry(:key, :value) in data.entries)
            if (key is String) key: value,
      },
      title: title is String ? title : null,
      body: body is String ? body : null,
    );
  }
}
