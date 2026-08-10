import AppKit
import Foundation

guard CommandLine.arguments.count == 9 else {
  FileHandle.standardError.write(
    Data("Usage: render-app-preview-caption.swift <callout|closing|blur> <text> <output.png> <x> <y> <width> <height> <font-size>\n".utf8)
  )
  exit(64)
}

let style = CommandLine.arguments[1]
let text = CommandLine.arguments[2]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard
  ["callout", "closing", "blur"].contains(style),
  let x = Double(CommandLine.arguments[4]),
  let y = Double(CommandLine.arguments[5]),
  let width = Double(CommandLine.arguments[6]),
  let height = Double(CommandLine.arguments[7]),
  let fontSize = Double(CommandLine.arguments[8])
else {
  FileHandle.standardError.write(Data("Invalid caption style or geometry.\n".utf8))
  exit(64)
}

let canvasSize = NSSize(width: 886, height: 1920)
let contentRect = NSRect(x: x, y: y, width: width, height: height)
guard
  contentRect.minX >= 0,
  contentRect.minY >= 0,
  contentRect.maxX <= canvasSize.width,
  contentRect.maxY <= canvasSize.height,
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  FileHandle.standardError.write(Data("Caption geometry is outside the 886x1920 canvas.\n".utf8))
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

if style == "blur" {
  let blurMask = NSBezierPath(roundedRect: contentRect, xRadius: 24, yRadius: 24)
  NSColor.white.setFill()
  blurMask.fill()
} else {
  let paragraphStyle = NSMutableParagraphStyle()
  paragraphStyle.alignment = .center
  paragraphStyle.lineBreakMode = .byWordWrapping

  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize, weight: .light),
    .foregroundColor: NSColor.black,
    .paragraphStyle: paragraphStyle,
  ]

  (text as NSString).draw(
    with: contentRect,
    options: [.usesLineFragmentOrigin, .usesFontLeading],
    attributes: attributes
  )
}
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write(Data("Unable to render caption image.\n".utf8))
  exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
