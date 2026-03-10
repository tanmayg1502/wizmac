import SwiftUI

struct FixtureSecondaryWindowView: View {
    @ObservedObject var store: FixtureStore
    let descriptor: String
    @State private var note: String

    init(store: FixtureStore, descriptor: String = "Primary") {
        self.store = store
        self.descriptor = descriptor
        _note = State(initialValue: "\(descriptor) secondary window content")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Secondary Window")
                .font(.title2.weight(.semibold))

            Text(descriptor)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Window title", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fixture.secondary.query.\(descriptor.lowercased())")

            TextEditor(text: $note)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2))
                )
                .accessibilityIdentifier("fixture.secondary.editor.\(descriptor.lowercased())")

            List(store.messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title)
                        .font(.headline)
                    Text(message.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("fixture.secondary.list.\(descriptor.lowercased())")
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 360)
    }
}

struct FixtureInspectorView: View {
    @ObservedObject var store: FixtureStore

    var body: some View {
        Form {
            Text("Inspector Window")
                .font(.headline)

            Toggle("Enabled", isOn: $store.toggleValue)
            Slider(value: $store.sliderValue, in: 0...1)
            TextField("Inspector search", text: $store.query)
                .accessibilityIdentifier("fixture.inspector.search")

            Text("Latest event")
            Text(store.actionLog.first ?? "No actions yet")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 300, minHeight: 220)
    }
}
