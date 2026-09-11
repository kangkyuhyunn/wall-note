import Foundation

@main
enum StorageTests {
    static func check(_ value: @autoclosure () throws -> Bool) throws {
        let result = try value()
        assert(result)
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SideMemo-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MemoStorage(directory: directory)
        try check(storage.load().cards.isEmpty)

        var task = MemoCard(kind: .task)
        task.bodyHeight = 180
        task.items = [TodoItem(text: "장보기 🥬"), TodoItem(text: "한국어 조합과 줄바꿈\n두 번째 줄")]
        let note = MemoCard(kind: .note, text: "메모를 바로 입력합니다.\nEnglish & 한글 👋\n\"quotes\" \\ slash", bodyHeight: 320)
        let position = PanelPosition(displayID: 42, displayUUID: "external-display",
                                     horizontalFraction: 0.23, topFraction: 0.41, width: 410)
        let original = MemoDocument(cards: [note, task], panelPosition: position)
        try storage.save(original)
        try check(storage.load() == original)

        // A 1.4 document retains card sizes but has no panel-position key.
        var previousVersion = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        previousVersion.removeValue(forKey: "panelPosition")
        try JSONSerialization.data(withJSONObject: previousVersion).write(to: storage.fileURL)
        let previousRestored = try storage.load()
        assert(previousRestored.panelPosition == nil && previousRestored.cards == original.cards)

        // A real pre-1.3 payload has no per-card height key.
        var legacy = previousVersion
        var legacyCards = legacy["cards"] as! [[String: Any]]
        for index in legacyCards.indices { legacyCards[index].removeValue(forKey: "bodyHeight") }
        legacy["cards"] = legacyCards
        try JSONSerialization.data(withJSONObject: legacy).write(to: storage.fileURL)
        let migrated = try storage.load()
        assert(migrated.panelPosition == nil)
        assert(migrated.cards.allSatisfy { $0.bodyHeight == nil })
        assert(migrated.cards[0].text == note.text && migrated.cards[1].items == task.items)

        var outOfRange = original
        outOfRange.cards[0].bodyHeight = 100000
        outOfRange.cards[1].bodyHeight = -10
        try storage.save(outOfRange)
        let normalized = try storage.load()
        assert(normalized.cards[0].bodyHeight == 100000 && normalized.cards[1].bodyHeight == 56)

        var moved = original
        moved.panelPosition = PanelPosition(displayID: 42, horizontalFraction: -2, topFraction: 3, width: 1000)
        try storage.save(moved)
        let clampedPosition = try storage.load()
        assert(clampedPosition.cards == original.cards)
        assert(clampedPosition.panelPosition == PanelPosition(displayID: 42, horizontalFraction: 0, topFraction: 1, width: 560))
        assert(PanelPosition(displayID: 42, horizontalFraction: 0, topFraction: 0, width: 1).normalized?.width == 330)
        for invalid in [Double.nan, .infinity, -.infinity] {
            assert(PanelPosition(displayID: 42, horizontalFraction: invalid, topFraction: 0).normalized == nil)
            assert(PanelPosition(displayID: 42, horizontalFraction: 0, topFraction: invalid).normalized == nil)
            assert(PanelPosition(displayID: 42, horizontalFraction: 0, topFraction: 0, width: invalid).normalized == nil)
        }
        moved.panelPosition = nil
        try storage.save(moved)
        let resetPosition = try storage.load()
        assert(resetPosition.panelPosition == nil && resetPosition.cards == original.cards)

        var completed = original
        completed.cards[1].items.removeFirst()
        try storage.save(completed)
        let restored = try storage.load()
        assert(restored.cards[1].items.count == 1)
        assert(restored.cards[0] == note)
        assert(restored.cards[1].items[0] == task.items[1])

        var deleted = completed
        deleted.cards.removeFirst()
        try storage.save(deleted)
        try check(storage.load().cards.count == 1)

        var large = MemoDocument()
        for index in 0..<500 { large.cards.append(MemoCard(kind: .note, text: "메모 \(index) " + String(repeating: "내용 ", count: 100))) }
        try storage.save(large)
        try check(storage.load() == large)

        let corrupt = Data("not valid json".utf8)
        try corrupt.write(to: storage.fileURL)
        do { _ = try storage.load(); fatalError("Corrupt data should throw") } catch { }
        try check(Data(contentsOf: storage.fileURL) == corrupt)

        var unsupported = original
        unsupported.version = 999
        try storage.save(unsupported)
        do { _ = try storage.load(); fatalError("Unknown version should throw") } catch StorageError.unsupportedVersion { }

        let duplicate = MemoDocument(cards: [note, note])
        try storage.save(duplicate)
        do { _ = try storage.load(); fatalError("Duplicate IDs should throw") } catch StorageError.duplicateIdentifiers { }

        try storage.save(MemoDocument())
        try check(storage.load().cards.isEmpty)
        // Upward deltas are positive; a scroll continues in the parent only at
        // the corresponding edge or when the card has no internal overflow.
        assert(CardScrollPolicy.passesToParent(contentHeight: 100, viewportHeight: 200, offset: 0, deltaY: -8))
        assert(CardScrollPolicy.passesToParent(contentHeight: 500, viewportHeight: 200, offset: 0, deltaY: 8))
        assert(!CardScrollPolicy.passesToParent(contentHeight: 500, viewportHeight: 200, offset: 0, deltaY: -8))
        assert(CardScrollPolicy.passesToParent(contentHeight: 500, viewportHeight: 200, offset: 300, deltaY: -8))
        assert(!CardScrollPolicy.passesToParent(contentHeight: 500, viewportHeight: 200, offset: 300, deltaY: 8))
        assert(!CardScrollPolicy.passesToParent(contentHeight: 500, viewportHeight: 200, offset: 150, deltaY: -8))

        print("PASS: saved panel position, legacy position-free and height-free data, normalized placement, invalid coordinates, position reset preserves notes, saved card heights, height bounds, nested scroll routing, empty state, Unicode round-trip, item completion, card deletion, 500 cards, corruption preservation, unknown version, duplicate IDs, empty save")
    }
}
