import Foundation

public struct FixtureMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var detail: String
    public var isFlagged: Bool

    public init(id: UUID, title: String, detail: String, isFlagged: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isFlagged = isFlagged
    }
}

private let fixtureDefaultMessages: [FixtureMessage] = [
    FixtureMessage(id: UUID(), title: "Inbox", detail: "Focusable list row with plain text", isFlagged: true),
    FixtureMessage(id: UUID(), title: "Status", detail: "A second row for table navigation", isFlagged: false),
    FixtureMessage(id: UUID(), title: "Automation", detail: "Use this to test selection and copy", isFlagged: true),
]

@MainActor
public final class FixtureStore {
    public private(set) var actionLog: [String]
    public var selectedMessageIDs: Set<UUID>
    public private(set) var messages: [FixtureMessage]
    public private(set) var clickCount: Int
    public private(set) var webEditableStatus: String
    public private(set) var showSheet: Bool

    public init(messages: [FixtureMessage]? = nil) {
        self.messages = messages ?? fixtureDefaultMessages
        self.actionLog = ["Fixture host launched"]
        self.selectedMessageIDs = []
        self.clickCount = 0
        self.webEditableStatus = "No WebKit interaction yet"
        self.showSheet = false
    }

    public func incrementCounter() {
        clickCount += 1
        appendLog("Primary button clicked \(clickCount)x")
    }

    public func deleteSelectedMessages() {
        let ids = selectedMessageIDs
        messages.removeAll { ids.contains($0.id) }
        selectedMessageIDs.removeAll()
        appendLog("Deleted selected rows")
    }

    public func recordWebInteraction(_ identifier: String) {
        webEditableStatus = identifier
        appendLog("WebKit editable focused: \(identifier)")
    }

    public func presentSheet() {
        showSheet = true
        appendLog("Approval sheet presented")
    }

    public func dismissSheet(confirming: Bool) {
        showSheet = false
        appendLog(confirming ? "Approval sheet confirmed" : "Approval sheet dismissed")
    }

    private func appendLog(_ entry: String) {
        actionLog.insert(entry, at: 0)
        if actionLog.count > 32 {
            actionLog = Array(actionLog.prefix(32))
        }
    }
}
