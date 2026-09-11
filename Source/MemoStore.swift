import Foundation
import Combine

final class MemoStore: ObservableObject {
    @Published private(set) var cards: [MemoCard] = []
    private(set) var panelPosition: PanelPosition?
    @Published var error: String?
    @Published var pendingSave = false
    @Published var focusID: UUID?
    @Published var focusEditorID: UUID?
    @Published var focusGeneration = 0
    private let storage: MemoStorage
    private var saveWork: DispatchWorkItem?
    private(set) var canEdit = true

    init(directory: URL) {
        storage = MemoStorage(directory: directory)
        do {
            let document = try storage.load()
            cards = document.cards
            panelPosition = document.panelPosition
        }
        catch {
            self.error = "저장 파일을 열 수 없습니다. 원본 파일은 보존됩니다. \(error.localizedDescription)"
            canEdit = false
        }
    }

    func add(_ kind: CardKind) {
        guard canEdit else { return }
        let card = MemoCard(kind: kind)
        cards.insert(card, at: 0)
        focusID = card.id
        focusEditorID = card.items.first?.id ?? card.id
        focusGeneration += 1
        scheduleSave()
    }

    func setPanelPosition(_ position: PanelPosition?) {
        guard canEdit else { return }
        if let position = position, position.normalized == nil { return }
        let normalized = position?.normalized
        guard panelPosition != normalized else { return }
        panelPosition = normalized
        scheduleSave()
    }

    func update(_ id: UUID, text: String) {
        guard canEdit, let index = cards.firstIndex(where: { $0.id == id }), cards[index].text != text else { return }
        cards[index].text = text
        scheduleSave()
    }

    func setBodyHeight(_ id: UUID, height: Double?, undoManager: UndoManager? = nil) {
        guard canEdit, let index = cards.firstIndex(where: { $0.id == id }) else { return }
        if let height = height, !height.isFinite { return }
        let normalized = CardSizing.normalizedHeight(height)
        let previous = cards[index].bodyHeight
        guard previous != normalized else { return }
        cards[index].bodyHeight = normalized
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.setBodyHeight(id, height: previous, undoManager: undoManager)
        }
        undoManager?.setActionName("메모 높이 조절")
        scheduleSave()
    }

    func updateItem(cardID: UUID, itemID: UUID, text: String) {
        guard canEdit, let cardIndex = cards.firstIndex(where: { $0.id == cardID }),
              let itemIndex = cards[cardIndex].items.firstIndex(where: { $0.id == itemID }),
              cards[cardIndex].items[itemIndex].text != text else { return }
        cards[cardIndex].items[itemIndex].text = text
        scheduleSave()
    }

    func addItem(cardID: UUID, after itemID: UUID) {
        guard canEdit, let cardIndex = cards.firstIndex(where: { $0.id == cardID }),
              let itemIndex = cards[cardIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        let item = TodoItem()
        cards[cardIndex].items.insert(item, at: itemIndex + 1)
        focusID = item.id
        focusEditorID = item.id
        focusGeneration += 1
        scheduleSave()
    }

    func removeItem(cardID: UUID, itemID: UUID, moveFocus: Bool = false, undoManager: UndoManager?) {
        guard canEdit, let cardIndex = cards.firstIndex(where: { $0.id == cardID }),
              let itemIndex = cards[cardIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        if moveFocus && cards[cardIndex].items.count == 1 { return }
        let previous = cards[cardIndex].items
        cards[cardIndex].items.remove(at: itemIndex)
        if cards[cardIndex].items.isEmpty { cards[cardIndex].items = [TodoItem()] }
        if moveFocus {
            let focus = cards[cardIndex].items[max(0, itemIndex - 1)].id
            focusID = focus
            focusEditorID = focus
            focusGeneration += 1
        }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.replaceItems(cardID: cardID, items: previous, undoManager: undoManager)
        }
        undoManager?.setActionName("할 일 완료")
        scheduleSave()
    }

    private func replaceItems(cardID: UUID, items: [TodoItem], undoManager: UndoManager?) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let previous = cards[index].items
        cards[index].items = items
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.replaceItems(cardID: cardID, items: previous, undoManager: undoManager)
        }
        scheduleSave()
    }

    func remove(_ id: UUID, undoManager: UndoManager?) {
        guard canEdit, let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let card = cards.remove(at: index)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.restore(card, at: index, undoManager: undoManager)
        }
        undoManager?.setActionName(card.kind == .task ? "할 일 삭제" : "메모 삭제")
        scheduleSave()
    }

    private func restore(_ card: MemoCard, at index: Int, undoManager: UndoManager?) {
        guard !cards.contains(where: { $0.id == card.id }) else { return }
        cards.insert(card, at: min(index, cards.count))
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.remove(card.id, undoManager: undoManager)
        }
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func flush() {
        saveWork?.cancel()
        guard canEdit, pendingSave else { return }
        do {
            try storage.save(MemoDocument(cards: cards, panelPosition: panelPosition))
            error = nil
            pendingSave = false
        } catch {
            self.error = "저장하지 못했습니다: \(error.localizedDescription)"
        }
    }
}
