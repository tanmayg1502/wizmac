import Foundation
import Network
import WizmacCore

struct ScreenCaptureScope: Sendable, Equatable {
    var windowID: Int?
    var rect: TargetRect?
    var description: String

    static let fullScreen = ScreenCaptureScope(windowID: nil, rect: nil, description: "full_screen")
}

struct ScreenshotCaptureRequest: Sendable {
    var path: String
    var format: String
    var includeCursor: Bool
    var scope: ScreenCaptureScope
}

struct ScreenRecordingRequest: Sendable {
    var sessionID: String
    var path: String
    var codec: String
    var fps: Int
    var includeCursor: Bool
    var maxDurationSeconds: Int?
    var scope: ScreenCaptureScope
}

struct ScreenStreamRequest: Sendable {
    var sessionID: String
    var format: String
    var endpoint: String?
    var fps: Int
    var includeCursor: Bool
    var scope: ScreenCaptureScope
}

struct ScreenMediaOperationResult: Sendable {
    var outcome: ActionOutcome
    var message: String
    var payload: JSONValue?
}

protocol ScreenMediaControlling: Sendable {
    func screenshot(_ request: ScreenshotCaptureRequest) async -> ScreenMediaOperationResult
    func startRecording(_ request: ScreenRecordingRequest) async -> ScreenMediaOperationResult
    func stopRecording(sessionID: String?) async -> ScreenMediaOperationResult
    func recordingStatus(sessionID: String?) async -> ScreenMediaOperationResult
    func startStream(_ request: ScreenStreamRequest) async -> ScreenMediaOperationResult
    func stopStream(sessionID: String?) async -> ScreenMediaOperationResult
    func streamStatus(sessionID: String?) async -> ScreenMediaOperationResult
}

