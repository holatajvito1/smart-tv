// Contact sheet of video frames (e.g. a TV screenrecord), via AVFoundation; headless Chrome cannot decode video.
// Usage: swift scripts/frames.swift <video.mp4> <outdir> <step s> <until s> [from s]   -> <outdir>/sheet.png
import AVFoundation
import AppKit
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
let step = Double(a[3])!, maxT = Double(a[4])!
var images: [(Double, CGImage)] = []
var t = Double(a.count > 5 ? a[5] : "0")!
while t <= maxT {
  if let img = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) { images.append((t, img)) }
  t += step
}
let w = 384, h = 216, cols = 5, rows = (images.count + cols - 1) / cols
let sheet = NSImage(size: NSSize(width: cols * w, height: rows * (h + 22)))
sheet.lockFocus()
NSColor.black.setFill(); NSRect(x: 0, y: 0, width: cols * w, height: rows * (h + 22)).fill()
for (i, (ts, img)) in images.enumerated() {
  let x = (i % cols) * w, y = (rows - 1 - i / cols) * (h + 22)
  NSImage(cgImage: img, size: .zero).draw(in: NSRect(x: x, y: y + 22, width: w - 4, height: h))
  (String(format: "t=%.2fs", ts) as NSString).draw(at: NSPoint(x: x + 4, y: y + 3), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 15)])
}
sheet.unlockFocus()
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2] + "/sheet.png"))
print("frames: \(images.count)")
