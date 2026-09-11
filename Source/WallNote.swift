import AppKit
import SwiftUI
import Carbon

private enum Palette {
    static let ink = Color(red: 0.23, green: 0.26, blue: 0.26)
    static let secondary = Color(red: 0.48, green: 0.51, blue: 0.50)
    static let green = Color(red: 0.27, green: 0.48, blue: 0.41)
    static let border = Color(red: 0.30, green: 0.35, blue: 0.31).opacity(0.09)
}

// The native window follows the rendered content height, so an empty board
// occupies only this compact toolbar instead of a transparent full-height window.
final class PanelViewport: ObservableObject {
    @Published var maximumHeight: CGFloat = 800
}

private struct ControlHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 52
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TodoBodyHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct SidebarView: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var viewport: PanelViewport
    let onContentHeightChange: (CGFloat, CGFloat) -> Void
    @State private var controlHeight: CGFloat = 52
    @State private var naturalBodyHeights: [UUID: CGFloat] = [:]
    @State private var resizePreviews: [UUID: CGFloat] = [:]

    private var layout: SidebarLayout {
        SidebarLayout(availableHeight: viewport.maximumHeight, controlHeight: controlHeight)
    }
    private func bodyHeight(for card: MemoCard) -> CGFloat {
        layout.bodyHeight(for: card, naturalHeight: naturalBodyHeights[card.id], previewHeight: resizePreviews[card.id])
    }
    private var bodyHeights: [CGFloat] { store.cards.map { bodyHeight(for: $0) } }
    private var naturalHeight: CGFloat { layout.contentHeight(bodyHeights: bodyHeights) }
    private var focusedCardID: UUID? {
        guard let focus = store.focusID else { return nil }
        return store.cards.first(where: { $0.id == focus || $0.items.contains(where: { $0.id == focus }) })?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            ControlBarView(store: store)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ControlHeightKey.self, value: geometry.size.height)
                })
                .zIndex(1)

            if !store.cards.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: SidebarLayout.cardGap) {
                            ForEach(store.cards) { card in
                                MemoCardView(store: store, card: card,
                                             visibleBodyHeight: bodyHeight(for: card),
                                             maximumBodyHeight: layout.maximumBodyHeight,
                                             onNaturalHeightChange: { height in
                                                 guard height > 0, abs((naturalBodyHeights[card.id] ?? 0) - height) > 0.5 else { return }
                                                 naturalBodyHeights[card.id] = height
                                             },
                                             onResizePreview: { resizePreviews[card.id] = $0 })
                                    .id(card.id)
                            }
                        }
                        .frame(height: layout.cardsHeight(bodyHeights: bodyHeights) - SidebarLayout.listBottomPadding,
                               alignment: .top)
                        .padding(.horizontal, 2)
                        .padding(.bottom, SidebarLayout.listBottomPadding)
                    }
                    .frame(height: layout.scrollHeight(bodyHeights: bodyHeights))
                    .onChange(of: store.focusGeneration) { _ in
                        guard let id = focusedCardID else { return }
                        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                    }
                    .accessibilityIdentifier("cards-scroll")
                }
                .padding(.top, SidebarLayout.toolbarGap)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(naturalHeight, viewport.maximumHeight), alignment: .top)
        .foregroundStyle(Palette.ink)
        .environment(\.colorScheme, .light)
        .onPreferenceChange(ControlHeightKey.self) { height in
            guard height > 0, abs(controlHeight - height) > 0.5 else { return }
            controlHeight = height
        }
        .onChange(of: store.cards.map(\.id)) { ids in
            let remaining = Set(ids)
            naturalBodyHeights = naturalBodyHeights.filter { remaining.contains($0.key) }
            resizePreviews = resizePreviews.filter { remaining.contains($0.key) }
        }
        .onAppear { onContentHeightChange(naturalHeight, controlHeight) }
        .onChange(of: naturalHeight) { onContentHeightChange($0, controlHeight) }
        .onChange(of: controlHeight) { onContentHeightChange(naturalHeight, $0) }
    }
}

