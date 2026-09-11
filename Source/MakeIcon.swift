import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var records = Data()
func bigEndianBytes(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let types = ["16-1": "icp4", "16-2": "ic11", "32-1": "icp5", "32-2": "ic12", "128-1": "ic07", "128-2": "ic13", "256-1": "ic08", "256-2": "ic14", "512-1": "ic09", "512-2": "ic10"]
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let size = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    NSColor(red: 0.89, green: 0.94, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 205, yRadius: 205).fill()
    NSColor(red: 0.98, green: 0.99, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 231, y: 196, width: 530, height: 641), xRadius: 60, yRadius: 60).fill()
    NSColor(red: 0.31, green: 0.50, blue: 0.40, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 692, y: 196, width: 69, height: 641), xRadius: 32, yRadius: 32).fill()
    NSColor(red: 0.59, green: 0.70, blue: 0.59, alpha: 1).setFill()
    for (y, width) in [(664, 270), (549, 222), (434, 270)] {
        NSBezierPath(roundedRect: NSRect(x: 313, y: y, width: width, height: 27), xRadius: 13, yRadius: 13).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let url = output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: url)
    records.append(Data(types["\(points)-\(scale)"]!.utf8))
    records.append(bigEndianBytes(png.count + 8))
    records.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndianBytes(records.count + 8))
icon.append(records)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
