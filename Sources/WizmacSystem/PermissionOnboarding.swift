import AppKit
import ApplicationServices
import Foundation
import WizmacCore

struct PermissionOnboardingOutcome: Sendable, Equatable {
    var outcome: ActionOutcome
    var message: String
}

enum PermissionOnboardingController {
    static func perform(permissionID: String, operation: String?) async -> PermissionOnboardingOutcome {
        await MainActor.run {
            performOnMainActor(permissionID: permissionID, operation: operation)
        }
    }

    @MainActor
    private static func performOnMainActor(permissionID: String, operation: String?) -> PermissionOnboardingOutcome {
        let normalizedOperation = operation?.lowercased() ?? "prompt"

        switch normalizedOperation {
        case "open_settings":
            guard openSettings(for: permissionID) else {
                return PermissionOnboardingOutcome(
                    outcome: .failed,
                    message: "Unable to open settings for \(permissionID)."
                )
            }

            return PermissionOnboardingOutcome(
                outcome: .success,
                message: "Opened settings for \(permissionID)."
            )
        case "prompt", "request":
            return requestPermission(permissionID)
        default:
            return PermissionOnboardingOutcome(
                outcome: .invalidRequest,
                message: "Unsupported permission onboarding operation '\(normalizedOperation)'."
            )
        }
    }

    @MainActor
    private static func requestPermission(_ permissionID: String) -> PermissionOnboardingOutcome {
        switch permissionID {
        case "accessibility":
            if AXIsProcessTrusted() {
                return PermissionOnboardingOutcome(
                    outcome: .success,
                    message: "Accessibility access is already available."
                )
            }

            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            let granted = AXIsProcessTrustedWithOptions(options)
            return PermissionOnboardingOutcome(
                outcome: granted ? .success : .permissionRequired,
                message: granted
                    ? "Accessibility access is available."
                    : "Opened the Accessibility privacy settings. Enable Wizmac for keyboard and UI automation."
            )
        case "screen_recording":
            if CGPreflightScreenCaptureAccess() {
                return PermissionOnboardingOutcome(
                    outcome: .success,
                    message: "Screen Recording access is already available."
                )
            }

            let granted = CGRequestScreenCaptureAccess()
            if granted == false {
                _ = openSettings(for: permissionID)
            }

            return PermissionOnboardingOutcome(
                outcome: granted ? .success : .permissionRequired,
                message: granted
                    ? "Screen Recording access is available."
                    : "Requested Screen Recording access and opened settings so you can finish enabling Wizmac."
            )
        case "automation_music":
            let opened = openSettings(for: permissionID)
            return PermissionOnboardingOutcome(
                outcome: opened ? .permissionRequired : .failed,
                message: opened
                    ? "Opened Automation settings. Apple Events permission will still be requested the first time Wizmac controls Music."
                    : "Unable to open Automation settings."
            )
        default:
            return PermissionOnboardingOutcome(
                outcome: .invalidRequest,
                message: "Unsupported permission '\(permissionID)'."
            )
        }
    }

    @MainActor
    private static func openSettings(for permissionID: String) -> Bool {
        guard let url = settingsURL(for: permissionID) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    private static func settingsURL(for permissionID: String) -> URL? {
        let rawValue: String
        switch permissionID {
        case "accessibility":
            rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case "screen_recording":
            rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case "automation_music":
            rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        default:
            return nil
        }

        return URL(string: rawValue)
    }
}
