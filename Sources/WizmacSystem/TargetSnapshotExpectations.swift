import Foundation
import WizmacCore

public enum StringMatchMode: Sendable {
    case equals
    case contains

    func matches(_ text: String, query: String, caseInsensitive: Bool) -> Bool {
        guard !query.isEmpty else { return false }
        let normalizedQuery = caseInsensitive ? query.lowercased() : query
        let normalizedText = caseInsensitive ? text.lowercased() : text

        switch self {
        case .equals:
            return normalizedText == normalizedQuery
        case .contains:
            return normalizedText.contains(normalizedQuery)
        }
    }

    var description: String {
        switch self {
        case .equals: return "equals"
        case .contains: return "contains"
        }
    }
}

public enum TargetDescriptorField: Sendable {
    case title
    case subtitle
    case value
    case hint
    case role
    case identifier
    case path

    public static var textSearchFields: [TargetDescriptorField] {
        [.title, .subtitle, .value, .hint]
    }

    fileprivate var name: String {
        switch self {
        case .title: return "title"
        case .subtitle: return "subtitle"
        case .value: return "value"
        case .hint: return "hint"
        case .role: return "role"
        case .identifier: return "identifier"
        case .path: return "path"
        }
    }
}

public struct TargetSnapshotTextMatcher: Sendable {
    public let query: String
    public let fields: [TargetDescriptorField]
    public let mode: StringMatchMode
    public let caseInsensitive: Bool

    public init(
        query: String,
        fields: [TargetDescriptorField] = TargetDescriptorField.textSearchFields,
        mode: StringMatchMode = .contains,
        caseInsensitive: Bool = true
    ) {
        self.query = query
        self.fields = fields
        self.mode = mode
        self.caseInsensitive = caseInsensitive
    }

    func matches(_ descriptor: TargetDescriptor) -> Bool {
        for field in fields {
            guard let text = descriptor.text(for: field) else { continue }
            if mode.matches(text, query: query, caseInsensitive: caseInsensitive) {
                return true
            }
        }
        return false
    }

    var description: String {
        let fieldNames = fields.map { field in field.name }.joined(separator: ", ")
        return "text \(mode.description) \"\(query)\" (fields: \(fieldNames))"
    }
}

public struct TargetDescriptorMatcher: Sendable {
    public let textMatcher: TargetSnapshotTextMatcher?
    public let role: String?
    public let identifier: String?

    public init(
        textMatcher: TargetSnapshotTextMatcher? = nil,
        role: String? = nil,
        identifier: String? = nil
    ) {
        self.textMatcher = textMatcher
        self.role = role
        self.identifier = identifier
    }

    public static func identifier(_ id: String) -> TargetDescriptorMatcher {
        TargetDescriptorMatcher(identifier: id)
    }

    public static func role(_ role: String) -> TargetDescriptorMatcher {
        TargetDescriptorMatcher(role: role)
    }

    public static func textContains(
        _ query: String,
        fields: [TargetDescriptorField] = TargetDescriptorField.textSearchFields,
        mode: StringMatchMode = .contains,
        caseInsensitive: Bool = true
    ) -> TargetDescriptorMatcher {
        TargetDescriptorMatcher(
            textMatcher: TargetSnapshotTextMatcher(
                query: query,
                fields: fields,
                mode: mode,
                caseInsensitive: caseInsensitive
            )
        )
    }

    func matches(_ descriptor: TargetDescriptor) -> Bool {
        if let identifier, identifier != descriptor.id { return false }
        if let role, role != descriptor.role { return false }
        if let textMatcher, !textMatcher.matches(descriptor) { return false }
        return true
    }

    var description: String {
        var components: [String] = []
        if let identifier { components.append("id == \(identifier)") }
        if let role { components.append("role == \(role)") }
        if let textMatcher { components.append(textMatcher.description) }
        return components.isEmpty ? "(any target)" : components.joined(separator: ", ")
    }
}

public enum TargetCountComparison: Sendable {
    case exactly(Int)
    case atLeast(Int)
    case atMost(Int)

    func isSatisfied(by count: Int) -> Bool {
        switch self {
        case .exactly(let value):
            return count == value
        case .atLeast(let value):
            return count >= value
        case .atMost(let value):
            return count <= value
        }
    }

