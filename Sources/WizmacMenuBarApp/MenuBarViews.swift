import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            permissionOnboarding
            serverControls
            remoteClients
            activeSessions
            permissionSummary
            pendingApprovals
            recentAudit
            footer
        }
        .padding(14)
        .frame(width: 360)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wizmac")
                    .font(.headline)
                Text("Keyboard and agent control for your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help("Refresh permissions, approvals, and audit data")
            .disabled(viewModel.isRefreshing)
        }
    }

    @ViewBuilder
    private var permissionOnboarding: some View {
        if viewModel.snapshot.needsPermissionOnboarding {
            GroupBox("Finish Setup") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.snapshot.setupSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Request Missing Permissions") {
                            viewModel.requestMissingPermissions()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Refresh") {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                        .buttonStyle(.bordered)

                        if viewModel.snapshot.canFinishSetup {
                            Button("Finish Setup") {
                                viewModel.completeSetup()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text("macOS still requires you to click Allow. Screen Recording may need a relaunch before Wizmac sees the new access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.snapshot.setupChecklist) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))

                                statusPill(for: item)

                                Spacer()

                                Button(item.actionTitle) {
                                    runSetupAction(for: item.id, primary: true)
                                }
                                .buttonStyle(.borderedProminent)

                                if let secondaryActionTitle = item.secondaryActionTitle {
                                    Button(secondaryActionTitle) {
                                        runSetupAction(for: item.id, primary: false)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func runSetupAction(for id: String, primary: Bool) {
        switch (id, primary) {
        case ("automation_music", _):
            viewModel.openPermissionSettings(id)
        case (_, true):
            viewModel.requestPermission(id)
        case (_, false):
            viewModel.openPermissionSettings(id)
        }
    }

    private func statusPill(for item: SetupChecklistItem) -> some View {
        Text(item.isComplete ? "Ready" : "Needs Setup")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(item.isComplete ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((item.isComplete ? Color.green : Color.orange).opacity(0.12))
            )
    }

    private var serverControls: some View {
        GroupBox("Control Plane") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Local CLI and MCP",
                    isOn: Binding(
                        get: { viewModel.snapshot.serverState.localControlPlaneRunning },
                        set: { viewModel.setLocalControlPlaneRunning($0) }
                    )
                )

                Toggle(
                    "Remote Agent API",
                    isOn: Binding(
                        get: { viewModel.snapshot.serverState.remoteHTTPRunning },
                        set: { viewModel.setRemoteHTTPRunning($0) }
                    )
                )

                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { viewModel.snapshot.launchAtLoginEnabled },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                .disabled(viewModel.snapshot.canToggleLaunchAtLogin == false)

                Text(viewModel.snapshot.launchAtLoginMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

                if let launchAtLoginError = viewModel.snapshot.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Remote requests still queue approval for risky actions, and paired clients enroll with certificates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Trusted Local Automation")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if viewModel.snapshot.hasTrustedAutomationSession {
                            Button("End Session") {
                                viewModel.endTrustedAutomationSession()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Start Session") {
                                viewModel.startTrustedAutomationSession()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if viewModel.snapshot.hasTrustedAutomationSession {
                        Text(
                            "Fast local mode is active for \(viewModel.snapshot.trustedAutomationAppName ?? "the current app")\(viewModel.snapshot.trustedAutomationExpiresAt.map { " until \(relativeDate($0))" } ?? "")."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Start a 10-minute trusted session to reduce approval round trips for local UI actions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                LabeledContent("Service", value: viewModel.snapshot.serverState.serviceStatus)
                    .font(.caption)

                if let localURL = viewModel.snapshot.serverState.localControlPlaneURL {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local")
                            .font(.caption.weight(.semibold))
                        Text(localURL)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let remoteURL = viewModel.snapshot.serverState.remoteControlPlaneURL {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote")
                            .font(.caption.weight(.semibold))
                        Text(remoteURL)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastError = viewModel.snapshot.serverState.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var remoteClients: some View {
        GroupBox("Remote Clients") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pair agents and revoke remote access from the shared service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Pair Client") {
                        viewModel.pairRemoteClient()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let pairing = viewModel.snapshot.lastPairing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest Pairing")
                            .font(.caption.weight(.semibold))
                        Text("\(pairing.client.name) at \(pairing.endpoint)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Server fingerprint: \(pairing.serverCertificateFingerprint)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }

                if viewModel.snapshot.remoteClients.isEmpty {
                    Text("No remote clients paired yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.snapshot.remoteClients) { client in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(client.fingerprint)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Revoke") {
                                    viewModel.revokeRemoteClient(client.id)
                                }
                                .buttonStyle(.bordered)
                            }

                            Text("Paired \(relativeDate(client.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var permissionSummary: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.snapshot.permissions.isEmpty {
                    Text("No permission data loaded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.snapshot.permissions) { permission in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: iconName(for: permission.state))
                                .foregroundStyle(color(for: permission.state))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(permission.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(permission.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeSessions: some View {
        GroupBox("Live Sessions") {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.snapshot.activeSessions.isEmpty {
                    Text("No active hint, scroll, or text sessions right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.snapshot.activeSessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(session.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(session.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Updated \(relativeDate(session.updatedAt))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var pendingApprovals: some View {
        GroupBox("Pending Approvals") {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.snapshot.pendingApprovals.isEmpty {
                    Text("No confirmations are waiting.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.snapshot.pendingApprovals) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(request.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(relativeDate(request.requestedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(request.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Approve") {
                                    viewModel.approve(request.id)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Reject") {
                                    viewModel.reject(request.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var recentAudit: some View {
        GroupBox("Recent Audit") {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.snapshot.recentAudit.isEmpty {
                    Text("No audit entries yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.snapshot.recentAudit) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(relativeDate(entry.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh Now") {
                Task {
                    await viewModel.refresh()
                }
            }

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }

    private func iconName(for state: PermissionState) -> String {
        switch state {
        case .granted:
            "checkmark.circle.fill"
        case .limited:
            "exclamationmark.triangle.fill"
        case .missing:
            "xmark.circle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .granted:
            .green
        case .limited:
            .orange
        case .missing:
            .red
        case .unknown:
            .secondary
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
