import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Uso: make_icon <directorio.iconset>\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func icon(side: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        NSGraphicsContext.current?.imageInterpolation = .high
        let shape = NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237)
        shape.addClip()
        let violet = NSColor(red: 0.42, green: 0.27, blue: 0.91, alpha: 1)
        let blue = NSColor(red: 0.18, green: 0.61, blue: 0.97, alpha: 1)
        NSGradient(starting: violet, ending: blue)?.draw(in: rect, angle: -45)

        NSColor.white.withAlphaComponent(0.12).setFill()
        let highlight = NSRect(x: -side * 0.18, y: side * 0.55, width: side * 0.78, height: side * 0.78)
        NSBezierPath(ovalIn: highlight).fill()

        let config = NSImage.SymbolConfiguration(pointSize: side * 0.57, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let symbol = (NSImage(systemSymbolName: "bubbles.and.sparkles.fill", accessibilityDescription: nil)
                      ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil))?.withSymbolConfiguration(config)
        if let symbol {
            let symbolSize = symbol.size
            let scale = min(side * 0.62 / symbolSize.width, side * 0.62 / symbolSize.height)
            let size = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
            let target = NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
            symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: nil)
        }
        return true
    }
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in variants {
    let image = icon(side: CGFloat(pixels))
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("No se pudo generar \(name)\n", stderr)
        exit(1)
    }
    try png.write(to: output.appendingPathComponent(name), options: .atomic)
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

func appendChunk(type: String, png: Data, to data: inout Data) {
    data.append(type.data(using: .ascii)!)
    appendUInt32(UInt32(png.count + 8), to: &data)
    data.append(png)
}

if let icnsPath = ProcessInfo.processInfo.environment["MYCLEANUP_ICNS_OUTPUT"] {
    let chunks: [(String, String)] = [
        ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
    ]
    var body = Data()
    for (type, name) in chunks {
        appendChunk(type: type, png: try Data(contentsOf: output.appendingPathComponent(name)), to: &body)
    }
    var file = Data("icns".utf8)
    appendUInt32(UInt32(body.count + 8), to: &file)
    file.append(body)
    try file.write(to: URL(fileURLWithPath: icnsPath), options: .atomic)
}
