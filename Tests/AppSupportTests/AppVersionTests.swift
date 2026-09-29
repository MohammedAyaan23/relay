import Testing
@testable import AppSupport

@Test func parsesWithAndWithoutV() {
    #expect(AppVersion("0.2.0")?.parts == [0, 2, 0])
    #expect(AppVersion("v1.10.3")?.parts == [1, 10, 3])
    #expect(AppVersion("V2")?.parts == [2])
}

@Test func junkIsNil() {
    for junk in ["", "latest", "1.x", "v", "1..2", "-1.0", "+1.0", "1.0-beta", "1.2.3.4.5"] {
        #expect(AppVersion(junk) == nil, "\(junk)")
    }
}

@Test func comparesNumericallyPartByPart() {
    #expect(AppVersion("0.10.0")! > AppVersion("0.9.2")!)
    #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
    #expect(AppVersion("1.0.1")! > AppVersion("1.0")!)
    #expect(AppVersion("v0.2.0")! > AppVersion("0.1.9")!)
    #expect(!(AppVersion("0.2.0")! > AppVersion("0.2.0")!))
}

@Test func descriptionJoinsParts() {
    #expect(AppVersion("v0.2.0")?.description == "0.2.0")
}
