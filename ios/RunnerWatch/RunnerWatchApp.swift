import RuniverseWatch
import SwiftUI

@main
struct RunnerWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: RuniverseWatchAppDelegate

    var body: some Scene {
        RuniverseWatchScene()
    }
}
