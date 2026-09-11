import Foundation
import CoreGraphics

@main
enum SidebarLayoutTests {
    static func checkClose(_ value: CGFloat, _ expected: CGFloat) {
        precondition(abs(value - expected) < 0.001, "Expected \(expected), got \(value)")
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SideMemo-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemoStore(directory: directory)
        let laptop = PanelDisplay(id: 1, isBuiltIn: true,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 78, width: 1512, height: 866), safeInsets: DisplayInsets(top: 38))
        let safe = PanelPlacement.usableFrame(for: laptop, menuBarHeight: 24, dockEdge: .bottom, dockThickness: 84)
        let layout = SidebarLayout(availableHeight: safe.height, controlHeight: 52)
        checkClose(layout.contentHeight(bodyHeights: []), 52)
        checkClose(layout.scrollHeight(bodyHeights: []), 0)

        store.add(.note)
        let note = store.cards[0]
        let initialBody = layout.bodyHeight(for: note, naturalHeight: 76, previewHeight: nil)
        let initialHeight = layout.contentHeight(bodyHeights: [initialBody])
        let initialFrame = PanelPlacement.panelFrame(in: safe, preferredHeight: initialHeight)

        // Reproduce the resize sequence with an unchanged empty editor. No lazy
        // stack geometry callback is needed to grow the scroll view or window.
        var lastHeight = initialHeight
        for preview in stride(from: CGFloat(76), through: layout.maximumBodyHeight + 100, by: 3.25) {
            let body = layout.bodyHeight(for: note, naturalHeight: 76, previewHeight: preview)
            let desiredHeight = layout.contentHeight(bodyHeights: [body])
            let frame = PanelPlacement.panelFrame(in: safe, preferredHeight: desiredHeight)
            precondition(frame.height >= lastHeight && safe.contains(frame))
            checkClose(frame.height, desiredHeight)
            checkClose(frame.maxY, initialFrame.maxY)
            // The complete card, including its grip and bottom padding, fits.
            checkClose(layout.scrollHeight(bodyHeights: [body]), body + SidebarLayout.cardChromeHeight + 4)
            lastHeight = frame.height
        }
        checkClose(lastHeight, safe.height)

        let shortBody = layout.bodyHeight(for: note, naturalHeight: 76, previewHeight: 100)
        let shortFrame = PanelPlacement.panelFrame(in: safe, preferredHeight: layout.contentHeight(bodyHeights: [shortBody]))
        precondition(shortFrame.height < lastHeight)
        checkClose(shortFrame.maxY, initialFrame.maxY)

        // Saving/reopening uses the same height as the drag preview, even before
        // the editor or any offscreen cards have been created by SwiftUI.
        store.setBodyHeight(note.id, height: Double(layout.maximumBodyHeight))
        store.flush()
        let reopened = MemoStore(directory: directory)
        let restoredBody = layout.bodyHeight(for: reopened.cards[0], naturalHeight: nil, previewHeight: nil)
        checkClose(layout.contentHeight(bodyHeights: [restoredBody]), safe.height)

        // A larger display can use more than the old fixed 1,200 pt limit.
        let tallLayout = SidebarLayout(availableHeight: 2200, controlHeight: 52)
        store.setBodyHeight(note.id, height: Double(tallLayout.maximumBodyHeight))
        store.flush()
        let tallReopened = MemoStore(directory: directory)
        let tallNote = tallReopened.cards[0]
        precondition(tallNote.bodyHeight! > 1200)
        checkClose(tallLayout.contentHeight(bodyHeights: [tallLayout.bodyHeight(for: tallNote, naturalHeight: nil, previewHeight: nil)]), 2200)
        checkClose(layout.contentHeight(bodyHeights: [layout.bodyHeight(for: tallNote, naturalHeight: nil, previewHeight: nil)]), safe.height)
        precondition(tallReopened.cards[0].bodyHeight == tallNote.bodyHeight)

        // Several cards still overflow into the board scroll view. Enlarging one
        // does not change another card's saved height; toolbar stays outside it.
        store.add(.task)
        store.setBodyHeight(store.cards[0].id, height: 200)
        let bodies = store.cards.map { layout.bodyHeight(for: $0, naturalHeight: nil, previewHeight: nil) }
        checkClose(bodies[0], 200)
        precondition(layout.contentHeight(bodyHeights: bodies) > safe.height)
        checkClose(layout.scrollHeight(bodyHeights: bodies), safe.height - 52 - 10)
        let crowdedFrame = PanelPlacement.panelFrame(in: safe, preferredHeight: layout.contentHeight(bodyHeights: bodies))
        precondition(crowdedFrame == safe.replacingWidth(370))

        // Long automatic content also keeps its grip within a screen-height card.
        for kind in [CardKind.note, .task] {
            let automatic = MemoCard(kind: kind)
            let body = layout.bodyHeight(for: automatic, naturalHeight: 10000, previewHeight: nil)
            checkClose(layout.contentHeight(bodyHeights: [body]), safe.height)
        }
        let errorLayout = SidebarLayout(availableHeight: safe.height, controlHeight: 94)
        checkClose(errorLayout.contentHeight(bodyHeights: [errorLayout.maximumBodyHeight]), safe.height)
        precondition(errorLayout.maximumBodyHeight < layout.maximumBodyHeight)

