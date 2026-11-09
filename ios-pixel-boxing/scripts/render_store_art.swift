import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Slide {
    let name: String
    let capture: String
    let poster: String?
    let titles: [String: String]
}

let slides = [
    Slide(name: "01-break-the-pattern", capture: "05-rival-fight", poster: "01-rival-arena",
          titles: ["ko-KR": "같은 패턴 말고,\n다음 한 수.",
                   "en-US": "Break the pattern.\nOwn the next round.",
                   "ja": "同じパターンより、\n次の一手。"]),
    Slide(name: "02-seven-rivals", capture: "03-story-progression", poster: "02-rival-overhead",
          titles: ["ko-KR": "일곱 상대.\n챔피언을 향해.",
                   "en-US": "Seven rivals.\nOne road to the title.",
                   "ja": "7人の相手。\n王座への道。"]),
    Slide(name: "03-southpaw", capture: "06-story-southpaw", poster: nil,
          titles: ["ko-KR": "익숙한 리듬을 깨는\n새로운 사우스포.",
                   "en-US": "A southpaw.\nA different rhythm.",
                   "ja": "サウスポーが変える、\nいつものリズム。"]),
    Slide(name: "04-your-corner", capture: "07-locker", poster: nil,
          titles: ["ko-KR": "내 스타일로.\n내 복장으로.",
                   "en-US": "Your style.\nYour corner.",
                   "ja": "自分のスタイルで。\n自分の衣装で。"]),
    Slide(name: "05-train-change-return", capture: "04-gym", poster: "03-rival-vintage",
          titles: ["ko-KR": "연습하고,\n다른 수로 돌아와라.",
                   "en-US": "Train freely.\nCome back different.",
                   "ja": "練習して、\n別の一手で戻ろう。"]),
    Slide(name: "06-back-in-the-ring", capture: "01-main-menu", poster: nil,
          titles: ["ko-KR": "다시, 링 위로.",
                   "en-US": "Back in the ring.",
                   "ja": "もう一度、リングへ。"])
]

guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: render_store_art.swift CAPTURE_ROOT POSTER_ROOT OUTPUT_ROOT")
}
let captures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let posters = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let paper = NSColor(srgbRed: 0.91, green: 0.90, blue: 0.86, alpha: 1)
let ink = NSColor(srgbRed: 0.027, green: 0.031, blue: 0.039, alpha: 1)

func load(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "StoreArt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot load \(url.path)"])
    }
    return image
}

func fit(_ image: CGImage, inside area: CGRect) -> CGRect {
    let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
}

func posterURL(_ stem: String, locale: String) -> URL {
    switch locale {
    case "en-US": posters.appendingPathComponent("en/\(stem)-en.png")
    case "ja": posters.appendingPathComponent("ja/\(stem)-ja.png")
    default: posters.appendingPathComponent("\(stem).png")
    }
}

func localizedFont(_ locale: String, size: CGFloat) -> NSFont {
    let name = locale == "en-US" ? "DINCondensed-Bold"
        : locale == "ja" ? "HiraginoSans-W6" : "AppleSDGothicNeo-Bold"
    guard let font = NSFont(name: name, size: size) else {
        fatalError("Required font unavailable: \(name)")
    }
    return font
}

func writeImage(size: CGSize, to url: URL, draw: (CGContext) throws -> Void) throws {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
              bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "StoreArt", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate RGB canvas"])
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    try draw(context)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "StoreArt", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "StoreArt", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot save \(url.path)"])
    }
}

