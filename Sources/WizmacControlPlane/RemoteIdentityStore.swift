import CryptoKit
import Foundation
import WizmacCore

public struct HTTPRemoteIdentityRecord: Sendable, Equatable {
    public var clientID: String
    public var fingerprint: String
    public var publicKeyRawRepresentation: Data?
    public var legacyAccessToken: String?

    public init(
        clientID: String,
        fingerprint: String,
        publicKeyRawRepresentation: Data?,
        legacyAccessToken: String?
    ) {
        self.clientID = clientID
        self.fingerprint = fingerprint
        self.publicKeyRawRepresentation = publicKeyRawRepresentation
        self.legacyAccessToken = legacyAccessToken
    }
}

private struct RemoteIdentityAuthorityRecord: Codable, Equatable, Sendable {
    var certificateAuthorityPEM: String
    var fingerprint: RemoteIdentityFingerprint
}

private struct StoredRemoteIdentityRecord: Codable, Equatable, Sendable {
    var clientID: UUID
    var name: String
    var fingerprint: RemoteIdentityFingerprint
    var issuedAt: Date
    var authenticationMethod: RemoteIdentityAuthenticationMethod
    var certificatePEM: String
    var publicKeyRawRepresentationBase64: String?
    var legacyAccessToken: String?

    var metadata: RemoteIdentityMetadata {
        RemoteIdentityMetadata(
            id: clientID,
            name: name,
            fingerprint: fingerprint,
            issuedAt: issuedAt,
            authenticationMethod: authenticationMethod
        )
    }
}

private struct RemoteIdentityStoreDocument: Codable, Equatable, Sendable {
    var authority: RemoteIdentityAuthorityRecord
    var identities: [StoredRemoteIdentityRecord]
}

private struct LegacyRemotePairingRecord: Codable, Equatable, Sendable {
    var clientID: UUID
    var token: String
    var issuedAt: Date
}

