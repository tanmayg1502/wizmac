import AppKit
import Foundation
import WizmacCore

public struct RunningApplicationResolution: Sendable, Equatable {
    public var pid: pid_t?
    public var appName: String?
    public var bundleIdentifier: String?
    public var unresolvedApp: String?
    public var launched: Bool

    public init(
        pid: pid_t? = nil,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        unresolvedApp: String? = nil,
        launched: Bool = false
    ) {
        self.pid = pid
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.unresolvedApp = unresolvedApp
        self.launched = launched
    }
}

public enum RunningApplicationResolver {
    public static func resolve(
        pid requestedPID: pid_t? = nil,
        app requestedApp: String? = nil,
        launchIfNeeded: Bool = false,
        activate: Bool = false,
        fallbackToFrontmostWhenUnspecified: Bool = false
    ) -> RunningApplicationResolution {
        if let requestedPID {
            if let runningApplication = NSRunningApplication(processIdentifier: requestedPID) {
                if activate {
                    _ = runningApplication.activate(options: [.activateIgnoringOtherApps])
                }
                return resolution(for: runningApplication, launched: false)
            }
            return RunningApplicationResolution(unresolvedApp: "pid \(requestedPID)")
        }

        guard let requestedApp, requestedApp.isEmpty == false else {
            guard fallbackToFrontmostWhenUnspecified,
                  let frontmostApplication = NSWorkspace.shared.frontmostApplication
            else {
                return RunningApplicationResolution()
            }

            if activate {
                _ = frontmostApplication.activate(options: [.activateIgnoringOtherApps])
            }
            return resolution(for: frontmostApplication, launched: false)
        }

        if let runningApplication = bestRunningApplication(matching: requestedApp) {
            if activate {
                _ = runningApplication.activate(options: [.activateIgnoringOtherApps])
            }
            return resolution(for: runningApplication, launched: false)
        }

        guard launchIfNeeded, let applicationURL = applicationURL(for: requestedApp) else {
            return RunningApplicationResolution(unresolvedApp: requestedApp)
        }

        if let launchedApplication = launchApplication(at: applicationURL, activate: activate)
            ?? bestRunningApplication(matching: requestedApp)
        {
            return resolution(for: launchedApplication, launched: true)
        }

        return RunningApplicationResolution(unresolvedApp: requestedApp)
    }

    private static func resolution(
        for application: NSRunningApplication,
        launched: Bool
    ) -> RunningApplicationResolution {
        RunningApplicationResolution(
            pid: application.processIdentifier,
            appName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            unresolvedApp: nil,
            launched: launched
        )
    }

    private static func bestRunningApplication(matching requestedApp: String) -> NSRunningApplication? {
        let normalizedRequest = AppIdentityNormalizer.normalize(requestedApp)
        guard normalizedRequest.isEmpty == false else { return nil }

        let rankedMatches = NSWorkspace.shared.runningApplications.compactMap { application -> (score: Int, app: NSRunningApplication)? in
            let identifiers = candidateIdentifiers(for: application)

            if identifiers.contains(normalizedRequest) {
                return (0, application)
            }
            if identifiers.contains(where: { $0.hasPrefix(normalizedRequest) || normalizedRequest.hasPrefix($0) }) {
                return (1, application)
            }
            if identifiers.contains(where: { $0.contains(normalizedRequest) || normalizedRequest.contains($0) }) {
                return (2, application)
            }
            return nil
        }

        return rankedMatches.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            if lhs.app.isActive != rhs.app.isActive {
                return lhs.app.isActive
            }
            return lhs.app.processIdentifier < rhs.app.processIdentifier
        }.first?.app
    }

    private static func candidateIdentifiers(for application: NSRunningApplication) -> Set<String> {
        var identifiers: Set<String> = []
        if let name = application.localizedName {
            identifiers.insert(AppIdentityNormalizer.normalize(name))
        }
        if let bundleIdentifier = application.bundleIdentifier {
            identifiers.insert(AppIdentityNormalizer.normalize(bundleIdentifier))
        }
        if let bundleName = application.bundleURL?.deletingPathExtension().lastPathComponent {
            identifiers.insert(AppIdentityNormalizer.normalize(bundleName))
        }
        if let executableName = application.executableURL?.deletingPathExtension().lastPathComponent {
            identifiers.insert(AppIdentityNormalizer.normalize(executableName))
        }
        return identifiers.filter { $0.isEmpty == false }
    }

    private static func applicationURL(for requestedApp: String) -> URL? {
        let trimmed = requestedApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if trimmed.contains("/") {
            let pathURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: pathURL.path) {
                return pathURL
            }
        }

        if trimmed.contains("."),
           let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
        {
            return bundleURL
        }

        if let standardLocation = standardApplicationURL(named: trimmed) {
            return standardLocation
        }

        return nil
    }

    private static func launchApplication(at url: URL, activate: Bool) -> NSRunningApplication? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate

        let semaphore = DispatchSemaphore(value: 0)
        let state = LaunchState()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, _ in
            state.application = application
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return state.application
    }

    private static func standardApplicationURL(named name: String) -> URL? {
        let candidates = [
            name,
            name.hasSuffix(".app") ? name : "\(name).app",
        ]
        let baseDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        for directory in baseDirectories {
            for candidate in candidates {
                let url = directory.appendingPathComponent(candidate, isDirectory: true)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }

    private final class LaunchState: @unchecked Sendable {
        var application: NSRunningApplication?
    }
}