var manifest: [[String: Any]] = []
for (device, size) in [("iphone-6.9", CGSize(width: 2868, height: 1320)),
                       ("ipad-13", CGSize(width: 2752, height: 2064))] {
    for locale in ["ko-KR", "en-US", "ja"] {
        let directory = output.appendingPathComponent("\(device)/\(locale)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for slide in slides {
            let captureURL = captures.appendingPathComponent("\(device)/\(locale)/\(slide.capture).png")
            let capture = try load(captureURL)
            guard capture.width == Int(size.width), capture.height == Int(size.height) else {
                fatalError("Incorrect native capture dimensions: \(captureURL.path)")
            }
            let artURL = slide.poster.map { posterURL($0, locale: locale) }
            let art = try artURL.map(load)
            let destination = directory.appendingPathComponent("\(slide.name).png")
            try writeImage(size: size, to: destination) { context in
                let onPaper = slide.capture == "07-locker"
                (onPaper ? paper : ink).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let scale = size.width / 2868
                let margin = 80 * scale
                let posterWidth = art == nil ? 0 : size.width * 0.33
                if let art {
                    let area = CGRect(x: 0, y: 0, width: posterWidth, height: size.height)
                    context.draw(art, in: fit(art, inside: area))
                }
                let textX = art == nil ? margin : posterWidth + margin
                let textWidth = size.width - textX - margin
                guard let title = slide.titles[locale] else { fatalError("Missing localized headline") }
                let font = localizedFont(locale, size: 92 * scale)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                paragraph.lineSpacing = 5 * scale
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: onPaper ? ink : paper, .paragraphStyle: paragraph
                ]
                let measured = (title as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
                let titleHeight = ceil(measured.height)
                guard titleHeight <= size.height / 3 else {
                    fatalError("Headline does not fit: \(locale) \(slide.name)")
                }
                (title as NSString).draw(in: CGRect(x: textX, y: size.height - margin - titleHeight,
                    width: textWidth, height: titleHeight), withAttributes: attributes)
                let area = CGRect(x: textX, y: margin, width: textWidth,
                                  height: size.height - titleHeight - margin * 2 - 30 * scale)
                context.draw(capture, in: fit(capture, inside: area))
            }
            manifest.append(["file": "\(device)/\(locale)/\(slide.name).png",
                             "capture": captureURL.path, "poster": artURL?.path ?? "",
                             "width": Int(size.width), "height": Int(size.height), "locale": locale])
            print(destination.path)
        }
    }
}
for locale in ["ko-KR", "en-US", "ja"] {
    let directory = output.appendingPathComponent("iphone-6.3/\(locale)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for slide in slides {
        let image = try load(output.appendingPathComponent("iphone-6.9/\(locale)/\(slide.name).png"))
        let size = CGSize(width: 2622, height: 1206)
        try writeImage(size: size, to: directory.appendingPathComponent("\(slide.name).png")) { context in
            (slide.capture == "07-locker" ? paper : ink).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.draw(image, in: fit(image, inside: CGRect(origin: .zero, size: size)))
        }
        manifest.append(["file": "iphone-6.3/\(locale)/\(slide.name).png",
                         "derivedFrom": "iphone-6.9/\(locale)/\(slide.name).png",
                         "width": 2622, "height": 1206, "locale": locale])
    }
}
let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("manifest.json"))
print("Rendered \(manifest.count) localized, opaque sRGB screenshots.")

let previewDirectory = output.appendingPathComponent("preview", isDirectory: true)
try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
for locale in ["ko-KR", "en-US", "ja"] {
    let poster = try load(posterURL("01-rival-arena", locale: locale))
    guard let title = slides[0].titles[locale] else { fatalError("Missing localized header") }
    try writeImage(size: CGSize(width: 3840, height: 1646),
        to: output.appendingPathComponent("header-\(locale).png")) { context in
        ink.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 3840, height: 1646))
        context.draw(poster, in: fit(poster, inside: CGRect(x: 520, y: 100, width: 1000, height: 1446)))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: localizedFont(locale, size: 142), .foregroundColor: paper
        ]
        let area = CGRect(x: 1740, y: 620, width: 1550, height: 420)
        let measured = (title as NSString).boundingRect(with: area.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        guard measured.height <= area.height else { fatalError("Header does not fit: \(locale)") }
        (title as NSString).draw(in: area, withAttributes: attributes)
    }
    try writeImage(size: CGSize(width: 2868, height: 1980),
        to: previewDirectory.appendingPathComponent("overview-\(locale).png")) { context in
        for (index, slide) in slides.enumerated() {
            let image = try load(output.appendingPathComponent("iphone-6.9/\(locale)/\(slide.name).png"))
            context.draw(image, in: CGRect(x: (index % 2) * 1434, y: (2 - index / 2) * 660,
                                           width: 1434, height: 660))
        }
    }
}

let arena = try load(URL(fileURLWithPath: "PixelBoxingIOS/Assets.xcassets/StoryArena.imageset/arena-backdrop.png"))
let lineup = try load(URL(fileURLWithPath: "PixelBoxingIOS/Assets.xcassets/StoryLineup.imageset/story-lineup.png"))
try writeImage(size: CGSize(width: 1024, height: 1024), to: output.appendingPathComponent("story-promotion-1024.png")) { context in
    ink.setFill()
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let scale = 1024 / CGFloat(arena.height)
    let width = CGFloat(arena.width) * scale
    context.draw(arena, in: CGRect(x: (1024 - width) / 2, y: 0, width: width, height: 1024))
    // Keep the characters clear of Apple's lower-left app-icon overlay.
    context.draw(lineup, in: fit(lineup, inside: CGRect(x: 45, y: 320, width: 934, height: 400)))
}
