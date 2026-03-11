import AppKit
import XCTest
@testable import WizmacSystem
import WizmacCore
import WizmacTextMode

final class SupportAndControllerTests: XCTestCase {
    func testLabelGeneratorProducesStableCount() {
        let labels = LabelGenerator.labels(count: 4, alphabet: "asdf")
        XCTAssertEqual(labels.count, 4)
    }

    func testTraversalHeuristicsPreserveDepthForStructuralContainers() {
        XCTAssertEqual(AccessibilityTraversalHeuristics.nextDepth(currentDepth: 8, parentRole: "AXRow"), 8)
        XCTAssertEqual(AccessibilityTraversalHeuristics.nextDepth(currentDepth: 8, parentRole: "AXCell"), 8)
        XCTAssertEqual(AccessibilityTraversalHeuristics.nextDepth(currentDepth: 8, parentRole: "AXButton"), 9)
    }

    func testTraversalHeuristicsPreferVisibleRowsForListRoles() {
        XCTAssertEqual(
            Array(AccessibilityTraversalHeuristics.orderedChildAttributes(parentRole: "AXList").prefix(3)),
            [AccessibilityTraversalHeuristics.visibleRowsAttribute, kAXRowsAttribute, kAXChildrenAttribute]
        )
        XCTAssertTrue(AccessibilityTraversalHeuristics.isListLikeRole("AXOutline"))
        XCTAssertTrue(AccessibilityTraversalHeuristics.isListLikeRole("AXBrowser"))
    }

    func testTraversalHeuristicsUseStandardChildrenForNonListRoles() {
        XCTAssertEqual(
            AccessibilityTraversalHeuristics.orderedChildAttributes(parentRole: "AXButton"),
            [kAXChildrenAttribute, kAXTabsAttribute, kAXColumnsAttribute, kAXContentsAttribute, kAXVisibleChildrenAttribute]
        )
        XCTAssertFalse(AccessibilityTraversalHeuristics.isListLikeRole("AXButton"))
    }

    func testAXElementValueParserAcceptsSingletonAndMixedArrays() {
        let appElement = AXUIElementCreateApplication(getpid())
        let systemElement = AXUIElementCreateSystemWide()

        XCTAssertEqual(AXElementValueParser.elements(from: appElement).count, 1)

        let mixed: [Any] = ["ignore", appElement, NSNull(), [systemElement]]
        let decoded = AXElementValueParser.elements(from: mixed as NSArray)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(CFEqual(decoded[0], appElement))
        XCTAssertTrue(CFEqual(decoded[1], systemElement))
    }

    func testSemanticTargetRankerPromotesAdjacentCheckboxForMatchedTaskTitle() {
        let checkbox = TargetDescriptor(
            id: "checkbox",
            appName: "TickTick",
            role: "AXButton",
            title: "AXButton",
            frame: TargetRect(x: 210, y: 158, width: 20, height: 20),
            path: ["AXWindow", "AXScrollArea[0]", "AXList[0]", "AXOutline[0]", "AXRow[2]", "AXCell[0]", "AXButton[0]"]
        )
        let taskTitle = TargetDescriptor(
            id: "task-title",
            appName: "TickTick",
            role: "AXStaticText",
            title: "_NS:task",
            value: "Complete the test group project",
            frame: TargetRect(x: 240, y: 158, width: 170, height: 20),
            path: ["AXWindow", "AXScrollArea[0]", "AXList[0]", "AXOutline[0]", "AXRow[2]", "AXCell[1]", "AXStaticText[0]"]
        )
        let headerButton = TargetDescriptor(
            id: "header-button",
            appName: "TickTick",
            role: "AXButton",
            title: "AXButton",
            frame: TargetRect(x: 500, y: 106, width: 26, height: 26),
            path: ["AXWindow", "AXScrollArea[0]", "AXList[0]", "AXList[1]", "AXGroup[2]"]
        )
        let snapshot = TargetSnapshot(
            appName: "TickTick",
            bundleIdentifier: "com.TickTick.task.mac",
            windowTitle: "TickTick",
            targets: [headerButton, taskTitle, checkbox]
        )

        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "Complete the test group project", limit: 10)

