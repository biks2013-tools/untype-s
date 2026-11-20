import Foundation

/// A meeting transcript as the body of a note in Apple Notes (HTML): the
/// title as the first line, then every line of the transcript on a line of
/// its own.
public enum AppleNotesHTML {
    public static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    public static func body(title: String, transcript: String) -> String {
        var html = "<h1>\(escaped(title))</h1>"
        let lines = transcript
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n")
        for line in lines {
            // An empty line is kept as one.
            html += line.trimmingCharacters(in: .whitespaces).isEmpty ? "<div><br></div>" : "<div>\(escaped(line))</div>"
        }
        return html
    }
}
