import Foundation

struct DiffRestoreReport {
    var createdFiles: [String] = []
    var updatedFiles: [String] = []
    var skippedFiles: [String] = []
    var deletedFiles: [String] = []
    var warnings: [String] = []
    var summary: String { "Создано: \(createdFiles.count), обновлено: \(updatedFiles.count), пропущено: \(skippedFiles.count), удалено: \(deletedFiles.count)" }
}

enum DiffRestoreError: LocalizedError {
    case invalidDiff
    case unsafePath(String)
    case patchMismatch(String)
    var errorDescription: String? {
        switch self {
        case .invalidDiff: return "Файл diff не содержит распознаваемых изменений."
        case .unsafePath(let path): return "Небезопасный путь в diff: \(path)"
        case .patchMismatch(let path): return "Контекст diff не совпадает с исходным файлом: \(path)"
        }
    }
}

final class DiffProjectRestorer {
    private struct PatchFile { let oldPath: String?; let newPath: String?; let hunks: [Hunk]; let binary: Bool }
    private struct Hunk { let oldStart: Int; let oldCount: Int; let newStart: Int; let newCount: Int; let lines: [String] }

    func restore(diffURL: URL, destination: URL) throws -> DiffRestoreReport {
        let data = try Data(contentsOf: diffURL)
        guard let text = String(data: data, encoding: .utf8) else { throw DiffRestoreError.invalidDiff }
        let patches = parse(text)
        guard !patches.isEmpty else { throw DiffRestoreError.invalidDiff }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var report = DiffRestoreReport()

        for patch in patches {
            if patch.binary {
                report.skippedFiles.append(patch.newPath ?? patch.oldPath ?? "unknown")
                report.warnings.append("Бинарный файл не может быть восстановлен из текстового diff: \(patch.newPath ?? patch.oldPath ?? "unknown")")
                continue
            }

            if patch.newPath == nil {
                if let old = patch.oldPath {
                    let safe = try safeRelativePath(old)
                    let url = destination.appendingPathComponent(safe)
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                        report.deletedFiles.append(safe)
                    } else { report.warnings.append("Файл для удаления отсутствует: \(safe)") }
                }
                continue
            }

            let newRelative = try safeRelativePath(patch.newPath!)
            let target = destination.appendingPathComponent(newRelative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let isNewFile = patch.oldPath == nil

            if isNewFile {
                let content = reconstructNewFile(patch)
                guard !patch.hunks.isEmpty else {
                    report.skippedFiles.append(newRelative)
                    report.warnings.append("Новый файл не содержит текстовых hunks: \(newRelative)")
                    continue
                }
                try Data(content.utf8).write(to: target, options: .atomic)
                report.createdFiles.append(newRelative)
                continue
            }

            let oldRelative = try safeRelativePath(patch.oldPath!)
            let oldURL = destination.appendingPathComponent(oldRelative)
            if oldRelative != newRelative && FileManager.default.fileExists(atPath: oldURL.path) && !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: oldURL, to: target)
            }

            guard FileManager.default.fileExists(atPath: target.path) else {
                if let reconstructed = reconstructFromFullContext(patch) {
                    try Data(reconstructed.utf8).write(to: target, options: .atomic)
                    report.createdFiles.append(newRelative)
                } else {
                    report.skippedFiles.append(newRelative)
                    report.warnings.append("Не найден исходный файл для применения изменений: \(newRelative)")
                }
                continue
            }

