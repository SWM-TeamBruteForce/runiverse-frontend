import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/features/notification/data/android_chat_notifications.dart';
import 'package:runiverse/features/notification/data/ios_push_channel.dart';
import 'package:runiverse/features/notification/data/notification_access_mapper.dart';
import 'package:runiverse/features/notification/domain/chat_push.dart';
import 'package:runiverse/features/notification/domain/push_messaging.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';

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
///
/// ## 예외 — 안드로이드 대기방 채팅
///
/// 서버가 data만 보내 OS가 아무것도 띄우지 않고, SSE 알림함에도 들어가지 않는다.
/// 그래서 앱이 직접 그린다([AndroidChatNotifications]). 꺼졌거나 뒤에 있을 때는
/// [handleBackgroundPush]가, 켜져 있을 때는 [received]를 듣는 `PushController`가
/// 그린다.
///
/// ## 예외 — 안드로이드 켜진 앱의 공지
///
/// 공지는 SSE 알림함에 들어가지 않는다. 배너를 띄우지 않으면 앱을 보고 있던
/// 사람은 공지를 못 본다. 그래서 `PushController`가 채팅과 같은 도구로 팝업을
/// 쌓는다.
///
/// ## 예외 — iOS 켜진 앱의 채팅·공지
///
/// 안드로이드와 같은 규칙으로 보인다. 다만 그리는 것은 OS다 — 서버가 둘 다 알림으로
/// 보내므로, 앱은 OS가 띄우려 할 때 보일 방식만 답한다([IosPushChannel]).
/// 전역 `setForegroundNotificationPresentationOptions`는 종류를 고르지 못해 쓰지 않는다.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging({
    FirebaseMessaging? messaging,
    AndroidChatNotifications? chat,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _chat = chat ?? (Platform.isAndroid ? AndroidChatNotifications() : null),
       _ios = Platform.isIOS ? const IosPushChannel() : null {
    // ⚠️ **앱이 뜰 때 바로 준비한다.** 채팅 알림을 누른 것은 준비된 뒤에야
    // [opened]로 들어온다.
    unawaited(_chat?.start(listenTaps: true));
  }

  final FirebaseMessaging _messaging;

  /// 안드로이드에서만 있다. iOS는 서버가 알림으로 보내 OS가 띄운다.
  final AndroidChatNotifications? _chat;

  /// iOS에서만 있다.
  final IosPushChannel? _ios;

  /// ⚠️ **던지지 않는다.** 셸이 기다리지 않고 부르므로, 던지면 처리되지 않은
  /// 오류가 되어 Crashlytics에 치명 오류로 쌓인다.
  @override
  Future<PermissionAccess?> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      return toNotificationAccess(
        settings.authorizationStatus,
        isIos: Platform.isIOS,
      );
    } on FirebaseException catch (error) {
      debugPrint('[push] 알림 권한을 묻지 못했다 · ${error.code}');
      return null;
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
  ///
  /// FCM이 띄운 알림이 아니면 앱이 그린 채팅 알림을 본다.
  @override
  Future<OpenedPush?> initialOpened() async {
    try {
      final message = await _messaging.getInitialMessage();
      if (message != null) return _openedOf(message);
    } on FirebaseException catch (error) {
      debugPrint('[push] 앱을 연 푸시를 읽지 못했다 · ${error.code}');
    }
    return _chat?.launchedBy();
  }

  @override
  Stream<OpenedPush> get opened {
    final fcm = FirebaseMessaging.onMessageOpenedApp.map(_openedOf);
    final chat = _chat;
    return chat == null ? fcm : _merge(fcm, chat.taps);
  }

  @override
  Stream<ReceivedPush> get received => FirebaseMessaging.onMessage.map(
    (message) => ReceivedPush(
      data: message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    ),
  );

  @override
  Future<void> showChat(ChatPush push, {required bool quiet}) async =>
      _chat?.show(push, quiet: quiet);

  @override
  Future<void> clearChat(String runningRoomId) async {
    await _chat?.clear(runningRoomId);
    await _ios?.clearChat(runningRoomId);
  }

  @override
  Future<void> showNotice({
    required String title,
    required String body,
  }) async => _chat?.showNotice(title: title, body: body);

  @override
  void decideForeground(ForegroundAlert Function(ReceivedPush push) decide) =>
      _ios?.decideForeground(decide);

  static OpenedPush _openedOf(RemoteMessage message) =>
      OpenedPush(messageId: message.messageId, data: message.data);

  /// 두 통로의 누름을 하나로 내보낸다. 듣는 쪽이 끊으면 둘 다 끊는다.
  static Stream<T> _merge<T>(Stream<T> first, Stream<T> second) {
    final subscriptions = <StreamSubscription<T>>[];
    late final StreamController<T> merged;
    merged = StreamController<T>(
      onListen: () {
        for (final source in [first, second]) {
          subscriptions.add(
            source.listen(merged.add, onError: merged.addError),
          );
        }
      },
      onCancel: () => Future.wait([
        for (final subscription in subscriptions) subscription.cancel(),
      ]),
    );
    return merged.stream;
  }
}

/// 앱이 꺼졌거나 뒤에 있을 때 받은 푸시. `main.dart`가 등록한다.
///
/// **따로 도는 isolate에서 불린다** — provider도, 앱의 상태도 없다. 안드로이드
/// 채팅 푸시만 그리고 나머지는 OS에 맡긴다(알림 블록이 있어 OS가 띄운다).
///
/// ⚠️ **최상위 함수여야 하고 `vm:entry-point`가 있어야 한다.** 없으면 릴리스
/// 빌드에서 지워져 백그라운드 푸시가 조용히 사라진다(firebase_messaging 문서).
@pragma('vm:entry-point')
Future<void> handleBackgroundPush(RemoteMessage message) async {
  if (!Platform.isAndroid) return;
  final push = ChatPush.of(message.data);
  if (push == null) return;
  await AndroidChatNotifications().show(push, quiet: false);
}
