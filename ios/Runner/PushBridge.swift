import Flutter
import UserNotifications

/// Dart(`lib/features/notification/data/ios_push_channel.dart`)와 알림센터 사이 통로.
///
/// 앱이 켜져 있을 때 OS가 띄우려는 알림을 어떻게 보일지 Dart에 묻는다. firebase_messaging은
/// 자기보다 먼저 걸린 알림 위임자에게 이 결정을 넘기고, `onMessage`는 그대로 Dart에 보낸다
/// (16.7.1 `FLTFirebaseMessagingPlugin.m` `willPresentNotification`). 그래서 `AppDelegate`가
/// 플러그인보다 먼저 이것을 위임자로 건다. 누름(`didReceive`)은 구현하지 않는다 — 플러그인이
/// 그대로 받아 랜딩이 바뀌지 않는다.
///
/// ⚠️ **`FlutterAppLifeCycleProvider`를 따르면 안 된다.** 따르는 위임자(FlutterAppDelegate 등)면
/// 플러그인이 자리를 넘겨받지 않아 이 결정이 오지 않는다.
final class PushBridge: NSObject, UNUserNotificationCenterDelegate {
  private var channel: FlutterMethodChannel?

  /// 엔진이 뜬 뒤에 부른다. 그 전에 온 알림은 띄우지 않는다.
  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "push", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "clearChat":
        guard let runningRoomId = call.arguments as? String else {
          result(FlutterError(code: "BAD_ARGUMENT", message: "clearChat은 방 번호를 받는다", details: nil))
          return
        }
        Self.clearChat(runningRoomId, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard let channel else {
      completionHandler([])
      return
    }
    let content = notification.request.content
    var arguments: [String: Any] = ["data": Self.dataOf(content.userInfo)]
    if !content.title.isEmpty { arguments["title"] = content.title }
    if !content.body.isEmpty { arguments["body"] = content.body }
    channel.invokeMethod("willPresent", arguments: arguments) { answer in
      completionHandler(Self.options(of: answer))
    }
  }

  // 답 값은 Dart `ForegroundAlert`의 이름이다. 오류·모르는 답·아직 듣는 쪽이 없으면 띄우지 않는다 —
  // 지금까지 켜진 앱에서 하던 그대로다. 소리는 서버가 넣은 것을 폰 설정대로 낸다.
  private static func options(of answer: Any?) -> UNNotificationPresentationOptions {
    switch answer as? String {
    case "quiet": return [.list, .sound]
    case "banner": return [.banner, .list, .sound]
    default: return []
    }
  }

  // 푸시 data 키만 남긴다. firebase_messaging이 `RemoteMessage.data`를 만들 때 빼는 키를 똑같이 뺀다.
  private static func dataOf(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var data: [String: Any] = [:]
    for (key, value) in userInfo {
      guard let key = key as? String,
            key != "aps", key != "fcm_options",
            !key.hasPrefix("gcm."), !key.hasPrefix("google.")
      else { continue }
      data[key] = value
    }
    return data
  }

  // 서버가 채팅 푸시의 `thread-id`에 방 번호를 넣는다(FcmPushClient). 그 방 알림만 지운다.
  private static func clearChat(_ runningRoomId: String, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { notifications in
      let ids = notifications
        .filter { $0.request.content.threadIdentifier == runningRoomId }
        .map { $0.request.identifier }
      center.removeDeliveredNotifications(withIdentifiers: ids)
      DispatchQueue.main.async { result(nil) }
    }
  }
}