            let originalData = try Data(contentsOf: target)
            guard let original = String(data: originalData, encoding: .utf8) else {
                report.skippedFiles.append(newRelative)
                report.warnings.append("Не удалось прочитать UTF-8: \(newRelative)")
                continue
            }
            do {
                let patched = try apply(patch.hunks, to: original)
                try Data(patched.utf8).write(to: target, options: .atomic)
                report.updatedFiles.append(newRelative)
            } catch { report.skippedFiles.append(newRelative); report.warnings.append("\(error.localizedDescription): \(newRelative)") }
        }
        return report
    }

    private func parse(_ text: String) -> [PatchFile] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [PatchFile] = []
        var index = 0
        while index < lines.count {
            guard lines[index].hasPrefix("diff --git ") else { index += 1; continue }
            index += 1
            var oldPath: String?
            var newPath: String?
            var binary = false
            var hunks: [Hunk] = []
            while index < lines.count && !lines[index].hasPrefix("diff --git ") {
                let line = lines[index]
                if line.hasPrefix("--- ") { oldPath = path(fromHeader: String(line.dropFirst(4))); index += 1; continue }
                if line.hasPrefix("+++ ") { newPath = path(fromHeader: String(line.dropFirst(4))); index += 1; continue }
                if line.hasPrefix("Binary files ") { binary = true; index += 1; continue }
                if line.hasPrefix("@@") {
                    guard let h = parseHunkHeader(line) else { index += 1; continue }
                    index += 1
                    var body: [String] = []
                    while index < lines.count && !lines[index].hasPrefix("@@") && !lines[index].hasPrefix("diff --git ") {
                        body.append(lines[index]); index += 1
                    }
                    hunks.append(Hunk(oldStart: h.0, oldCount: h.1, newStart: h.2, newCount: h.3, lines: body))
                    continue
                }
                index += 1
            }
            result.append(PatchFile(oldPath: oldPath == "/dev/null" ? nil : oldPath, newPath: newPath == "/dev/null" ? nil : newPath, hunks: hunks, binary: binary))
        }
        return result
    }

    private func path(fromHeader header: String) -> String {
        var value = header.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? header
        if value.hasPrefix("a/") || value.hasPrefix("b/") { value.removeFirst(2) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int)? {
        guard let range = line.range(of: "@@"), let end = line[range.upperBound...].range(of: "@@") else { return nil }
        let value = line[range.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: " "); guard parts.count >= 2 else { return nil }
        func parseRange(_ value: Substring) -> (Int, Int) {
            let raw = value.dropFirst(); let p = raw.split(separator: ",", maxSplits: 1)
            return (Int(p[0]) ?? 0, p.count > 1 ? Int(p[1]) ?? 1 : 1)
        }
        let old = parseRange(parts[0]); let new = parseRange(parts[1])
        return (old.0, old.1, new.0, new.1)
    }

    private func reconstructNewFile(_ patch: PatchFile) -> String {
        patch.hunks.flatMap { $0.lines.filter { $0.first == "+" }.map { String($0.dropFirst()) } }.joined(separator: "\n") + "\n"
    }

    private func reconstructFromFullContext(_ patch: PatchFile) -> String? {
        guard !patch.hunks.isEmpty else { return nil }
        guard patch.hunks.allSatisfy({ h in h.lines.filter { $0.first == " " || $0.first == "+" }.count == h.newCount }) else { return nil }
        return patch.hunks.flatMap { $0.lines.filter { $0.first == " " || $0.first == "+" }.map { String($0.dropFirst()) } }.joined(separator: "\n") + "\n"
    }

    private func apply(_ hunks: [Hunk], to original: String) throws -> String {
        var source = original.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let hadTrailingNewline = source.last == ""
        if hadTrailingNewline { source.removeLast() }
        var delta = 0
        for hunk in hunks {
            let start = max(0, hunk.oldStart - 1 + delta)
            guard start <= source.count else { throw DiffRestoreError.patchMismatch("line \(hunk.oldStart)") }
            var cursor = start
            var replacement: [String] = []
            var consumed = 0
            for line in hunk.lines {
                guard let marker = line.first else { continue }
                let value = String(line.dropFirst())
                switch marker {
                case " ":
                    guard cursor < source.count, source[cursor] == value else { throw DiffRestoreError.patchMismatch("context") }
                    replacement.append(value); cursor += 1; consumed += 1
                case "-":
                    guard cursor < source.count, source[cursor] == value else { throw DiffRestoreError.patchMismatch("removed line") }
                    cursor += 1; consumed += 1
                case "+": replacement.append(value)
                case "\\": break
                default: break
                }
            }
            guard cursor >= start, consumed == hunk.oldCount || (hunk.oldCount == 0 && consumed == 0) else { throw DiffRestoreError.patchMismatch("hunk line count") }
            source.replaceSubrange(start..<cursor, with: replacement)
            delta += replacement.count - consumed
        }
        return source.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
    }

    private func safeRelativePath(_ raw: String) throws -> String {
        let path = raw.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, path != "/dev/null", !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw DiffRestoreError.unsafePath(raw) }
        return path
    }
}
