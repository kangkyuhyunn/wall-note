import Foundation
import CoreGraphics

@main
enum PanelPlacementTests {
    static func checkClose(_ value: CGFloat, _ expected: CGFloat) {
        precondition(abs(value - expected) < 0.001, "Expected \(expected), got \(value)")
    }

    static func main() {
        let laptop = PanelDisplay(id: 1, isBuiltIn: true,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 78, width: 1512, height: 866),
            safeInsets: DisplayInsets(top: 38), uuid: "laptop")
        let external = PanelDisplay(id: 2, isBuiltIn: false,
            frame: CGRect(x: 1512, y: -100, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: -100, width: 1920, height: 1056), uuid: "desk")
        let upper = PanelDisplay(id: 3, isBuiltIn: false,
            frame: CGRect(x: -900, y: 982, width: 2560, height: 1440),
            visibleFrame: CGRect(x: -900, y: 982, width: 2560, height: 1416))

        assert(PanelPlacement.preferredDisplay(in: [laptop], previousID: nil)?.id == 1)
        assert(PanelPlacement.preferredDisplay(in: [laptop, external], previousID: 1)?.id == 2)
        assert(PanelPlacement.preferredDisplay(in: [laptop], previousID: 2)?.id == 1)
        assert(PanelPlacement.preferredDisplay(in: [laptop, external], previousID: 1)?.id == 2)
        assert(PanelPlacement.preferredDisplay(in: [laptop, upper, external], previousID: 2)?.id == 2)
        assert(PanelPlacement.preferredDisplay(in: [external], previousID: 1)?.id == 2)
        assert(PanelPlacement.preferredDisplay(in: [], previousID: 2) == nil)

        // A deliberate move to the laptop overrides automatic external-screen
        // preference. Resetting that choice restores the external-screen rule.
        let manualLaptop = PanelPosition(displayID: 1, displayUUID: "laptop", horizontalFraction: 0.2, topFraction: 0.3)
        assert(PanelPlacement.display(in: [laptop, external], position: manualLaptop, previousID: 2)?.id == 1)
        assert(PanelPlacement.display(in: [laptop, external], position: nil, previousID: 1)?.id == 2)
        let manualExternal = PanelPosition(displayID: 2, displayUUID: "desk", horizontalFraction: 0.2, topFraction: 0.3)
        assert(PanelPlacement.display(in: [laptop], position: manualExternal, previousID: 2)?.id == 1)
        let reconnected = PanelDisplay(id: 20, isBuiltIn: false, frame: external.frame,
                                      visibleFrame: external.visibleFrame, uuid: "desk")
        let reusedID = PanelDisplay(id: 2, isBuiltIn: false, frame: upper.frame,
                                   visibleFrame: upper.visibleFrame, uuid: "other-monitor")
        assert(PanelPlacement.display(in: [laptop, reusedID, reconnected], position: manualExternal, previousID: 2)?.id == 20)
        // Once a UUID is known, a recycled numeric ID must not select a different monitor.
        assert(PanelPlacement.display(in: [laptop, external, reusedID], position: manualLaptop, previousID: 2)?.id == 1)
        let missingUUID = PanelPosition(displayID: 2, displayUUID: "disconnected-monitor", horizontalFraction: 0, topFraction: 0)
        assert(PanelPlacement.display(in: [laptop, reconnected, reusedID], position: missingUUID, previousID: 20)?.id == 20)
        let numericOnly = PanelPosition(displayID: 3, horizontalFraction: 0, topFraction: 0)
        assert(PanelPlacement.display(in: [laptop, external, upper], position: numericOnly, previousID: 2)?.id == 3)
        assert(PanelPlacement.display(in: [], position: manualExternal, previousID: 2) == nil)

        assert(PanelPlacement.display(at: CGPoint(x: 1700, y: -50), in: [laptop, external, upper])?.id == 2)
        assert(PanelPlacement.display(at: CGPoint(x: -500, y: 1100), in: [laptop, external, upper])?.id == 3)
        assert(PanelPlacement.display(at: CGPoint(x: -50, y: 200), in: [laptop, external, upper])?.id == 1)
        assert(PanelPlacement.display(at: CGPoint(x: 10000, y: 0), in: [laptop, external])?.id == 2)
        assert(PanelPlacement.display(at: .zero, in: []) == nil)

        let safe = PanelPlacement.usableFrame(for: laptop, menuBarHeight: 24, dockEdge: .bottom, dockThickness: 64)
        let panel = PanelPlacement.panelFrame(in: safe)
        // Visible Dock is already taller than the fallback, so it is counted once.
        assert(panel.minY == 88 && panel.maxY == 934 && panel.maxX == 1502)
        assert(panel.width == 370)
        assert(laptop.visibleFrame.contains(panel))

