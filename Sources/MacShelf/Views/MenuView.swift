import SwiftUI
import SwiftData
import AppKit

/// Popover content shown from the menubar. Owns the search field, the
/// keyboard-navigable list of clipboard history items and basic actions.
struct MenuView: View {
    let closePopup: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardMonitor.self) private var monitor

    // Sorting pinned-first is done in `filtered` because SwiftData's
    // SortDescriptor doesn't support Bool key paths on @Model types.
    @Query(sort: \ClipboardItem.createdAt, order: .reverse)
    private var items: [ClipboardItem]

    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @State private var hoveredID: UUID?
    @State private var previewID: UUID?
    @State private var isSpacePreviewing: Bool = false
    @FocusState private var searchFocused: Bool

    init(closePopup: @escaping () -> Void) {
        self.closePopup = closePopup
    }

    private var filtered: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [ClipboardItem]
        if query.isEmpty {
            base = items
        } else {
            base = items.filter { $0.text.localizedCaseInsensitiveContains(query) }
        }
        // Stable: pinned items first, then most-recent first.
        return base.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var previewItem: ClipboardItem? {
        guard let id = previewID else { return nil }
        return items.first(where: { $0.id == id })
    }

    private var filteredIDs: [UUID] {
        filtered.map(\.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                searchBar
                Divider()
                content
                Divider()
                footer
            }
            .background(.regularMaterial)

            if let preview = previewItem {
                DetailsCard(item: preview)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: previewID)
        .onAppear {
            selectedIndex = 0
            hoveredID = nil
            previewID = nil
            isSpacePreviewing = false
            searchFocused = false
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
            clearHoverState()
        }
        .onChange(of: filteredIDs) { _, ids in
            selectedIndex = min(selectedIndex, max(0, ids.count - 1))
            if let hoveredID, !ids.contains(hoveredID) {
                self.hoveredID = nil
            }
            if let previewID, !ids.contains(previewID) {
                self.previewID = nil
                self.isSpacePreviewing = false
            }
        }
    }

    // MARK: - Sections

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { pasteSelected() }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            searchFocused = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            item: item,
                            index: index,
                            isHovered: hoveredID == item.id
                        )
                        .id(item.id)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active:
                                hoveredID = item.id
                                if let i = filtered.firstIndex(where: { $0.id == item.id }) {
                                    selectedIndex = i
                                }
                            case .ended:
                                if hoveredID == item.id {
                                    hoveredID = nil
                                }
                                if previewID == item.id, !isSpacePreviewing {
                                    previewID = nil
                                }
                            }
                        }
                        .onTapGesture {
                            paste(item)
                        }
                        .contextMenu {
                            Button(item.isPinned ? "Unpin" : "Pin") {
                                item.isPinned.toggle()
                            }
                            Button(item.isImage ? "Copy without pasting" : "Copy without pasting") {
                                PasteService.write(item)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                monitor.delete(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, new in
                if filtered.indices.contains(new) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(filtered[new].id, anchor: .center)
                    }
                }
            }
            .background(KeyCaptureView(
                onArrowDown: { moveSelection(by: 1); previewID = nil },
                onArrowUp: { moveSelection(by: -1); previewID = nil },
                onReturn: { pasteSelected() },
                onEscape: {
                    if previewID != nil { stopPreview() }
                    else if searchFocused { searchFocused = false }
                    else { closePopup() }
                },
                onDigit: { digit in
                    if digit >= 1 && digit <= 9 && filtered.count >= digit {
                        selectedIndex = digit - 1
                        pasteSelected()
                    }
                },
                onSpace: { isDown in
                    handleSpace(isDown: isDown)
                }
            ))
            .onHover { hovering in
                if !hovering, !isSpacePreviewing {
                    clearHoverState()
                }
            }
            .onDisappear {
                clearHoverState()
                isSpacePreviewing = false
            }
            .simultaneousGesture(TapGesture().onEnded {
                searchFocused = false
            })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No history yet" : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Copy something and it will show up here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            searchFocused = false
        }
    }

    private var footer: some View {
        HStack {
            Text("\(items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Clear history...") {
                    monitor.clearAll()
                }
                Divider()
                SettingsLink {
                    Text("Settings...")
                }
                Button("Quit MacShelf") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .simultaneousGesture(TapGesture().onEnded {
            searchFocused = false
        })
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let count = filtered.count
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func pasteSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        paste(filtered[selectedIndex])
    }

    private func paste(_ item: ClipboardItem) {
        previewID = nil
        hoveredID = nil
        isSpacePreviewing = false
        closePopup()
        PasteService.paste(item)
    }

    private func clearHoverState() {
        hoveredID = nil
        previewID = nil
        isSpacePreviewing = false
    }

    private func stopPreview() {
        previewID = nil
        isSpacePreviewing = false
    }

    /// Returns true to swallow the Space event, false to let it pass through
    /// to the search field.
    private func handleSpace(isDown: Bool) -> Bool {
        // Only intercept Space when the user is hovering over a row.
        // This keeps Space usable as a separator in the search query.
        if isDown {
            if previewID != nil { return true }
            guard let id = hoveredID, items.contains(where: { $0.id == id }) else {
                return false
            }
            isSpacePreviewing = true
            previewID = id
        } else {
            guard isSpacePreviewing || previewID != nil else { return false }
            stopPreview()
        }
        return true
    }
}

// MARK: - Key capture helper

/// Invisible NSView that intercepts arrow keys, Return and digit shortcuts so
/// the user can navigate the list while the search field has focus.
private struct KeyCaptureView: NSViewRepresentable {
    let onArrowDown: () -> Void
    let onArrowUp: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void
    let onDigit: (Int) -> Void
    let onSpace: (_ isDown: Bool) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.handler = self
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.handler = self
    }

    final class KeyView: NSView {
        var handler: KeyCaptureView?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil

            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, let h = self.handler, self.window?.isKeyWindow == true else {
                    return event
                }

                // Space (keycode 49) is handled on both keyDown and keyUp so we
                // can implement press-and-hold preview semantics.
                if Int(event.keyCode) == 49 {
                    let consumed = h.onSpace(event.type == .keyDown)
                    return consumed ? nil : event
                }

                // Everything else is keyDown only.
                guard event.type == .keyDown else { return event }

                let cmd = event.modifierFlags.contains(.command)

                switch Int(event.keyCode) {
                case 125: h.onArrowDown(); return nil
                case 126: h.onArrowUp();   return nil
                case 36, 76:
                    h.onReturn(); return nil
                case 53:
                    h.onEscape(); return nil
                default: break
                }

                if cmd, let chars = event.charactersIgnoringModifiers,
                   chars.count == 1, let digit = Int(chars), digit >= 1, digit <= 9 {
                    h.onDigit(digit)
                    return nil
                }

                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