        XCTAssertEqual(ranked.first?.id, checkbox.id)
        XCTAssertTrue(ranked.map(\.id).contains(taskTitle.id))
        XCTAssertFalse(ranked.map(\.id).contains(headerButton.id))
    }

    func testGlobalInputTranslatorMapsModifiersAndSpecialKey() {
        let modifiers = GlobalInputTranslator.modifiers(from: [.control, .option, .shift])
        let event = GlobalInputTranslator.event(
            kind: .keyDown,
            keyCode: 53,
            characters: "\u{1b}",
            modifiers: modifiers,
            timestamp: Date(timeIntervalSince1970: 123)
        )

        XCTAssertEqual(event.modifiers, [.control, .option, .shift])
        XCTAssertEqual(event.textEvent.specialValue, .escape)
    }

    func testTestableGlobalInputCaptureForwardsEvents() async {
        let capture = TestableGlobalInputCapture()
        let expectation = expectation(description: "captured event")
        let recorder = CapturedEventRecorder()

        capture.start { event in
            Task {
                await recorder.record(event)
                expectation.fulfill()
            }
        }
        capture.emit(GlobalInputTranslator.event(kind: .keyDown, keyCode: 17, characters: "t", modifiers: [.control]))

        await fulfillment(of: [expectation], timeout: 1.0)
        let received = await recorder.event
        XCTAssertTrue(capture.isRunning)
        XCTAssertEqual(received?.characters, "t")
        XCTAssertEqual(received?.modifiers, [.control])

        capture.stop()
        XCTAssertFalse(capture.isRunning)
    }

    func testWindowControllerBuildsExcludeRuleFromMatchedWindow() {
        let candidate = VisibleWindow(
            id: 77,
            appName: "FixtureHost",
            title: "Secondary Window",
            pid: 42,
            frame: TargetRect(x: 10, y: 12, width: 300, height: 200)
        )
        let controller = WindowController(
            visibleWindowProvider: { _ in [candidate] },
            focusPerformer: { _ in true }
        )

        let rule = controller.excludeRule(windowID: 77, title: nil, pid: nil, excluding: [])

        XCTAssertEqual(rule, ExcludedWindowRule(appName: "FixtureHost", title: "Secondary Window"))
    }

    func testAirPlayParsingStripsDiscoveryPreambleAndDeduplicates() {
        let output = """
Browsing for _airplay._tcp
DATE: ---Tue 10 Mar 2026---
 9:00:00.000  ...STARTING...
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
 9:00:01.000  Add        2   15 local.               _airplay._tcp.       Studio Display
 9:00:01.001  Add        2   15 local.               _airplay._tcp.       Studio Display
 9:00:01.100  Add        2   15 local.               _airplay._tcp.       Living Room TV
"""

        let devices = AirPlayController.parseDevices(from: output)

        XCTAssertEqual(devices, ["Living Room TV", "Studio Display"])
    }

    func testScrollControllerTracksSessionLifecycle() {
        let performer = RecordingScrollPerformer()
        let controller = ScrollController(performer: performer)
        let target = TargetDescriptor(
            id: "scroll-1",
            appName: "FixtureHost",
            role: "AXScrollArea",
            title: "Messages",
            frame: TargetRect(x: 40, y: 50, width: 120, height: 80)
        )
        let snapshot = TargetSnapshot(
            appName: "FixtureHost",
            bundleIdentifier: "com.example.fixture",
            windowTitle: "Fixture Host",
            targets: [target]
        )

        let session = controller.startSession(targetID: nil, snapshot: snapshot)
        let didScroll = controller.step(direction: "down", amount: 3, snapshot: snapshot)
        let ended = controller.endSession()

        XCTAssertEqual(session?.targetID, target.id)
        XCTAssertTrue(didScroll)
        XCTAssertEqual(performer.calls.count, 1)
        XCTAssertEqual(ended?.stepCount, 1)
        XCTAssertNil(controller.currentSession())
    }
}

private final class RecordingScrollPerformer: ScrollEventPerforming {
    private(set) var calls: [(direction: String, amount: Int, point: CGPoint)] = []

    func scroll(direction: String, amount: Int, at point: CGPoint) -> Bool {
        calls.append((direction, amount, point))
        return true
    }
}

private actor CapturedEventRecorder {
    private(set) var event: GlobalKeyCaptureEvent?

    func record(_ event: GlobalKeyCaptureEvent) {
        self.event = event
    }
}
