import Foundation

struct DiffFileEntry: Identifiable, Hashable {
    enum Operation: String { case added = "Добавлен", modified = "Изменен", deleted = "Удален", binary = "Бинарный" }
    let id = UUID()
    let path: String
    let oldPath: String?
    let operation: Operation
    let additions: Int
    let deletions: Int
    let newLineCount: Int
}

struct DiffProjectPlan {
    let files: [DiffFileEntry]
    let directories: [String]
    let sourceURL: URL
    var summary: String { "Файлов: \(files.count), каталогов: \(directories.count), +\(files.reduce(0) { $0 + $1.additions }), -\(files.reduce(0) { $0 + $1.deletions })" }
}

enum DiffAnalysisError: LocalizedError {
    case invalidEncoding
    case invalidPath(String)
    case emptyDiff
    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "Diff не является UTF-8 текстом."
        case .invalidPath(let path): return "Недопустимый путь в diff: \(path)"
        case .emptyDiff: return "В diff не найдено файловых изменений."
        }
    }
}

final class DiffProjectAnalyzer {
    func analyze(url: URL) throws -> DiffProjectPlan {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw DiffAnalysisError.invalidEncoding }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var entries: [DiffFileEntry] = []
        var directories = Set<String>()
        var i = 0
        while i < lines.count {
            guard lines[i].hasPrefix("diff --git ") else { i += 1; continue }
            i += 1
            var oldPath: String?
            var newPath: String?
            var binary = false
            var additions = 0
            var deletions = 0
            var newLineCount = 0
            while i < lines.count && !lines[i].hasPrefix("diff --git ") {
                let line = lines[i]
                if line.hasPrefix("--- ") { oldPath = normalizeHeaderPath(String(line.dropFirst(4))) }
                else if line.hasPrefix("+++ ") { newPath = normalizeHeaderPath(String(line.dropFirst(4))) }
                else if line.hasPrefix("Binary files ") { binary = true }
                else if line.hasPrefix("@@") {
                    if let counts = parseHunkHeader(line) { newLineCount += counts.newCount }
                    i += 1
                    while i < lines.count && !lines[i].hasPrefix("@@") && !lines[i].hasPrefix("diff --git ") {
                        let body = lines[i]
                        // Inside a hunk the first character is authoritative; a source line may itself begin with +++ or ---.
                        if body.first == "+" { additions += 1 }
                        if body.first == "-" { deletions += 1 }
                        i += 1
                    }
                    continue
                }
                i += 1
            }
            let old = oldPath == "/dev/null" ? nil : oldPath
            let new = newPath == "/dev/null" ? nil : newPath
            guard let path = new ?? old else { continue }
            try validate(path)
            if let old { try validate(old) }
            addDirectories(for: path, into: &directories)
            if let old { addDirectories(for: old, into: &directories) }
            let operation: DiffFileEntry.Operation = binary ? .binary : (old == nil ? .added : (new == nil ? .deleted : .modified))
            entries.append(DiffFileEntry(path: path, oldPath: old, operation: operation, additions: additions, deletions: deletions, newLineCount: newLineCount))
        }
        guard !entries.isEmpty else { throw DiffAnalysisError.emptyDiff }
        return DiffProjectPlan(files: entries, directories: directories.sorted(), sourceURL: url)
    }

    private func normalizeHeaderPath(_ raw: String) -> String {
        var value = raw.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? raw
        if value.hasPrefix("a/") || value.hasPrefix("b/") { value.removeFirst(2) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private func validate(_ path: String) throws {
        let p = path.replacingOccurrences(of: "\\", with: "/")
        guard !p.isEmpty, !p.hasPrefix("/"), !p.split(separator: "/").contains("..") else { throw DiffAnalysisError.invalidPath(path) }
    }

    private func addDirectories(for path: String, into set: inout Set<String>) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return }
        for index in 1..<parts.count { set.insert(parts[0..<index].joined(separator: "/")) }
    }

    private func parseHunkHeader(_ line: String) -> (newStart: Int, newCount: Int)? {
        guard let first = line.range(of: "@@"), let second = line[first.upperBound...].range(of: "@@") else { return nil }
        let body = line[first.upperBound..<second.lowerBound].trimmingCharacters(in: .whitespaces)
        let parts = body.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let raw = parts[1].dropFirst()
        let values = raw.split(separator: ",", maxSplits: 1)
        return (Int(values[0]) ?? 0, values.count > 1 ? Int(values[1]) ?? 1 : 1)
    }
}
