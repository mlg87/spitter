// Renders assets/icon-1024.png — the source art make_icon.sh turns into Spitter.icns.
//
// Committed rather than thrown away so the icon can be re-rendered at other sizes or recoloured
// without reverse-engineering a flat PNG. Run it from the repo root:
//
//     swift assets/make_icon_source.swift assets/icon-1024.png
//
// Design: a speech bubble holding a waveform — what the app does, in one glyph. The waveform is
// drawn as discrete rounded bars rather than the SF `waveform` symbol because that glyph's
// hairlines disappear at 16pt, the size the Finder shows most often. Sources/Spitter/MenubarGlyph
// restates this geometry for the menubar mark; this file is a standalone script, not part of the
// package, so the two cannot share code.

import AppKit

let tileTop = NSColor(calibratedRed: 32 / 255, green: 34 / 255, blue: 48 / 255, alpha: 1)
let tileBottom = NSColor(calibratedRed: 12 / 255, green: 12 / 255, blue: 20 / 255, alpha: 1)
let waveColor = NSColor(calibratedRed: 255 / 255, green: 92 / 255, blue: 141 / 255, alpha: 1)

/// Rounded bubble body plus a tail, drawn by hand so the tail angle and interior padding are ours
/// to control — the SF bubble glyph gives neither.
func bubblePath(rect: NSRect, radius: CGFloat, tailWidth: CGFloat, tailDrop: CGFloat) -> NSBezierPath {
    let body = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let tail = NSBezierPath()
    let baseX = rect.minX + rect.width * 0.26
    tail.move(to: NSPoint(x: baseX, y: rect.minY + 2))
    tail.curve(
        to: NSPoint(x: baseX - tailWidth * 0.30, y: rect.minY - tailDrop),
        controlPoint1: NSPoint(x: baseX - tailWidth * 0.05, y: rect.minY - tailDrop * 0.45),
        controlPoint2: NSPoint(x: baseX - tailWidth * 0.22, y: rect.minY - tailDrop * 0.80))
    tail.curve(
        to: NSPoint(x: baseX + tailWidth, y: rect.minY + 2),
        controlPoint1: NSPoint(x: baseX + tailWidth * 0.28, y: rect.minY - tailDrop * 0.45),
        controlPoint2: NSPoint(x: baseX + tailWidth * 0.72, y: rect.minY - tailDrop * 0.05))
    tail.close()
    body.append(tail)
    body.windingRule = .nonZero
    return body
}

func drawWaveform(center: NSPoint, width: CGFloat, unit: CGFloat) {
    let heights: [CGFloat] = [0.34, 0.62, 1.0, 0.78, 0.46, 0.86, 0.30]
    let gap = width / CGFloat(heights.count)
    let barWidth = gap * 0.46
    waveColor.set()
    for (index, height) in heights.enumerated() {
        let x = center.x - width / 2 + gap * (CGFloat(index) + 0.5)
        let barHeight = unit * height
        let bar = NSRect(x: x - barWidth / 2, y: center.y - barHeight / 2, width: barWidth, height: barHeight)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
}

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

// The 5.5% inset keeps the tile inside macOS's icon grid instead of bleeding to the edge.
let inset = size * 0.055
let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSBezierPath(roundedRect: tile, xRadius: size * 0.225, yRadius: size * 0.225).addClip()
NSGradient(starting: tileTop, ending: tileBottom)!.draw(in: tile, angle: -90)

let bubbleWidth = size * 0.62
let bubbleHeight = size * 0.46
let bubbleRect = NSRect(x: (size - bubbleWidth) / 2, y: size * 0.40, width: bubbleWidth, height: bubbleHeight)
NSColor.white.set()
bubblePath(rect: bubbleRect, radius: size * 0.115, tailWidth: size * 0.15, tailDrop: size * 0.16).fill()
drawWaveform(
    center: NSPoint(x: bubbleRect.midX, y: bubbleRect.midY),
    width: bubbleWidth * 0.66,
    unit: bubbleHeight * 0.58)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else { fatalError("failed to render icon") }

let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/icon-1024.png"
try png.write(to: URL(fileURLWithPath: destination))
print("wrote \(destination)")
