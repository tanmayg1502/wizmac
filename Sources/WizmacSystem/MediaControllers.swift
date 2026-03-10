import Foundation

public actor MusicController: MusicVolumeControlling {
    private let shellRunner: any ShellRunning

    init(shellRunner: any ShellRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
    }

    public func currentVolume() async -> Int? {
        for appName in ["Music", "iTunes"] {
            let script = #"tell application "\#(appName)" to get sound volume"#
            guard let result = try? await shellRunner.run(launchPath: "/usr/bin/osascript", arguments: ["-e", script], timeout: 1.0) else {
                continue
            }
            if let value = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }

    public func setVolume(_ value: Int) async -> (Bool, String) {
        let bounded = min(max(value, 0), 100)
        for appName in ["Music", "iTunes"] {
            let script = #"tell application "\#(appName)" to set sound volume to \#(bounded)"#
            guard let result = try? await shellRunner.run(launchPath: "/usr/bin/osascript", arguments: ["-e", script], timeout: 1.0) else {
                continue
            }
            if result.terminationStatus == 0 {
                return (true, "\(appName) volume set to \(bounded).")
            }
        }
        return (false, "Unable to communicate with Music or iTunes.")
    }
}

public actor AirPlayController: AirPlayControlling {
    private let shellRunner: any ShellRunning

    init(shellRunner: any ShellRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
    }

    public func listDevices() async -> [String] {
        guard
            let result = try? await shellRunner.run(
                launchPath: "/usr/bin/dns-sd",
                arguments: ["-B", "_airplay._tcp"],
                timeout: 0.6
            )
        else {
            return []
        }

        return Self.parseDevices(from: result.stdout)
    }

    public func connect(device: String) async -> (Bool, String) {
        await performMenuScript("""
        set found to false
        tell application "System Events"
            tell process "SystemUIServer"
                set airplayMenuItem to click (menu bar item 1 of menu bar 1 whose description contains "Displays")
                delay 0.1
                try
                    click menu item "\(device)" of menu 1 of airplayMenuItem
                    set found to true
                    delay 0.5
                on error
                    try
                        key code 53
                    end try
                end try
            end tell
        end tell
        return found
        """, success: "AirPlay display routed to \(device).", failure: "Could not select \(device).")
    }

    public func disconnect() async -> (Bool, String) {
        let candidates = ["Stop AirPlay", "Turn AirPlay Off"]
        for candidate in candidates {
            let result = await performMenuScript(
                """
                set found to false
                tell application "System Events"
                    tell process "SystemUIServer"
                        set airplayMenuItem to click (menu bar item 1 of menu bar 1 whose description contains "Displays")
                        delay 0.1
                        try
                            click menu item "\(candidate)" of menu 1 of airplayMenuItem
                            set found to true
                        on error
                            try
                                key code 53
                            end try
                        end try
                    end tell
                end tell
                return found
                """,
                success: "AirPlay display disconnected.",
                failure: "Could not disconnect AirPlay display."
            )
            if result.0 {
                return result
            }
        }
        return (false, "Could not disconnect AirPlay display.")
    }

    public func openMenu() async -> (Bool, String) {
        await performMenuScript(
            """
            set found to false
            tell application "System Events"
                tell process "SystemUIServer"
                    click (menu bar item 1 of menu bar 1 whose description contains "Displays")
                    set found to true
                end tell
            end tell
            return found
            """,
            success: "Opened the Displays menu.",
            failure: "Could not open the Displays menu."
        )
    }
}

extension AirPlayController {
    static func parseDevices(from output: String) -> [String] {
        let lines = output.split(separator: "\n").dropFirst(4)
        var devices = Set<String>()
        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 7 {
                devices.insert(parts.dropFirst(6).joined(separator: " "))
            }
        }
        return devices.sorted()
    }
}

private extension AirPlayController {
    func performMenuScript(_ script: String, success: String, failure: String) async -> (Bool, String) {
        guard let result = try? await shellRunner.run(
            launchPath: "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: 2.0
        ) else {
            return (false, "Unable to control the Displays menu.")
        }

        let wasFound = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        return (wasFound, wasFound ? success : failure)
    }
}
