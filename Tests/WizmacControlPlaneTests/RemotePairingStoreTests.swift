import Foundation
import XCTest
@testable import WizmacControlPlane

final class RemotePairingStoreTests: XCTestCase {
    func testIssuedTokensPersistAcrossRestartAndRevokeRemovesAccess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wizmac-remote-pairing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("remote-client-secrets.json")
        let clientID = UUID()

        let firstStore = try RemotePairingStore(url: url)
        let token = try await firstStore.issueSecret(for: clientID)

        let reopenedStore = try RemotePairingStore(url: url)
        let reopenedValidation = try await reopenedStore.validate(clientID: clientID, token: token)
        let reopenedTokensByClient = try await reopenedStore.tokensByClientID()
        let reopenedTokens = try await reopenedStore.allTokens()
        XCTAssertTrue(reopenedValidation)
        XCTAssertEqual(reopenedTokensByClient[clientID.uuidString], token)
        XCTAssertEqual(reopenedTokens, [token])

        try await reopenedStore.revoke(clientID: clientID)

        let finalStore = try RemotePairingStore(url: url)
        let finalValidation = try await finalStore.validate(clientID: clientID, token: token)
        let finalTokens = try await finalStore.allTokens()
        XCTAssertFalse(finalValidation)
        XCTAssertTrue(finalTokens.isEmpty)
    }
}