private struct ControlBarView: View {
    @ObservedObject var store: MemoStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                PanelMoveHandle()
                    .frame(width: 16, height: 32)
                AddButton(title: "메모 추가", symbol: "square.and.pencil", identifier: "add-note") { store.add(.note) }
                    .disabled(!store.canEdit)
                AddButton(title: "할 일 추가", symbol: "checklist", identifier: "add-task") { store.add(.task) }
                    .disabled(!store.canEdit)
                Rectangle().fill(Palette.border).frame(width: 1, height: 17)
                HStack(spacing: 4) {
                    Circle().fill(store.error == nil ? Palette.green.opacity(0.65) : Color.red)
                        .frame(width: 4, height: 4)
                    Text(store.error != nil ? "저장 오류" : (store.pendingSave ? "저장 중…" : "자동 저장"))
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.secondary)
                .frame(width: 51)
                .help(store.error ?? "이 Mac에 자동으로 저장됩니다")
                .accessibilityIdentifier("save-status")
                Button { NSApp.terminate(nil) } label: {
                    Label("앱 종료", systemImage: "power")
                        .font(.system(size: 10, weight: .medium))
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondary)
                .help("메모를 저장하고 Wall Note 종료 (⌘Q)")
                .accessibilityIdentifier("quit-app")
            }
            .padding(10)

            if let error = store.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(Color(red: 0.965, green: 0.970, blue: 0.957).opacity(0.94))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("control-bar")
    }
}

private struct PanelMoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelMoveHandleView { PanelMoveHandleView() }
    func updateNSView(_ view: PanelMoveHandleView, context: Context) {}
}

private final class PanelMoveHandleView: NSView {
    private var pointerOffset: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "드래그하여 메모장 이동 · 더블클릭하면 오른쪽으로 되돌리기"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("메모장 이동 손잡이")
        setAccessibilityHelp(toolTip)
        setAccessibilityIdentifier("move-panel")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.65).setFill()
        for x in [-2.5, 2.5] {
            for y in [-5.0, 0.0, 5.0] {
                NSBezierPath(ovalIn: NSRect(x: bounds.midX + x - 1.2, y: bounds.midY + y - 1.2,
                                           width: 2.4, height: 2.4)).fill()
            }
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        guard let window = window, let delegate = NSApp.delegate as? AppDelegate else { return }
        if event.clickCount == 2 {
            pointerOffset = nil
            delegate.resetPanelPosition(nil)
            return
        }
        // AppKit coordinates start at the bottom; keep the pointer's distance
        // from the top-left of the toolbar as the content below it resizes.
        pointerOffset = NSPoint(x: event.locationInWindow.x, y: window.frame.height - event.locationInWindow.y)
        delegate.beginPanelMove()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let offset = pointerOffset else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        NSCursor.closedHand.set()
        (NSApp.delegate as? AppDelegate)?.movePanel(topLeft: NSPoint(x: point.x - offset.x, y: point.y + offset.y),
                                                   pointer: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard pointerOffset != nil else { return }
        pointerOffset = nil
        (NSApp.delegate as? AppDelegate)?.endPanelMove()
        NSCursor.openHand.set()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let reset = menu.addItem(withTitle: "오른쪽으로 되돌리기", action: #selector(AppDelegate.resetPanelPosition(_:)), keyEquivalent: "")
        reset.target = NSApp.delegate
        return menu
    }
}

private struct AddButton: View {
    let title: String
    let symbol: String
    let identifier: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13, weight: .regular)).foregroundStyle(Palette.green)
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(hovered ? Color.white : Color.white.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityIdentifier(identifier)
        .help(title)
    }
}

