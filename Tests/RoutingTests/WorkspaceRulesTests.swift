import Testing
@testable import Routing

@Test(arguments: [
    ("quit slack", RoutedIntent.quitApp),
    ("close spotify completely", .quitApp),
    ("close spotify", .quitApp),
    ("exit xcode", .quitApp),
    ("hide this app", .hideApp),
    ("minimize this window", .minimizeWindow),
    ("make this full screen", .fullScreen),
    ("exit full screen", .fullScreen),
    ("close this window", .closeWindow),
    ("close the tab", .closeWindow),
    ("make a new folder called invoices", .createFolder),
    ("create a text file called todo in documents", .createFile),
    ("open the budget spreadsheet", .openFile),
    ("find my lease agreement", .findFile),
    ("where is the tax document", .findFile),
    ("show the downloads folder in finder", .revealFile),
    ("screenshot this window", .screenshot),
    ("copy a screenshot", .screenshot),
    ("screenshot an area", .screenshot),
])
func workspaceCommandsMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

/// Held-out phrases from the 2026-09-28 routing spike (written before the rules existed).
@Test(arguments: [
    ("quit chrome", RoutedIntent.quitApp),
    ("hide slack", .hideApp),
    ("minimise safari", .minimizeWindow),
    ("go into full screen mode", .fullScreen),
    ("close this tab please", .closeWindow),
    ("create a folder called receipts in downloads", .createFolder),
    ("make a new text file named ideas", .createFile),
    ("find the lease agreement", .findFile),
    ("find my resume file", .findFile),
    ("open the budget spreadsheet", .openFile),
    ("show my desktop folder in finder", .revealFile),
])
func heldOutWorkspacePhrasesMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test(arguments: [
    "open safari",
    "open photos",
    "open sound settings",
    "find out who won the match",
    "quit playing music",
])
func appAndWebRequestsStayWithLaya(_ transcript: String) {
    #expect(CommandRules.match(transcript) == nil)
}
