import Foundation
import WizmacControlPlane

@main
enum WizmacServiceMain {
    static func main() async {
        do {
            let host = try WizmacServiceHost()
            try await host.start()
            try await host.runUntilCancelled()
        } catch {
            fputs("WizmacService failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
