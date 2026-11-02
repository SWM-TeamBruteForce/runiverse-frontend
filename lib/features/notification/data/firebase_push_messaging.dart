import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/features/notification/domain/push_messaging.dart';

/// FCM에 닿는 [PushMessaging]. `main.dart`가 끼운다.
///
/// ## 앱이 켜져 있으면 배너를 띄우지 않는다
///
/// FCM의 기본값이 그렇다(Android·iOS 둘 다). 같은 알림이 앱 스트림(SSE)으로
/// 이미 들어와 알림함과 배지에 반영되므로, 배너까지 띄우면 두 번 알리는 셈이다.
/// 그래서 `setForegroundNotificationPresentationOptions`를 부르지 않는다.
///
/// ⚠️ **iOS에서 한 번 켜면 지워도 남는다.** 그 값은 기기에 저장된다 — 끄려면
/// `alert: false`로 직접 불러야 한다(패키지 문서).
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// ⚠️ **던지지 않는다.** 셸이 기다리지 않고 부르므로, 던지면 처리되지 않은
  /// 오류가 되어 Crashlytics에 치명 오류로 쌓인다.
  @override
  Future<void> requestPermission() async {
    try {
      await _messaging.requestPermission();
    } on FirebaseException catch (error) {
      debugPrint('[push] 알림 권한을 묻지 못했다 · ${error.code}');
    }
  }

  /// ⚠️ **iOS는 APNs 토큰이 먼저다.** 없을 때 FCM 토큰을 달라고 하면 예외가 난다
  /// (Firebase iOS SDK 10.4+). 앱을 켠 직후에는 아직 없을 수 있어 `null`로
  /// 답한다 — 처음 생기면 [tokenRefreshes]로 오고, 아니면 복귀 때 다시 묻는다.
  @override
  Future<String?> token() async {
    try {
      if (Platform.isIOS && await _messaging.getAPNSToken() == null) {
        debugPrint('[push] APNs 토큰이 아직 없다');
        return null;
      }
      return await _messaging.getToken();
    } on FirebaseException catch (error) {
      // 망이 없거나 구글 서버가 답하지 않았다. 토큰 값은 찍지 않는다.
      debugPrint('[push] 토큰을 받지 못했다 · ${error.code}');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  /// 못 읽으면 누른 푸시가 없던 것으로 친다 — 앱만 열린다.
  @override
  Future<OpenedPush?> initialOpened() async {
    try {
      final message = await _messaging.getInitialMessage();
      return message == null ? null : _openedOf(message);
    } on FirebaseException catch (error) {
      debugPrint('[push] 앱을 연 푸시를 읽지 못했다 · ${error.code}');
      return null;
    }
  }

  @override
  Stream<OpenedPush> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(_openedOf);

  static OpenedPush _openedOf(RemoteMessage message) =>
      OpenedPush(messageId: message.messageId, data: message.data);
}
