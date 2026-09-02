import SwiftUI
import AppKit

struct ItemRow: View {
    let item: ClipboardItem
    let index: Int
    /// Where the cursor is, whether it got there by mouse or by arrow key.
    /// Highlighting only on hover left keyboard navigation invisible: the list
    /// scrolled but nothing showed which row was about to be acted on.
    let isSelected: Bool
    /// Shows the "Copied" confirmation. Selecting a row copies it without
    /// closing the popover, so the row itself has to report what happened.
    let isCopied: Bool

    var body: some View {
        HStack(spacing: 8) {
            indexBadge

            if item.isImage {
                imageThumbnail
            } else {
                kindIcon
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(RoundedRelativeTime.string(for: item.createdAt, relativeTo: context.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isCopied {
                copiedBadge
            } else if isSelected {
                spaceHint
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if isCopied { return Color.green.opacity(0.14) }
        if isSelected { return Color.primary.opacity(0.08) }
        return Color.clear
    }

    /// Hint that holding space shows the preview, like Finder Quick Look.
    private var spaceHint: some View {
        Image(systemName: "space")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
    }

    private var copiedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Copied")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.green.opacity(0.18)))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var indexBadge: some View {
        Text(index < 9 ? "\(index + 1)" : ".")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .frame(width: 18, height: 18)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }

    private var kindIcon: some View {
        Image(systemName: "text.alignleft")
            .font(.system(size: 11))
            .frame(width: 28, height: 22)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var imageThumbnail: some View {
        if let data = item.imageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        } else {
            Image(systemName: "photo")
                .font(.system(size: 11))
                .frame(width: 28, height: 22)
                .foregroundStyle(.secondary)
        }
    }
}
