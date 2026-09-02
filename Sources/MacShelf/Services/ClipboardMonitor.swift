import AppKit
import CryptoKit
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// Polls `NSPasteboard.general` for changes and persists new entries.
///
/// macOS provides no notification for pasteboard mutations; the supported
/// pattern is to compare `changeCount` periodically. Polling can only ever see
/// the last value of a burst — copying ten things in half a second records
/// whichever ones happened to be on the pasteboard at a tick — so the interval
/// trades captured history against wakeups. Comparing `changeCount` is a cheap
/// integer read and stays invisible in CPU profiles at this rate.
@MainActor
@Observable
final class ClipboardMonitor {
    /// How often to poll the pasteboard.
    private let pollInterval: TimeInterval = 0.25

    /// Longest text we will persist.
    ///
    /// A clipboard manager is a history, not an archive. Past roughly this size
    /// an entry stops being a useful row and starts being a database that never
    /// shrinks: `text` has no `.externalStorage`, so it lands inline in SQLite,
    /// and deleting it later only moves its pages to the free list.
    private let maxTextLength = 256_000

    /// Largest image we will persist, as PNG bytes.
    private let maxImageBytes = 16 * 1024 * 1024

    /// Maximum number of unpinned items kept in history. Pinned items always survive.
    var historyLimit: Int {
        get { UserDefaults.standard.integer(forKey: SettingsKey.historyLimit).nonZero
              ?? SettingsKey.defaultHistoryLimit }
        set {
            UserDefaults.standard.set(newValue, forKey: SettingsKey.historyLimit)
        }
    }