private struct MemoCardView: View {
    @ObservedObject var store: MemoStore
    let card: MemoCard
    let visibleBodyHeight: CGFloat
    let maximumBodyHeight: CGFloat
    let onNaturalHeightChange: (CGFloat) -> Void
    let onResizePreview: (CGFloat?) -> Void
    @State private var editorHeight: CGFloat = 76
    @State private var todoBodyHeight: CGFloat = 0
    @State private var deleteHovered = false
    @State private var resizeHovered = false
    @State private var dragStartHeight: CGFloat?
    @State private var draggedHeight: CGFloat?

    private var isTask: Bool { card.kind == .task }
    private var naturalBodyHeight: CGFloat {
        isTask ? max(48, todoBodyHeight > 0 ? todoBodyHeight : CGFloat(card.items.count) * 34 + 15) : max(76, editorHeight)
    }
    private func constrainedHeight(_ height: CGFloat) -> CGFloat {
        min(maximumBodyHeight, max(CGFloat(CardSizing.minimumBodyHeight), height))
    }
    private var textBinding: Binding<String> {
        Binding(get: { store.cards.first(where: { $0.id == card.id })?.text ?? "" },
                set: { store.update(card.id, text: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarLayout.cardContentGap) {
            HStack {
                Text(isTask ? "할 일" : "메모")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.secondary)
                Spacer()
                Button {
                    store.remove(card.id, undoManager: NSApp.keyWindow?.undoManager)
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                        .foregroundStyle(deleteHovered ? Color(red: 0.73, green: 0.34, blue: 0.30) : Palette.secondary)
                        .frame(width: 25, height: SidebarLayout.cardHeaderHeight)
                        .background(deleteHovered ? Color.red.opacity(0.07) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { deleteHovered = $0 }
                .help(isTask ? "할 일 삭제" : "메모 삭제")
                .accessibilityLabel(isTask ? "할 일 삭제" : "메모 삭제")
                .accessibilityIdentifier("delete-\(card.id)")
            }
            .frame(height: SidebarLayout.cardHeaderHeight)
            .padding(.leading, 2)
            .padding(.trailing, -5)
            .padding(.top, SidebarLayout.cardHeaderTopPadding)

            CardContentScroll(contentHeight: naturalBodyHeight, content: bodyContent)
                .frame(height: visibleBodyHeight)

            resizeHandle
        }
        .padding(SidebarLayout.cardPadding)
        .frame(height: visibleBodyHeight + SidebarLayout.cardChromeHeight, alignment: .top)
        .background(isTask ? Color(red: 0.936, green: 0.963, blue: 0.940) : Color(red: 1.0, green: 0.988, blue: 0.947))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.025), radius: 3, y: 2)
        .accessibilityElement(children: .contain)
        .onAppear { onNaturalHeightChange(naturalBodyHeight) }
        .onChange(of: naturalBodyHeight) { onNaturalHeightChange($0) }
        .onDisappear {
            if let height = draggedHeight {
                store.setBodyHeight(card.id, height: Double(height))
                onResizePreview(nil)
            }
            dragStartHeight = nil
            draggedHeight = nil
            if resizeHovered { NSCursor.pop(); resizeHovered = false }
        }
    }

    @ViewBuilder private var bodyContent: some View {
        if isTask {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.items) { item in
                    TodoRow(store: store, cardID: card.id, item: item).id(item.id)
                }
                Text("Enter로 다음 할 일 · Shift+Enter로 줄바꿈")
                    .font(.system(size: 9)).foregroundStyle(Palette.secondary.opacity(0.8))
                    .padding(.leading, 33).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: TodoBodyHeightKey.self, value: geometry.size.height)
            })
            .onPreferenceChange(TodoBodyHeightKey.self) { height in
                guard height > 0, abs(todoBodyHeight - height) > 0.5 else { return }
                DispatchQueue.main.async { todoBodyHeight = height }
            }
        } else {
            NativeEditor(text: textBinding, measuredHeight: $editorHeight,
                         placeholder: "여기를 클릭하고 바로 적어 보세요…", minimumHeight: 76,
                         focusRequested: store.focusEditorID == card.id, focusGeneration: store.focusGeneration,
                         identifier: "editor-\(card.id)", editable: store.canEdit,
                         onFocusApplied: { if store.focusEditorID == card.id { store.focusEditorID = nil } })
                .frame(height: max(naturalBodyHeight, visibleBodyHeight))
        }
    }

    private var resizeHandle: some View {
        Capsule()
            .fill(Palette.secondary.opacity(resizeHovered || draggedHeight != nil ? 0.65 : 0.25))
            .frame(width: 28, height: 3)
            .frame(maxWidth: .infinity).frame(height: SidebarLayout.resizeHandleHeight)
            .contentShape(Rectangle())
            .onHover { hovered in
                guard hovered != resizeHovered else { return }
                resizeHovered = hovered
                if hovered { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    guard store.canEdit else { return }
                    if dragStartHeight == nil { dragStartHeight = visibleBodyHeight }
                    draggedHeight = constrainedHeight((dragStartHeight ?? visibleBodyHeight) + value.translation.height)
                    onResizePreview(draggedHeight)
                }
                .onEnded { _ in
                    if let height = draggedHeight {
                        store.setBodyHeight(card.id, height: Double(height), undoManager: NSApp.keyWindow?.undoManager)
                    }
                    dragStartHeight = nil
                    draggedHeight = nil
                    onResizePreview(nil)
                })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                store.setBodyHeight(card.id, height: nil, undoManager: NSApp.keyWindow?.undoManager)
            })
            .contextMenu {
                Button("내용에 맞게 자동 높이") {
                    store.setBodyHeight(card.id, height: nil, undoManager: NSApp.keyWindow?.undoManager)
                }
            }
            .help("위아래로 드래그해 높이 조절 · 더블클릭하면 자동 높이")
            .accessibilityLabel("메모 높이 조절")
            .accessibilityValue("\(Int(visibleBodyHeight)) 포인트")
            .accessibilityIdentifier("resize-\(card.id)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: store.setBodyHeight(card.id, height: Double(constrainedHeight(visibleBodyHeight + 24)))
                case .decrement: store.setBodyHeight(card.id, height: Double(constrainedHeight(visibleBodyHeight - 24)))
                @unknown default: break
                }
            }
    }
}

