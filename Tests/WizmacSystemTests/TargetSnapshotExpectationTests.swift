import XCTest

@testable import WizmacSystem
import WizmacCore

final class TargetSnapshotExpectationTests: XCTestCase {
    func testTargetExistsConditionMatchesSnapshot() {
        let matcher = TargetDescriptorMatcher.textContains("Primary Action")
        let result = TargetSnapshotCondition.targetExists(matcher).evaluate(on: fixtureSnapshot)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.matchedTargets.first?.id, "primary-action")
    }

    func testTargetCountConditionReportsExactMatches() {
        let matcher = TargetDescriptorMatcher.textContains("Row")
        let result = TargetSnapshotCondition.targetCount(matcher, .exactly(2)).evaluate(on: fixtureSnapshot)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.matchedTargets.count, 2)
    }

    func testWindowTitleConditionMatchesIgnoringCase() {
        let condition = TargetSnapshotCondition.windowTitle(query: "main panel", mode: .equals, caseInsensitive: true)
        let result = condition.evaluate(on: fixtureSnapshot)

        XCTAssertTrue(result.passed)
    }

    func testTextContainsConditionFindsSubtitle() {
        let matcher = TargetSnapshotTextMatcher(query: "detailed description", fields: [.subtitle])
        let result = TargetSnapshotCondition.textContains(matcher).evaluate(on: fixtureSnapshot)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.matchedTargets.first?.id, "detail-row")
    }

    func testTargetGoneConditionRecognizesAbsence() {
        let condition = TargetSnapshotCondition.targetGone(.identifier("missing"))
        let result = condition.evaluate(on: fixtureSnapshot)

        XCTAssertTrue(result.passed)
    }

    func testTargetSelectedConditionReadsSelectionState() {
        let matcher = TargetDescriptorMatcher.role("AXCheckBox")
        let result = TargetSnapshotCondition.targetSelected(matcher).evaluate(on: fixtureSnapshot)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.matchedTargets.first?.id, "toggle-option")
    }

    private var fixtureSnapshot: TargetSnapshot {
        let primary = descriptor(
            id: "primary-action",
            title: "Primary Action",
            role: "AXButton",
            subtitle: "Main action"
        )
        let rowOne = descriptor(id: "row-one", title: "Row One", role: "AXStaticText")
        let rowTwo = descriptor(id: "row-two", title: "Row Two", role: "AXStaticText")
        let detailRow = descriptor(
            id: "detail-row",
            title: "Status",
            value: "Detail narrative",
            subtitle: "Detailed description is available"
        )
        let toggle = descriptor(
            id: "toggle-option",
            title: "Toggle Option",
            role: "AXCheckBox",
            value: "1"
        )

        return TargetSnapshot(
            appName: "FixtureHost",
            bundleIdentifier: "com.fixture.host",
            windowTitle: "Main Panel",
            targets: [primary, rowOne, rowTwo, detailRow, toggle]
        )
    }

    private func descriptor(
        id: String,
        title: String,
        role: String = "AXStaticText",
        value: String? = nil,
        subtitle: String? = nil
    ) -> TargetDescriptor {
        TargetDescriptor(
            id: id,
            appName: "FixtureHost",
            role: role,
            title: title,
            subtitle: subtitle,
            value: value,
            frame: nil,
            path: []
        )
    }
}
