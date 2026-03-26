import XCTest
@testable import WizmacControlPlane

final class ServiceLaunchPathTests: XCTestCase {
    func testServiceLaunchCandidatesIncludeBundledServiceForCaskCLI() {
        let executable = URL(fileURLWithPath: "/Applications/Wizmac.app/Contents/Resources/bin/wizmac")
        let candidates = WizmacServiceProcessManager.serviceLaunchCandidates(
            executable: executable,
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertTrue(
            candidates.contains {
                $0.0.path == "/Applications/Wizmac.app/Contents/MacOS/WizmacService" && $0.1.isEmpty
            }
        )
        XCTAssertTrue(
            candidates.contains {
                $0.0.path == "/Applications/Wizmac.app/Contents/Resources/bin/wizmac" && $0.1 == ["service", "start"]
            }
        )
    }
}
