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

        // Direct match (taskTitle) now ranks first; adjacent checkbox ranks second
        XCTAssertEqual(ranked.first?.id, taskTitle.id)
        XCTAssertTrue(ranked.count >= 2)
        XCTAssertEqual(ranked[1].id, checkbox.id)
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

    // MARK: - SemanticTargetRanker: Direct Match Priority Tests

    func testDirectMatchRanksAboveAdjacentElements() {
        let jimButton = TargetDescriptor(
            id: "jim-button", appName: "Slack", role: "AXButton",
            title: "jim",
            frame: TargetRect(x: 100, y: 200, width: 150, height: 30),
            path: ["AXWindow", "AXGroup[0]", "AXScrollArea[0]", "AXList[0]", "AXGroup[1]", "AXButton[0]"]
        )
        let nearbyCheckbox = TargetDescriptor(
            id: "nearby-checkbox", appName: "Slack", role: "AXCheckBox",
            title: "toggle",
            frame: TargetRect(x: 70, y: 200, width: 20, height: 20),
            path: ["AXWindow", "AXGroup[0]", "AXScrollArea[0]", "AXList[0]", "AXGroup[1]", "AXCheckBox[0]"]
        )
        let jimText = TargetDescriptor(
            id: "jim-text", appName: "Slack", role: "AXStaticText",
            title: "jim",
            frame: TargetRect(x: 100, y: 200, width: 50, height: 20),
            path: ["AXWindow", "AXGroup[0]", "AXScrollArea[0]", "AXList[0]", "AXGroup[1]", "AXStaticText[0]"]
        )
        let snapshot = TargetSnapshot(
            appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "Slack", targets: [nearbyCheckbox, jimText, jimButton]
        )
        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "jim", limit: 10)

        let directMatchIDs = Set(["jim-button", "jim-text"])
        // Both direct matches must come before the adjacent-only checkbox
        for (index, target) in ranked.enumerated() {
            if target.id == "nearby-checkbox" {
                let directsBefore = ranked[0..<index].filter { directMatchIDs.contains($0.id) }.count
                XCTAssertEqual(directsBefore, 2, "Both direct matches should rank before adjacent checkbox")
                break
            }
        }
        XCTAssertTrue(directMatchIDs.contains(ranked.first!.id), "First result should be a direct match")
    }

    func testContainerSiblingsRankAfterDirectMatches() {
        let directMatch = TargetDescriptor(
            id: "match", appName: "App", role: "AXStaticText",
            title: "jim",
            frame: TargetRect(x: 100, y: 100, width: 100, height: 20),
            path: ["AXWindow", "AXGroup[0]", "AXList[0]", "AXGroup[1]", "AXStaticText[0]"]
        )
        let sibling = TargetDescriptor(
            id: "sibling", appName: "App", role: "AXStaticText",
            title: "Message",
            frame: TargetRect(x: 210, y: 100, width: 60, height: 20),
            path: ["AXWindow", "AXGroup[0]", "AXList[0]", "AXGroup[1]", "AXStaticText[1]"]
        )
        let unrelated = TargetDescriptor(
            id: "unrelated", appName: "App", role: "AXButton",
            title: "Settings",
            frame: TargetRect(x: 500, y: 500, width: 80, height: 30),
            path: ["AXWindow", "AXGroup[0]", "AXToolbar[0]", "AXButton[0]"]
        )
        let snapshot = TargetSnapshot(
            appName: "App", bundleIdentifier: nil,
            windowTitle: "App", targets: [unrelated, sibling, directMatch]
        )
        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "jim", limit: 10)

        XCTAssertEqual(ranked.first?.id, "match", "Direct match should be first")
        // Sibling should appear in results (container boost); unrelated should not
        XCTAssertTrue(ranked.map(\.id).contains("sibling"), "Container sibling should appear")
        XCTAssertFalse(ranked.map(\.id).contains("unrelated"), "Unrelated element should not appear")
    }

    func testMultipleDirectMatchesSortedByExactness() {
        let exact = TargetDescriptor(
            id: "exact", appName: "App", role: "AXButton",
            title: "jim",
            frame: TargetRect(x: 100, y: 100, width: 60, height: 30),
            path: ["AXWindow", "AXGroup[0]", "AXButton[0]"]
        )
        let fuzzy = TargetDescriptor(
            id: "fuzzy", appName: "App", role: "AXButton",
            title: "jim's workspace",
            frame: TargetRect(x: 100, y: 200, width: 120, height: 30),
            path: ["AXWindow", "AXGroup[1]", "AXButton[0]"]
        )
        let snapshot = TargetSnapshot(
            appName: "App", bundleIdentifier: nil,
            windowTitle: "App", targets: [fuzzy, exact]
        )
        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "jim", limit: 10)

        XCTAssertEqual(ranked.first?.id, "exact", "Exact match should rank above fuzzy match")
        XCTAssertEqual(ranked[1].id, "fuzzy")
    }

    func testCollapsedElementsStillScoredByRanker() {
        // The ranker scores all elements; filtering happens in AccessibilitySnapshotter.filteringSnapshot().
        // This test verifies the ranker doesn't silently drop them.
        let collapsed = TargetDescriptor(
            id: "collapsed", appName: "App", role: "AXButton",
            title: "jim",
            frame: TargetRect(x: 100, y: 100, width: 1, height: 0),
            path: ["AXWindow", "AXButton[0]"]
        )
        let visible = TargetDescriptor(
            id: "visible", appName: "App", role: "AXButton",
            title: "jim",
            frame: TargetRect(x: 100, y: 100, width: 60, height: 30),
            path: ["AXWindow", "AXButton[1]"]
        )
        let snapshot = TargetSnapshot(
            appName: "App", bundleIdentifier: nil,
            windowTitle: "App", targets: [collapsed, visible]
        )
        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "jim", limit: 10)

        XCTAssertTrue(ranked.contains(where: { $0.id == "collapsed" }), "Ranker should return collapsed elements")
        XCTAssertTrue(ranked.contains(where: { $0.id == "visible" }), "Ranker should return visible elements")
    }

    func testAdjacentPromotionStillWorksButBelowDirectMatch() {
        // When searching for a task title, the text label (direct match) should rank first,
        // and the adjacent checkbox should still appear (ranked second).
        let textLabel = TargetDescriptor(
            id: "label", appName: "App", role: "AXStaticText",
            title: "Review PR", value: "Review PR",
            frame: TargetRect(x: 60, y: 100, width: 200, height: 20),
            path: ["AXWindow", "AXScrollArea[0]", "AXList[0]", "AXRow[0]", "AXCell[1]", "AXStaticText[0]"]
        )
        let checkbox = TargetDescriptor(
            id: "checkbox", appName: "App", role: "AXCheckBox",
            title: "toggle",
            frame: TargetRect(x: 20, y: 100, width: 30, height: 30),
            path: ["AXWindow", "AXScrollArea[0]", "AXList[0]", "AXRow[0]", "AXCell[0]", "AXCheckBox[0]"]
        )
        let farButton = TargetDescriptor(
            id: "far-button", appName: "App", role: "AXButton",
            title: "Close",
            frame: TargetRect(x: 600, y: 10, width: 30, height: 30),
            path: ["AXWindow", "AXToolbar[0]", "AXButton[0]"]
        )
        let snapshot = TargetSnapshot(
            appName: "App", bundleIdentifier: nil,
            windowTitle: "App", targets: [farButton, checkbox, textLabel]
        )
        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "Review PR", limit: 10)

        XCTAssertEqual(ranked.first?.id, "label", "Direct match should rank first")
        XCTAssertTrue(ranked.map(\.id).contains("checkbox"), "Adjacent checkbox should still be promoted")
        XCTAssertFalse(ranked.map(\.id).contains("far-button"), "Unrelated button should not appear")
    }

    func testExactNamedMatchesRankBeforeSlackStyleAdjacentArtifacts() {
        let avatar = TargetDescriptor(
            id: "avatar",
            appName: "Slack",
            role: "AXImage",
            title: "AXImage",
            frame: TargetRect(x: 164, y: 1267, width: 13, height: 13),
            path: ["AXWindow", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXWebArea[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[5]", "AXGroup[1]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[1]", "AXGroup[0]", "AXOutline[13]", "AXRow[0]", "AXGroup[0]", "AXGroup[1]"]
        )
        let decorativeLink = TargetDescriptor(
            id: "decorative-link",
            appName: "Slack",
            role: "AXLink",
            title: "AXLink",
            frame: TargetRect(x: 343, y: 932, width: 24, height: 16),
            path: ["AXWindow", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXWebArea[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[5]", "AXGroup[1]", "AXGroup[0]", "AXGroup[0]", "AXGroup[2]", "AXGroup[5]", "AXGroup[0]", "AXGroup[0]", "AXGroup[1]", "AXGroup[0]", "AXList[4]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]"]
        )
        let personButton = TargetDescriptor(
            id: "person-button",
            appName: "Slack",
            role: "AXButton",
            title: "Yi-Hung Chou",
            frame: TargetRect(x: 375, y: 875, width: 96, height: 23),
            path: ["AXWindow", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXWebArea[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[5]", "AXGroup[1]", "AXGroup[0]", "AXGroup[0]", "AXGroup[2]", "AXGroup[5]", "AXGroup[0]", "AXGroup[0]", "AXGroup[1]", "AXGroup[0]", "AXList[3]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]"]
        )
        let personText = TargetDescriptor(
            id: "person-text",
            appName: "Slack",
            role: "AXStaticText",
            title: "AXStaticText",
            value: "Yi-Hung Chou",
            frame: TargetRect(x: 179, y: 1260, width: 80, height: 18),
            path: ["AXWindow", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXWebArea[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[5]", "AXGroup[1]", "AXGroup[0]", "AXGroup[0]", "AXGroup[0]", "AXGroup[1]", "AXGroup[0]", "AXOutline[13]", "AXRow[0]", "AXGroup[1]"]
        )
        let snapshot = TargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "general",
            targets: [avatar, decorativeLink, personText, personButton]
        )

        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "Yi-Hung Chou", limit: 10)

        XCTAssertEqual(ranked.prefix(2).map(\.id), ["person-button", "person-text"])
        XCTAssertTrue(ranked.dropFirst(2).map(\.id).contains("avatar"))
    }

    func testSearchScoringPrefersExactPhraseOverSlackNearMatches() {
        let exactButton = TargetDescriptor(
            id: "exact-button",
            appName: "Slack",
            role: "AXButton",
            title: "Add People to Channel",
            frame: TargetRect(x: 300, y: 200, width: 180, height: 30),
            path: ["AXWindow", "AXGroup[0]", "AXPopover[0]", "AXButton[0]"]
        )
        let nearbyPopup = TargetDescriptor(
            id: "nearby-popup",
            appName: "Slack",
            role: "AXPopUpButton",
            title: "Add channels",
            frame: TargetRect(x: 300, y: 245, width: 180, height: 30),
            path: ["AXWindow", "AXGroup[0]", "AXPopover[0]", "AXPopUpButton[0]"]
        )
        let nearbyRow = TargetDescriptor(
            id: "nearby-row",
            appName: "Slack",
            role: "AXRow",
            title: "AXRow",
            value: "Add channels",
            frame: TargetRect(x: 300, y: 280, width: 180, height: 24),
            path: ["AXWindow", "AXGroup[0]", "AXPopover[0]", "AXRow[0]"]
        )
        let snapshot = TargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "general",
            targets: [nearbyPopup, nearbyRow, exactButton]
        )

        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "Add People to Channel", limit: 10)

        XCTAssertEqual(ranked.first?.id, "exact-button")
        XCTAssertEqual(Set(ranked.prefix(3).map(\.id)), Set(["exact-button", "nearby-popup", "nearby-row"]))
    }

    func testMentionSearchPrefersExactMentionBeforePlainName() {
        let exactMention = TargetDescriptor(
            id: "exact-mention",
            appName: "Slack",
            role: "AXStaticText",
            title: "AXStaticText",
            value: "@jim",
            frame: TargetRect(x: 180, y: 1232, width: 28, height: 18),
            path: ["AXWindow", "AXGroup[0]", "AXWebArea[0]", "AXOutline[12]", "AXRow[0]", "AXGroup[1]"]
        )
        let plainName = TargetDescriptor(
            id: "plain-name",
            appName: "Slack",
            role: "AXStaticText",
            title: "AXStaticText",
            value: "jim",
            frame: TargetRect(x: 220, y: 1232, width: 20, height: 18),
            path: ["AXWindow", "AXGroup[0]", "AXWebArea[0]", "AXOutline[13]", "AXRow[0]", "AXGroup[1]"]
        )
        let snapshot = TargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "general",
            targets: [plainName, exactMention]
        )

        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "@jim", limit: 10)

        XCTAssertEqual(ranked.prefix(2).map(\.id), ["exact-mention", "plain-name"])
    }

    func testMentionSearchFallsBackToPlainNameWhenSigilMissing() {
        let plainName = TargetDescriptor(
            id: "plain-name",
            appName: "Slack",
            role: "AXStaticText",
            title: "AXStaticText",
            value: "jim",
            frame: TargetRect(x: 180, y: 1232, width: 20, height: 18),
            path: ["AXWindow", "AXGroup[0]", "AXWebArea[0]", "AXOutline[12]", "AXRow[0]", "AXGroup[1]"]
        )
        let unrelated = TargetDescriptor(
            id: "unrelated",
            appName: "Slack",
            role: "AXStaticText",
            title: "AXStaticText",
            value: "jill",
            frame: TargetRect(x: 240, y: 1232, width: 18, height: 18),
            path: ["AXWindow", "AXGroup[0]", "AXWebArea[0]", "AXOutline[13]", "AXRow[0]", "AXGroup[1]"]
        )
        let snapshot = TargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "general",
            targets: [unrelated, plainName]
        )

        let ranked = SemanticTargetRanker.rankedTargets(in: snapshot, query: "@jim", limit: 10)

        XCTAssertEqual(ranked.first?.id, "plain-name")
        XCTAssertFalse(ranked.map(\.id).contains("unrelated"))
    }

    func testStableTargetResolverRebindsLegacyIDAfterPathAndFrameShift() {
        let legacyID = Data(
            "Slack|AXStaticText|AXStaticText|@jim|AXWindow/AXGroup[0]/AXWebArea[0]/AXGroup[1]/AXStaticText[0]|100:200:40:18".utf8
        ).base64EncodedString()
        let refreshedTarget = TargetDescriptor(
            id: "current-target",
            appName: "Slack",
            role: "AXStaticText",
            title: "AXStaticText",
            value: "@jim",
            frame: TargetRect(x: 108, y: 214, width: 41, height: 18),
            path: ["AXWindow", "AXGroup[2]", "AXWebArea[0]", "AXGroup[4]", "AXStaticText[0]"]
        )
        let distractor = TargetDescriptor(
            id: "distractor",
            appName: "Slack",
            role: "AXStaticText",
            title: "AXStaticText",
            value: "@jill",
            frame: TargetRect(x: 240, y: 300, width: 40, height: 18),
            path: ["AXWindow", "AXGroup[0]", "AXWebArea[0]", "AXGroup[1]", "AXStaticText[0]"]
        )
        let snapshot = TargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "general",
            targets: [distractor, refreshedTarget]
        )

        let resolved = StableTargetResolver.resolve(targetID: legacyID, in: snapshot)

        XCTAssertEqual(resolved?.id, "current-target")
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

    func testScrollControllerPrefersWideSlackContentPaneOverSidebarOutline() {
        let controller = ScrollController(performer: RecordingScrollPerformer())
        let sidebar = TargetDescriptor(
            id: "sidebar-outline",
            appName: "Slack",
            role: "AXOutline",
            title: "AXOutline",
            value: "",
            frame: TargetRect(x: 131, y: 825, width: 179, height: 610),
            path: [
                "AXWindow",
                "AXWindow[0]",
                "AXGroup[0]",
                "AXWebArea[0]",
                "AXOutline[0]",
            ]
        )
        let contentPane = TargetDescriptor(
            id: "content-row",
            appName: "Slack",
            role: "AXGroup",
            title: "Hang Du: . Image: No alt text. 2:06 PM. 1 attachment.",
            value: "",
            frame: TargetRect(x: 311, y: 1217, width: 964, height: 84),
            path: [
                "AXWindow",
                "AXWindow[0]",
                "AXGroup[0]",
                "AXWebArea[0]",
                "AXGroup[0]",
                "AXList[4]",
            ]
        )
        let snapshot = TargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "lab-meeting (Channel) - spideruci - Slack",
            targets: [sidebar, contentPane]
        )

        let targets = controller.scrollTargets(from: snapshot)

        XCTAssertEqual(targets.first?.id, contentPane.id)
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
