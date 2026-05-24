import Foundation

enum Dotenv {
    static func parse(_ contents: String, path: String) throws -> [String: String] {
        var result: [String: String] = [:]

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard let equals = line.firstIndex(of: "="), equals != line.startIndex else {
                continue
            }

            let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                continue
            }

            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            } else if let commentRange = value.range(of: " #") {
                value = String(value[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }

            result[key] = value
        }

        return result
    }

    static func readIfExists(_ url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return try parse(contents, path: url.path)
        } catch let error as UntypeError {
            throw error
        } catch {
            throw UntypeError.invalidConfiguration(
                "Failed to read .env file at \(url.path): \(error.localizedDescription)"
            )
        }
    }
}
