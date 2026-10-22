// Gera Resources/AppIcon.icns a partir de design/icon-source.png no formato de
// ícone do macOS (quadrado arredondado de 824 px numa tela de 1024, com sombra).
// Uso: swift scripts/make-icon.swift
import AppKit

let source = NSImage(contentsOfFile: "design/icon-source.png")!
let canvas = 1024.0, size = 824.0, inset = (canvas - size) / 2
let rect = NSRect(x: inset, y: inset + 10, width: size, height: size)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

shape.addClip()
source.draw(in: rect)
NSGraphicsContext.restoreGraphicsState()

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = iconset.appendingPathComponent("master.png")
try! rep.representation(using: .png, properties: [:])!.write(to: master)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let out = iconset.appendingPathComponent(name).path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", out]
        p.standardOutput = FileHandle.nullDevice
        try! p.run(); p.waitUntilExit()
    }
}
try! FileManager.default.removeItem(at: master)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run(); iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "iconutil falhou")