public actor RemoteIdentityStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let url: URL
    private let legacyTokenURL: URL

    public init(
        fileManager: FileManager = .default,
        url: URL? = nil,
        legacyTokenURL: URL? = nil
    ) throws {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let baseDirectory = try WizmacPaths.applicationSupportDirectory(fileManager: fileManager)
        self.url = try url ?? WizmacPaths.remoteIdentityURL(fileManager: fileManager)
        self.legacyTokenURL = legacyTokenURL ?? baseDirectory.appendingPathComponent("remote-client-secrets.json")

        try Self.bootstrap(
            fileManager: self.fileManager,
            url: self.url,
            legacyTokenURL: self.legacyTokenURL,
            decoder: self.decoder,
            encoder: self.encoder
        )
    }

    public func listIdentities() throws -> [RemoteIdentityMetadata] {
        try loadDocument()
            .identities
            .sorted { $0.issuedAt > $1.issuedAt }
            .map(\.metadata)
    }

    public func enroll(
        clientID: UUID,
        name: String,
        serverHost: String,
        serverPort: Int
    ) throws -> RemoteEnrollmentBundle {
        var document = try loadDocument()
        let privateKey = P256.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        let fingerprint = Self.fingerprint(for: publicKeyData)
        let issuedAt = Date()
        let certificatePEM = try Self.makeCertificatePEM(
            clientID: clientID,
            name: name,
            issuedAt: issuedAt,
            publicKeyData: publicKeyData,
            fingerprint: fingerprint
        )
        let privateKeyPEM = Self.makePEM(type: "PRIVATE KEY", payload: privateKey.rawRepresentation)

        let record = StoredRemoteIdentityRecord(
            clientID: clientID,
            name: name,
            fingerprint: RemoteIdentityFingerprint(value: fingerprint),
            issuedAt: issuedAt,
            authenticationMethod: .signature,
            certificatePEM: certificatePEM,
            publicKeyRawRepresentationBase64: publicKeyData.base64EncodedString(),
            legacyAccessToken: nil
        )

        document.identities.removeAll { $0.clientID == clientID }
        document.identities.append(record)
        try saveDocument(document)

        return RemoteEnrollmentBundle(
            identity: record.metadata,
            clientCertificatePEM: certificatePEM,
            clientPrivateKeyPEM: privateKeyPEM,
            certificateAuthorityPEM: document.authority.certificateAuthorityPEM,
            serverHost: serverHost,
            serverPort: serverPort,
            serverCertificateFingerprint: document.authority.fingerprint.value
        )
    }

    public func revoke(clientID: UUID) throws {
        var document = try loadDocument()
        document.identities.removeAll { $0.clientID == clientID }
        try saveDocument(document)
    }

    public func retainOnly(clientIDs: Set<UUID>) throws {
        var document = try loadDocument()
        document.identities = document.identities.filter { clientIDs.contains($0.clientID) }
        try saveDocument(document)
    }

    public func httpIdentityRecordsByClientID() throws -> [String: HTTPRemoteIdentityRecord] {
        Dictionary(
            uniqueKeysWithValues: try loadDocument().identities.map { record in
                let publicKey = record.publicKeyRawRepresentationBase64.flatMap { Data(base64Encoded: $0) }
                return (
                    record.clientID.uuidString,
                    HTTPRemoteIdentityRecord(
                        clientID: record.clientID.uuidString,
                        fingerprint: record.fingerprint.value,
                        publicKeyRawRepresentation: publicKey,
                        legacyAccessToken: record.legacyAccessToken
                    )
                )
            }
        )
    }

    private static func bootstrap(
        fileManager: FileManager,
        url: URL,
        legacyTokenURL: URL,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) throws {
        if fileManager.fileExists(atPath: url.path) {
            return
        }

        var document = RemoteIdentityStoreDocument(
            authority: Self.makeAuthorityRecord(),
            identities: []
        )

        if fileManager.fileExists(atPath: legacyTokenURL.path) {
            let legacyRecords = try decoder.decode([LegacyRemotePairingRecord].self, from: Data(contentsOf: legacyTokenURL))
            if legacyRecords.isEmpty == false {
                document.identities = legacyRecords.map { record in
                    let fingerprintValue = RemotePairingStore.fingerprint(for: record.token)
                    return StoredRemoteIdentityRecord(
                        clientID: record.clientID,
                        name: "Migrated Client \(record.clientID.uuidString.prefix(8))",
                        fingerprint: RemoteIdentityFingerprint(value: fingerprintValue),
                        issuedAt: record.issuedAt,
                        authenticationMethod: .legacyBearerMigration,
                        certificatePEM: Self.makePEM(type: "CERTIFICATE", payload: Data(record.token.utf8)),
                        publicKeyRawRepresentationBase64: nil,
                        legacyAccessToken: record.token
                    )
                }
            }
        }

        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    private func loadDocument() throws -> RemoteIdentityStoreDocument {
        let data = try Data(contentsOf: url)
        return try decoder.decode(RemoteIdentityStoreDocument.self, from: data)
    }

    private func saveDocument(_ document: RemoteIdentityStoreDocument) throws {
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    private static func makeAuthorityRecord() -> RemoteIdentityAuthorityRecord {
        let authorityKey = P256.Signing.PrivateKey()
        let publicKeyData = authorityKey.publicKey.rawRepresentation
        let fingerprint = RemoteIdentityFingerprint(value: fingerprint(for: publicKeyData))
        return RemoteIdentityAuthorityRecord(
            certificateAuthorityPEM: makePEM(type: "CERTIFICATE", payload: publicKeyData),
            fingerprint: fingerprint
        )
    }

    private static func makeCertificatePEM(
        clientID: UUID,
        name: String,
        issuedAt: Date,
        publicKeyData: Data,
        fingerprint: String
    ) throws -> String {
        let payload = try JSONEncoder().encode([
            "clientID": clientID.uuidString,
            "name": name,
            "issuedAt": ISO8601DateFormatter().string(from: issuedAt),
            "fingerprint": fingerprint,
            "publicKey": publicKeyData.base64EncodedString(),
        ])
        return makePEM(type: "CERTIFICATE", payload: payload)
    }

    static func fingerprint(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
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

    private static func makePEM(type: String, payload: Data) -> String {
        let base64 = payload.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return """
        -----BEGIN \(type)-----
        \(base64)
        -----END \(type)-----
        """
    }
}
