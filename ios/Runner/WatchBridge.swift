import Flutter
import HealthKit
import WatchConnectivity
import os

/// Dart(`lib/core/watch/watch_channel.dart`)와 애플워치 사이 통로. 채널 이름과 결과 값은
/// 안드로이드 `WatchBridge.kt`와 같다. 메시지 형식과 보내는 규칙은 워치 레포
/// `docs/phone-communication.md`가 정본이다.
///
/// 본문은 Dart가 만든 JSON 문자열을 그대로 싣는다 — 여기서는 해석하지 않는다.
final class WatchBridge: NSObject, FlutterStreamHandler, WCSessionDelegate {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private lazy var healthStore = HKHealthStore()

  // 지금 구독 중인 Dart 쪽. 메인 스레드에서만 읽고 쓴다.
  private var sink: FlutterEventSink?

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: "watch", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "watch/messages", binaryMessenger: messenger)
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel.setStreamHandler(self)
    // 받기 구독과 따로 켠다 — 보내기는 구독 없이도 된다
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "send":
      guard let body = call.arguments as? String else {
        result(FlutterError(code: "BAD_ARGUMENT", message: "send는 JSON 문자열을 받는다", details: nil))
        return
      }
      send(body, result: result)
    case "launchApp":
      launchApp(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // 결과 값은 Dart `WatchSendResult.fromWire`가 읽는다.
  // 답 없이(replyHandler: nil) 보내면 성공 콜백이 없어, 부르는 즉시 SENT다 — 워치가 받았다는 뜻이 아니다.
  // 못 받은 메시지는 워치가 3초 감시와 WATCH_SYNC로 다시 맞춘다.
  private func send(_ body: String, result: FlutterResult) {
    guard let session = watchSession() else {
      result("NO_WATCH")
      return
    }
    session.sendMessageData(Data(body.utf8), replyHandler: nil) { error in
      Self.logger.warning("워치로 보내기 실패: \(error, privacy: .public)")
    }
    result("SENT")
  }

  // 결과 값은 Dart `WatchLaunchResult.fromWire`가 읽는다.
  // LAUNCHED는 워치에 실행 요청이 넘어갔다는 뜻이다. 화면이 떴다는 뜻은 아니다.
  // 워치부터 본다 — 워치 앱이 없는 폰이 NOT_LISTENING이 아니라 NO_WATCH를 받도록.
  private func launchApp(result: @escaping FlutterResult) {
    // 세션이 켜지는 중이거나 워치를 바꾸는 중엔 워치 유무를 모른다 — 안드로이드의 받기 등록 전처럼 다시 시도하게 한다
    if WCSession.isSupported(), WCSession.default.activationState != .activated {
      result("NOT_LISTENING")
      return
    }
    guard watchSession() != nil else {
      result("NO_WATCH")
      return
    }
    // 구독 전이면 켜지 않는다 — 켜도 첫 SYNC를 못 받는다
    guard sink != nil else {
      result("NOT_LISTENING")
      return
    }
    // 폰이 워치 앱을 켜는 길은 이것뿐이다. 워치는 이 설정을 받아 운동 세션을 시작한다
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .running
    configuration.locationType = .outdoor
    healthStore.startWatchApp(with: configuration) { success, error in
      DispatchQueue.main.async {
        if success {
          result("LAUNCHED")
        } else {
          Self.logger.warning("워치 앱 켜기 실패: \(String(describing: error), privacy: .public)")
          result("FAILED")
        }
      }
    }
  }

  // 짝지은 워치에 우리 앱이 깔려 있고 세션이 켜졌을 때만 돌려준다. 워치는 한 대(지금 고른 워치)다.
  // isReachable은 보지 않는다 — 폰 쪽에서 언제 true인지 헤더에 없고, 손목을 내린 운동 중에
  // false로 나오면 콤보 진동이 안 나간다. 닿지 못하면 보내기 오류 콜백이 알린다.
  private func watchSession() -> WCSession? {
    guard WCSession.isSupported() else { return nil }
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
      return nil
    }
    return session
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // 실패는 설정 오류(대리자 없음 등)라 다시 켜지 않는다 — 그동안 보내기는 NO_WATCH, 켜기는 NOT_LISTENING이다
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      Self.logger.error("세션 켜기 실패: \(error, privacy: .public)")
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  // 짝지은 워치를 바꾸면 앞 워치 세션이 끝난 뒤 새 워치로 다시 켜야 한다
  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  // 대리자는 메인이 아닌 큐에서 불린다 — 받은 순서 그대로 메인에서 Dart로 넘긴다
  func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
    guard let body = String(data: messageData, encoding: .utf8) else {
      Self.logger.warning("UTF-8이 아닌 워치 메시지를 버렸다")
      return
    }
    DispatchQueue.main.async { [weak self] in
      // 구독 전에 온 것은 버린다 — 워치가 SYNC로 다시 맞춘다
      self?.sink?(body)
    }
  }

  private static let logger = Logger(subsystem: "Runiverse", category: "WatchBridge")
}