    var description: String {
        switch self {
        case .exactly(let value): return "count == \(value)"
        case .atLeast(let value): return "count >= \(value)"
        case .atMost(let value): return "count <= \(value)"
        }
    }
}

public enum TargetSnapshotCondition: Sendable {
    case targetExists(TargetDescriptorMatcher)
    case targetGone(TargetDescriptorMatcher)
    case targetCount(TargetDescriptorMatcher, TargetCountComparison)
    case windowTitle(query: String, mode: StringMatchMode, caseInsensitive: Bool)
    case textContains(TargetSnapshotTextMatcher)
    case targetSelected(TargetDescriptorMatcher)

    public func evaluate(on snapshot: TargetSnapshot) -> TargetSnapshotConditionResult {
        switch self {
        case .targetExists(let matcher):
            let matches = snapshot.targets.filter(matcher.matches)
            return TargetSnapshotConditionResult(condition: self, passed: !matches.isEmpty, matchedTargets: matches)
        case .targetGone(let matcher):
            let matches = snapshot.targets.filter(matcher.matches)
            return TargetSnapshotConditionResult(condition: self, passed: matches.isEmpty, matchedTargets: matches)
        case .targetCount(let matcher, let comparison):
            let matches = snapshot.targets.filter(matcher.matches)
            let passed = comparison.isSatisfied(by: matches.count)
            return TargetSnapshotConditionResult(condition: self, passed: passed, matchedTargets: matches)
        case .windowTitle(let query, let mode, let caseInsensitive):
            let windowTitle = snapshot.windowTitle ?? ""
            let passed = mode.matches(windowTitle, query: query, caseInsensitive: caseInsensitive)
            return TargetSnapshotConditionResult(condition: self, passed: passed, matchedTargets: [])
        case .textContains(let matcher):
            let matches = snapshot.targets.filter(matcher.matches)
            return TargetSnapshotConditionResult(condition: self, passed: !matches.isEmpty, matchedTargets: matches)
        case .targetSelected(let matcher):
            let matches = snapshot.targets.filter { matcher.matches($0) && $0.isSelectedLike }
            return TargetSnapshotConditionResult(condition: self, passed: !matches.isEmpty, matchedTargets: matches)
        }
    }

    var description: String {
        switch self {
        case .targetExists(let matcher):
            return "target exists (\(matcher.description))"
        case .targetGone(let matcher):
            return "target gone (\(matcher.description))"
        case .targetCount(_, let comparison):
            return "target count (\(comparison.description))"
        case .windowTitle(let query, let mode, _):
            return "window title \(mode.description) \"\(query)\""
        case .textContains(let matcher):
            return "text contains (\(matcher.description))"
        case .targetSelected(let matcher):
            return "target selected (\(matcher.description))"
        }
    }
}

public struct TargetSnapshotConditionResult: Sendable {
    public let condition: TargetSnapshotCondition
    public let passed: Bool
    public let matchedTargets: [TargetDescriptor]

    public var detail: String {
        let status = passed ? "passed" : "failed"
        return "\(condition.description) \(status) with \(matchedTargets.count) match(es)"
    }
}

extension TargetDescriptor {
    fileprivate func text(for field: TargetDescriptorField) -> String? {
        switch field {
        case .title: return title
        case .subtitle: return subtitle
        case .value: return value
        case .hint: return hint
        case .role: return role
        case .identifier: return id
        case .path: return path.joined(separator: " ")
        }
    }

    fileprivate var normalizedValue: String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate var numericValue: Double? {
        guard let normalized = normalizedValue else { return nil }
        return Double(normalized)
    }

    var isSelectedLike: Bool {
        guard let rawValue = normalizedValue, !rawValue.isEmpty else { return false }
        let lowercased = rawValue.lowercased()
        let positiveOptions: Set<String> = [
            "1",
            "true",
            "yes",
            "on",
            "selected",
            "checked",
            "pressed",
            "active",
            "axselected",
            "axchecked",
            "axpressed"
        ]

        if positiveOptions.contains(lowercased) {
            return true
        }

        if let bool = Bool(lowercased) {
            return bool
        }

        if let number = numericValue {
            return number > 0.5
        }

        return false
    }
}
