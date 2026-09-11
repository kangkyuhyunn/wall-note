import Foundation

// The card, scroll viewport, and native panel all use these same dimensions.
// Never size the window from the geometry of an already-clipped lazy stack.
struct SidebarLayout {
    static let toolbarGap: CGFloat = 10
    static let cardGap: CGFloat = 12
    static let listBottomPadding: CGFloat = 4
    static let cardPadding: CGFloat = 14
    static let cardHeaderHeight: CGFloat = 25
    static let cardHeaderTopPadding: CGFloat = -4
    static let cardContentGap: CGFloat = 10
    static let resizeHandleHeight: CGFloat = 14
    static let cardChromeHeight = cardPadding * 2 + cardHeaderHeight + cardHeaderTopPadding +
        cardContentGap * 2 + resizeHandleHeight

    let availableHeight: CGFloat
    let controlHeight: CGFloat

    static func minimumPanelHeight(controlHeight: CGFloat, hasCards: Bool) -> CGFloat {
        controlHeight + (hasCards ? toolbarGap + cardChromeHeight + CGFloat(CardSizing.minimumBodyHeight) + listBottomPadding : 0)
    }

    var maximumBodyHeight: CGFloat {
        max(CGFloat(CardSizing.minimumBodyHeight), availableHeight - controlHeight - Self.toolbarGap -
            Self.listBottomPadding - Self.cardChromeHeight)
    }

    func constrainedBodyHeight(_ height: CGFloat) -> CGFloat {
        min(maximumBodyHeight, max(CGFloat(CardSizing.minimumBodyHeight), height))
    }

    func bodyHeight(for card: MemoCard, naturalHeight: CGFloat?, previewHeight: CGFloat?) -> CGFloat {
        if let manual = previewHeight ?? card.bodyHeight.map({ CGFloat($0) }) {
            return constrainedBodyHeight(manual)
        }
        let fallback: CGFloat = card.kind == .note ? 76 : max(48, CGFloat(card.items.count) * 34 + 15)
        return min(maximumBodyHeight, max(card.kind == .note ? 76 : 48, naturalHeight ?? fallback))
    }

    func cardsHeight(bodyHeights: [CGFloat]) -> CGFloat {
        guard !bodyHeights.isEmpty else { return 0 }
        return bodyHeights.reduce(0, +) + CGFloat(bodyHeights.count) * Self.cardChromeHeight +
            CGFloat(bodyHeights.count - 1) * Self.cardGap + Self.listBottomPadding
    }

    func contentHeight(bodyHeights: [CGFloat]) -> CGFloat {
        controlHeight + (bodyHeights.isEmpty ? 0 : Self.toolbarGap + cardsHeight(bodyHeights: bodyHeights))
    }

    func scrollHeight(bodyHeights: [CGFloat]) -> CGFloat {
        min(cardsHeight(bodyHeights: bodyHeights), max(0, availableHeight - controlHeight - Self.toolbarGap))
    }
}
