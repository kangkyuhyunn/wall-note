import Foundation

enum CardKind: String, Codable {
    case note
    case task
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
}

enum CardSizing {
    static let minimumBodyHeight: Double = 56

    static func normalizedHeight(_ height: Double?) -> Double? {
        guard let height = height, height.isFinite else { return nil }
        // The active display limits the rendered height in SidebarLayout.
        // Preserve the preferred height when moving between different displays.
        return max(minimumBodyHeight, height.rounded())
    }
}

enum CardScrollPolicy {
    static func passesToParent(contentHeight: Double, viewportHeight: Double, offset: Double, deltaY: Double) -> Bool {
        let maximumOffset = max(0, contentHeight - viewportHeight)
        return maximumOffset <= 0.5 || (deltaY > 0 && offset <= 0.5) ||
            (deltaY < 0 && offset >= maximumOffset - 0.5)
    }
}

struct MemoCard: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: CardKind
    var text: String
    var createdAt: Date
    var items: [TodoItem]
    // Missing in older save files; nil keeps the original automatic sizing.
    var bodyHeight: Double?

    init(id: UUID = UUID(), kind: CardKind, text: String = "", createdAt: Date = Date(), bodyHeight: Double? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.items = kind == .task ? [TodoItem()] : []
        self.bodyHeight = CardSizing.normalizedHeight(bodyHeight)
    }
}

struct PanelPosition: Codable, Equatable {
    var displayID: UInt32
    var displayUUID: String?
    // Fractions of the display's usable area, measured from its top-left.
    // They do not depend on the current number or height of cards.
    var horizontalFraction: Double
    var topFraction: Double
    var width: Double = 370

    var normalized: PanelPosition? {
        guard horizontalFraction.isFinite, topFraction.isFinite, width.isFinite else { return nil }
        var result = self
        result.horizontalFraction = min(1, max(0, horizontalFraction))
        result.topFraction = min(1, max(0, topFraction))
        result.width = min(560, max(330, width))
        return result
    }
}

struct MemoDocument: Codable, Equatable {
    var version = 1
    var cards: [MemoCard] = []
    // Absent in older files: keep the original automatic right-side placement.
    var panelPosition: PanelPosition?
}

enum StorageError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicateIdentifiers

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "지원하지 않는 저장 형식입니다 (버전 \(version))."
        case .duplicateIdentifiers: return "저장 파일에 중복된 메모가 있습니다."
        }
    }
}

struct MemoStorage {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("notes.json") }

    func load() throws -> MemoDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return MemoDocument() }
        var document = try JSONDecoder().decode(MemoDocument.self, from: Data(contentsOf: fileURL))
        guard document.version == 1 else { throw StorageError.unsupportedVersion(document.version) }
        let identifiers = document.cards.flatMap { [$0.id] + $0.items.map(\.id) }
        guard Set(identifiers).count == identifiers.count else {
            throw StorageError.duplicateIdentifiers
        }
        for index in document.cards.indices {
            document.cards[index].bodyHeight = CardSizing.normalizedHeight(document.cards[index].bodyHeight)
        }
        document.panelPosition = document.panelPosition?.normalized
        return document
    }

    func save(_ document: MemoDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
