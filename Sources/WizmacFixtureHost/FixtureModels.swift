import Foundation
import SwiftUI

private let fixtureDefaultMessages: [FixtureMessage] = [
    FixtureMessage(id: UUID(), title: "Inbox", detail: "Focusable list row with plain text", isFlagged: true),
    FixtureMessage(id: UUID(), title: "Status", detail: "A second row for table navigation", isFlagged: false),
    FixtureMessage(id: UUID(), title: "Automation", detail: "Use this to test selection and copy", isFlagged: true)
]

private let fixtureDefaultCards: [FixtureCard] = [
    FixtureCard(id: UUID(), title: "Alpha", caption: "First scrollable card", tint: .mint),
    FixtureCard(id: UUID(), title: "Bravo", caption: "Second scrollable card", tint: .orange),
    FixtureCard(id: UUID(), title: "Charlie", caption: "Third scrollable card", tint: .cyan),
    FixtureCard(id: UUID(), title: "Delta", caption: "Fourth scrollable card", tint: .pink),
    FixtureCard(id: UUID(), title: "Echo", caption: "Fifth scrollable card", tint: .purple)
]

private let fixtureDefaultHierarchySections: [FixtureHierarchySection] = [
    FixtureHierarchySection(
        id: "projects",
        title: "Projects",
        items: [
            FixtureHierarchyItem(id: "projects.inbox", title: "Inbox", detail: "Nested destination for hinting and outline focus"),
            FixtureHierarchyItem(id: "projects.review", title: "Review Queue", detail: "A second hierarchy leaf to test navigation"),
        ]
    ),
    FixtureHierarchySection(
        id: "devices",
        title: "Devices",
        items: [
            FixtureHierarchyItem(id: "devices.local", title: "Local Mac", detail: "Represents the current machine"),
            FixtureHierarchyItem(id: "devices.airplay", title: "Conference Display", detail: "Represents a remote AirPlay destination"),
        ]
    ),
]

private let fixtureDefaultSurfacePads: [FixtureSurfacePad] = [
    FixtureSurfacePad(id: "pad-a1", title: "Pad A1", detail: "Top-left manual target", tint: .teal),
    FixtureSurfacePad(id: "pad-a2", title: "Pad A2", detail: "Top-right manual target", tint: .blue),
    FixtureSurfacePad(id: "pad-b1", title: "Pad B1", detail: "Bottom-left manual target", tint: .indigo),
    FixtureSurfacePad(id: "pad-b2", title: "Pad B2", detail: "Bottom-right manual target", tint: .red),
]

struct FixtureMessage: Identifiable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var isFlagged: Bool
}

struct FixtureCard: Identifiable {
    let id: UUID
    var title: String
    var caption: String
    var tint: Color
}

struct FixtureHierarchyItem: Identifiable, Hashable {
    let id: String
    var title: String
    var detail: String
}

struct FixtureHierarchySection: Identifiable, Hashable {
    let id: String
    var title: String
    var items: [FixtureHierarchyItem]
}

struct FixtureSurfacePad: Identifiable {
    let id: String
    var title: String
    var detail: String
    var tint: Color
}

@MainActor
final class FixtureStore: ObservableObject {
    private enum Constants {
        static let maxLogEntries = 32
    }

    @Published var query = "Search fixture content"
    @Published var secureValue = "hunter2"
    @Published var appKitFieldValue = "NSTextField fixture"
    @Published var appKitTextViewValue = """
This NSTextView-backed fixture exists to exercise AppKit text synchronization,
cursor movement, and modal editing outside SwiftUI wrappers.
"""
    @Published var webEditableStatus = "No WebKit interaction yet"
    @Published var notes = """
This text editor is intentionally long enough to exercise text selection,
cursor movement, and modal text editing in the fixture host.
"""
    @Published var sliderValue = 0.42
    @Published var toggleValue = true
    @Published var selectedMessageIDs = Set<UUID>()
    @Published var messages: [FixtureMessage]
    @Published var cards: [FixtureCard]
    @Published var hierarchySections: [FixtureHierarchySection]
    @Published var surfacePads: [FixtureSurfacePad]
    @Published var clickCount = 0
    @Published var showAlert = false
    @Published var showSheet = false
    @Published var showPopover = false
    @Published var sheetDraft = "Pending approval note"
    @Published var lastHierarchySelection: String?
    @Published var lastSurfacePadActivation: String?
    @Published var actionLog: [String]

    init(
        messages: [FixtureMessage] = fixtureDefaultMessages,
        cards: [FixtureCard] = fixtureDefaultCards,
        hierarchySections: [FixtureHierarchySection] = fixtureDefaultHierarchySections,
        surfacePads: [FixtureSurfacePad] = fixtureDefaultSurfacePads
    ) {
        self.messages = messages
        self.cards = cards
        self.hierarchySections = hierarchySections
        self.surfacePads = surfacePads
        self.actionLog = ["Fixture host launched"]
    }

    func incrementCounter() {
        clickCount += 1
        appendLog("Primary button clicked \(clickCount)x")
    }

    func queueAlert() {
        showAlert = true
        appendLog("Alert requested")
    }

    func addMessage() {
        let next = FixtureMessage(
            id: UUID(),
            title: "Generated row \(messages.count + 1)",
            detail: "Added to exercise dynamic tables and list updates.",
            isFlagged: false
        )
        messages.append(next)
        appendLog("Added table row \(next.title)")
    }

    func deleteSelectedMessages() {
        let ids = selectedMessageIDs
        messages.removeAll { ids.contains($0.id) }
        selectedMessageIDs.removeAll()
        appendLog("Deleted selected rows")
    }

    func openCard(_ card: FixtureCard) {
        appendLog("Opened card \(card.title)")
    }

    func presentSheet() {
        showSheet = true
        appendLog("Approval sheet presented")
    }

    func dismissSheet(confirming: Bool) {
        showSheet = false
        appendLog(confirming ? "Approval sheet confirmed" : "Approval sheet dismissed")
    }

    func togglePopover() {
        showPopover.toggle()
        appendLog(showPopover ? "Popover opened" : "Popover closed")
    }

    func selectHierarchyItem(_ item: FixtureHierarchyItem) {
        lastHierarchySelection = item.id
        appendLog("Selected hierarchy item \(item.title)")
    }

    func activateSurfacePad(_ pad: FixtureSurfacePad) {
        lastSurfacePadActivation = pad.id
        appendLog("Activated manual surface \(pad.title)")
    }

    func recordWindowOpen(_ identifier: String) {
        appendLog("Opened window \(identifier)")
    }

    func recordWebInteraction(_ identifier: String) {
        webEditableStatus = identifier
        appendLog("WebKit editable focused: \(identifier)")
    }

    func appendLog(_ entry: String) {
        actionLog.insert(entry, at: 0)
        if actionLog.count > Constants.maxLogEntries {
            actionLog = Array(actionLog.prefix(Constants.maxLogEntries))
        }
    }
}
