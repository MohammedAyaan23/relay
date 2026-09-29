// Draws Relay's app icon: the listening pill's goo inside a glass capsule on a dark rounded square.
// Usage: swift scripts/make-icon.swift <output.png>   (scripts/make-icon.sh turns it into Resources/Relay.icns)
import AppKit
import SwiftUI

private let canvas: CGFloat = 1024
private let gooColors: [Color] = [.blue, .purple, .pink, .orange, .cyan, .blue] // same as the pill

/// Blobs in the pill's "listening" look: a row of merging drops, bigger in the middle.
private let blobs: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
    (-205, 8, 52), (-120, -14, 74), (-20, 10, 96), (95, -8, 82), (190, 12, 58), (255, -4, 34),
]

struct Goo: View {
    var body: some View {
        Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.5, color: .white))
            context.addFilter(.blur(radius: 18))
            context.drawLayer { layer in
                for blob in blobs {
                    let center = CGPoint(x: size.width / 2 + blob.x, y: size.height / 2 + blob.y)
                    layer.fill(Path(ellipseIn: CGRect(x: center.x - blob.r, y: center.y - blob.r,
                                                      width: blob.r * 2, height: blob.r * 2)), with: .color(.white))
                }
            }
        }
    }
}

struct Icon: View {
    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
        let pill = Capsule(style: .continuous)
        let gradient = AngularGradient(colors: gooColors, center: .center, angle: .degrees(20))
        ZStack {
            // Dark tile, as in Apple's icon grid (824 pt square inside the 1024 canvas).
            tile.fill(LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.25),
                                              Color(red: 0.05, green: 0.05, blue: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(tile.strokeBorder(.white.opacity(0.10), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)

            // Soft glow of the goo colours behind the pill.
            gradient.mask(Goo()).blur(radius: 40).opacity(0.75)
                .frame(width: 700, height: 360)

            // Glass capsule.
            pill.fill(.white.opacity(0.07))
                .overlay(pill.fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                                  startPoint: .top, endPoint: .center)))
                .overlay(pill.strokeBorder(.white.opacity(0.35), lineWidth: 4))
                .frame(width: 660, height: 290)

            // The goo itself, clipped to the capsule. Blurring the colours hides the gradient's centre point.
            gradient.blur(radius: 45).mask(Goo())
                .frame(width: 660, height: 290)
                .clipShape(pill)
        }
        .frame(width: canvas, height: canvas)
    }
}

@MainActor
func render(to path: String) {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    renderer.isOpaque = false
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Couldn't render the icon\n".utf8))
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path) (\(image.width)×\(image.height))")
}

guard CommandLine.arguments.count == 2 else {
    print("Usage: swift scripts/make-icon.swift <output.png>")
    exit(2)
}
MainActor.assumeIsolated { render(to: CommandLine.arguments[1]) }
