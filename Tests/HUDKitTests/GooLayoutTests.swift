import CoreGraphics
import Testing
@testable import HUDKit

private let layout = GooLayout(size: CGSize(width: 120, height: 40))

private func isInside(_ blobs: [Blob]) -> Bool {
    blobs.allSatisfy { blob in
        blob.center.x - blob.radius >= -0.001 && blob.center.x + blob.radius <= 120.001 &&
        blob.center.y - blob.radius >= -0.001 && blob.center.y + blob.radius <= 40.001
    }
}

private func meanRadius(_ blobs: [Blob]) -> CGFloat {
    blobs.map(\.radius).reduce(0, +) / CGFloat(blobs.count)
}

@Test func blobsStayInsideThePillInEveryMode() {
    for mode in GooMode.allCases {
        for step in 0..<200 {
            for level in [0.0, 0.5, 1.0] {
                let blobs = layout.blobs(mode: mode, level: level, time: Double(step) * 0.037, reduceMotion: false)
                #expect(blobs.count == GooLayout.blobCount)
                #expect(isInside(blobs), "mode \(mode), t \(step), level \(level)")
            }
        }
    }
}

@Test func louderVoiceMakesBiggerBlobs() {
    let quiet = layout.blobs(mode: .listening, level: 0, time: 3, reduceMotion: false)
    let loud = layout.blobs(mode: .listening, level: 1, time: 3, reduceMotion: false)
    #expect(meanRadius(loud) > meanRadius(quiet) * 1.3)
}

@Test func thinkingBlobsOrbitOverTime() {
    let now = layout.blobs(mode: .thinking, level: 0, time: 1, reduceMotion: false)
    let later = layout.blobs(mode: .thinking, level: 0, time: 1.3, reduceMotion: false)
    #expect(now != later)
}

@Test func reduceMotionHoldsTheLayoutStill() {
    let first = layout.blobs(mode: .listening, level: 0.5, time: 0, reduceMotion: true)
    let later = layout.blobs(mode: .listening, level: 0.5, time: 10, reduceMotion: true)
    #expect(first == later)
}

@Test func resultCollapsesIntoOneDroplet() {
    let blobs = layout.blobs(mode: .result, level: 0, time: 5, reduceMotion: false)
    #expect(blobs.allSatisfy { $0.center == CGPoint(x: 60, y: 20) })
}

@Test func blendMovesSmoothlyBetweenLayouts() {
    let from = [Blob(center: CGPoint(x: 0, y: 0), radius: 2)]
    let to = [Blob(center: CGPoint(x: 10, y: 20), radius: 6)]
    #expect(GooLayout.blend(from: from, to: to, progress: 0) == from)
    #expect(GooLayout.blend(from: from, to: to, progress: 1) == to)
    let middle = GooLayout.blend(from: from, to: to, progress: 0.5)[0]
    #expect(middle.center.x > 0 && middle.center.x < 10)
    #expect(middle.radius > 2 && middle.radius < 6)
}
