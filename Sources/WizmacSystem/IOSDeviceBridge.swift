import Foundation

// MARK: - Models

struct IOSDevice: Sendable {
    let udid: String
    let name: String
    let osVersion: String
    let state: String
}

struct IOSApp: Sendable {
    let bundleID: String
    let name: String
    let installType: String
}

enum IOSBridgeError: Error, LocalizedError {
    case idbNotFound(String)
    case commandFailed(String)
    case noDeviceFound
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .idbNotFound(let path):
            return "idb not found at \(path). Install with: brew install idb-companion"
        case .commandFailed(let stderr):
            return stderr.isEmpty ? "idb command failed." : stderr
        case .noDeviceFound:
            return "No connected iOS device found. Ensure the device is plugged in and trusted."
        case .parseError(let detail):
            return "Failed to parse idb output: \(detail)"
        }
    }
}

// MARK: - Bridge

/// Wraps the `idb` CLI (Meta's iOS Device Bridge) to control physical iOS/iPadOS devices.
/// Install idb: brew install idb-companion  (provides both idb and idb_companion)
/// Docs: https://fbidb.io
final class IOSDeviceBridge: @unchecked Sendable {
    private let shellRunner: any ShellRunning
    private let idbPath: String

    init(shellRunner: any ShellRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
        self.idbPath = Self.resolveIDBPath()
    }

    // MARK: - Device Discovery

    func listDevices() async -> Result<[IOSDevice], IOSBridgeError> {
        guard isIDBAvailable() else {
            return .failure(.idbNotFound(idbPath))
        }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["list-targets", "--json"],
                timeout: 10.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            let devices = parseDevices(from: result.stdout)
            return .success(devices)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    // MARK: - WiFi Connection Management

    /// Connect to a device (or idb_companion) over the network.
    /// host: IP address of the device or Mac running idb_companion.
    /// port: idb_companion port (default 27015).
    func connect(host: String, port: Int = 27015) async -> Result<String, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["connect", "\(host):\(port)"],
                timeout: 15.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(output.isEmpty ? "Connected to \(host):\(port)." : output)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    /// Disconnect a previously connected network device by UDID or host:port.
    func disconnect(udid: String) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["disconnect", udid],
                timeout: 10.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    // MARK: - Screenshot

    func screenshot(udid: String, outputPath: String) async -> Result<String, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["screenshot", outputPath, "--udid", udid],
                timeout: 15.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(outputPath)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    // MARK: - Accessibility Tree

    func accessibilityTree(udid: String) async -> Result<String, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["ui", "describe-all", "--udid", udid],
                timeout: 20.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(result.stdout)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    // MARK: - UI Actions

    func tap(udid: String, x: Double, y: Double) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["ui", "tap", "\(x)", "\(y)", "--udid", udid],
                timeout: 10.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    func swipe(udid: String, x1: Double, y1: Double, x2: Double, y2: Double, durationMs: Int = 300) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        let duration = Double(durationMs) / 1000.0
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["ui", "swipe", "\(x1)", "\(y1)", "\(x2)", "\(y2)", "\(duration)", "--udid", udid],
                timeout: Double(durationMs) / 1000.0 + 5.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    func typeText(udid: String, text: String) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["ui", "text", text, "--udid", udid],
                timeout: max(5.0, Double(text.count) * 0.1 + 3.0)
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    /// button: HOME | LOCK | SIDE_BUTTON | SIRI | APPLE_PAY | VOLUME_UP | VOLUME_DOWN
    func pressButton(udid: String, button: String) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        let normalized = button.uppercased()
        let valid = ["HOME", "LOCK", "SIDE_BUTTON", "SIRI", "APPLE_PAY", "VOLUME_UP", "VOLUME_DOWN"]
        guard valid.contains(normalized) else {
            return .failure(.commandFailed("Unknown button '\(button)'. Valid: \(valid.joined(separator: ", "))"))
        }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["ui", "button", normalized, "--udid", udid],
                timeout: 10.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    // MARK: - App Management

    func listApps(udid: String) async -> Result<[IOSApp], IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["list-apps", "--udid", udid, "--json"],
                timeout: 15.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            let apps = parseApps(from: result.stdout)
            return .success(apps)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    func launch(udid: String, bundleID: String) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["launch", bundleID, "--udid", udid],
                timeout: 30.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    func terminate(udid: String, bundleID: String) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["terminate", bundleID, "--udid", udid],
                timeout: 10.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    func openURL(udid: String, url: String) async -> Result<Void, IOSBridgeError> {
        guard isIDBAvailable() else { return .failure(.idbNotFound(idbPath)) }
        do {
            let result = try await shellRunner.run(
                launchPath: idbPath,
                arguments: ["open", url, "--udid", udid],
                timeout: 15.0
            )
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(result.stderr))
            }
            return .success(())
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    // MARK: - Helpers

    private func isIDBAvailable() -> Bool {
        if idbPath == "idb" {
            // Rely on PATH; can't pre-check without running it
            return true
        }
        return FileManager.default.fileExists(atPath: idbPath)
    }

    private static func resolveIDBPath() -> String {
        let candidates = [
            "/opt/homebrew/bin/idb",
            "/usr/local/bin/idb",
            "/usr/bin/idb",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "idb"
    }

    // MARK: - Parsing

    private func parseDevices(from output: String) -> [IOSDevice] {
        // idb list-targets --json emits one JSON object per line
        output.components(separatedBy: "\n")
            .compactMap { line -> IOSDevice? in
                guard
                    !line.trimmingCharacters(in: .whitespaces).isEmpty,
                    let data = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }

                let type = (json["type"] as? String ?? "").lowercased()
                // Only surface physical devices, not simulators
                guard type == "device" else { return nil }

                return IOSDevice(
                    udid: json["udid"] as? String ?? "",
                    name: json["name"] as? String ?? "Unknown Device",
                    osVersion: json["os_version"] as? String ?? "",
                    state: json["state"] as? String ?? "unknown"
                )
            }
    }

    private func parseApps(from output: String) -> [IOSApp] {
        // idb list-apps --json emits one JSON object per line
        output.components(separatedBy: "\n")
            .compactMap { line -> IOSApp? in
                guard
                    !line.trimmingCharacters(in: .whitespaces).isEmpty,
                    let data = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }

                return IOSApp(
                    bundleID: json["bundle_id"] as? String ?? "",
                    name: json["name"] as? String ?? "",
                    installType: json["install_type"] as? String ?? ""
                )
            }
    }
}
