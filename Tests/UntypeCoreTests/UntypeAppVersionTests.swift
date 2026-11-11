import Testing
@testable import UntypeCore

@Test func appVersionLabelShowsVersionAndBuild() {
    let version = UntypeAppVersion(infoDictionary: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "51"])
    #expect(version.label == "0.1.0 · build 51")
}

@Test func appVersionLabelSaysWhenThereIsNoAppBundle() {
    #expect(UntypeAppVersion(infoDictionary: nil).label == "not an app bundle")
    #expect(UntypeAppVersion(version: nil, build: "7").label == "build 7")
    #expect(UntypeAppVersion(version: "1.2", build: nil).label == "1.2")
}
