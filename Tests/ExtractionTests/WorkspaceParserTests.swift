import Testing
@testable import Extraction

@Test(arguments: [
    ("quit slack", AppTarget.named("slack")),
    ("close spotify completely", .named("spotify")),
    ("quit visual studio code please", .named("visual studio code")),
    ("hide this app", .frontmost),
    ("hide", .frontmost),
    ("quit this window", .frontmost),
])
func appTargets(_ transcript: String, _ expected: AppTarget) {
    #expect(AppTargetParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("make a new folder called invoices", FileRequest(name: "invoices", location: nil, fileExtension: nil)),
    ("make a new folder called invoices on the desktop", FileRequest(name: "invoices", location: .desktop, fileExtension: nil)),
    ("create a folder named Tax Returns in my documents", FileRequest(name: "Tax Returns", location: .documents, fileExtension: nil)),
    ("create a text file called todo in downloads", FileRequest(name: "todo", location: .downloads, fileExtension: nil)),
    ("create a file called notes dot md", FileRequest(name: "notes", location: nil, fileExtension: "md")),
    ("create a file called notes.md in documents", FileRequest(name: "notes", location: .documents, fileExtension: "md")),
    ("make a new folder", FileRequest(name: nil, location: nil, fileExtension: nil)),
    ("show the downloads folder in finder", FileRequest(name: nil, location: .downloads, fileExtension: nil)),
])
func fileRequests(_ transcript: String, _ expected: FileRequest) {
    #expect(FileRequestParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("open the budget spreadsheet", "budget"),
    ("find my lease agreement", "lease"),
    ("where is the tax document", "tax"),
    ("where did i put my passport scan", "passport scan"),
    ("reveal the invoice in finder", "invoice"),
    ("open the file report dot pdf", "report.pdf"),
    ("show the downloads folder in finder", "downloads"),
])
func searchQueries(_ transcript: String, _ expected: String) {
    #expect(FileRequestParser.query(transcript) == expected)
}

@Test func noSearchTextIsNil() {
    #expect(FileRequestParser.query("open it") == nil)
    #expect(FileRequestParser.query("find") == nil)
}

@Test(arguments: [
    ("take a screenshot", ScreenshotOptions(target: .screen, toClipboard: false, openAfter: false)),
    ("screenshot this window", ScreenshotOptions(target: .window, toClipboard: false, openAfter: false)),
    ("screenshot an area", ScreenshotOptions(target: .area, toClipboard: false, openAfter: false)),
    ("screenshot part of the screen", ScreenshotOptions(target: .area, toClipboard: false, openAfter: false)),
    ("copy a screenshot", ScreenshotOptions(target: .screen, toClipboard: true, openAfter: false)),
    ("copy a screenshot of this window to the clipboard", ScreenshotOptions(target: .window, toClipboard: true, openAfter: false)),
    ("take a screenshot and show it", ScreenshotOptions(target: .screen, toClipboard: false, openAfter: true)),
    ("copy a screenshot and show it", ScreenshotOptions(target: .screen, toClipboard: true, openAfter: false)),
])
func screenshotOptions(_ transcript: String, _ expected: ScreenshotOptions) {
    #expect(ScreenshotOptionsParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("minimise safari", AppTarget.named("safari")),
    ("close the safari window", .named("safari")),
    ("make this full screen", .frontmost),
    ("close the tab", .frontmost),
    ("quit the current app", .frontmost),
])
func windowCommandTargets(_ transcript: String, _ expected: AppTarget) {
    #expect(AppTargetParser.parse(transcript) == expected)
}
