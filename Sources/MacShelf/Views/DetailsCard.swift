import SwiftUI
import AppKit

/// Quick Look-style preview shown while the user holds Space over a row.
///
/// Sized to fit inside the menubar popover; shows the full text or a
/// large image preview plus metadata (source app, captured time, byte/char
/// counts).
struct DetailsCard: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
        .padding(12)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isImage ? "photo" : "text.alignleft")
                .foregroundStyle(.secondary)
            Text(item.isImage ? "Image" : "Text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("hold  Space")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if item.isImage {
            imageContent
        } else {
            textContent
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let data = item.imageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 280)
                .padding(12)
        } else {
            placeholder("Image data missing")
        }
    }

    private var textContent: some View {
        ScrollView {
            Text(item.text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: 280)
    }

    private func placeholder(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let app = item.sourceAppName {
                metaItem(systemImage: "app.fill", text: app)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                metaItem(
                    systemImage: "clock",
                    text: RoundedRelativeTime.string(for: item.createdAt, relativeTo: context.date)
                )
            }
            Spacer()
            metaItem(systemImage: "ruler", text: sizeLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func metaItem(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text(text)
        }
    }

    private var sizeLabel: String {
        if item.isImage {
            if let w = item.imageWidth, let h = item.imageHeight {
                let bytes = item.imageData?.count ?? 0
                return "\(w) x \(h)  -  \(byteString(bytes))"
            }
            return byteString(item.imageData?.count ?? 0)
        }
        let chars = item.text.count
        return "\(chars) chars"
    }

    private func byteString(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

}
