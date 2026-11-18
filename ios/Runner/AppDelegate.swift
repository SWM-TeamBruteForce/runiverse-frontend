import Flutter
import UIKit
import UserNotifications
import firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var watchBridge: WatchBridge?
  private let pushBridge = PushBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ⚠️ 플러그인보다 먼저 건다. 플러그인은 먼저 걸린 위임자에게 켜진 앱의 알림을
    // 어떻게 보일지 넘긴다(PushBridge).
    UNUserNotificationCenter.current().delegate = pushBridge
    // 푸시를 누른 것을 받을 자리를 여기서 건다. UIScene 앱은 플러그인이 이 함수가
    // 끝난 뒤에 등록돼, 플러그인에 맡기면 꺼진 앱을 연 푸시를 놓친다
    // (firebase_messaging README "iOS apps using UIScene").
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    watchBridge = WatchBridge(messenger: engineBridge.applicationRegistrar.messenger())
    pushBridge.attach(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
