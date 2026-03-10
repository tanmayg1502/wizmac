import Foundation
import XCTest
@testable import WizmacControlPlane

final class RemoteIdentityStoreTests: XCTestCase {
    func testEnrollmentPersistsAcrossRestartAndRevocationRemovesIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wizmac-remote-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let identityURL = directory.appendingPathComponent("remote-identities.json")
        let legacyURL = directory.appendingPathComponent("remote-client-secrets.json")
        let clientID = UUID()

        let store = try RemoteIdentityStore(url: identityURL, legacyTokenURL: legacyURL)
        let bundle = try await store.enroll(
            clientID: clientID,
            name: "Regression Agent",
            serverHost: "127.0.0.1",
            serverPort: 47242
        )

        let reopenedStore = try RemoteIdentityStore(url: identityURL, legacyTokenURL: legacyURL)
        let reopenedIdentities = try await reopenedStore.listIdentities()
        let reopenedHTTPRecords = try await reopenedStore.httpIdentityRecordsByClientID()
        XCTAssertEqual(reopenedIdentities.count, 1)
        XCTAssertEqual(reopenedIdentities.first?.fingerprint.value, bundle.identity.fingerprint.value)
        XCTAssertEqual(reopenedIdentities.first?.authenticationMethod, .signature)
        XCTAssertNotNil(reopenedHTTPRecords[clientID.uuidString]?.publicKeyRawRepresentation)
        XCTAssertNil(reopenedHTTPRecords[clientID.uuidString]?.legacyAccessToken)

        try await reopenedStore.revoke(clientID: clientID)

        let finalStore = try RemoteIdentityStore(url: identityURL, legacyTokenURL: legacyURL)
        let finalIdentities = try await finalStore.listIdentities()
        XCTAssertTrue(finalIdentities.isEmpty)
    }

    func testLegacyTokenMigrationProducesMigratedIdentityMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wizmac-remote-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let identityURL = directory.appendingPathComponent("remote-identities.json")
        let legacyURL = directory.appendingPathComponent("remote-client-secrets.json")
        let clientID = UUID()

        let legacyStore = try RemotePairingStore(url: legacyURL)
        let token = try await legacyStore.issueSecret(for: clientID)

        let identityStore = try RemoteIdentityStore(url: identityURL, legacyTokenURL: legacyURL)
        let identities = try await identityStore.listIdentities()
        let httpRecords = try await identityStore.httpIdentityRecordsByClientID()

        XCTAssertEqual(identities.count, 1)
        XCTAssertEqual(identities.first?.id, clientID)
        XCTAssertEqual(identities.first?.authenticationMethod, .legacyBearerMigration)
        XCTAssertEqual(httpRecords[clientID.uuidString]?.legacyAccessToken, token)
        XCTAssertNil(httpRecords[clientID.uuidString]?.publicKeyRawRepresentation)
    }
}
