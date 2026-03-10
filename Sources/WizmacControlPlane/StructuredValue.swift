import Foundation

public enum StructuredValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([StructuredValue])
    case object([String: StructuredValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([StructuredValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: StructuredValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            if value.rounded(.towardZero) == value {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public var objectValue: [String: StructuredValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var arrayValue: [StructuredValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    public var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard let numberValue else { return nil }
        return Int(numberValue)
    }

    public subscript(key: String) -> StructuredValue? {
        objectValue?[key]
    }

    public init(_ dictionary: [String: StructuredValue]) {
        self = .object(dictionary)
    }

    public init(_ array: [StructuredValue]) {
        self = .array(array)
    }

    public init(_ string: String) {
        self = .string(string)
    }

    public init(_ bool: Bool) {
        self = .bool(bool)
    }

    public init(_ number: Double) {
        self = .number(number)
    }

    public func jsonData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return try encoder.encode(self)
    }

    public func jsonString(prettyPrinted: Bool = false) -> String {
        guard let data = try? jsonData(prettyPrinted: prettyPrinted) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: jsonData())
    }

    public static func encode<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> StructuredValue {
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(StructuredValue.self, from: data)
    }
}
