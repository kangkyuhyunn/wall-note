import Foundation

@main
enum StoreTests {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SideMemo-store-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let directory = base.appendingPathComponent("normal")
        let store = MemoStore(directory: directory)
        store.add(.note)
        let noteID = store.cards[0].id
        store.update(noteID, text: "바로 입력한 메모\n한국어 🙂")
        store.setBodyHeight(noteID, height: 280)
        store.add(.task)
        let taskID = store.cards[0].id
        let firstID = store.cards[0].items[0].id
        assert(store.focusEditorID == firstID)
        store.updateItem(cardID: taskID, itemID: firstID, text: "첫 번째 할 일")
        store.addItem(cardID: taskID, after: firstID)
        let secondID = store.cards[0].items[1].id
        store.updateItem(cardID: taskID, itemID: secondID, text: "두 번째 할 일")
        assert(store.focusEditorID == secondID)
        store.addItem(cardID: taskID, after: firstID)
        let middleID = store.cards[0].items[1].id
        store.updateItem(cardID: taskID, itemID: middleID, text: "중간 항목")
        assert(store.cards[0].items.map(\.text) == ["첫 번째 할 일", "중간 항목", "두 번째 할 일"])

        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        store.removeItem(cardID: taskID, itemID: middleID, undoManager: undo)
        undo.endUndoGrouping()
        assert(store.cards[0].items.map(\.text) == ["첫 번째 할 일", "두 번째 할 일"])
        assert(store.cards[1].text == "바로 입력한 메모\n한국어 🙂")
        undo.undo()
        assert(store.cards[0].items[1].id == middleID)
        undo.redo()
        assert(store.cards[0].items.count == 2)

        undo.beginUndoGrouping()
        store.setBodyHeight(noteID, height: 320.4, undoManager: undo)
        undo.endUndoGrouping()
        assert(store.cards[1].bodyHeight == 320 && store.cards[0].bodyHeight == nil)
        assert(store.cards[1].text == "바로 입력한 메모\n한국어 🙂")
        undo.undo()
        assert(store.cards[1].bodyHeight == 280)
        undo.redo()
        assert(store.cards[1].bodyHeight == 320)
        store.setBodyHeight(noteID, height: 0)
        assert(store.cards[1].bodyHeight == 56)
        store.setBodyHeight(noteID, height: 100000)
        assert(store.cards[1].bodyHeight == 100000)
        store.setBodyHeight(noteID, height: .nan)
        store.setBodyHeight(noteID, height: .infinity)
        assert(store.cards[1].bodyHeight == 100000)
        store.setBodyHeight(noteID, height: nil)
        assert(store.cards[1].bodyHeight == nil)
        store.setBodyHeight(noteID, height: 320)
        store.setBodyHeight(taskID, height: 144)
        assert(store.cards[0].items.map(\.text) == ["첫 번째 할 일", "두 번째 할 일"])

        store.removeItem(cardID: taskID, itemID: firstID, undoManager: nil)
        store.removeItem(cardID: taskID, itemID: secondID, undoManager: nil)
        assert(store.cards[0].items.count == 1 && store.cards[0].items[0].text.isEmpty)
        let blankID = store.cards[0].items[0].id
        store.removeItem(cardID: taskID, itemID: blankID, moveFocus: true, undoManager: nil)
        assert(store.cards[0].items[0].id == blankID)

        undo.beginUndoGrouping()
        store.remove(noteID, undoManager: undo)
        undo.endUndoGrouping()
        assert(store.cards.count == 1)
        undo.undo()
        assert(store.cards.count == 2 && store.cards[1].id == noteID)
        assert(store.cards[1].bodyHeight == 320)
        undo.redo()
        assert(store.cards.count == 1)

        // Let the actual debounce run, then create a fresh store as on app restart.
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        assert(!store.pendingSave && store.error == nil)
        let reopened = MemoStore(directory: directory)
        assert(reopened.cards == store.cards)
        assert(reopened.cards[0].bodyHeight == 144)

        // Movement uses the same save transaction as notes, including empty
        // boards. Later text edits must not discard the restored position.
        let movementDirectory = base.appendingPathComponent("movement")
        let movement = MemoStore(directory: movementDirectory)
        let position = PanelPosition(displayID: 22, displayUUID: "desk-monitor",
                                     horizontalFraction: 0.32, topFraction: 0.47, width: 390)
        movement.setPanelPosition(position)
        assert(movement.pendingSave && movement.cards.isEmpty)
        movement.flush()
        let emptyMoved = MemoStore(directory: movementDirectory)
        assert(emptyMoved.panelPosition == position && emptyMoved.cards.isEmpty)
        emptyMoved.add(.note)
        let movedNoteID = emptyMoved.cards[0].id
        emptyMoved.update(movedNoteID, text: "위치를 옮겨도 남아 있는 메모")
        emptyMoved.setBodyHeight(movedNoteID, height: 360)
        emptyMoved.add(.task)
        emptyMoved.updateItem(cardID: emptyMoved.cards[0].id, itemID: emptyMoved.cards[0].items[0].id, text: "이동 후 할 일")
        emptyMoved.flush()
        let movedReopened = MemoStore(directory: movementDirectory)
        assert(movedReopened.panelPosition == position && movedReopened.cards == emptyMoved.cards)
        let retainedCards = movedReopened.cards
        movedReopened.setPanelPosition(position)
        assert(!movedReopened.pendingSave)
        var invalidPosition = position
        invalidPosition.topFraction = .nan
        movedReopened.setPanelPosition(invalidPosition)
        assert(movedReopened.panelPosition == position && !movedReopened.pendingSave)
        let outside = PanelPosition(displayID: 22, horizontalFraction: -1, topFraction: 2, width: 120)
        movedReopened.setPanelPosition(outside)
        assert(movedReopened.panelPosition == outside.normalized)
        movedReopened.flush()
        assert(MemoStore(directory: movementDirectory).panelPosition == outside.normalized)
        movedReopened.setPanelPosition(nil)
        movedReopened.flush()
        let resetReopened = MemoStore(directory: movementDirectory)
        assert(resetReopened.panelPosition == nil && resetReopened.cards == retainedCards)

        let invalidDirectory = base.appendingPathComponent("blocked-by-file")
        try Data("blocked".utf8).write(to: invalidDirectory)
        let blocked = MemoStore(directory: invalidDirectory)
        blocked.add(.note)
        blocked.flush()
        assert(blocked.pendingSave && blocked.error != nil)
        try FileManager.default.removeItem(at: invalidDirectory)
        blocked.flush()
        assert(!blocked.pendingSave && blocked.error == nil)

        let corruptDirectory = base.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corruptFile = corruptDirectory.appendingPathComponent("notes.json")
        let corruptData = Data("broken".utf8)
        try corruptData.write(to: corruptFile)
        let corruptStore = MemoStore(directory: corruptDirectory)
        assert(!corruptStore.canEdit && corruptStore.error != nil)
        corruptStore.add(.note)
        corruptStore.setPanelPosition(position)
        corruptStore.flush()
        assert(corruptStore.cards.isEmpty && corruptStore.panelPosition == nil)
        let stillCorrupt = try Data(contentsOf: corruptFile)
        assert(stillCorrupt == corruptData)
        print("PASS: panel move save/relaunch with empty board and notes, edits retain position, redundant/invalid moves ignored, placement normalization and reset preserve cards, independent card resizing, resize undo/redo, automatic-height reset, bounds/invalid input, resized-card deletion undo, saved height on relaunch, card creation/editing, multiple tasks, insertion order, completion, last-item placeholder, debounce, write failure/retry, corrupted-data protection")
    }
}
