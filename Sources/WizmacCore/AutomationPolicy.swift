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
        .uiOpen,
        .uiSelect,
        .uiToggle,
        .uiFocus,
        .uiSubmit,
        .uiChooseFile,
        .uiDrag,
        .inputKeyCombo,
        .inputKeySequence,
        .uiGesture,
        .uiExecute,
        .menuSelect,
        .textInsert,
        .textRead,
        .textAttach,
        .textSendKeys,
        .textDetach,
        .windowFocus,
        .windowAssert,
        .scrollStep,
        .scrollTo,
        .scrollUntil,
        .scrollIntoView,
    ]

    public static let trustedBatchAllowedActions: Set<ActionName> = [
        .uiSearch,
        .uiRead,
        .uiWait,
        .uiUntil,
        .uiAssert,
        .uiDiff,
        .uiWatch,
        .uiCapture,
        .uiPrefetch,
        .uiHints,
        .uiAct,
        .uiCopy,
        .uiOpen,
        .uiSelect,
        .uiToggle,
        .uiFocus,
        .uiSubmit,
        .uiChooseFile,
        .uiDrag,
        .inputKeyCombo,
        .inputKeySequence,
        .uiGesture,
        .menuSelect,
        .textInsert,
        .textRead,
        .textAttach,
        .textSendKeys,
        .textDetach,
        .windowFocus,
        .windowAssert,
        .scrollStep,
        .scrollTo,
        .scrollUntil,
        .scrollIntoView,
    ]
}