// A card can scroll internally without trapping the wheel when it reaches an
// edge. The outer board continues scrolling, and neither level shows a scroller.
private struct CardContentScroll<Content: View>: NSViewRepresentable {
    let contentHeight: CGFloat
    let content: Content

    func makeNSView(context: Context) -> CardScrollView {
        let scroll = CardScrollView()
        let host = NSHostingView(rootView: AnyView(content.environment(\.colorScheme, .light)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)))
        host.isFlipped = true
        host.sizingOptions = []
        scroll.documentView = host
        context.coordinator.host = host
        return scroll
    }

    func updateNSView(_ scroll: CardScrollView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content.environment(\.colorScheme, .light)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        scroll.naturalContentHeight = contentHeight
        scroll.needsLayout = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var host: NSHostingView<AnyView>?
    }
}

private final class CardScrollView: NSScrollView {
    var naturalContentHeight: CGFloat = 76

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = NSSize(width: max(1, contentSize.width), height: max(naturalContentHeight, contentSize.height))
        if documentView?.frame.size != size {
            documentView?.setFrameSize(size)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let editor = self.window?.firstResponder as? NSTextView,
                      let document = self.documentView, editor.isDescendant(of: document) else { return }
                editor.scrollRangeToVisible(editor.selectedRange())
            }
        }
        // Re-clamp the offset after text is deleted or the card is enlarged.
        let bounds = contentView.constrainBoundsRect(contentView.bounds)
        if bounds.origin != contentView.bounds.origin { contentView.scroll(to: bounds.origin) }
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
        let exhausted = CardScrollPolicy.passesToParent(
            contentHeight: Double(documentView?.frame.height ?? 0), viewportHeight: Double(contentSize.height),
            offset: Double(documentVisibleRect.minY), deltaY: Double(event.scrollingDeltaY))
        if exhausted, let outer = superview?.enclosingScrollView {
            outer.scrollWheel(with: event)
        } else { super.scrollWheel(with: event) }
    }
}

