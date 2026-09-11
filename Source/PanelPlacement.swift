import Foundation
import CoreGraphics

struct DisplayInsets {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0
}

struct PanelDisplay {
    let id: UInt32
    let isBuiltIn: Bool
    let frame: CGRect
    let visibleFrame: CGRect
    var safeInsets = DisplayInsets()
    var uuid: String?
}

enum DockEdge: String {
    case bottom, left, right
}

enum PanelPlacement {
    static func display(in displays: [PanelDisplay], position: PanelPosition?, previousID: UInt32?) -> PanelDisplay? {
        if let position = position {
            if let uuid = position.displayUUID {
                // A display's numeric ID can change after reconnecting it.
                if let match = displays.first(where: { $0.uuid == uuid }) { return match }
            } else if let match = displays.first(where: { $0.id == position.displayID }) {
                return match
            }
        }
        return preferredDisplay(in: displays, previousID: previousID)
    }

    static func display(at point: CGPoint, in displays: [PanelDisplay]) -> PanelDisplay? {
        if let containing = displays.first(where: { $0.frame.contains(point) }) { return containing }
        // Display arrangements can have gaps. Pick the nearest real screen.
        func distance(to frame: CGRect) -> CGFloat {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            return dx * dx + dy * dy
        }
        return displays.min { distance(to: $0.frame) < distance(to: $1.frame) }
    }

    static func position(topLeft: CGPoint, preferredWidth: CGFloat, display: PanelDisplay,
                         in available: CGRect) -> PanelPosition {
        PanelPosition(displayID: display.id, displayUUID: display.uuid,
                      horizontalFraction: Double((topLeft.x - available.minX) / max(1, available.width)),
                      topFraction: Double((available.maxY - topLeft.y) / max(1, available.height)),
                      width: Double(preferredWidth)).normalized!
    }

    static func anchoredArea(in available: CGRect, position: PanelPosition?, minimumHeight: CGFloat) -> CGRect {
        guard let position = position?.normalized else { return available }
        // Keep the toolbar at the chosen top edge as cards grow or shrink.
        // Near the Dock, lift it only enough to keep one short card usable.
        let top = max(available.minY + min(available.height, minimumHeight),
                      available.maxY - CGFloat(position.topFraction) * available.height)
        return CGRect(x: available.minX, y: available.minY, width: available.width, height: top - available.minY)
    }

    static func preferredDisplay(in displays: [PanelDisplay], previousID: UInt32?) -> PanelDisplay? {
        let external = displays.filter { !$0.isBuiltIn }
        let candidates = external.isEmpty ? displays : external
        return candidates.first(where: { $0.id == previousID }) ?? candidates.first
    }

    // NSScreen.visibleFrame is authoritative for visible system UI. Reserve space
    // for the menu bar and the configured Dock as well when they auto-hide or move
    // between monitors. All coordinates here are AppKit points, never pixels.
    static func usableFrame(for display: PanelDisplay, menuBarHeight: CGFloat,
                            dockEdge: DockEdge, dockThickness: CGFloat, gap: CGFloat = 10) -> CGRect {
        let screen = display.frame
        let intersection = screen.intersection(display.visibleFrame)
        let visible = intersection.isNull || intersection.isEmpty ? screen : intersection
        var left = max(visible.minX, screen.minX + display.safeInsets.left)
        var right = min(visible.maxX, screen.maxX - display.safeInsets.right)
        var bottom = max(visible.minY, screen.minY + display.safeInsets.bottom)
        let top = min(visible.maxY, screen.maxY - max(display.safeInsets.top, menuBarHeight))
        let dock = max(0, dockThickness)
        switch dockEdge {
        case .bottom: bottom = max(bottom, screen.minY + dock)
        case .left: left = max(left, screen.minX + dock)
        case .right: right = min(right, screen.maxX - dock)
        }
        let usable = CGRect(x: left, y: bottom, width: max(1, right - left), height: max(1, top - bottom))
        return usable.insetBy(dx: min(gap, max(0, (usable.width - 1) / 2)),
                              dy: min(gap, max(0, (usable.height - 1) / 2)))
    }

    static func panelFrame(in available: CGRect, preferredWidth: CGFloat = 370, preferredHeight: CGFloat? = nil,
                           position: PanelPosition? = nil) -> CGRect {
        let width = min(preferredWidth, available.width)
        let height = min(max(1, preferredHeight ?? available.height), available.height)
        let x: CGFloat
        if let position = position?.normalized {
            x = min(available.maxX - width, available.minX + CGFloat(position.horizontalFraction) * available.width)
        } else {
            x = available.maxX - width
        }
        return CGRect(x: x, y: available.maxY - height, width: width, height: height)
    }

    static func constrain(_ proposed: CGRect, to available: CGRect) -> CGRect {
        let width = min(max(1, proposed.width), available.width)
        let height = min(max(1, proposed.height), available.height)
        let x = max(available.minX, min(proposed.minX, available.maxX - width))
        let y = max(available.minY, min(proposed.minY, available.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