        // The saved top-left uses the screen's usable area, not the current
        // panel height. Adding cards therefore grows down from the chosen bar.
        let chosenTopLeft = CGPoint(x: safe.minX + 280, y: safe.maxY - 200)
        let chosen = PanelPlacement.position(topLeft: chosenTopLeft, preferredWidth: 410, display: laptop, in: safe)
        assert(chosen.displayID == laptop.id && chosen.displayUUID == laptop.uuid && chosen.width == 410)
        let anchored = PanelPlacement.anchoredArea(in: safe, position: chosen, minimumHeight: 205)
        checkClose(anchored.maxY, chosenTopLeft.y)
        for contentHeight: CGFloat in [52, 205, 450, 10000, 52] {
            let moved = PanelPlacement.panelFrame(in: anchored, preferredWidth: 410,
                                                  preferredHeight: contentHeight, position: chosen)
            checkClose(moved.minX, chosenTopLeft.x)
            checkClose(moved.maxY, chosenTopLeft.y)
            checkClose(moved.height, min(contentHeight, anchored.height))
            assert(safe.contains(moved))
        }
        assert(PanelPlacement.anchoredArea(in: safe, position: nil, minimumHeight: 205) == safe)

        // At the bottom edge an empty bar can sit lower; the first card lifts
        // its anchor only enough to leave a usable card above the Dock.
        let bottom = PanelPosition(displayID: 1, horizontalFraction: 1, topFraction: 1)
        let bottomEmpty = PanelPlacement.anchoredArea(in: safe, position: bottom, minimumHeight: 52)
        let bottomCard = PanelPlacement.anchoredArea(in: safe, position: bottom, minimumHeight: 205)
        checkClose(bottomEmpty.height, 52)
        checkClose(bottomCard.height, 205)
        let bottomFrame = PanelPlacement.panelFrame(in: bottomCard, preferredHeight: 10000, position: bottom)
        checkClose(bottomFrame.minY, safe.minY)
        checkClose(bottomFrame.maxX, safe.maxX)
        assert(safe.contains(bottomFrame))

        // Relative positioning survives negative screen origins, rearrangement,
        // and resolution changes without drifting outside the safe rectangle.
        let negativeSafe = CGRect(x: -1910, y: -986, width: 1900, height: 942)
        let negativeDisplay = PanelDisplay(id: 7, isBuiltIn: false,
            frame: CGRect(x: -1920, y: -1080, width: 1920, height: 1080), visibleFrame: negativeSafe, uuid: "left-below")
        let negativeTopLeft = CGPoint(x: -1500, y: -210)
        let negativePosition = PanelPlacement.position(topLeft: negativeTopLeft, preferredWidth: 370,
                                                       display: negativeDisplay, in: negativeSafe)
        let negativeAnchor = PanelPlacement.anchoredArea(in: negativeSafe, position: negativePosition, minimumHeight: 205)
        let negativeFrame = PanelPlacement.panelFrame(in: negativeAnchor, preferredHeight: 350, position: negativePosition)
        checkClose(negativeFrame.minX, negativeTopLeft.x)
        checkClose(negativeFrame.maxY, negativeTopLeft.y)
        assert(negativeSafe.contains(negativeFrame))
        let scaledSafe = CGRect(x: 2200, y: 100, width: 1520, height: 753.6)
        let scaledAnchor = PanelPlacement.anchoredArea(in: scaledSafe, position: negativePosition, minimumHeight: 205)
        let scaledFrame = PanelPlacement.panelFrame(in: scaledAnchor, preferredHeight: 350, position: negativePosition)
        checkClose(scaledFrame.minX, scaledSafe.minX + 328)
        checkClose(scaledFrame.maxY, scaledSafe.maxY - 132.8)
        assert(scaledSafe.contains(scaledFrame))