private struct TodoRow: View {
    @ObservedObject var store: MemoStore
    let cardID: UUID
    let item: TodoItem
    @State private var height: CGFloat = 26
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                store.removeItem(cardID: cardID, itemID: item.id, undoManager: NSApp.keyWindow?.undoManager)
            } label: {
                ZStack {
                    Circle().strokeBorder(Palette.green.opacity(hovered ? 1 : 0.43), lineWidth: 1.5)
                        .background(Circle().fill(hovered ? Palette.green.opacity(0.10) : Color.clear))
                    if hovered { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.green) }
                }.frame(width: 17, height: 17).padding(3).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help("완료하고 지우기")
            .accessibilityLabel("할 일 완료")
            .accessibilityIdentifier("complete-\(item.id)")

            NativeEditor(text: Binding(
                get: { store.cards.first(where: { $0.id == cardID })?.items.first(where: { $0.id == item.id })?.text ?? "" },
                set: { store.updateItem(cardID: cardID, itemID: item.id, text: $0) }),
                measuredHeight: $height, placeholder: "해야 할 일을 적어 보세요…", minimumHeight: 26,
                focusRequested: store.focusEditorID == item.id, focusGeneration: store.focusGeneration,
                identifier: "editor-\(item.id)", editable: store.canEdit,
                onReturn: { store.addItem(cardID: cardID, after: item.id) },
                onDeleteEmpty: { store.removeItem(cardID: cardID, itemID: item.id, moveFocus: true, undoManager: NSApp.keyWindow?.undoManager) },
                onFocusApplied: { if store.focusEditorID == item.id { store.focusEditorID = nil } })
                .frame(height: max(26, height))
        }
    }
}

// A regular NSTextView preserves native selection, undo, paste, and Korean IME composition.
// The editor reports its natural height; its enclosing card controls the viewport.
private struct NativeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let placeholder: String
    let minimumHeight: CGFloat
    let focusRequested: Bool
    let focusGeneration: Int
    let identifier: String
    let editable: Bool
    var onReturn: (() -> Void)? = nil
    var onDeleteEmpty: (() -> Void)? = nil
    var onFocusApplied: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> EditorContainer {
        let container = EditorContainer()
        container.editor.delegate = context.coordinator
        container.editor.string = text
        container.editor.placeholder = placeholder
        container.minimumHeight = minimumHeight
        container.editor.setAccessibilityLabel(placeholder)
        container.editor.setAccessibilityIdentifier(identifier)
        container.heightChanged = { height in
            if abs(context.coordinator.parent.measuredHeight - height) > 0.5 {
                DispatchQueue.main.async { context.coordinator.parent.measuredHeight = height }
            }
        }
        return container
    }

    func updateNSView(_ container: EditorContainer, context: Context) {
        context.coordinator.parent = self
        container.focusApplied = onFocusApplied
        container.editor.isEditable = editable
        if container.editor.string != text && !container.editor.hasMarkedText() {
            container.editor.string = text
        }
        container.editor.needsDisplay = true
        container.needsLayout = true
        if focusRequested && context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            container.focusOnAttach = true
            DispatchQueue.main.async { [weak container] in container?.applyFocusIfNeeded() }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        var lastFocusGeneration = -1
        init(_ parent: NativeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? PlaceholderTextView else { return }
            parent.text = editor.string
            editor.needsDisplay = true
            if let container = editor.superview as? EditorContainer {
                container.revealCaretAfterLayout = true
                container.measure()
                container.needsLayout = true
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false), let onReturn = parent.onReturn {
                onReturn()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty,
               let onDeleteEmpty = parent.onDeleteEmpty {
                onDeleteEmpty()
                return true
            }
            return false
        }
    }
}

