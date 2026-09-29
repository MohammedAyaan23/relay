import Foundation
import Testing
@testable import AppSupport

@Test func stepsAdvanceAndClamp() {
    var flow = WelcomeFlow()
    #expect(flow.step == .meet && flow.isFirst)
    flow.back()
    #expect(flow.step == .meet)
    flow.next()
    #expect(flow.step == .setup)
    flow.next()
    #expect(flow.step == .tryIt && flow.isLast)
    flow.next()
    #expect(flow.step == .tryIt)
    flow.back()
    #expect(flow.step == .setup)
}

@Test func showsUntilMarkedSeen() {
    let name = "relay-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(WelcomeFlow.shouldShowOnLaunch(defaults))
    WelcomeFlow.markSeen(defaults)
    #expect(!WelcomeFlow.shouldShowOnLaunch(defaults))
}

@Test func permissionButtonTitles() {
    #expect(PermissionRow.State.granted.buttonTitle == nil)
    #expect(PermissionRow.State.notAsked.buttonTitle == "Allow")
    #expect(PermissionRow.State.denied.buttonTitle == "Open Settings")
}
