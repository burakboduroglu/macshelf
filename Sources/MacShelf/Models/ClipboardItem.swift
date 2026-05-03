import Foundation
import AppKit
import SwiftData

/// A single entry in the user's clipboard history.
///
/// Items are either text or image. The kind is derived from the presence of
/// `imageData` (so we can extend storage with new attachment kinds without
/// breaking the persisted schema).
@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID

    var createdAt: Date

    /// Text payload. Empty string for image-only items.
    var text: String

    /// PNG-encoded image bytes for image items, nil for text items.
    /// Stored externally so SwiftData doesn't bloat its main SQLite blob.
    @Attribute(.externalStorage) var imageData: Data?

    /// SHA-256 hex hash of `imageData`. Used for cross-history image dedupe.
    var imageHash: String?

    /// Pixel width of the captured image, if known.
    var imageWidth: Int?

    /// Pixel height of the captured image, if known.
    var imageHeight: Int?

    /// Bundle identifier of the application that owned the pasteboard
    /// when this item was captured (best-effort; may be nil for system sources).
    var sourceBundleID: String?

    /// User-pinned items survive history pruning.
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        text: String = "",
        imageData: Data? = nil,
        imageHash: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        sourceBundleID: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.imageData = imageData
        self.imageHash = imageHash
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.sourceBundleID = sourceBundleID
        self.isPinned = isPinned
    }
}

extension ClipboardItem {
    /// Whether this item is an image (has stored image data).
    var isImage: Bool { imageData != nil }

    /// Whether this item is plain text.
    var isText: Bool { imageData == nil }

    /// A short single-line preview suitable for list rows.
    var preview: String {
        if isImage {
            let suffix = imageHash.map { " - \($0.prefix(6).uppercased())" } ?? ""
            if let w = imageWidth, let h = imageHeight {
                return "Image  \(w) x \(h)\(suffix)"
            }
            return "Image\(suffix)"
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.isEmpty ? "(empty)" : collapsed
    }

    /// User-facing source app name (best effort).
    var sourceAppName: String? {
        guard let id = sourceBundleID else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return id
    }
}
