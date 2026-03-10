import SwiftUI

struct FixtureContentView: View {
    @ObservedObject var store: FixtureStore
    @Environment(\.openWindow) private var openWindow
    @State private var expandedHierarchySections: Set<String> = ["projects", "devices"]

    var body: some View {
        NavigationSplitView {
            List {
                Section("Actions") {
                    Button("Open Secondary Window") {
                        store.recordWindowOpen("secondary")
                        openWindow(id: "secondary")
                    }
                    .accessibilityIdentifier("fixture.open.secondary")

                    Button("Open Duplicate Secondary Window") {
                        store.recordWindowOpen("secondary-duplicate")
                        openWindow(id: "secondary-duplicate")
                    }
                    .accessibilityIdentifier("fixture.open.secondaryDuplicate")

                    Button("Open Inspector Window") {
                        store.recordWindowOpen("inspector")
                        openWindow(id: "inspector")
                    }
                    .accessibilityIdentifier("fixture.open.inspector")

                    Button("Show Approval Sheet") {
                        store.presentSheet()
                    }
                    .accessibilityIdentifier("fixture.sheet.show")
                }

                Section("Recent Log") {
                    ForEach(store.actionLog, id: \.self) { entry in
                        Text(entry)
                            .font(.caption)
                    }
                }
            }
            .frame(minWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    formSection
                    advancedEditorsSection
                    tableSection
                    hierarchySection
                    interactionSection
                    cardSection
                }
                .padding(20)
            }
            .navigationTitle("Fixture Host")
        }
        .sheet(isPresented: $store.showSheet) {
            FixtureApprovalSheet(store: store)
        }
        .alert("Fixture Alert", isPresented: $store.showAlert) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("This alert exists to exercise keyboard navigation and confirmation handling.")
        }
    }

    private var formSection: some View {
        GroupBox("Text and Controls") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search", text: $store.query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("fixture.searchField")

                SecureField("Secret", text: $store.secureValue)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("fixture.secureField")

                TextEditor(text: $store.notes)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.2))
                    )
                    .accessibilityIdentifier("fixture.notesEditor")

                HStack(spacing: 12) {
                    Toggle("Enabled", isOn: $store.toggleValue)
                        .accessibilityIdentifier("fixture.enabledToggle")
                    Slider(value: $store.sliderValue, in: 0...1)
                        .accessibilityIdentifier("fixture.slider")
                    Text(store.sliderValue.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Button("Primary Action") {
                        store.incrementCounter()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fixture.primaryAction")

                    Button("Show Alert") {
                        store.queueAlert()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("fixture.alertAction")

                    Button("Add Row") {
                        store.addMessage()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("fixture.addRow")

                    Text("Clicks: \(store.clickCount)")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private var tableSection: some View {
        GroupBox("Table and List") {
            VStack(alignment: .leading, spacing: 12) {
                Table(store.messages, selection: $store.selectedMessageIDs) {
                    TableColumn("Title", value: \.title)
                    TableColumn("Detail", value: \.detail)
                    TableColumn("Flagged") { message in
                        Image(systemName: message.isFlagged ? "flag.fill" : "flag")
                            .foregroundStyle(message.isFlagged ? .orange : .secondary)
                    }
                }
                .frame(minHeight: 160)
                .accessibilityIdentifier("fixture.messageTable")

                HStack {
                    Button("Delete Selected", role: .destructive) {
                        store.deleteSelectedMessages()
                    }
                    .disabled(store.selectedMessageIDs.isEmpty)
                    .accessibilityIdentifier("fixture.deleteSelected")

                    Spacer()

                    Text("\(store.messages.count) rows")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var advancedEditorsSection: some View {
        GroupBox("AppKit and WebKit Editors") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NSTextField")
                        .font(.subheadline.weight(.semibold))
                    AppKitTextFieldFixture(text: $store.appKitFieldValue)
                        .frame(height: 28)
                        .accessibilityIdentifier("fixture.appkitField")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("NSTextView")
                        .font(.subheadline.weight(.semibold))
                    AppKitTextViewFixture(text: $store.appKitTextViewValue)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("fixture.appkitTextView")
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("WebKit Editable Surface")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(store.webEditableStatus)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    WebKitEditableFixture { event in
                        store.recordWebInteraction(event)
                    }
                    .frame(minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2))
                    )
                    .accessibilityIdentifier("fixture.webkitEditable")
                }
            }
        }
    }

    private var hierarchySection: some View {
        GroupBox("Hierarchy and Nested Actions") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.hierarchySections) { section in
                    DisclosureGroup(
                        section.title,
                        isExpanded: Binding(
                            get: { expandedHierarchySections.contains(section.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedHierarchySections.insert(section.id)
                                } else {
                                    expandedHierarchySections.remove(section.id)
                                }
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.items) { item in
                                Button {
                                    store.selectHierarchyItem(item)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.body.weight(.medium))
                                            Text(item.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if store.lastHierarchySelection == item.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("fixture.hierarchy.\(item.id)")
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private var interactionSection: some View {
        GroupBox("Popover and Manual Surface") {
            VStack(alignment: .leading, spacing: 14) {
                Button(store.showPopover ? "Hide Popover" : "Show Popover") {
                    store.togglePopover()
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $store.showPopover, arrowEdge: .bottom) {
                    FixtureQuickPopover(store: store)
                }
                .accessibilityIdentifier("fixture.popover.toggle")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(store.surfacePads) { pad in
                        Button {
                            store.activateSurfacePad(pad)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pad.title)
                                    .font(.headline)
                                Text(pad.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                if store.lastSurfacePadActivation == pad.id {
                                    Label("Last target", systemImage: "scope")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                            .background(pad.tint.gradient.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fixture.surface.\(pad.id)")
                    }
                }
            }
        }
    }

    private var cardSection: some View {
        GroupBox("Scrollable Cards") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(store.cards) { card in
                        Button {
                            store.openCard(card)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(card.title)
                                    .font(.headline)
                                Text(card.caption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Label("Open", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(16)
                            .frame(width: 180, height: 120, alignment: .leading)
                            .background(card.tint.gradient.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fixture.card.\(card.title.lowercased())")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct FixtureApprovalSheet: View {
    @ObservedObject var store: FixtureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Approval Fixture")
                .font(.title2.weight(.semibold))

            Text("Use this sheet to exercise modal focus changes, text entry, and confirm/cancel actions.")
                .foregroundStyle(.secondary)

            TextField("Approval note", text: $store.sheetDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fixture.sheet.note")

            HStack {
                Button("Cancel") {
                    store.dismissSheet(confirming: false)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("fixture.sheet.cancel")

                Spacer()

                Button("Confirm") {
                    store.dismissSheet(confirming: true)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fixture.sheet.confirm")
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 220)
    }
}

private struct FixtureQuickPopover: View {
    @ObservedObject var store: FixtureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Popover")
                .font(.headline)
            Text("Last hierarchy selection")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(store.lastHierarchySelection ?? "None yet")
                .font(.body.monospaced())
            Text("Last manual target")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(store.lastSurfacePadActivation ?? "None yet")
                .font(.body.monospaced())
        }
        .padding(16)
        .frame(width: 260)
        .accessibilityIdentifier("fixture.popover")
    }
}
