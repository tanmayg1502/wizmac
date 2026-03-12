import Foundation

public enum AppIdentityNormalizer {
    private static let invisibleAndDirectionalScalars = CharacterSet(charactersIn: [
        "\u{200B}",
        "\u{200C}",
        "\u{200D}",
        "\u{200E}",
        "\u{200F}",
        "\u{202A}",
        "\u{202B}",
        "\u{202C}",
        "\u{202D}",
        "\u{202E}",
        "\u{2066}",
        "\u{2067}",
        "\u{2068}",
        "\u{2069}",
        "\u{FEFF}",
    ].joined())

    public static func normalize(_ value: String?) -> String {
        guard let value else { return "" }

        let filteredScalars = value.unicodeScalars.filter { scalar in
            CharacterSet.controlCharacters.contains(scalar) == false
                && invisibleAndDirectionalScalars.contains(scalar) == false
        }

        let filtered = String(String.UnicodeScalarView(filteredScalars))
        let folded = filtered.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )

        return folded
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }
}

public enum TrustedAutomationPolicy {
    public static let defaultAllowedActions: [ActionName] = [
        .uiAct,
        .uiCopy,
        .uiDrag,
        .uiExecute,
        .textInsert,
        .textAttach,
        .textSendKeys,
        .textDetach,
        .windowFocus,
        .scrollStep,
    ]

    public static let trustedBatchAllowedActions: Set<ActionName> = [
        .uiSearch,
        .uiCapture,
        .uiPrefetch,
        .uiHints,
        .uiAct,
        .uiCopy,
        .uiDrag,
        .textInsert,
        .textAttach,
        .textSendKeys,
        .textDetach,
        .windowFocus,
        .scrollStep,
    ]
}
