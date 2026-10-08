import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct AltrStreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 540, idealWidth: 560, maxWidth: 600, minHeight: 480, idealHeight: 500, maxHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}
