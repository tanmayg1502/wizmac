import CryptoKit
import Foundation
import WizmacCore

private struct RemoteClientSecretRecord: Codable, Equatable, Sendable {
    var clientID: UUID
    var token: String
    var issuedAt: Date
}

public actor RemotePairingStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let url: URL

    public init(fileManager: FileManager = .default, url: URL? = nil) throws {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let baseURL = try url ?? WizmacPaths.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("remote-client-secrets.json")
        self.url = baseURL

        if fileManager.fileExists(atPath: baseURL.path) == false {
            let data = try encoder.encode([RemoteClientSecretRecord]())
            try data.write(to: baseURL, options: .atomic)
        }
    }

    public func issueSecret(for clientID: UUID) throws -> String {
        var records = try load()
        let token = Self.makeToken()
        records.removeAll { $0.clientID == clientID }
        records.append(RemoteClientSecretRecord(clientID: clientID, token: token, issuedAt: Date()))
        try save(records)
        return token
    }

    public func validate(clientID: UUID, token: String) throws -> Bool {
        try load().contains { $0.clientID == clientID && $0.token == token }
    }

    public func revoke(clientID: UUID) throws {
        let filtered = try load().filter { $0.clientID != clientID }
        try save(filtered)
    }

    public func retainOnly(clientIDs: Set<UUID>) throws {
        let filtered = try load().filter { clientIDs.contains($0.clientID) }
        try save(filtered)
    }

    public func allTokens() throws -> [String] {
        try load().map(\.token)
    }

    public func tokensByClientID() throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try load().map { ($0.clientID.uuidString, $0.token) })
    }

    private func load() throws -> [RemoteClientSecretRecord] {
        let data = try Data(contentsOf: url)
        return try decoder.decode([RemoteClientSecretRecord].self, from: data)
    }

    private func save(_ records: [RemoteClientSecretRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: url, options: .atomic)
    }

    public static func fingerprint(for token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: min(hex.count, 32), by: 4)
            .map { index in
                let start = hex.index(hex.startIndex, offsetBy: index)
                let end = hex.index(start, offsetBy: min(4, hex.distance(from: start, to: hex.endIndex)))
                return String(hex[start..<end])
            }
            .joined(separator: ":")
            .uppercased()
    }

    private static func makeToken() -> String {
        Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
