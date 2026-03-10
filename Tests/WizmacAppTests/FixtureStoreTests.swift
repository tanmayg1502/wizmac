import XCTest
@testable import WizmacFixtureHostSupport

@MainActor
final class FixtureStoreTests: XCTestCase {
    func testIncrementCounterAppendsLog() {
        let store = FixtureStore()

        store.incrementCounter()

        XCTAssertEqual(store.clickCount, 1)
        XCTAssertEqual(store.actionLog.first, "Primary button clicked 1x")
    }

    func testDeleteSelectedMessagesClearsSelection() {
        let store = FixtureStore()
        let firstID = try! XCTUnwrap(store.messages.first?.id)
        store.selectedMessageIDs = [firstID]

        store.deleteSelectedMessages()

        XCTAssertEqual(store.messages.count, 2)
        XCTAssertTrue(store.selectedMessageIDs.isEmpty)
    }

    func testWebInteractionUpdatesStatusAndLog() {
        let store = FixtureStore()

        store.recordWebInteraction("web-rich:focus")

        XCTAssertEqual(store.webEditableStatus, "web-rich:focus")
        XCTAssertEqual(store.actionLog.first, "WebKit editable focused: web-rich:focus")
    }

    func testPresentingAndConfirmingSheetUpdatesLog() {
        let store = FixtureStore()

        store.presentSheet()
        store.dismissSheet(confirming: true)

        XCTAssertFalse(store.showSheet)
        XCTAssertEqual(store.actionLog.prefix(2), ["Approval sheet confirmed", "Approval sheet presented"])
    }
}
