import Foundation

public enum MarkerKind: String, Sendable, Equatable {
    case stateCommand = "state_command"
    case sectionEnd = "section_end"
    case sectionCancel = "section_cancel"
    case literalNext = "literal_next"
}

public struct MarkerDefinition: Sendable, Equatable {
    public let kind: MarkerKind
    public let phrases: [String]

    public init(kind: MarkerKind, phrases: [String]) {
        self.kind = kind
        self.phrases = phrases
    }
}

public struct MarkerMatch: Sendable, Equatable {
    public let kind: MarkerKind
    public let phrase: String
    public let start: String.Index
    public let end: String.Index
}

public struct ConsumedCommandArguments: Sendable, Equatable {
    public let operatorName: String?
    public let value: String?
    public let end: String.Index
}

private struct NormalizedText {
    let normalized: String
    let map: [String.Index]
}

public func normalizeOrdinaryMarker(_ text: String) -> String {
    var output = ""
    var lastWasSpace = true

    for scalar in normalizedScalars(text) {
        if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.letters.contains(scalar) {
            output.unicodeScalars.append(scalar)
            lastWasSpace = false
        } else if !lastWasSpace {
            output.append(" ")
            lastWasSpace = true
        }
    }

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

public func findFirstMarker(
    in text: String,
    definitions: [MarkerDefinition],
    startAt: String.Index? = nil
) -> MarkerMatch? {
    let start = startAt ?? text.startIndex
    var best: MarkerMatch?

    for definition in definitions {
        for phrase in definition.phrases {
            let match: MarkerMatch?
            if phrase.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
                match = findSlashPhrase(in: text, phrase: phrase, kind: definition.kind, startAt: start)
            } else {
                match = findOrdinaryPhrase(in: text, phrase: phrase, kind: definition.kind, startAt: start)
            }
            guard let match else {
                continue
            }
            if best == nil ||
                match.start < best!.start ||
                (match.start == best!.start && match.end > best!.end) {
                best = match
            }
        }
    }

    return best
}

public func stripMarkersForDisplay(_ text: String, definitions: [MarkerDefinition]) -> String {
    var output = text
    var searchStart = output.startIndex

    while searchStart < output.endIndex {
        guard let match = findFirstMarker(in: output, definitions: definitions, startAt: searchStart) else {
            break
        }
        let commandEnd = match.kind == .stateCommand
            ? consumeCommandArgs(in: output, start: match.end).end
            : match.end
        output.replaceSubrange(match.start..<commandEnd, with: " ")
        searchStart = match.start
    }

    return normalizePayloadWhitespace(output)
}

