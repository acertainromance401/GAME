import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let canvasWidth = 1080
let canvasHeight = 1920
let white = NSColor.white
let blue = NSColor(srgbRed: 0.16, green: 0.72, blue: 1, alpha: 1)
let red = NSColor(srgbRed: 1, green: 0.18, blue: 0.28, alpha: 1)

func text(_ value: String, top: CGFloat, size: CGFloat, color: NSColor = .white) {
    let font = NSFont(name: "DINAlternate-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
    shadow.shadowBlurRadius = 8
    shadow.shadowOffset = NSSize(width: 0, height: -2)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .shadow: shadow
    ]
    let attributed = NSAttributedString(string: value, attributes: attributes)
    let dimensions = attributed.size()
    precondition(dimensions.width <= CGFloat(canvasWidth) - 144, "Caption exceeds safe width")
    precondition(top + dimensions.height <= 1630, "Caption exceeds safe height")
    attributed.draw(at: NSPoint(x: 72, y: CGFloat(canvasHeight) - top - dimensions.height))
}

func rectangle(top: CGFloat, height: CGFloat, alpha: CGFloat) {
    NSColor(white: 0.015, alpha: alpha).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: CGFloat(canvasHeight) - top - height,
        width: CGFloat(canvasWidth), height: height)).fill()
}

func render(_ filename: String, draw: () -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: canvasWidth, pixelsHigh: canvasHeight,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create portrait canvas")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode portrait graphics")
    }
    try data.write(to: outputDirectory.appendingPathComponent(filename))
}

let captions: [(String, [String], NSColor)] = [
    ("01-hook.png", ["HE MISSED.", "I DIDN'T."], blue),
    ("02-rivals.png", ["EVERY RIVAL.", "A NEW FIGHT."], red),
    ("03-exchange.png", ["READ.", "REACT."], white),
    ("04-coach.png", ["FIGHT YOUR", "OWN WAY."], white),
    ("05-counter.png", ["MAKE IT", "COUNT."], red),
    ("06-story.png", ["MORE THAN", "THE RING."], blue),
    ("07-champion.png", ["EARN THIS", "MOMENT."], white)
]

for (filename, lines, color) in captions {
    try render(filename) {
        rectangle(top: 0, height: 510, alpha: 0.72)
        text("RIVAL: BOXING", top: 182, size: 38)
        for (index, line) in lines.enumerated() {
            text(line, top: 265 + CGFloat(index) * 114, size: 100, color: color)
        }
        text("1.2 UPDATE PREVIEW", top: 1450, size: 28)
    }
}

try render("08-end.png") {
    text("YOUR NEXT", top: 215, size: 98, color: blue)
    text("OPPONENT.", top: 329, size: 98, color: blue)
    text("RIVAL: BOXING", top: 1250, size: 66)
    text("ON THE APP STORE", top: 1350, size: 40)
    text("iPhone + iPad / iOS 17+", top: 1425, size: 30)
    text("1.2 PREVIEW / CURRENT GAME AVAILABLE", top: 1510, size: 24)
}

try render("cover-overlay.png") {
    text("RIVAL", top: 420, size: 145)
    text("ONE MISS.", top: 605, size: 70, color: blue)
    text("ONE COUNTER.", top: 695, size: 70, color: blue)
    text("BOXING / 1.2 PREVIEW", top: 1490, size: 28)
}

print("Rendered 9 portrait graphics at 1080 x 1920")