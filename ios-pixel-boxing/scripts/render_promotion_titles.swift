import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canvasWidth = 1920
let canvasHeight = 1080
let renderScale = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1
let pixelWidth = Int(CGFloat(canvasWidth) * renderScale)
let pixelHeight = Int(CGFloat(canvasHeight) * renderScale)
let white = NSColor.white
let blue = NSColor(srgbRed: 0.16, green: 0.72, blue: 1, alpha: 1)
let red = NSColor(srgbRed: 1, green: 0.18, blue: 0.28, alpha: 1)

func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, color: NSColor) {
    let font = NSFont(name: "DINAlternate-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let attributed = NSAttributedString(string: value, attributes: attributes)
    let dimensions = attributed.size()
    precondition(dimensions.width <= CGFloat(canvasWidth) - x - 64, "Text exceeds the canvas")
    attributed.draw(at: NSPoint(x: x, y: CGFloat(canvasHeight) - top - dimensions.height))
}

func rectangle(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(rect: NSRect(x: x, y: CGFloat(canvasHeight) - top - height, width: width, height: height)).fill()
}

func render(_ filename: String, draw: () -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create title canvas")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    context.cgContext.scaleBy(x: renderScale, y: renderScale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode title PNG")
    }
    try png.write(to: outputDirectory.appendingPathComponent(filename))
}

let captions: [(String, String, NSColor)] = [
    ("01-hook.png", "ONE RING. YOUR FIGHT.", white),
    ("02-rival.png", "MEET YOUR RIVALS.", red),
    ("03-dodge.png", "DODGE. THEN COUNTER.", blue),
    ("04-coach.png", "FIND YOUR OWN WAY.", white),
    ("05-counter.png", "MAKE IT COUNT.", red),
    ("06-story.png", "MORE THAN A FIGHT.", blue),
    ("07-champion.png", "EARN YOUR MOMENT.", white)
]

for (filename, caption, color) in captions {
    try render(filename) {
        rectangle(x: 0, top: 0, width: 1920, height: 166, color: NSColor(white: 0.015, alpha: 0.96))
        rectangle(x: 64, top: 36, width: 5, height: 88, color: color)
        text("RIVAL / BOXING", x: 91, top: 22, size: 30, color: white)
        text(caption, x: 88, top: 62, size: 72, color: color)
    }
}

try render("08-end.png") {
    rectangle(x: 0, top: 0, width: 920, height: 1080, color: NSColor(white: 0.015, alpha: 0.97))
    text("YOUR NEXT OPPONENT.", x: 88, top: 242, size: 44, color: blue)
    text("RIVAL", x: 80, top: 296, size: 210, color: white)
    text("BOXING", x: 88, top: 522, size: 55, color: red)
    rectangle(x: 88, top: 629, width: 660, height: 2, color: NSColor(white: 0.45, alpha: 1))
    text("GET IT ON THE APP STORE", x: 88, top: 672, size: 45, color: white)
    text("iPhone + iPad  /  iOS 17+", x: 88, top: 744, size: 31, color: NSColor(white: 0.8, alpha: 1))
    text("Search: RIVAL: Boxing", x: 88, top: 802, size: 29, color: NSColor(white: 0.8, alpha: 1))
}

try render("09-perfect.png") {
    rectangle(x: 68, top: 914, width: 510, height: 100, color: NSColor(white: 0.015, alpha: 0.94))
    rectangle(x: 68, top: 914, width: 5, height: 100, color: blue)
    text("PERFECT COUNTER", x: 94, top: 940, size: 46, color: blue)
}

print("Rendered 9 promotion title PNGs to \(outputDirectory.path)")