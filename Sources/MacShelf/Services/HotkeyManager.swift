import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Default global hotkey for showing/hiding the MacShelf popover.
    /// Mirrors the convention used by other clipboard managers (Maccy, Paste, ...).
    static let togglePopup = Self(
        "togglePopup",
        default: .init(.v, modifiers: [.command, .shift])
    )
}
