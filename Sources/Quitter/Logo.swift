import AppKit

/// Power symbol (open ring + top bar) with a Q tail. Drawn on an 18-unit grid and scaled to `size`.
/// Template image, so the menu bar tints it for light/dark mode and highlight.
func quitterLogo(size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = rect.width / 18
        func stroke(_ path: NSBezierPath) {
            path.lineWidth = 1.8 * s
            path.lineCapStyle = .round
            path.stroke()
        }
        func line(_ a: NSPoint, _ b: NSPoint) {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: a.x * s, y: a.y * s))
            p.line(to: NSPoint(x: b.x * s, y: b.y * s))
            stroke(p)
        }
        NSColor.black.setStroke()
        let ring = NSBezierPath()
        ring.appendArc(withCenter: NSPoint(x: 9 * s, y: 9 * s), radius: 6.2 * s, startAngle: 122, endAngle: 58, clockwise: false)
        stroke(ring)
        line(NSPoint(x: 9, y: 9.5), NSPoint(x: 9, y: 16.5))     // power bar
        line(NSPoint(x: 12.2, y: 5.8), NSPoint(x: 15.8, y: 2.2)) // Q tail
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Quitter"
    return image
}
