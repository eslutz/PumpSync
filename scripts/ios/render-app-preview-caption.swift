import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(Data("Usage: render-app-preview-caption.swift <text> <output.png>\n".utf8))
  exit(64)
}

let text = CommandLine.arguments[1]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = NSSize(width: 886, height: 1920)
guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(size.width),
  pixelsHigh: Int(size.height),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  FileHandle.standardError.write(Data("Unable to allocate caption bitmap.\n".utf8))
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let panelRect = NSRect(x: 54, y: 164, width: 778, height: 170)
let panel = NSBezierPath(roundedRect: panelRect, xRadius: 34, yRadius: 34)
NSColor(calibratedWhite: 0.04, alpha: 0.82).setFill()
panel.fill()

let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center
paragraphStyle.lineBreakMode = .byWordWrapping

let attributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 43, weight: .semibold),
  .foregroundColor: NSColor.white,
  .paragraphStyle: paragraphStyle,
]

let textRect = NSRect(x: 88, y: 194, width: 710, height: 110)
(text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write(Data("Unable to render caption image.\n".utf8))
  exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