private final class EditorContainer: NSView {
    let editor = PlaceholderTextView(frame: .zero)
    var minimumHeight: CGFloat = 76
    var heightChanged: ((CGFloat) -> Void)?
    var focusOnAttach = false
    var focusApplied: (() -> Void)?
    var revealCaretAfterLayout = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainerInset = NSSize(width: 0, height: 2)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        editor.font = .systemFont(ofSize: 13.5)
        editor.textColor = NSColor(red: 0.23, green: 0.26, blue: 0.26, alpha: 1)
        editor.insertionPointColor = NSColor(red: 0.27, green: 0.48, blue: 0.41, alpha: 1)
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = true
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .foregroundColor: editor.textColor!, .paragraphStyle: paragraph]
        addSubview(editor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        editor.frame = bounds
        editor.textContainer?.containerSize = NSSize(width: max(1, bounds.width), height: CGFloat.greatestFiniteMagnitude)
        measure()
        if revealCaretAfterLayout {
            revealCaretAfterLayout = false
            DispatchQueue.main.async { [weak self] in self?.revealCaret() }
        }
    }

    func measure() {
        guard bounds.width > 1 else { return }
        guard let layout = editor.layoutManager, let container = editor.textContainer else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let extra = layout.extraLineFragmentRect
        heightChanged?(max(minimumHeight, ceil(max(used.maxY, extra.maxY)) + 8))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyFocusIfNeeded()
    }

    func applyFocusIfNeeded() {
        guard focusOnAttach, let window = window else { return }
        focusOnAttach = false
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        DispatchQueue.main.async { [weak self] in
            self?.revealCaret()
            self?.focusApplied?()
        }
    }

    private func revealCaret() {
        guard window?.firstResponder === editor else { return }
        editor.scrollRangeToVisible(editor.selectedRange())
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholder = ""
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(at: NSPoint(x: 0, y: 2), withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: 13.5),
                .foregroundColor: NSColor(red: 0.55, green: 0.57, blue: 0.53, alpha: 0.85)
            ])
        }
    }

    // Escape gives the underlying app its space back without affecting saved text.
    override func cancelOperation(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.hidePanel()
    }
}

