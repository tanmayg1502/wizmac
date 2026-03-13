import XCTest
@testable import WizmacSystem

final class WindowControllerTests: XCTestCase {
    func testWindowIDPrecedenceAvoidsFuzzyMatch() {
        let primary = VisibleWindow(id: 1, appName: "PrimaryApp", title: "Primary Title", pid: 101, frame: nil)
        let fuzzyTarget = VisibleWindow(id: 2, appName: "FuzzyApp", title: "Fuzzy Title", pid: 202, frame: nil)
        var focusedWindow: VisibleWindow?

        let controller = WindowController(
            visibleWindowProvider: { _ in [primary, fuzzyTarget] },
            focusPerformer: { focusedWindow = $0; return true }
        )

        let didFocus = controller.focus(windowID: 1, title: "Fuzzy Title", pid: nil)
        XCTAssertTrue(didFocus)
        XCTAssertEqual(focusedWindow?.id, primary.id)
    }

    func testFuzzyQueryMatchesAcrossAppAndTitleTokens() {
        let candidate = VisibleWindow(id: 10, appName: "FixtureHost", title: "Secondary Window", pid: 42, frame: nil)
        let other = VisibleWindow(id: 11, appName: "OtherApp", title: "Random Title", pid: 84, frame: nil)
        var focusedWindow: VisibleWindow?

        let controller = WindowController(
            visibleWindowProvider: { _ in [other, candidate] },
            focusPerformer: { focusedWindow = $0; return true }
        )

        let didFocus = controller.focus(windowID: nil, title: "Fixture Secondary", pid: nil)
        XCTAssertTrue(didFocus)
        XCTAssertEqual(focusedWindow?.id, candidate.id)
    }
}