        // Moving a board downward reduces the viewport below its chosen bar.
        // Its resize grip remains reachable, without changing saved heights.
        let lowPosition = PanelPosition(displayID: 1, horizontalFraction: 0.25, topFraction: 0.65)
        let minimumCardPanel = SidebarLayout.minimumPanelHeight(controlHeight: 52, hasCards: true)
        let lowArea = PanelPlacement.anchoredArea(in: safe, position: lowPosition, minimumHeight: minimumCardPanel)
        let lowLayout = SidebarLayout(availableHeight: lowArea.height, controlHeight: 52)
        precondition(lowLayout.maximumBodyHeight < layout.maximumBodyHeight)
        let originalSavedHeight = tallNote.bodyHeight
        let lowSavedBody = lowLayout.bodyHeight(for: tallNote, naturalHeight: nil, previewHeight: nil)
        checkClose(lowLayout.contentHeight(bodyHeights: [lowSavedBody]), lowArea.height)
        for preview in [CGFloat(56), 76, lowLayout.maximumBodyHeight, 10000] {
            let body = lowLayout.bodyHeight(for: tallNote, naturalHeight: nil, previewHeight: preview)
            let contentHeight = lowLayout.contentHeight(bodyHeights: [body])
            let frame = PanelPlacement.panelFrame(in: lowArea, preferredHeight: contentHeight, position: lowPosition)
            checkClose(frame.height, contentHeight)
            checkClose(frame.maxY, safe.maxY - safe.height * 0.65)
            checkClose(frame.minX, safe.minX + safe.width * 0.25)
            checkClose(lowLayout.scrollHeight(bodyHeights: [body]), body + SidebarLayout.cardChromeHeight + 4)
            precondition(safe.contains(frame))
        }
        let lowBodies = store.cards.map { lowLayout.bodyHeight(for: $0, naturalHeight: nil, previewHeight: nil) }
        precondition(lowLayout.contentHeight(bodyHeights: lowBodies) > lowArea.height)
        checkClose(lowLayout.scrollHeight(bodyHeights: lowBodies), lowArea.height - 52 - 10)
        checkClose(PanelPlacement.panelFrame(in: lowArea, preferredHeight: lowLayout.contentHeight(bodyHeights: lowBodies),
                                           position: lowPosition).height, lowArea.height)
        precondition(tallNote.bodyHeight == originalSavedHeight)
        // Moving back up expands the same saved preference again.
        checkClose(layout.bodyHeight(for: tallNote, naturalHeight: nil, previewHeight: nil), layout.maximumBodyHeight)

        let bottomPosition = PanelPosition(displayID: 1, horizontalFraction: 0.5, topFraction: 1)
        checkClose(SidebarLayout.minimumPanelHeight(controlHeight: 52, hasCards: false), 52)
        let emptyBottom = PanelPlacement.anchoredArea(in: safe, position: bottomPosition,
            minimumHeight: SidebarLayout.minimumPanelHeight(controlHeight: 52, hasCards: false))
        checkClose(emptyBottom.height, 52)
        let firstCardBottom = PanelPlacement.anchoredArea(in: safe, position: bottomPosition, minimumHeight: minimumCardPanel)
        let bottomLayout = SidebarLayout(availableHeight: firstCardBottom.height, controlHeight: 52)
        checkClose(bottomLayout.maximumBodyHeight, CGFloat(CardSizing.minimumBodyHeight))
        let bottomBody = bottomLayout.bodyHeight(for: note, naturalHeight: 1000, previewHeight: nil)
        checkClose(bottomLayout.contentHeight(bodyHeights: [bottomBody]), firstCardBottom.height)
        checkClose(bottomLayout.scrollHeight(bodyHeights: [bottomBody]), bottomBody + SidebarLayout.cardChromeHeight + 4)
        let bottomErrorArea = PanelPlacement.anchoredArea(in: safe, position: bottomPosition,
            minimumHeight: SidebarLayout.minimumPanelHeight(controlHeight: 94, hasCards: true))
        let bottomErrorLayout = SidebarLayout(availableHeight: bottomErrorArea.height, controlHeight: 94)
        checkClose(bottomErrorLayout.maximumBodyHeight, CGFloat(CardSizing.minimumBodyHeight))
        checkClose(bottomErrorLayout.contentHeight(bodyHeights: [bottomErrorLayout.maximumBodyHeight]), bottomErrorArea.height)

        // Even a malformed huge preference is bounded before constructing a view.
        let huge = MemoCard(kind: .note, bodyHeight: Double.greatestFiniteMagnitude)
        checkClose(layout.bodyHeight(for: huge, naturalHeight: nil, previewHeight: nil), layout.maximumBodyHeight)
        store.cards.forEach { store.remove($0.id, undoManager: nil) }
        checkClose(layout.contentHeight(bodyHeights: store.cards.map { layout.bodyHeight(for: $0, naturalHeight: nil, previewHeight: nil) }), 52)

        print("PASS: moved-down viewport resizing/overflow, saved height retained across movement, bottom toolbar and first-card clearance, bottom save-error clearance, empty-editor live resize to full usable height, grip fits, shrink, top anchoring, restore before rendering, tall display beyond 1200 pt, display change, independent cards, board overflow, long automatic content, toolbar errors, huge stored height, toolbar-only reset")
    }
}

private extension CGRect {
    func replacingWidth(_ width: CGFloat) -> CGRect {
        CGRect(x: maxX - width, y: minY, width: width, height: height)
    }
}