private final class SidePanel: NSPanel {
    var allowedFrame: NSRect?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { (NSApp.delegate as? AppDelegate)?.hidePanel() }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let allowedFrame = allowedFrame else { return super.constrainFrameRect(frameRect, to: screen) }
        return PanelPlacement.constrain(frameRect, to: allowedFrame)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        let constrained = allowedFrame.map { PanelPlacement.constrain(frameRect, to: $0) } ?? frameRect
        super.setFrame(constrained, display: flag)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: SidePanel!
    private var statusItem: NSStatusItem!
    private var store: MemoStore!
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var selectedDisplayID: UInt32?
    private var preferredPanelWidth: CGFloat = 370
    private var panelPosition: PanelPosition?
    private var isMovingPanel = false
    private var didMovePanel = false
    private var contentHeight: CGFloat = 52
    private var controlHeight: CGFloat = 52
    private let viewport = PanelViewport()
    private var contentResizeGeneration = 0
    private var isPositioning = false
    private var placementGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = ProcessInfo.processInfo.arguments
        let directory: URL
        if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1) {
            directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SideMemo", isDirectory: true) // Keep existing notes and saved placement.
        }
        store = MemoStore(directory: directory)
        panelPosition = store.panelPosition
        if let position = panelPosition { preferredPanelWidth = CGFloat(position.width) }
        configureMenu()
        configureStatusItem()
        configureHotKey()
        configurePanel()
        observeWorkspaceChanges()
        showPanel()
    }

    private func configurePanel() {
        panel = SidePanel(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Wall Note"
        panel.setAccessibilityTitle("Wall Note")
        panel.identifier = NSUserInterfaceItemIdentifier("WallNotePanel")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingView(rootView: SidebarView(store: store, viewport: viewport, onContentHeightChange: { [weak self] height, controlHeight in
            self?.updateContentHeight(height, controlHeight: controlHeight)
        }))
        host.sizingOptions = []
        panel.contentView = host
        panel.appearance = NSAppearance(named: .aqua)
        positionPanel()
    }

    private func updateContentHeight(_ height: CGFloat, controlHeight: CGFloat) {
        guard height.isFinite, height > 0, controlHeight.isFinite, controlHeight > 0 else { return }
        contentResizeGeneration += 1
        let generation = contentResizeGeneration
        // Resize outside SwiftUI's layout pass and discard obsolete measurements.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.contentResizeGeneration == generation,
                  abs(self.contentHeight - height) > 0.5 || abs(self.controlHeight - controlHeight) > 0.5 else { return }
            self.contentHeight = height
            self.controlHeight = controlHeight
            self.positionPanel()
        }
    }

    private func currentDisplays() -> [PanelDisplay] {
        NSScreen.screens.compactMap { screen -> PanelDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            let safe = screen.safeAreaInsets
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            return PanelDisplay(id: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                                frame: screen.frame, visibleFrame: screen.visibleFrame,
                                safeInsets: DisplayInsets(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right), uuid: uuid)
        }
    }

    private func usableFrame(for display: PanelDisplay) -> CGRect {
        let dockSettings = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        let dockEdge = DockEdge(rawValue: dockSettings["orientation"] as? String ?? "bottom") ?? .bottom
        let tileSize = (dockSettings["tilesize"] as? NSNumber)?.doubleValue ?? 64
        let magnified = (dockSettings["magnification"] as? NSNumber)?.boolValue ?? false
        let largeSize = (dockSettings["largesize"] as? NSNumber)?.doubleValue ?? tileSize
        let dockThickness = CGFloat(min(180, max(32, magnified ? max(tileSize, largeSize) : tileSize))) + 20
        return PanelPlacement.usableFrame(for: display, menuBarHeight: max(24, NSStatusBar.system.thickness),
                                         dockEdge: dockEdge, dockThickness: dockThickness)
    }

    private func positionPanel(whileMoving: Bool = false) {
        guard panel != nil, !isPositioning, !isMovingPanel || whileMoving else { return }
        guard let display = PanelPlacement.display(in: currentDisplays(), position: panelPosition, previousID: selectedDisplayID) else { return }
        let available = PanelPlacement.anchoredArea(in: usableFrame(for: display), position: panelPosition,
            minimumHeight: SidebarLayout.minimumPanelHeight(controlHeight: controlHeight, hasCards: !store.cards.isEmpty))
        isPositioning = true
        defer { isPositioning = false }
        selectedDisplayID = display.id
        panel.allowedFrame = available
        if abs(viewport.maximumHeight - available.height) > 0.5 { viewport.maximumHeight = available.height }
        panel.minSize = NSSize(width: min(330, available.width), height: min(controlHeight, available.height))
        panel.maxSize = NSSize(width: min(560, available.width), height: available.height)
        let width = panel.inLiveResize ? panel.frame.width : preferredPanelWidth
        var desired = PanelPlacement.panelFrame(in: available, preferredWidth: width, preferredHeight: contentHeight, position: panelPosition)
        if panel.inLiveResize, panelPosition != nil {
            // Left-edge resizing also moves the origin. Do not pull it back to
            // the previously saved x while SwiftUI remeasures the new width.
            desired.origin.x = max(available.minX, min(panel.frame.minX, available.maxX - desired.width))
        }
        if panel.frame != desired { panel.setFrame(desired, display: true) }
    }

    func beginPanelMove() {
        placementGeneration += 1
        isMovingPanel = true
        didMovePanel = false
    }

    func movePanel(topLeft: NSPoint, pointer: NSPoint) {
        guard isMovingPanel, let display = PanelPlacement.display(at: pointer, in: currentDisplays()) else { return }
        panelPosition = PanelPlacement.position(topLeft: topLeft, preferredWidth: preferredPanelWidth,
                                               display: display, in: usableFrame(for: display))
        didMovePanel = true
        positionPanel(whileMoving: true)
    }

    func endPanelMove() {
        guard isMovingPanel else { return }
        isMovingPanel = false
        if didMovePanel { store.setPanelPosition(panelPosition) }
        didMovePanel = false
        positionPanel()
        refreshPlacement()
    }

    @objc func resetPanelPosition(_ sender: Any?) {
        isMovingPanel = false
        didMovePanel = false
        panelPosition = nil
        store.setPanelPosition(nil)
        positionPanel()
        refreshPlacement()
    }

    private func observeWorkspaceChanges() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
    }

    @objc private func workspaceChanged(_ notification: Notification) { refreshPlacement() }

    func applicationDidChangeScreenParameters(_ notification: Notification) { refreshPlacement() }

    func applicationDidBecomeActive(_ notification: Notification) { refreshPlacement() }

    func windowDidChangeScreen(_ notification: Notification) {
        if !isPositioning, !isMovingPanel { refreshPlacement() }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        preferredPanelWidth = min(560, max(330, panel.frame.width))
        if var position = panelPosition {
            position.width = Double(preferredPanelWidth)
            if let display = PanelPlacement.display(in: currentDisplays(), position: panelPosition, previousID: selectedDisplayID) {
                let available = usableFrame(for: display)
                position.horizontalFraction = Double((panel.frame.minX - available.minX) / max(1, available.width))
            }
            panelPosition = position.normalized
            store.setPanelPosition(panelPosition)
        }
        refreshPlacement()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Width can be dragged; height belongs to the toolbar and its cards.
        if isPositioning { return frameSize }
        return NSSize(width: frameSize.width, height: min(contentHeight, viewport.maximumHeight))
    }

    private func refreshPlacement() {
        guard !isMovingPanel else { return }
        placementGeneration += 1
        let generation = placementGeneration
        // Display topology, the menu bar, and the Dock settle in separate steps.
        // These bounded retries run only on display/Space/wake events, with no polling timer.
        for delay in [0.0, 0.25, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.placementGeneration == generation else { return }
                self.positionPanel()
            }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Wall Note")
            button.image?.isTemplate = true
            button.toolTip = "Wall Note — 클릭하여 열기 / 숨기기 (⌃⌥N)"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Wall Note 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let toggle = menu.addItem(withTitle: panel.isVisible ? "메모 숨기기" : "메모 열기", action: #selector(togglePanel), keyEquivalent: "")
            toggle.target = self
            let reset = menu.addItem(withTitle: "오른쪽으로 되돌리기", action: #selector(resetPanelPosition(_:)), keyEquivalent: "")
            reset.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Wall Note 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else { togglePanel() }
    }

    @objc func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshPlacement()
    }

    func hidePanel() {
        endPanelMove()
        store.flush()
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    private func configureHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context = context else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.togglePanel()
            return noErr
        }, 1, &eventType, context, &hotKeyHandler)
        let identifier = EventHotKeyID(signature: OSType(0x534D454D), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.flush()
        if store.pendingSave && store.canEdit {
            let alert = NSAlert()
            alert.messageText = "메모를 저장하지 못했습니다"
            alert.informativeText = "창을 열어 둔 채 저장 위치를 확인해 주세요. 종료하면 저장하지 못한 변경 사항이 사라집니다."
            alert.addButton(withTitle: "돌아가기")
            alert.addButton(withTitle: "저장하지 않고 종료")
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        placementGeneration += 1
        contentResizeGeneration += 1
        store.flush()
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler = hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}

@main
enum WallNoteMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
