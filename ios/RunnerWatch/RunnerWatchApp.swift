import RuniverseWatch
import SwiftUI

/// 애플워치 앱 진입점. 화면·로직은 워치 레포 패키지 `RuniverseWatch`에 있다.
@main
struct RunnerWatchApp: App {
  // 폰이 켠 운동과 앱이 죽기 전 남은 운동을 받는다.
  @WKApplicationDelegateAdaptor private var appDelegate: RuniverseWatchAppDelegate

  var body: some Scene {
    RuniverseWatchScene()
  }
}
