import ApplicationServices
import AppKit

/// Wraps the macOS Accessibility API trust check used to authorise synthetic
/// keyboard events (the Cmd+V we send when the user picks a history item).
enum PermissionsService {
    /// Whether the running process is currently trusted to post HID events.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the system prompt that asks the user to add MacShelf to
    /// System Settings -> Privacy & Security -> Accessibility.
    ///
    /// Returns the trust status BEFORE the user interacts with the prompt,
    /// so callers should not treat false as "denied"; it just means the
    /// prompt was shown and the user has not yet granted access.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [promptKey: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open the Accessibility pane in System Settings so the user can grant
    /// permission manually if the prompt is dismissed.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