        // Empty board: the actual window occupies just the control bar.
        let toolbarOnly = PanelPlacement.panelFrame(in: safe, preferredHeight: 52)
        assert(toolbarOnly.height == 52 && toolbarOnly.maxY == safe.maxY)
        assert(toolbarOnly.minY > safe.minY)
        let oneCard = PanelPlacement.panelFrame(in: safe, preferredHeight: 210)
        assert(oneCard.height == 210 && oneCard.maxY == toolbarOnly.maxY)
        assert(oneCard.minY < toolbarOnly.minY && oneCard.minY > safe.minY)
        let overflowing = PanelPlacement.panelFrame(in: safe, preferredHeight: 10000)
        assert(overflowing.height == safe.height && overflowing.minY == safe.minY)
        let removedAll = PanelPlacement.panelFrame(in: safe, preferredHeight: 52)
        assert(removedAll == toolbarOnly)
        let narrowContent = PanelPlacement.panelFrame(in: safe, preferredWidth: 310, preferredHeight: 290)
        assert(narrowContent.width == 310 && narrowContent.height == 290 && narrowContent.maxY == safe.maxY)

        let oldExternalFrame = CGRect(x: 1142, y: -100, width: 600, height: 1440)
        let corrected = PanelPlacement.constrain(oldExternalFrame, to: safe)
        assert(safe.contains(corrected))
        assert(corrected.maxY <= laptop.visibleFrame.maxY - 10)
        assert(corrected.minY >= laptop.visibleFrame.minY + 10)

        // Menu bar and Dock auto-hide: visibleFrame alone would cover both.
        let autoHidden = PanelDisplay(id: 1, isBuiltIn: true, frame: laptop.frame, visibleFrame: laptop.frame,
                                     safeInsets: DisplayInsets(top: 38))
        let hiddenSafe = PanelPlacement.usableFrame(for: autoHidden, menuBarHeight: 24, dockEdge: .bottom, dockThickness: 100)
        assert(hiddenSafe.minY == 110 && hiddenSafe.maxY == 934)
        let leftSafe = PanelPlacement.usableFrame(for: autoHidden, menuBarHeight: 24, dockEdge: .left, dockThickness: 90)
        let rightSafe = PanelPlacement.usableFrame(for: autoHidden, menuBarHeight: 24, dockEdge: .right, dockThickness: 90)
        assert(leftSafe.minX == 100)
        assert(rightSafe.maxX == 1412)

        for display in [external, upper] {
            let available = PanelPlacement.usableFrame(for: display, menuBarHeight: 24, dockEdge: .bottom, dockThickness: 84)
            let frame = PanelPlacement.panelFrame(in: available)
            assert(display.frame.contains(frame))
            assert(frame.maxY <= display.frame.maxY - 34)
            assert(frame.minY >= display.frame.minY + 94)
            assert(frame.maxX == display.frame.maxX - 10)
            for contentHeight: CGFloat in [52, 210, 20000] {
                let fitted = PanelPlacement.panelFrame(in: available, preferredHeight: contentHeight)
                assert(fitted.height == min(contentHeight, available.height))
                assert(fitted.maxY == available.maxY && fitted.maxX == available.maxX)
                assert(available.contains(fitted))
            }
        }

        // A stale full-screen visibleFrame must still respect a tall notch/menu area.
        let tallNotch = PanelDisplay(id: 1, isBuiltIn: true, frame: laptop.frame, visibleFrame: laptop.frame,
                                    safeInsets: DisplayInsets(top: 54))
        let notchSafe = PanelPlacement.usableFrame(for: tallNotch, menuBarHeight: 24, dockEdge: .bottom, dockThickness: 84)
        assert(notchSafe.maxY == 918)

        let small = PanelDisplay(id: 4, isBuiltIn: false, frame: CGRect(x: -320, y: 0, width: 320, height: 300),
                                 visibleFrame: CGRect(x: -320, y: 0, width: 320, height: 300))
        let smallSafe = PanelPlacement.usableFrame(for: small, menuBarHeight: 24, dockEdge: .bottom, dockThickness: 64)
        let smallPanel = PanelPlacement.panelFrame(in: smallSafe)
        assert(smallSafe.contains(smallPanel) && smallPanel.width < 310 && smallPanel.height < 330)
        let expanded = PanelPlacement.constrain(CGRect(x: -10000, y: -10000, width: 20000, height: 20000), to: smallSafe)
        assert(expanded == smallSafe)
        let tinyArea = PanelPlacement.anchoredArea(in: smallSafe, position: bottom, minimumHeight: 205)
        assert(tinyArea == smallSafe)

        print("PASS: manual monitor preference/reset, display UUID reconnect and recycled IDs, drag screen selection and gaps, saved top-left through content growth/shrink, bottom card clearance, negative-origin capture and resolution changes, toolbar-only window, overflow cap, laptop menu/Dock bounds, automatic external-display preference, connect/disconnect/reconnect, clamshell, multiple monitors, auto-hidden Dock/menu, left/right Dock, notch, stale oversized frames, small displays")
    }
}
