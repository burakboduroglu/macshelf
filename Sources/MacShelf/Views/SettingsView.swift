import SwiftUI
import SwiftData
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "command") }

            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .padding(20)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(ClipboardMonitor.self) private var monitor
    @AppStorage(SettingsKey.historyLimit) private var historyLimit: Int = SettingsKey.defaultHistoryLimit

    private let options = [25, 50, 100, 250, 500, 1000]

    var body: some View {
        Form {
            Picker("History limit:", selection: $historyLimit) {
                ForEach(options, id: \.self) { count in
                    Text("\(count) items").tag(count)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 240)

            Text("Older items beyond this limit are removed automatically. Pinned items always survive.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("Clear all history")
                Spacer()
                Button("Clear...", role: .destructive) {
                    monitor.clearAll()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle MacShelf:", name: .togglePopup)

            Text("Press the global shortcut from anywhere to show or hide MacShelf. Default is Cmd+Shift+V.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @State private var trusted: Bool = PermissionsService.isAccessibilityTrusted

    var body: some View {
        Form {
            Section("Accessibility access") {
                HStack {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trusted ? "Granted" : "Required for paste")
                            .font(.headline)
                        Text("MacShelf synthesises Cmd+V to paste items into the focused app. Without Accessibility access the item is still copied to the clipboard, but you must press Cmd+V yourself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        PermissionsService.openAccessibilitySettings()
                    }
                }
            }

            Section("Skipped sources") {
                Text("MacShelf ignores copies marked with org.nspasteboard.ConcealedType (used by 1Password, Bitwarden and other password managers) as well as known password manager bundle IDs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            trusted = PermissionsService.isAccessibilityTrusted
        }
    }
}
