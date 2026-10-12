import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ReviewAttachment: Decodable {
    let exportedFileName: String
    let suggestedHumanReadableName: String
}

struct ReviewTestAttachments: Decodable {
    let attachments: [ReviewAttachment]
}

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: export_review_screenshots.swift INPUT_DIRECTORY OUTPUT_DIRECTORY")
}

let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let manifest = try Data(contentsOf: inputDirectory.appendingPathComponent("manifest.json"))
let tests = try JSONDecoder().decode([ReviewTestAttachments].self, from: manifest)
let locales = ["en": "en-US", "ko": "ko-KR", "ja": "ja"]
var exportedCount = 0

for attachment in tests.flatMap(\.attachments) {
    let stem = attachment.suggestedHumanReadableName.components(separatedBy: "_")[0]
    let components = stem.split(separator: "-", maxSplits: 3)
    guard components.count == 4, components[0] == "review",
          let locale = locales[String(components[1])] else { continue }
    let inputURL = inputDirectory.appendingPathComponent(attachment.exportedFileName)
    guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        fatalError("Unable to read screenshot: \(inputURL.path)")
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height)
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
          image.width > image.height else {
        fatalError("Screenshot is not landscape: \(inputURL.path)")
    }
    let localeDirectory = outputDirectory.appendingPathComponent(locale, isDirectory: true)
    try FileManager.default.createDirectory(at: localeDirectory, withIntermediateDirectories: true)
    let outputURL = localeDirectory.appendingPathComponent("\(components[2])-\(components[3]).png")
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL,
        UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Unable to create screenshot: \(outputURL.path)")
    }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Unable to export screenshot: \(outputURL.path)")
    }
    exportedCount += 1
    print("\(outputURL.path): \(image.width)x\(image.height)")
}

guard exportedCount > 0 else { fatalError("No review screenshots in the attachment manifest") }
print("Exported \(exportedCount) landscape review screenshots")