    /// Bundle IDs whose copies should be ignored (e.g. password managers).
    /// In v1 this is hard-coded; SettingsView will gain a UI later.
    private let ignoredBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal"
    ]

    /// Upper bound on remembered focus changes, so a pathological burst of app
    /// switching between two ticks can't grow this without limit.
    private let maxFrontmostCandidates = 16

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var frontmostObserver: NSObjectProtocol?
    private let modelContext: ModelContext

    /// Bundle IDs that held focus at any point since the last tick, oldest
    /// first.
    ///
    /// `changeCount` tells us the pasteboard changed *somewhere* in the last
    /// interval, not when. Reading `frontmostApplication` at tick time
    /// therefore credits the copy to whatever is focused now, which is both
    /// wrong for attribution and unsafe for `ignoredBundleIDs`: copy a password
    /// and switch windows before the next tick and the ignore check no longer
    /// sees the password manager. Tracking every app focused during the window
    /// lets us treat them all as candidates.
    private var frontmostCandidates: [String] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        observeFrontmostApp()
        resetFrontmostCandidates()

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        // Common runloop mode keeps polling while menus / popovers are open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
            self.frontmostObserver = nil
        }
    }

    // MARK: - Frontmost app tracking

    private func observeFrontmostApp() {
        guard frontmostObserver == nil else { return }
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }
            // Delivered on .main, so we are already on the main actor.
            MainActor.assumeIsolated {
                self?.noteFrontmost(bundleID)
            }
        }
    }

    private func noteFrontmost(_ bundleID: String) {
        guard frontmostCandidates.last != bundleID else { return }
        frontmostCandidates.append(bundleID)
        if frontmostCandidates.count > maxFrontmostCandidates {
            // Drop from the middle: the first entry is our best guess at who
            // owned the pasteboard, and the last is the current app.
            frontmostCandidates.remove(at: 1)
        }
    }

    /// Begin a new observation window seeded with whoever holds focus now.
    private func resetFrontmostCandidates() {
        frontmostCandidates = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            .map { [$0] } ?? []
    }

    // MARK: - Polling

    private func tick() {
        let candidates = frontmostCandidates
        // Every path below ends this observation window, including the early
        // returns, so a skipped copy can't leak its candidates into the next one.
        defer { resetFrontmostCandidates() }

        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // Respect "Concealed" / "Transient" markers used by password managers
        // and other privacy-sensitive copies. See nspasteboard.org for the convention.
        let types = pasteboard.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) { return }
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) { return }
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")) { return }

        // Skip if an ignored app held focus at any point in the window, not
        // just at this instant: we can't tell which of them owned the copy, so
        // the safe reading is that any of them might have.
        if candidates.contains(where: ignoredBundleIDs.contains) { return }

        // The app focused at the start of the window is the likeliest source —
        // you copy, then switch away.
        let bundleID = candidates.first

        // Image takes priority over text: most image copies also include a
        // path/text fallback that we don't want to capture twice.
        if let (data, width, height) = readImage(from: pasteboard, types: types) {
            insertImage(data: data, width: width, height: height, sourceBundleID: bundleID)
            return
        }

        // Whitespace-only copies render as "(empty)" in the list, which is a
        // row the user can't identify or act on.
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insertText(text, sourceBundleID: bundleID)
        }
    }

    // MARK: - Read helpers

    /// Try to extract an NSImage from the pasteboard and re-encode it as PNG so
    /// every item is stored in a single canonical format. Returns the PNG data
    /// plus the image's natural pixel size.
    private func readImage(
        from pb: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> (data: Data, width: Int, height: Int)? {
        if let data = readImageData(from: pb, types: types) {
            return pngData(fromImageData: data)
        }

        if let url = readImageFileURL(from: pb),
           let image = NSImage(contentsOf: url) {
            return pngData(from: image)
        }

        if types.contains(where: isImagePasteboardType),
           let image = NSImage(pasteboard: pb) {
            return pngData(from: image)
        }

        return nil
    }

    private func readImageData(
        from pb: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Data? {
        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("org.webmproject.webp")
        ]

        for type in preferredTypes where types.contains(type) {
            if let data = pb.data(forType: type) {
                return data
            }
        }

        for type in types where isImagePasteboardType(type) {
            if let data = pb.data(forType: type) {
                return data
            }
        }

        return nil
    }

    private func readImageFileURL(from pb: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pb.readObjects(forClasses: [NSURL.self], options: options) ?? []
        let urls = objects.compactMap { object -> URL? in
            if let url = object as? URL { return url }
            if let url = object as? NSURL { return url as URL }
            return nil
        }
        return urls.first(where: isImageFileURL)
    }

    private func isImageFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .image)
        }
        return NSImage(contentsOf: url) != nil
    }

    private func isImagePasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
        UTType(type.rawValue)?.conforms(to: .image) == true
    }

    private func pngData(fromImageData data: Data) -> (data: Data, width: Int, height: Int)? {
        if let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, rep.pixelsWide, rep.pixelsHigh)
        }

        guard let image = NSImage(data: data) else { return nil }
        return pngData(from: image)
    }

    private func pngData(from image: NSImage) -> (data: Data, width: Int, height: Int)? {
        if let rep = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { lhs, rhs in
                (lhs.pixelsWide * lhs.pixelsHigh) < (rhs.pixelsWide * rhs.pixelsHigh)
            }),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, rep.pixelsWide, rep.pixelsHigh)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = image.size
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, rep.pixelsWide, rep.pixelsHigh)
    }

    // MARK: - Persistence

    /// Insert a text entry only if the exact text is not already in history.
    private func insertText(_ text: String, sourceBundleID: String?) {
        guard text.count <= maxTextLength else { return }

        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.text == text && $0.imageData == nil }
        )
        if let matches = try? modelContext.fetch(descriptor),
           let existing = matches.first {
            // Re-copying an entry makes it the most recent one. Leaving the
            // original timestamp would strand the thing the user just used at
            // the bottom of the list, where prune() reaches it first.
            existing.createdAt = .now
            if existing.sourceBundleID == nil, sourceBundleID != nil {
                existing.sourceBundleID = sourceBundleID
            }
            try? modelContext.save()
            return
        }

        let item = ClipboardItem(text: text, sourceBundleID: sourceBundleID)
        modelContext.insert(item)
        prune()
        try? modelContext.save()
    }

    /// Insert an image entry only if the PNG hash is not already in history.
    private func insertImage(data: Data, width: Int, height: Int, sourceBundleID: String?) {
        guard data.count <= maxImageBytes else { return }

        let hash = sha256(data)

        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.imageHash == hash }
        )
        if let matches = try? modelContext.fetch(descriptor),
           let existing = matches.first {
            // Same reasoning as insertText: a re-copy is a fresh use.
            existing.createdAt = .now
            if existing.sourceBundleID == nil, sourceBundleID != nil {
                existing.sourceBundleID = sourceBundleID
            }
            if existing.imageWidth == nil {
                existing.imageWidth = width
            }
            if existing.imageHeight == nil {
                existing.imageHeight = height
            }
            try? modelContext.save()
            return
        }

        let item = ClipboardItem(
            text: "",
            imageData: data,
            imageHash: hash,
            imageWidth: width,
            imageHeight: height,
            sourceBundleID: sourceBundleID
        )
        modelContext.insert(item)
        prune()
        try? modelContext.save()
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Drop the oldest unpinned items beyond `historyLimit`.
    private func prune() {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let items = try? modelContext.fetch(descriptor) else { return }
        guard items.count > historyLimit else { return }
        for item in items[historyLimit...] {
            modelContext.delete(item)
        }
    }

    /// Programmatically clear all history (pinned items included).
    func clearAll() {
        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }
        for item in items { modelContext.delete(item) }
        try? modelContext.save()
    }

    /// Delete a single item.
    func delete(_ item: ClipboardItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}

private extension Int {
    /// Treat 0 (the default for an unset UserDefaults integer) as "no value".
    var nonZero: Int? { self == 0 ? nil : self }
}
