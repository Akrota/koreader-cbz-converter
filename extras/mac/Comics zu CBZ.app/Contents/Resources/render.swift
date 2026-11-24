import Foundation
import AppKit
import PDFKit

let a = CommandLine.arguments
guard a.count >= 3, let doc = PDFDocument(url: URL(fileURLWithPath: a[1])) else { FileHandle.standardError.write("PDF nicht lesbar\n".data(using: .utf8)!); exit(1) }
let targetH: CGFloat = a.count > 3 ? CGFloat(Double(a[3]) ?? 1680) : 1680
let quality: Double = a.count > 4 ? (Double(a[4]) ?? 90) / 100 : 0.9
for i in 0..<doc.pageCount {
    guard let page = doc.page(at: i) else { continue }
    let r = page.bounds(for: .cropBox)
    let scale = targetH / r.height
    let h = Int(targetH), w = Int((r.width * scale).rounded())
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -r.origin.x, y: -r.origin.y)
    page.draw(with: .cropBox, to: ctx)
    guard let img = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: img)
    if let d = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
        try? d.write(to: URL(fileURLWithPath: a[2]).appendingPathComponent(String(format: "page%05d.jpg", i + 1)))
    }
}