public func normalizePayloadWhitespace(_ text: String) -> String {
    text
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

public func consumeCommandArgs(in text: String, start: String.Index) -> ConsumedCommandArguments {
    var index = skipWhitespace(in: text, from: start)
    let operatorStart = index
    while index < text.endIndex, !isCommandDelimiter(text[index]) {
        index = text.index(after: index)
    }

    let operatorName = operatorStart == index ? nil : String(text[operatorStart..<index])
    let afterOperatorWhitespace = skipWhitespace(in: text, from: index)
    var end = index
    var value: String?

    if afterOperatorWhitespace > index {
        var valueEnd = afterOperatorWhitespace
        while valueEnd < text.endIndex, !isCommandDelimiter(text[valueEnd]) {
            valueEnd = text.index(after: valueEnd)
        }
        let candidate = String(text[afterOperatorWhitespace..<valueEnd]).lowercased()
        if candidate == "on" || candidate == "off" {
            value = candidate
            end = valueEnd
        }
    }

    return ConsumedCommandArguments(operatorName: operatorName, value: value, end: end)
}

func markerDefinitions(for markers: MarkerConfig) -> [MarkerDefinition] {
    [
        MarkerDefinition(kind: .stateCommand, phrases: [markers.commandPhrase]),
        MarkerDefinition(
            kind: .sectionEnd,
            phrases: uniqueTrimmed([markers.sectionEndPhrase] + markers.sectionEndAliases)
        ),
        MarkerDefinition(kind: .sectionCancel, phrases: [markers.sectionCancelPhrase]),
        MarkerDefinition(kind: .literalNext, phrases: [markers.literalNextPhrase])
    ]
}

private func findSlashPhrase(
    in text: String,
    phrase: String,
    kind: MarkerKind,
    startAt: String.Index
) -> MarkerMatch? {
    let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else {
        return nil
    }
    var range = startAt..<text.endIndex

    while let found = text.range(of: needle, options: [.caseInsensitive], range: range, locale: nil) {
        let before = found.lowerBound == text.startIndex
            ? nil
            : text[text.index(before: found.lowerBound)]
        let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
        if !isLetterOrNumber(before) && !isLetterOrNumber(after) {
            return MarkerMatch(kind: kind, phrase: phrase, start: found.lowerBound, end: found.upperBound)
        }
        range = text.index(after: found.lowerBound)..<text.endIndex
    }

    return nil
}

private func findOrdinaryPhrase(
    in text: String,
    phrase: String,
    kind: MarkerKind,
    startAt: String.Index
) -> MarkerMatch? {
    let phraseNorm = normalizeOrdinaryMarker(phrase)
    guard !phraseNorm.isEmpty else {
        return nil
    }
    let normalized = normalizeWithMap(text)
    var searchIndex = normalizedIndex(forOriginalIndex: startAt, in: normalized)

    while searchIndex <= normalized.normalized.endIndex {
        guard let found = normalized.normalized.range(of: phraseNorm, range: searchIndex..<normalized.normalized.endIndex) else {
            return nil
        }
        let before = found.lowerBound == normalized.normalized.startIndex
            ? " "
            : normalized.normalized[normalized.normalized.index(before: found.lowerBound)]
        let after = found.upperBound == normalized.normalized.endIndex ? " " : normalized.normalized[found.upperBound]
        if before == " ", after == " " {
            let lowerOffset = normalized.normalized.distance(from: normalized.normalized.startIndex, to: found.lowerBound)
            let upperOffset = normalized.normalized.distance(from: normalized.normalized.startIndex, to: found.upperBound)
            if lowerOffset < normalized.map.count, upperOffset > 0, upperOffset - 1 < normalized.map.count {
                let firstOriginal = normalized.map[lowerOffset]
                let lastOriginal = normalized.map[upperOffset - 1]
                return MarkerMatch(
                    kind: kind,
                    phrase: phrase,
                    start: firstOriginal,
                    end: text.index(after: lastOriginal)
                )
            }
        }
        searchIndex = normalized.normalized.index(after: found.lowerBound)
    }

    return nil
}

private func normalizeWithMap(_ text: String) -> NormalizedText {
    var normalized = ""
    var map: [String.Index] = []
    var lastWasSpace = true
    var index = text.startIndex

    while index < text.endIndex {
        let character = text[index]
        let folded = String(character)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "el_GR"))
            .replacingOccurrences(of: "ς", with: "σ")

        if folded.unicodeScalars.count == 1,
           let scalar = folded.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) || CharacterSet.letters.contains(scalar) {
            normalized.unicodeScalars.append(scalar)
            map.append(index)
            lastWasSpace = false
        } else if !lastWasSpace {
            normalized.append(" ")
            map.append(index)
            lastWasSpace = true
        }
        index = text.index(after: index)
    }

    while normalized.last == " " {
        normalized.removeLast()
        map.removeLast()
    }

    return NormalizedText(normalized: normalized, map: map)
}

private func normalizedIndex(forOriginalIndex original: String.Index, in normalized: NormalizedText) -> String.Index {
    guard let offset = normalized.map.firstIndex(where: { $0 >= original }) else {
        return normalized.normalized.endIndex
    }
    return normalized.normalized.index(normalized.normalized.startIndex, offsetBy: offset)
}

private func normalizedScalars(_ text: String) -> [UnicodeScalar] {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "el_GR"))
        .replacingOccurrences(of: "ς", with: "σ")
        .unicodeScalars
        .map { $0 }
}

private func skipWhitespace(in text: String, from start: String.Index) -> String.Index {
    var index = start
    while index < text.endIndex, text[index].isWhitespace {
        index = text.index(after: index)
    }
    return index
}

private func isCommandDelimiter(_ character: Character) -> Bool {
    character.isWhitespace || [".", ",", ";", ":", "!", "?"].contains(character)
}

private func isLetterOrNumber(_ character: Character?) -> Bool {
    guard let character else {
        return false
    }
    return String(character).unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || CharacterSet.letters.contains($0)
    }
}

private func uniqueTrimmed(_ values: [String]) -> [String] {
    var output: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !output.contains(trimmed) {
            output.append(trimmed)
        }
    }
    return output
}
