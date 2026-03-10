import Foundation

public actor ServiceStateStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let url: URL

    public init(fileManager: FileManager = .default, url: URL? = nil) throws {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.url = try url ?? WizmacPaths.serviceStateURL(fileManager: fileManager)
    }

    public func load() throws -> ServiceHealth? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ServiceHealth.self, from: data)
    }

    public func save(_ state: ServiceHealth) throws {
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }
}
