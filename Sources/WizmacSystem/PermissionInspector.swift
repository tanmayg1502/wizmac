import ApplicationServices
import Foundation
import WizmacCore

public final class PermissionInspector {
    public init() {}

    public func currentStatuses() -> [CapabilityStatus] {
        let accessibility = AXIsProcessTrusted()
        let screenRecording = CGPreflightScreenCaptureAccess()

        return [
            CapabilityStatus(
                name: "accessibility",
                state: accessibility ? .available : .permissionRequired,
                detail: accessibility
                    ? "Accessibility access is available."
                    : "Accessibility access is required for keyboard and UI automation."
            ),
            CapabilityStatus(
                name: "screen_recording",
                state: screenRecording ? .available : .permissionRequired,
                detail: screenRecording
                    ? "Screen recording access is available."
                    : "Screen recording access improves window and non-AX inspection."
            ),
            CapabilityStatus(
                name: "automation_music",
                state: .unavailable,
                detail: "Apple Events permission is checked lazily when a Music action runs."
            ),
        ]
    }
}
