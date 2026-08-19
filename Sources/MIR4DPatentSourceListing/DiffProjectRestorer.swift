import Foundation

struct DiffRestoreReport {
    var createdFiles: [String] = []
    var updatedFiles: [String] = []
    var skippedFiles: [String] = []
    var deletedFiles: [String] = []
    var warnings: [String] = []

    var summary: String {
        "Создано: \(createdFiles.count), обновлено: \(updatedFiles.count), пропущено: \(skippedFiles.count), удалено: \(deletedFiles.count)"
    }
}

enum DiffRestoreError: LocalizedError {
    case invalidDiff
    case unsafePath(String)
    var errorDescription: String? {
        switch self {
        case .invalidDiff: return "Файл diff не содержит распознаваемых изменений."
        case .unsafePath(let path): return "Небезопасный путь в diff: \(path)"
        }
    }
}

/// Restores a project from a standard unified/Git diff.
/// New files are reconstructed completely. Modified files are patched
/// against files already present in the selected destination directory.
final class DiffProjectRestorer {
    private struct PatchFile { let oldPath: String?; let newPath: String?; let hunks: [Hunk] }
    private struct Hunk { let oldStart: Int; let oldCount: Int; let newStart: Int; let newCount: Int; let lines: [String] }

    func restore(diffURL: URL, destination: URL) throws -> DiffRestoreReport {
        let data = try Data(contentsOf: diffURL)
        guard let text = String(data: data, encoding: .utf8) else { throw DiffRestoreError.invalidDiff }
        let patches = parse(text)
        guard !patches.isEmpty else { throw DiffRestoreError.invalidDiff }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var report = DiffRestoreReport()

        for patch in patches {
            if patch.newPath == nil {
                if let old = patch.oldPath {
                    let safe = try safeRelativePath(old)
                    let url = destination.appendingPathComponent(safe)
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                        report.deletedFiles.append(safe)
                    }
                }
                continue
            }

            let relative = try safeRelativePath(patch.newPath!)
            let target = destination.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

            let isNewFile = patch.oldPath == nil || patch.oldPath == "/dev/null"
            if isNewFile {
                let content = reconstructNewFile(patch)
                try Data(content.utf8).write(to: target, options: .atomic)
                report.createdFiles.append(relative)
            } else {
                guard FileManager.default.fileExists(atPath: target.path) else {
                    report.skippedFiles.append(relative)
                    report.warnings.append("Не найден исходный файл для применения изменений: \(relative)")
                    continue
                }
                let originalData = try Data(contentsOf: target)
                guard let original = String(data: originalData, encoding: .utf8) else {
                    report.skippedFiles.append(relative)
                    report.warnings.append("Не удалось прочитать UTF-8: \(relative)")
                    continue
                }
                let patched = try apply(patch.hunks, to: original)
                try Data(patched.utf8).write(to: target, options: .atomic)
                report.updatedFiles.append(relative)
            }
        }
        return report
    }

    private func parse(_ text: String) -> [PatchFile] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [PatchFile] = []
        var index = 0
        while index < lines.count {
            guard lines[index].hasPrefix("--- ") else { index += 1; continue }
            let old = path(fromHeader: lines[index].dropFirst(4)); index += 1
            guard index < lines.count, lines[index].hasPrefix("+++ ") else { continue }
            let new = path(fromHeader: lines[index].dropFirst(4)); index += 1
            var hunks: [Hunk] = []
            while index < lines.count && !lines[index].hasPrefix("--- ") {
                guard lines[index].hasPrefix("@@") else { index += 1; continue }
                guard let h = parseHunkHeader(lines[index]) else { index += 1; continue }
                index += 1
                var body: [String] = []
                while index < lines.count && !lines[index].hasPrefix("@@") && !lines[index].hasPrefix("--- ") {
                    if lines[index].hasPrefix("diff --git ") { break }
                    body.append(lines[index]); index += 1
                }
                hunks.append(Hunk(oldStart: h.0, oldCount: h.1, newStart: h.2, newCount: h.3, lines: body))
            }
            result.append(PatchFile(oldPath: old == "/dev/null" ? nil : old, newPath: new == "/dev/null" ? nil : new, hunks: hunks))
        }
        return result
    }

    private func path(fromHeader header: Substring) -> String {
        var value = String(header).split(separator: "\t", maxSplits: 1).first.map(String.init) ?? String(header)
        if value.hasPrefix("a/") || value.hasPrefix("b/") { value.removeFirst(2) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int)? {
        guard let range = line.range(of: "@@"), let end = line[range.upperBound...].range(of: "@@") else { return nil }
        let value = line[range.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: " "); guard parts.count >= 2 else { return nil }
        func parseRange(_ value: Substring) -> (Int, Int)? {
            let raw = value.dropFirst(); let p = raw.split(separator: ",", maxSplits: 1).map(String.init)
            return (Int(p[0]) ?? 0, p.count > 1 ? Int(p[1]) ?? 1 : 1)
        }
        let old = parseRange(parts[0]); let new = parseRange(parts[1])
        return (old.0, old.1, new.0, new.1)
    }

    private func reconstructNewFile(_ patch: PatchFile) -> String {
        var result = ""
        for hunk in patch.hunks {
            for line in hunk.lines where line.first == "+" { result += String(line.dropFirst()) + "\n" }
        }
        return result
    }

    private func apply(_ hunks: [Hunk], to original: String) throws -> String {
        var source = original.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if source.last == "" { source.removeLast() }
        var delta = 0
        for hunk in hunks {
            let expected = max(0, hunk.oldStart - 1 + delta)
            var cursor = expected; var replacement: [String] = []; var consumed = 0
            for line in hunk.lines {
                guard let marker = line.first else { continue }
                let value = String(line.dropFirst())
                switch marker {
                case " ":
                    guard cursor < source.count, source[cursor] == value else { throw DiffRestoreError.invalidDiff }
                    replacement.append(value); cursor += 1; consumed += 1
                case "-":
                    guard cursor < source.count, source[cursor] == value else { throw DiffRestoreError.invalidDiff }
                    cursor += 1; consumed += 1
                case "+": replacement.append(value)
                case "\\": break
                default: break
                }
            }
            source.replaceSubrange(expected..<cursor, with: replacement)
            delta += replacement.count - consumed
        }
        return source.joined(separator: "\n") + "\n"
    }

    private func safeRelativePath(_ raw: String) throws -> String {
        let path = raw.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, path != "/dev/null", !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw DiffRestoreError.unsafePath(raw) }
        return path
    }
}
