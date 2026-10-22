// Draws the RSS Feed Magazine app icon: swift buildscripts/make-app-icon.swift icon_1024.png, then sips into AppIcon.appiconset.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
cg.clear(CGRect(x: 0, y: 0, width: size, height: size))

func rgb(_ h: Int, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((h>>16)&255)/255, green: CGFloat((h>>8)&255)/255, blue: CGFloat(h&255)/255, alpha: a) }

// macOS icon grid: 824 x 824 body, corner radius ~185, centered, slight drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = rgb(0x000000, 0.28); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
rgb(0xF26B1D).setFill(); bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
bodyPath.addClip()
NSGradient(starting: rgb(0xFF9A3C), ending: rgb(0xE8550F))!.draw(in: body, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Back page, tilted: a magazine, not a single sheet.
func page(_ rect: CGRect, angle: CGFloat, color: NSColor, shadowAlpha: CGFloat) {
	NSGraphicsContext.saveGraphicsState()
	let t = NSAffineTransform()
	t.translateX(by: rect.midX, yBy: rect.midY); t.rotate(byDegrees: angle); t.translateX(by: -rect.midX, yBy: -rect.midY)
	t.concat()
	let s = NSShadow(); s.shadowColor = rgb(0x6A2300, shadowAlpha); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -12); s.set()
	color.setFill(); NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34).fill()
	NSGraphicsContext.restoreGraphicsState()
}
let front = CGRect(x: 300, y: 215, width: 440, height: 590)
page(front.offsetBy(dx: -46, dy: 6), angle: 8, color: rgb(0xFFE3CC), shadowAlpha: 0.25)
page(front, angle: -3, color: .white, shadowAlpha: 0.35)

// Contents of the front page, rotated with it.
NSGraphicsContext.saveGraphicsState()
let t = NSAffineTransform(); t.translateX(by: front.midX, yBy: front.midY); t.rotate(byDegrees: -3); t.translateX(by: -front.midX, yBy: -front.midY); t.concat()
// RSS glyph, built like the standard feed icon: the gaps between dot, inner arc, and outer arc are equal.
let orange = rgb(0xF0631A)
let stroke: CGFloat = 70
let dotRadius = stroke * 0.62
let gap = stroke * 0.85
let innerRadius = dotRadius + gap + stroke / 2
let outerRadius = innerRadius + stroke + gap
let origin = CGPoint(x: front.minX + 82, y: front.minY + 250)
orange.setFill(); NSBezierPath(ovalIn: CGRect(x: origin.x - dotRadius, y: origin.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)).fill()
for r in [innerRadius, outerRadius] {
	let arc = NSBezierPath()
	arc.appendArc(withCenter: origin, radius: r, startAngle: 0, endAngle: 90)
	arc.lineWidth = stroke; arc.lineCapStyle = .butt
	orange.setStroke(); arc.stroke()
}
// Text lines
rgb(0xCFCFCF).setFill()
for (i, w) in [340.0, 300.0, 330.0].enumerated() {
	NSBezierPath(roundedRect: CGRect(x: front.minX + 50, y: front.minY + 150 - CGFloat(i) * 46, width: w, height: 22), xRadius: 11, yRadius: 11).fill()
}
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
