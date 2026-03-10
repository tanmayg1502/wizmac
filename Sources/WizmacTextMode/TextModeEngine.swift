import Foundation

public enum TextModeEngineError: Error, Sendable, Equatable {
    case attachmentNotFound(TextAttachmentID)
    case secureInputUnsupported(TextAttachmentID)
}

public protocol TextModeEngine: Sendable {
    func attach(context: TextContextSnapshot) async throws -> TextAttachment
    func detach(attachmentID: TextAttachmentID) async
    func sync(context: TextContextSnapshot, attachmentID: TextAttachmentID) async throws -> TextModeState
    func handle(event: TextKeyEvent, attachmentID: TextAttachmentID) async throws -> TextModeDecision
    func state(for attachmentID: TextAttachmentID) async -> TextModeState?
    func attachments() async -> [TextAttachment]
}

public struct TextModeEngineAvailability: Sendable, Equatable {
    public enum Backend: String, Sendable, Equatable, Codable {
        case fallback
        case libvim
    }

    public var backend: Backend
    public var isAvailable: Bool
    public var detail: String?

    public init(backend: Backend, isAvailable: Bool, detail: String? = nil) {
        self.backend = backend
        self.isAvailable = isAvailable
        self.detail = detail
    }
}

public enum LibVimEngineFactory {
    private static let emergencyFallbackEnvironmentKey = "WIZMAC_TEXTMODE_EMERGENCY_FALLBACK"
    private static let forcedBackendEnvironmentKey = "WIZMAC_TEXTMODE_ENGINE"

    public static func availability() -> TextModeEngineAvailability {
        TextModeEngineAvailability(
            backend: .libvim,
            isAvailable: true,
            detail: "Using the embedded libvim shim backend by default."
        )
    }

    public static func makeDefaultEngine(
        processInfo: ProcessInfo = .processInfo,
        configuration: TextRuntimeConfiguration = TextRuntimeConfiguration()
    ) -> any TextModeEngine {
        if configuration.emergencyFallbackEnabled {
            return FallbackTextModeEngine()
        }

        if liveEnv(forcedBackendEnvironmentKey)?.lowercased() == TextModeEngineAvailability.Backend.fallback.rawValue {
            return FallbackTextModeEngine()
        }

        if liveEnv(emergencyFallbackEnvironmentKey) == "1" {
            return FallbackTextModeEngine()
        }

        return LibVimTextModeEngine()
    }

    private static func liveEnv(_ key: String) -> String? {
        key.withCString { ptr in getenv(ptr).map { String(cString: $0) } }
    }
}