public actor ScreenMediaController: ScreenMediaControlling {
    private struct RecordingHandle {
        var process: Process
        var path: String
        var codec: String
        var fps: Int
        var scope: ScreenCaptureScope
        var startedAt: Date
    }

    private struct StreamHandle {
        var listener: NWListener
        var endpoint: String
        var format: String
        var fps: Int
        var includeCursor: Bool
        var scope: ScreenCaptureScope
        var startedAt: Date
        var task: Task<Void, Never>
        var connections: [UUID: NWConnection]
    }

    private let shellRunner: any ShellRunning
    private let fileManager: FileManager
    private let tempDirectory: URL
    private var recordingSessions: [String: RecordingHandle] = [:]
    private var streamSessions: [String: StreamHandle] = [:]

    init(
        shellRunner: any ShellRunning = ShellCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.shellRunner = shellRunner
        self.fileManager = fileManager
        self.tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("wizmac-media", isDirectory: true)
    }

    func screenshot(_ request: ScreenshotCaptureRequest) async -> ScreenMediaOperationResult {
        let format = normalizedScreenshotFormat(request.format)
        let path = URL(fileURLWithPath: request.path)
        do {
            try ensureParentDirectory(for: path)
            let result = try await shellRunner.run(
                launchPath: "/usr/sbin/screencapture",
                arguments: screenshotArguments(
                    scope: request.scope,
                    format: format,
                    includeCursor: request.includeCursor,
                    outputPath: path.path
                ),
                timeout: 8.0
            )
            guard result.terminationStatus == 0 else {
                return ScreenMediaOperationResult(
                    outcome: .failed,
                    message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Unable to capture screenshot."
                        : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                    payload: nil
                )
            }
            return ScreenMediaOperationResult(
                outcome: .success,
                message: "Captured screenshot.",
                payload: [
                    "path": .string(path.path),
                    "format": .string(format),
                    "scope": .string(request.scope.description),
                ]
            )
        } catch {
            return ScreenMediaOperationResult(
                outcome: .failed,
                message: error.localizedDescription,
                payload: nil
            )
        }
    }

    func startRecording(_ request: ScreenRecordingRequest) async -> ScreenMediaOperationResult {
        guard recordingSessions[request.sessionID] == nil else {
            return ScreenMediaOperationResult(
                outcome: .invalidRequest,
                message: "Recording session \(request.sessionID) already exists.",
                payload: nil
            )
        }

        let outputURL = URL(fileURLWithPath: request.path)
        do {
            try ensureParentDirectory(for: outputURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = recordingArguments(for: request, outputPath: outputURL.path)
            try process.run()

            recordingSessions[request.sessionID] = RecordingHandle(
                process: process,
                path: outputURL.path,
                codec: request.codec,
                fps: request.fps,
                scope: request.scope,
                startedAt: Date()
            )

            return ScreenMediaOperationResult(
                outcome: .success,
                message: "Started screen recording.",
                payload: recordingPayload(
                    sessionID: request.sessionID,
                    status: process.isRunning ? "recording" : "completed",
                    path: outputURL.path,
                    codec: request.codec,
                    fps: request.fps,
                    scope: request.scope,
                    startedAt: recordingSessions[request.sessionID]?.startedAt ?? Date()
                )
            )
        } catch {
            return ScreenMediaOperationResult(
                outcome: .failed,
                message: error.localizedDescription,
                payload: nil
            )
        }
    }

    func stopRecording(sessionID: String?) async -> ScreenMediaOperationResult {
        guard let resolvedSessionID = resolveRecordingSessionID(sessionID) else {
            return ScreenMediaOperationResult(
                outcome: .notFound,
                message: "No matching recording session.",
                payload: nil
            )
        }
        guard let handle = recordingSessions[resolvedSessionID] else {
            return ScreenMediaOperationResult(
                outcome: .notFound,
                message: "No matching recording session.",
                payload: nil
            )
        }

        if handle.process.isRunning {
            handle.process.interrupt()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if handle.process.isRunning {
                handle.process.terminate()
            }
        }

        recordingSessions.removeValue(forKey: resolvedSessionID)
        return ScreenMediaOperationResult(
            outcome: .success,
            message: "Stopped screen recording.",
            payload: recordingPayload(
                sessionID: resolvedSessionID,
                status: "stopped",
                path: handle.path,
                codec: handle.codec,
                fps: handle.fps,
                scope: handle.scope,
                startedAt: handle.startedAt
            )
        )
    }

    func recordingStatus(sessionID: String?) async -> ScreenMediaOperationResult {
        guard let resolvedSessionID = resolveRecordingSessionID(sessionID),
              let handle = recordingSessions[resolvedSessionID]
        else {
            return ScreenMediaOperationResult(
                outcome: .notFound,
                message: "No matching recording session.",
                payload: nil
            )
        }

        return ScreenMediaOperationResult(
            outcome: .success,
            message: handle.process.isRunning ? "Recording is active." : "Recording has finished.",
            payload: recordingPayload(
                sessionID: resolvedSessionID,
                status: handle.process.isRunning ? "recording" : "completed",
                path: handle.path,
                codec: handle.codec,
                fps: handle.fps,
                scope: handle.scope,
                startedAt: handle.startedAt
            )
        )
    }

    func startStream(_ request: ScreenStreamRequest) async -> ScreenMediaOperationResult {
        guard streamSessions[request.sessionID] == nil else {
            return ScreenMediaOperationResult(
                outcome: .invalidRequest,
                message: "Stream session \(request.sessionID) already exists.",
                payload: nil
            )
        }

        let format = normalizedStreamFormat(request.format)
        guard format == "mjpeg" || format == "raw" else {
            return ScreenMediaOperationResult(
                outcome: .invalidRequest,
                message: "media.stream supports formats 'mjpeg' and 'raw'.",
                payload: nil
            )
        }

        do {
            try ensureTempDirectory()
            let listener = try NWListener(using: .tcp, on: .any)
            let queue = DispatchQueue(label: "wizmac.stream.\(request.sessionID)")
            listener.start(queue: queue)

            var attempts = 0
            while listener.port == nil, attempts < 20 {
                attempts += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let port = listener.port else {
                listener.cancel()
                return ScreenMediaOperationResult(
                    outcome: .failed,
                    message: "Unable to allocate a local stream port.",
                    payload: nil
                )
            }

            let endpoint = request.endpoint ?? "tcp://127.0.0.1:\(port.rawValue)"
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                await self.runStreamLoop(sessionID: request.sessionID)
            }

            streamSessions[request.sessionID] = StreamHandle(
                listener: listener,
                endpoint: endpoint,
                format: format,
                fps: max(request.fps, 1),
                includeCursor: request.includeCursor,
                scope: request.scope,
                startedAt: Date(),
                task: task,
                connections: [:]
            )

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.acceptConnection(
                        connection,
                        sessionID: request.sessionID,
                        format: format,
                        queue: queue
                    )
                }
            }

            return ScreenMediaOperationResult(
                outcome: .success,
                message: "Started local screen stream.",
                payload: streamPayload(
                    sessionID: request.sessionID,
                    status: "streaming",
                    format: format,
                    endpoint: endpoint,
                    scope: request.scope,
                    startedAt: streamSessions[request.sessionID]?.startedAt ?? Date()
                )
            )
        } catch {
            return ScreenMediaOperationResult(
                outcome: .failed,
                message: error.localizedDescription,
                payload: nil
            )
        }
    }

    func stopStream(sessionID: String?) async -> ScreenMediaOperationResult {
        guard let resolvedSessionID = resolveStreamSessionID(sessionID),
              let handle = streamSessions.removeValue(forKey: resolvedSessionID)
        else {
            return ScreenMediaOperationResult(
                outcome: .notFound,
                message: "No matching stream session.",
                payload: nil
            )
        }

        handle.task.cancel()
        handle.listener.cancel()
        for connection in handle.connections.values {
            connection.cancel()
        }

        return ScreenMediaOperationResult(
            outcome: .success,
            message: "Stopped local screen stream.",
            payload: streamPayload(
                sessionID: resolvedSessionID,
                status: "stopped",
                format: handle.format,
                endpoint: handle.endpoint,
                scope: handle.scope,
                startedAt: handle.startedAt
            )
        )
    }

    func streamStatus(sessionID: String?) async -> ScreenMediaOperationResult {
        guard let resolvedSessionID = resolveStreamSessionID(sessionID),
              let handle = streamSessions[resolvedSessionID]
        else {
            return ScreenMediaOperationResult(
                outcome: .notFound,
                message: "No matching stream session.",
                payload: nil
            )
        }

        return ScreenMediaOperationResult(
            outcome: .success,
            message: "Stream is active.",
            payload: streamPayload(
                sessionID: resolvedSessionID,
                status: "streaming",
                format: handle.format,
                endpoint: handle.endpoint,
                scope: handle.scope,
                startedAt: handle.startedAt
            )
        )
    }
}

