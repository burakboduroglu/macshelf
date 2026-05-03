import SwiftUI
import SwiftData
import AppKit

@main
struct MacShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The visible menubar UI is owned by AppDelegate (NSStatusItem + NSPopover)
        // so we can programmatically toggle it from a global hotkey. We still
        // expose a Settings scene to get the standard Cmd+, shortcut for free.
        Settings {
            SettingsView()
                .modelContainer(appDelegate.modelContainer)
                .environment(appDelegate.monitor)
                .frame(width: 480, height: 360)
        }
    }
}

/// Centralised UserDefaults keys.
enum SettingsKey {
    static let historyLimit = "settings.historyLimit"
    static let defaultHistoryLimit = 100
}
