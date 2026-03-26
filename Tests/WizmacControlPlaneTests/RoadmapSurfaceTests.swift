import Foundation
import XCTest
@testable import WizmacControlPlane

final class RoadmapSurfaceTests: XCTestCase {
    func testPhase1MutatingToolsExposeTimeoutAndTimingControls() throws {
        let expectedTools = [
            "input.key_combo",
            "input.key_sequence",
            "ui.act",
            "ui.gesture",
            "text.send_keys",
        ]

        for toolName in expectedTools {
            let properties = try toolProperties(for: toolName)
            XCTAssertEqual(properties["preDelayMs"]?.stringValue, "number", toolName)
            XCTAssertEqual(properties["postDelayMs"]?.stringValue, "number", toolName)
            XCTAssertEqual(properties["timeoutMs"]?.stringValue, "number", toolName)
        }
    }

    func testRoadmapToolFamiliesAreRegistered() throws {
        for toolName in [
            "batch.run",
            "wait.ui.exists",
            "wait.window.focused",
            "wait.condition",
            "media.screenshot",
            "media.record",
            "media.stream",
        ] {
            XCTAssertNotNil(ControlPlaneToolRegistry.default.tool(named: toolName), toolName)
        }
    }

    func testRoadmapToolSchemasExposeExpectedArguments() throws {
        let batchProperties = try toolProperties(for: "batch.run")
        XCTAssertEqual(batchProperties["steps"]?.stringValue, "array")
        XCTAssertEqual(batchProperties["file"]?.stringValue, "string")
        XCTAssertEqual(batchProperties["format"]?.stringValue, "string")
        XCTAssertEqual(batchProperties["failFast"]?.stringValue, "boolean")
        XCTAssertEqual(batchProperties["continueOnError"]?.stringValue, "boolean")
        XCTAssertEqual(batchProperties["output"]?.stringValue, "string")
        XCTAssertEqual(batchProperties["maxParallel"]?.stringValue, "number")
        XCTAssertEqual(batchProperties["cachePolicy"]?.stringValue, "string")
        XCTAssertEqual(batchProperties["snapshotReuse"]?.stringValue, "string")
        XCTAssertEqual(batchProperties["invalidateOn"]?.stringValue, "array")

        let waitExistsProperties = try toolProperties(for: "wait.ui.exists")
        let waitWindowProperties = try toolProperties(for: "wait.window.focused")
        let waitConditionProperties = try toolProperties(for: "wait.condition")

        XCTAssertEqual(waitExistsProperties["query"]?.stringValue, "string")
        XCTAssertEqual(waitExistsProperties["timeoutMs"]?.stringValue, "number")
        XCTAssertEqual(waitExistsProperties["intervalMs"]?.stringValue, "number")
        XCTAssertEqual(waitExistsProperties["stableForMs"]?.stringValue, "number")
        XCTAssertEqual(waitExistsProperties["app"]?.stringValue, "string")
        XCTAssertEqual(waitExistsProperties["pid"]?.stringValue, "number")

        XCTAssertEqual(waitWindowProperties["timeoutMs"]?.stringValue, "number")
        XCTAssertEqual(waitWindowProperties["intervalMs"]?.stringValue, "number")
        XCTAssertEqual(waitWindowProperties["stableForMs"]?.stringValue, "number")
        XCTAssertEqual(waitWindowProperties["app"]?.stringValue, "string")
        XCTAssertEqual(waitWindowProperties["pid"]?.stringValue, "number")

        XCTAssertEqual(waitConditionProperties["timeoutMs"]?.stringValue, "number")
        XCTAssertEqual(waitConditionProperties["intervalMs"]?.stringValue, "number")
        XCTAssertEqual(waitConditionProperties["stableForMs"]?.stringValue, "number")
        XCTAssertEqual(waitConditionProperties["app"]?.stringValue, "string")
        XCTAssertEqual(waitConditionProperties["pid"]?.stringValue, "number")

        let screenshotProperties = try toolProperties(for: "media.screenshot")
        XCTAssertEqual(screenshotProperties["path"]?.stringValue, "string")
        XCTAssertEqual(screenshotProperties["format"]?.stringValue, "string")
        XCTAssertEqual(screenshotProperties["includeCursor"]?.stringValue, "boolean")
        XCTAssertEqual(screenshotProperties["app"]?.stringValue, "string")
        XCTAssertEqual(screenshotProperties["pid"]?.stringValue, "number")
        XCTAssertEqual(screenshotProperties["windowID"]?.stringValue, "number")

        let recordProperties = try toolProperties(for: "media.record")
        XCTAssertEqual(recordProperties["sessionID"]?.stringValue, "string")
        XCTAssertEqual(recordProperties["path"]?.stringValue, "string")
        XCTAssertEqual(recordProperties["fps"]?.stringValue, "number")
        XCTAssertEqual(recordProperties["codec"]?.stringValue, "string")
        XCTAssertEqual(recordProperties["app"]?.stringValue, "string")
        XCTAssertEqual(recordProperties["windowID"]?.stringValue, "number")

        let streamProperties = try toolProperties(for: "media.stream")
        XCTAssertEqual(streamProperties["format"]?.stringValue, "string")
        XCTAssertEqual(streamProperties["sessionID"]?.stringValue, "string")
        XCTAssertEqual(streamProperties["app"]?.stringValue, "string")
        XCTAssertEqual(streamProperties["windowID"]?.stringValue, "number")
    }

    private func toolProperties(for name: String) throws -> [String: StructuredValue] {
        let tool = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: name))
        return try XCTUnwrap(tool.inputSchema.objectValue?["properties"]?.objectValue)
    }
}
