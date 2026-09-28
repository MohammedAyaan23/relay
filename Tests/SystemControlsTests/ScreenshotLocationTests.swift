import Foundation
import Testing
@testable import SystemControls

private let home = URL(fileURLWithPath: "/Users/test")

@Test func defaultsToDesktop() {
    #expect(ScreenshotLocation.folder(defaultsValue: nil, home: home).path == "/Users/test/Desktop")
    #expect(ScreenshotLocation.folder(defaultsValue: "  ", home: home).path == "/Users/test/Desktop")
}

@Test func usesTheConfiguredFolderAndExpandsTilde() {
    #expect(ScreenshotLocation.folder(defaultsValue: "/Volumes/Shots", home: home).path == "/Volumes/Shots")
    #expect(ScreenshotLocation.folder(defaultsValue: "~/Pictures/Screens", home: home).path == "/Users/test/Pictures/Screens")
}

@Test func fileNameMatchesMacOSStyle() {
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 28
    components.hour = 11; components.minute = 48; components.second = 3
    let date = Calendar.current.date(from: components)!
    #expect(ScreenshotLocation.fileName(for: date) == "Screenshot 2026-09-28 at 11.48.03.png")
}