private extension ScreenMediaController {
    func runStreamLoop(sessionID: String) async {
        while Task.isCancelled == false {
            guard let handle = streamSessions[sessionID] else { return }
            let frameFormat = handle.format == "mjpeg" ? "jpg" : "png"
            guard let frameData = await captureFrameData(
                scope: handle.scope,
                format: frameFormat,
                includeCursor: handle.includeCursor
            ) else {
                try? await Task.sleep(nanoseconds: 250_000_000)
                continue
            }

            let payload: Data
            let contentType: String
            if handle.format == "mjpeg" {
                contentType = "image/jpeg"
                payload = makeMultipartFrame(data: frameData, contentType: contentType)
            } else {
                contentType = "application/octet-stream"
                payload = makeLengthPrefixedFrame(data: frameData)
            }

            for (id, connection) in handle.connections {
                let sent = await send(payload, over: connection)
                if sent == false {
                    streamSessions[sessionID]?.connections.removeValue(forKey: id)
                }
            }

            let frameDelayNs = UInt64(max(1, 1_000 / max(handle.fps, 1))) * 1_000_000
            try? await Task.sleep(nanoseconds: frameDelayNs)
        }
    }

    func acceptConnection(
        _ connection: NWConnection,
        sessionID: String,
        format: String,
        queue: DispatchQueue
    ) async {
        let id = UUID()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task {
                    await self.registerConnection(connection, id: id, sessionID: sessionID)
                    if format == "mjpeg" {
                        _ = await self.send(Self.mjpegHeader, over: connection)
                    }
                }
            case .failed, .cancelled:
                Task {
                    await self.unregisterConnection(id: id, sessionID: sessionID)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func registerConnection(_ connection: NWConnection, id: UUID, sessionID: String) {
        streamSessions[sessionID]?.connections[id] = connection
    }

    func unregisterConnection(id: UUID, sessionID: String) {
        streamSessions[sessionID]?.connections.removeValue(forKey: id)
    }

    func captureFrameData(
        scope: ScreenCaptureScope,
        format: String,
        includeCursor: Bool
    ) async -> Data? {
        do {
            try ensureTempDirectory()
            let outputURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(format)
            defer { try? fileManager.removeItem(at: outputURL) }
            let result = try await shellRunner.run(
                launchPath: "/usr/sbin/screencapture",
                arguments: screenshotArguments(
                    scope: scope,
                    format: format,
                    includeCursor: includeCursor,
                    outputPath: outputURL.path
                ),
                timeout: 5.0
            )
            guard result.terminationStatus == 0 else { return nil }
            return try? Data(contentsOf: outputURL)
        } catch {
            return nil
        }
    }

    func screenshotArguments(
        scope: ScreenCaptureScope,
        format: String,
        includeCursor: Bool,
        outputPath: String
    ) -> [String] {
        var arguments = ["-x", "-t\(format)"]
        if includeCursor {
            arguments.append("-C")
        }
        arguments.append(contentsOf: scopeArguments(for: scope))
        arguments.append(outputPath)
        return arguments
    }

    func recordingArguments(for request: ScreenRecordingRequest, outputPath: String) -> [String] {
        var arguments = ["-x", "-v"]
        if request.includeCursor {
            arguments.append("-k")
        }
        if let maxDurationSeconds = request.maxDurationSeconds, maxDurationSeconds > 0 {
            arguments.append("-V\(maxDurationSeconds)")
        }
        arguments.append(contentsOf: scopeArguments(for: request.scope))
        arguments.append(outputPath)
        return arguments
    }

    func scopeArguments(for scope: ScreenCaptureScope) -> [String] {
        if let windowID = scope.windowID {
            return ["-l\(windowID)"]
        }
        if let rect = scope.rect {
            let x = Int(rect.x.rounded())
            let y = Int(rect.y.rounded())
            let width = max(Int(rect.width.rounded()), 1)
            let height = max(Int(rect.height.rounded()), 1)
            return ["-R\(x),\(y),\(width),\(height)"]
        }
        return []
    }

    func resolveRecordingSessionID(_ sessionID: String?) -> String? {
        if let sessionID, recordingSessions[sessionID] != nil {
            return sessionID
        }
        if sessionID == nil, recordingSessions.count == 1 {
            return recordingSessions.keys.first
        }
        return nil
    }

    func resolveStreamSessionID(_ sessionID: String?) -> String? {
        if let sessionID, streamSessions[sessionID] != nil {
            return sessionID
        }
        if sessionID == nil, streamSessions.count == 1 {
            return streamSessions.keys.first
        }
        return nil
    }

    func recordingPayload(
        sessionID: String,
        status: String,
        path: String,
        codec: String,
        fps: Int,
        scope: ScreenCaptureScope,
        startedAt: Date
    ) -> JSONValue {
        [
            "sessionID": .string(sessionID),
            "status": .string(status),
            "path": .string(path),
            "codec": .string(codec),
            "fps": .number(Double(fps)),
            "scope": .string(scope.description),
            "startedAt": .string(ISO8601DateFormatter().string(from: startedAt)),
        ]
    }

    func streamPayload(
        sessionID: String,
        status: String,
        format: String,
        endpoint: String,
        scope: ScreenCaptureScope,
        startedAt: Date
    ) -> JSONValue {
        [
            "sessionID": .string(sessionID),
            "status": .string(status),
            "format": .string(format),
            "endpoint": .string(endpoint),
            "scope": .string(scope.description),
            "startedAt": .string(ISO8601DateFormatter().string(from: startedAt)),
        ]
    }

    func normalizedScreenshotFormat(_ value: String) -> String {
        switch value.lowercased() {
        case "jpeg":
            return "jpg"
        default:
            return value.lowercased()
        }
    }

    func normalizedStreamFormat(_ value: String) -> String {
        value.lowercased()
    }

    func ensureParentDirectory(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func ensureTempDirectory() throws {
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    func send(_ data: Data, over connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    func makeMultipartFrame(data: Data, contentType: String) -> Data {
        var result = Data()
        result.append(Data("--frame\r\n".utf8))
        result.append(Data("Content-Type: \(contentType)\r\n".utf8))
        result.append(Data("Content-Length: \(data.count)\r\n\r\n".utf8))
        result.append(data)
        result.append(Data("\r\n".utf8))
        return result
    }

    func makeLengthPrefixedFrame(data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var payload = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        payload.append(data)
        return payload
    }

    static let mjpegHeader = Data(
        """
        HTTP/1.1 200 OK\r
        Content-Type: multipart/x-mixed-replace; boundary=frame\r
        Cache-Control: no-cache\r
        Connection: close\r
        \r
        """.utf8
    )
}
