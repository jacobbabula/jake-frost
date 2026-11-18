import AppKit
import CoreGraphics

// Quartz reports global coordinates from the upper-left of the primary display.
// Every scene below uses upper-left coordinates local to its visible desktop.
struct WindowFrame {
    let id: UInt32
    let rect: CGRect
}

struct SnowEdge {
    let id: UInt32
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var visible: [ClosedRange<CGFloat>]

    func contains(_ position: CGFloat) -> Bool {
        visible.contains { $0.contains(position) }
    }
}

enum DesktopEdges {
    static func windows() -> [WindowFrame] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value != ownPID,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let data = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: data as CFDictionary),
                  rect.width >= 24, rect.height >= 16, rect.width <= 32768,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01 else { return nil }
            return WindowFrame(id: number.uint32Value, rect: rect)
        }
    }

    static func visible(_ windows: [WindowFrame], in screen: CGRect) -> [SnowEdge] {
        var edges = [SnowEdge]()
        var blockers = [CGRect]()
        for window in windows where window.rect.intersects(screen) {
            let rect = window.rect
            defer { blockers.append(rect) }
            let left = max(rect.minX + 5, screen.minX)
            let right = min(rect.maxX - 5, screen.maxX)
            guard right - left >= 12, rect.minY > screen.minY + 1, rect.minY < screen.maxY - 2 else { continue }
            var intervals = [left...right]
            for above in blockers where above.minY <= rect.minY && above.maxY > rect.minY {
                var remainder = [ClosedRange<CGFloat>]()
                for interval in intervals {
                    if above.maxX <= interval.lowerBound || above.minX >= interval.upperBound {
                        remainder.append(interval)
                    } else {
                        if above.minX - interval.lowerBound >= 10 { remainder.append(interval.lowerBound...above.minX) }
                        if interval.upperBound - above.maxX >= 10 { remainder.append(above.maxX...interval.upperBound) }
                    }
                }
                intervals = remainder
                if intervals.isEmpty { break }
            }
            let local = intervals.map { ($0.lowerBound - screen.minX)...($0.upperBound - screen.minX) }
            if !local.isEmpty {
                edges.append(SnowEdge(id: window.id, x: rect.minX-screen.minX, y: rect.minY-screen.minY,
                                      width: rect.width, visible: local))
            }
        }
        return edges
    }
}
