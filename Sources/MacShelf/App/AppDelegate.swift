import AppKit
import SwiftUI
import SwiftData
import KeyboardShortcuts

/// Owns the long-lived application objects: SwiftData container, status item,
/// popover, clipboard monitor and global hotkey listener.
///
/// Using `NSApplicationDelegateAdaptor` (instead of pure SwiftUI `MenuBarExtra`)
/// is required because `MenuBarExtra` exposes no API to programmatically open
/// its popup, which is a hard requirement for a hotkey-driven clipboard manager.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let modelContainer: ModelContainer
    let monitor: ClipboardMonitor

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    override init() {
        let schema = Schema([ClipboardItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema is incompatible with the on-disk store (e.g. after adding
            // image fields). Wipe the default store and try again so the user
            // doesn't have to hand-clean Application Support.
            NSLog("MacShelf: ModelContainer load failed (\(error)). Resetting store.")
            Self.deleteDefaultStore()
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
        self.modelContainer = container
        self.monitor = ClipboardMonitor(modelContext: ModelContext(container))
        super.init()
    }

    private static func deleteDefaultStore() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let candidates = [
            appSupport.appendingPathComponent("default.store"),
            appSupport.appendingPathComponent("default.store-shm"),
            appSupport.appendingPathComponent("default.store-wal")
        ]
        for url in candidates {
            try? fm.removeItem(at: url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pure menubar app: don't bounce in the Dock.
        NSApp.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false

        installStatusItem()
        installPopover()
        installHotkey()

        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - UI wiring

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "MacShelf"
            )
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    private func installPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 480)

        let root = MenuView(closePopup: { [weak self] in
            self?.closePopover()
        })
        .modelContainer(modelContainer)
        .environment(monitor)
        .frame(width: 360, height: 480)

        popover.contentViewController = NSHostingController(rootView: root)
        self.popover = popover
    }

    private func installHotkey() {
        KeyboardShortcuts.onKeyDown(for: .togglePopup) { [weak self] in
            self?.togglePopover(nil)
        }
    }

    // MARK: - Popover control

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            // Activate so keyboard input goes to our popover.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async {
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func closePopover() {
        popover?.close()
    }
}
