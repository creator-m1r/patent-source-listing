import Foundation

struct CommentCleaningResult {
    let content: String
    let removedCommentCount: Int
    let removedLineCount: Int
}

/// Conservative lexer-style comment cleaner. It preserves ordinary, triple-quoted,
/// and backtick string literals so comment markers inside strings are not deleted.
struct CommentCleaner {
    func clean(_ source: String, language: String) -> CommentCleaningResult {
        let slashLine = ["Swift", "Objective-C", "Objective-C++", "C++", "C/C++ Header", "C", "C#", "Java", "Kotlin", "JavaScript", "JavaScript/JSX", "TypeScript", "TypeScript/TSX", "Go", "Rust", "PHP", "Dart", "Scala", "Shell"].contains(language)
        let slashBlock = slashLine && language != "Shell"
        let hashLine = ["Python", "Ruby", "Shell"].contains(language)
        let sqlLine = language == "SQL"
        let xmlBlock = ["HTML", "XML"].contains(language)
        let supportsTripleQuotes = ["Swift", "Python", "Ruby", "JavaScript", "JavaScript/JSX", "TypeScript", "TypeScript/TSX"].contains(language)

        let chars = Array(source)
        var output = String()
        output.reserveCapacity(source.count)
        var i = 0
        var state = State.normal
        var comments = 0
        var commentLines = 0
        var lineHadComment = false

        func char(_ offset: Int) -> Character? {
            let index = i + offset
            return index < chars.count ? chars[index] : nil
        }
        func has(_ a: Character, _ b: Character, _ c: Character? = nil) -> Bool {
            guard char(0) == a, char(1) == b else { return false }
            if let c { return char(2) == c }
            return true
        }

        while i < chars.count {
            let c = chars[i]
            let n = char(1)
            switch state {
            case .normal:
                if c == "\n" { output.append(c); i += 1; lineHadComment = false; continue }
                if supportsTripleQuotes && has("\"", "\"", "\"") { output.append("\"\"\""); state = .tripleDouble; i += 3; continue }
                if supportsTripleQuotes && has("'", "'", "'") { output.append("''' ".trimmingCharacters(in: .whitespaces)); state = .tripleSingle; i += 3; continue }
                if c == "\"" { output.append(c); state = .doubleQuote; i += 1; continue }
                if c == "'" { output.append(c); state = .singleQuote; i += 1; continue }
                if c == "`" && ["Swift", "JavaScript", "JavaScript/JSX", "TypeScript", "TypeScript/TSX", "Python", "Ruby"].contains(language) { output.append(c); state = .backtick; i += 1; continue }
                if slashBlock && c == "/" && n == "*" { state = .blockComment; comments += 1; lineHadComment = true; i += 2; continue }
                if slashLine && c == "/" && n == "/" { state = .lineComment; comments += 1; lineHadComment = true; i += 2; continue }
                if hashLine && c == "#" {
                    if i == 0 && n == "!" { output.append(c); i += 1; continue }
                    state = .lineComment; comments += 1; lineHadComment = true; i += 1; continue
                }
                if sqlLine && c == "-" && n == "-" { state = .lineComment; comments += 1; lineHadComment = true; i += 2; continue }
                if xmlBlock && c == "<" && n == "!" && char(2) == "-" && char(3) == "-" { state = .blockComment; comments += 1; lineHadComment = true; i += 4; continue }
                output.append(c); i += 1

            case .lineComment:
                if c == "\n" { output.append(c); if lineHadComment { commentLines += 1 }; lineHadComment = false; state = .normal }
                i += 1

            case .blockComment:
                if xmlBlock && c == "-" && n == "-" && char(2) == ">" { state = .normal; i += 3; continue }
                if !xmlBlock && c == "*" && n == "/" { state = .normal; i += 2; continue }
                if c == "\n" { output.append("\n"); commentLines += 1; lineHadComment = false }
                i += 1

            case .doubleQuote:
                output.append(c)
                if c == "\\", n != nil { output.append(n!); i += 2; continue }
                if c == "\"" { state = .normal }
                i += 1

            case .singleQuote:
                output.append(c)
                if c == "\\", n != nil { output.append(n!); i += 2; continue }
                if c == "'" { state = .normal }
                i += 1

            case .tripleDouble:
                if has("\"", "\"", "\"") { output.append("\"\"\""); state = .normal; i += 3; continue }
                output.append(c); i += 1

            case .tripleSingle:
                if has("'", "'", "'") { output.append("'''"); state = .normal; i += 3; continue }
                output.append(c); i += 1

            case .backtick:
                output.append(c)
                if c == "\\", n != nil { output.append(n!); i += 2; continue }
                if c == "`" { state = .normal }
                i += 1
            }
        }
        if lineHadComment { commentLines += 1 }
        return CommentCleaningResult(content: output, removedCommentCount: comments, removedLineCount: commentLines)
    }

    private enum State { case normal, lineComment, blockComment, doubleQuote, singleQuote, tripleDouble, tripleSingle, backtick }
}
