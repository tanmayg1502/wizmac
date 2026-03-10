import Foundation

public enum WizmacPaths {
    public static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Wizmac", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func settingsURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("settings.json")
    }

    public static func auditURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("audit.jsonl")
    }

    public static func approvalsURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("pending-approvals.json")
    }

    public static func serviceStateURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("service-state.json")
    }

    public static func serviceEndpointURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("service-endpoint.xpc")
    }

    public static func remoteIdentityURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("remote-identities.json")
    }

    public static func certificateDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Certificates", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

public actor SettingsStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let url: URL

    public init(fileManager: FileManager = .default, url: URL? = nil) throws {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.url = try url ?? WizmacPaths.settingsURL(fileManager: fileManager)
    }

    public func load() throws -> WizmacSettings {
        guard fileManager.fileExists(atPath: url.path) else {
            let settings = WizmacSettings()
            try save(settings)
            return settings
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(WizmacSettings.self, from: data)
    }

    public func save(_ settings: WizmacSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }

    public func update(_ mutate: (inout WizmacSettings) -> Void) throws -> WizmacSettings {
        var settings = try load()
        mutate(&settings)
        try save(settings)
        return settings
    }
}

public actor AuditStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let url: URL

    public init(fileManager: FileManager = .default, url: URL? = nil) throws {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.url = try url ?? WizmacPaths.auditURL(fileManager: fileManager)

        if fileManager.fileExists(atPath: self.url.path) == false {
            fileManager.createFile(atPath: self.url.path, contents: nil)
        }
    }

    public func append(_ entry: AuditEntry) throws {
        let data = try encoder.encode(entry)
        let line = data + Data([0x0A])
        if let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    public func recent(limit: Int = 20) throws -> [AuditEntry] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .suffix(limit)

        return try lines.map { line in
            try decoder.decode(AuditEntry.self, from: Data(line.utf8))
        }
    }
}

public actor ApprovalStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let url: URL

    public init(fileManager: FileManager = .default, url: URL? = nil) throws {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.url = try url ?? WizmacPaths.approvalsURL(fileManager: fileManager)

        if fileManager.fileExists(atPath: self.url.path) == false {
            let data = try self.encoder.encode([PendingApprovalRecord]())
            try data.write(to: self.url, options: .atomic)
        }
    }

    public func list() throws -> [PendingApprovalRecord] {
        let data = try Data(contentsOf: url)
        return try decoder.decode([PendingApprovalRecord].self, from: data)
            .sorted { $0.approval.createdAt > $1.approval.createdAt }
    }

    public func enqueue(_ record: PendingApprovalRecord) throws {
        var records = try list()
        records.removeAll { $0.approval.actionRequestID == record.approval.actionRequestID }
        records.append(record)
        try save(records)
    }

    public func resolve(id: UUID) throws -> PendingApprovalRecord? {
        var records = try list()
        guard let index = records.firstIndex(where: { $0.approval.id == id }) else {
            return nil
        }
        let record = records.remove(at: index)
        try save(records)
        return record
    }

    private func save(_ records: [PendingApprovalRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: url, options: .atomic)
    }
}
