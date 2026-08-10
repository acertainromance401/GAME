import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.dropFirst().first ?? "PixelBoxingIOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let pixelSize = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

guard let context = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: pixelSize * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else {
    fatalError("Unable to allocate app icon bitmap")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, 1])!
}

func polygon(_ points: [CGPoint], fill: CGColor? = nil, stroke: CGColor? = nil, width: CGFloat = 1) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    points.dropFirst().forEach { context.addLine(to: $0) }
    context.closePath()
    if let fill {
        context.setFillColor(fill)
        context.fillPath()
    }
    if let stroke {
        context.beginPath()
        context.move(to: first)
        points.dropFirst().forEach { context.addLine(to: $0) }
        context.closePath()
        context.setStrokeColor(stroke)
        context.setLineWidth(width)
        context.strokePath()
    }
}

context.setFillColor(color(0.035, 0.078, 0.153))
context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

let ring = [
    CGPoint(x: 130, y: 210), CGPoint(x: 894, y: 210),
    CGPoint(x: 768, y: 760), CGPoint(x: 256, y: 760),
]
polygon(ring, fill: color(0.09, 0.18, 0.32))

let ropes = [color(0.94, 0.35, 0.45), color(0.92, 0.92, 0.92), color(0.35, 0.78, 0.91)]
for (index, ropeColor) in ropes.enumerated() {
    let inset = CGFloat(84 + index * 42)
    let points = [
        CGPoint(x: 130 + inset * 0.35, y: 210 + inset * 0.18),
        CGPoint(x: 894 - inset * 0.35, y: 210 + inset * 0.18),
        CGPoint(x: 768 - inset * 0.24, y: 760 - inset * 0.18),
        CGPoint(x: 256 + inset * 0.24, y: 760 - inset * 0.18),
    ]
    polygon(points, stroke: ropeColor, width: 18)
}

context.setFillColor(color(0.40, 0.82, 1.0))
context.fillEllipse(in: CGRect(x: 208, y: 386, width: 174, height: 174))
context.setFillColor(color(1.0, 0.42, 0.56))
context.fillEllipse(in: CGRect(x: 642, y: 386, width: 174, height: 174))

let font = CTFontCreateWithName("AvenirNextCondensed-Heavy" as CFString, 270, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(1, 1, 1),
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "R", attributes: attributes))
let textBounds = CTLineGetBoundsWithOptions(line, [])
context.textPosition = CGPoint(x: (CGFloat(pixelSize) - textBounds.width) / 2, y: 395)
CTLineDraw(line, context)

guard let image = context.makeImage() else { fatalError("Unable to create app icon image") }
let outputURL = URL(fileURLWithPath: output) as CFURL
guard let destination = CGImageDestinationCreateWithURL(outputURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Unable to create app icon destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write app icon PNG") }
