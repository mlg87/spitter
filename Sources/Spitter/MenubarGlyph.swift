import AppKit

/// The menubar mark: the same speech-bubble-with-waveform as the app icon, drawn at menubar size.
///
/// State is communicated by colour rather than by swapping symbols, so the shape in the bar never
/// jumps around. Idle renders as a template image (macOS inverts it for light/dark menubars);
/// every other state uses an explicit colour, which requires `isTemplate = false` because template
/// rendering flattens all opaque pixels to a single mask and would erase the waveform bars.
///
/// The geometry mirrors `assets/make_icon_source.swift`; it is restated here rather than shared
/// because that generator is a standalone script, not part of the built package.
enum MenubarGlyph {
    /// Menubar images are ~18pt tall on the standard 22pt bar.
    private static let height: CGFloat = 18

    /// Bars are drawn as discrete rounded rects: the SF `waveform` hairlines vanish at this size.
    private static let barHeights: [CGFloat] = [0.34, 0.72, 1.0, 0.56]

    /// `nil` colour produces the adaptive template image used when idle.
    static func image(color: NSColor?) -> NSImage {
        let h = height
        let w = h * 1.12
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()

        let ink = color ?? .black
        ink.set()

        let line = max(1.4, h * 0.085)
        let body = NSRect(x: line / 2, y: h * 0.26, width: w - line, height: h * 0.70)
        let bubble = NSBezierPath(roundedRect: body, xRadius: h * 0.24, yRadius: h * 0.24)
        bubble.lineWidth = line
        bubble.stroke()

        let tail = NSBezierPath()
        let tailBase = body.minX + body.width * 0.26
        tail.move(to: NSPoint(x: tailBase, y: body.minY + line * 0.4))
        tail.line(to: NSPoint(x: tailBase - h * 0.05, y: line / 2))
        tail.line(to: NSPoint(x: tailBase + h * 0.30, y: body.minY + line * 0.4))
        tail.close()
        tail.fill()

        let barWidth = max(1.2, h * 0.075)
        let span = body.width * 0.62
        let gap = span / CGFloat(barHeights.count)
        for (index, factor) in barHeights.enumerated() {
            let x = body.midX - span / 2 + gap * (CGFloat(index) + 0.5)
            let barHeight = body.height * 0.52 * factor
            let bar = NSRect(x: x - barWidth / 2, y: body.midY - barHeight / 2, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }

        image.unlockFocus()
        image.isTemplate = color == nil
        return image
    }
}

/// Menubar colours. Chosen to stay legible on both a white and a dark menubar, and to keep the
/// two states a user sees most (recording, transcribing) far apart in hue.
enum GlyphColor {
    /// Recording — the one state where being unmissable matters.
    static let recording = NSColor(calibratedRed: 1.00, green: 0.18, blue: 0.44, alpha: 1)
    /// Transcribing is violet rather than another warm hue so it cannot be confused with the
    /// recording pink at a glance.
    static let transcribing = NSColor(calibratedRed: 0.48, green: 0.36, blue: 1.00, alpha: 1)
    static let pasted = NSColor(calibratedRed: 0.19, green: 0.78, blue: 0.37, alpha: 1)
    static let clipboard = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)
    /// A dictation that failed — a 1.5s flash, so it gets its own hue rather than sharing the
    /// persistent permission-warning red.
    static let failed = NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.05, alpha: 1)
    /// Missing permissions: persistent, and dimmed so a standing warning never reads as the
    /// momentary flash of a failed take.
    static let warning = NSColor(calibratedRed: 0.88, green: 0.15, blue: 0.12, alpha: 0.55)
    /// Empty transcript: nothing went wrong, nothing was delivered — a neutral grey blip.
    static let empty = NSColor(calibratedRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)
}
