import Foundation

struct ReconstructionReport {
    var projectRoot: URL
    var directories: [String] = []
    var filesCreated: [String] = []
    var filesReconstructed: [String] = []
    var filesPatched: [String] = []
    var filesDeleted: [String] = []
    var warnings: [String] = []

    var summary: String {
        "Каталоги: \(directories.count), создано: \(filesCreated.count), восстановлено: \(filesReconstructed.count), изменено: \(filesPatched.count), удалено: \(filesDeleted.count)"
    }
}

enum ReconstructionError: LocalizedError {
    case invalidDiff
    case unsafePath(String)
    case patchMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidDiff: return "Не удалось распознать содержимое diff."
        case .unsafePath(let path): return "Небезопасный путь: \(path)"
        case .patchMismatch(let path): return "Изменения не удалось согласовать с содержимым: \(path)"
        }
    }
}

/// Анализирует unified/Git diff и восстанавливает проект в новой папке.
/// Новые файлы восстанавливаются непосредственно из diff; измененные файлы
/// патчатся, если базовый файл уже существует. Если diff содержит полный
/// новый текст измененного файла, возможна автономная реконструкция.
final class DiffProjectReconstructor {
    private struct FilePatch {
        let oldPath: String?
        let newPath: String?
        let hunks: [Hunk]
        let isBinary: Bool
    }

    private struct Hunk {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        let lines: [String]
    }

    func reconstruct(diffURL: URL, destination: URL) throws -> ReconstructionReport {
        let text = try String(contentsOf: diffURL, encoding: .utf8)
        let patches = parse(text)
        guard !patches.isEmpty else { throw ReconstructionError.invalidDiff }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var report = ReconstructionReport(projectRoot: destination)

        for patch in patches {
            if patch.isBinary {
                report.warnings.append("Бинарный файл пропущен: \(patch.newPath ?? patch.oldPath ?? "unknown")")
                continue
            }
            if let old = patch.oldPath, patch.newPath == nil {
                let path = try safePath(old)
                let url = destination.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    report.filesDeleted.append(path)
                } else {
                    report.warnings.append("Файл для удаления отсутствует: \(path)")
                }
                continue
            }
            guard let newPath = patch.newPath else { continue }
            let path = try safePath(newPath)
            let target = destination.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let isNew = patch.oldPath == nil || patch.oldPath == "/dev/null"
            if isNew {
                let content = newFileContent(patch)
                try Data(content.utf8).write(to: target, options: .atomic)
                if isCompleteNewFile(patch) { report.filesCreated.append(path) }
                else {
                    report.filesReconstructed.append(path)
                    report.warnings.append("Новый файл восстановлен по доступному содержимому diff: \(path)")
                }
                continue
            }
            if FileManager.default.fileExists(atPath: target.path) {
                let original = try String(contentsOf: target, encoding: .utf8)
                do {
                    let patched = try apply(patch.hunks, to: original)
                    try Data(patched.utf8).write(to: target, options: .atomic)
                    report.filesPatched.append(path)
                } catch {
                    report.warnings.append("Не удалось применить patch: \(path)")
                }
            } else if let reconstructed = reconstructModifiedFile(patch) {
                try Data(reconstructed.utf8).write(to: target, options: .atomic)
                report.filesReconstructed.append(path)
            } else {
                report.warnings.append("Для измененного файла отсутствует полный базовый текст: \(path)")
            }
        }
        return report
    }

    private func parse(_ text: String) -> [FilePatch] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [FilePatch] = []
        var i = 0
        while i < lines.count {
            guard lines[i].hasPrefix("--- ") else { i += 1; continue }
            let old = headerPath(lines[i].dropFirst(4)); i += 1
            guard i < lines.count, lines[i].hasPrefix("+++ ") else { continue }
            let new = headerPath(lines[i].dropFirst(4)); i += 1
            var hunks: [Hunk] = []
            var binary = false
            while i < lines.count && !lines[i].hasPrefix("--- ") {
                if lines[i].hasPrefix("Binary files ") { binary = true; i += 1; break }
                guard lines[i].hasPrefix("@@") else { i += 1; continue }
                guard let header = parseHunkHeader(lines[i]) else { i += 1; continue }
                i += 1
                var body: [String] = []
                while i < lines.count && !lines[i].hasPrefix("@@") && !lines[i].hasPrefix("--- ") {
                    if lines[i].hasPrefix("diff --git ") { break }
                    body.append(lines[i]); i += 1
                }
                hunks.append(Hunk(oldStart: header.0, oldCount: header.1, newStart: header.2, newCount: header.3, lines: body))
            }
            result.append(FilePatch(oldPath: old == "/dev/null" ? nil : old, newPath: new == "/dev/null" ? nil : new, hunks: hunks, isBinary: binary))
        }
        return result
    }

    private func headerPath(_ value: Substring) -> String {
        var p = String(value).split(separator: "\t", maxSplits: 1).first.map(String.init) ?? String(value)
        if p.hasPrefix("a/") || p.hasPrefix("b/") { p.removeFirst(2) }
        return p.trimmingCharacters(in: .whitespaces)
    }

    private func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int)? {
        guard let a = line.range(of: "@@"), let b = line[a.upperBound...].range(of: "@@") else { return nil }
        let body = line[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespaces)
        let p = body.split(separator: " ")
        guard p.count >= 2 else { return nil }
        func parse(_ s: Substring) -> (Int, Int)? {
            let raw = s.dropFirst(); let q = raw.split(separator: ",", maxSplits: 1)
            return (Int(q.first ?? "0") ?? 0, q.count > 1 ? Int(q[1]) ?? 1 : 1)
        }
        let old = parse(p[0]); let new = parse(p[1])
        return (old.0, old.1, new.0, new.1)
    }

    private func newFileContent(_ patch: FilePatch) -> String {
        var result = ""
        for h in patch.hunks {
            for line in h.lines where line.first == "+" { result += String(line.dropFirst()) + "\n" }
        }
        return result
    }

    private func isCompleteNewFile(_ patch: FilePatch) -> Bool {
        let additions = patch.hunks.reduce(0) { $0 + $1.lines.filter { $0.first == "+" }.count }
        let expected = patch.hunks.reduce(0) { $0 + $1.newCount }
        return additions == expected && expected > 0
    }

    private func reconstructModifiedFile(_ patch: FilePatch) -> String? {
        guard !patch.hunks.isEmpty else { return nil }
        guard patch.hunks.allSatisfy({ h in h.lines.filter { $0.first == " " || $0.first == "+" }.count == h.newCount }) else { return nil }
        return patch.hunks.flatMap { $0.lines.filter { $0.first == " " || $0.first == "+" }.map { String($0.dropFirst()) } }.joined(separator: "\n") + "\n"
    }

    private func apply(_ hunks: [Hunk], to original: String) throws -> String {
        var source = original.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if source.last == "" { source.removeLast() }
        var delta = 0
        for h in hunks {
            let start = max(0, h.oldStart - 1 + delta)
            var cursor = start; var replacement: [String] = []; var consumed = 0
            for line in h.lines {
                guard let marker = line.first else { continue }
                let value = String(line.dropFirst())
                switch marker {
                case " ": guard cursor < source.count, source[cursor] == value else { throw ReconstructionError.patchMismatch("context") }; replacement.append(value); cursor += 1; consumed += 1
                case "-": guard cursor < source.count, source[cursor] == value else { throw ReconstructionError.patchMismatch("removed line") }; cursor += 1; consumed += 1
                case "+": replacement.append(value)
                case "\\": break
                default: break
                }
            }
            source.replaceSubrange(start..<cursor, with: replacement)
            delta += replacement.count - consumed
        }
        return source.joined(separator: "\n") + "\n"
    }

    private func safePath(_ raw: String) throws -> String {
        let path = raw.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw ReconstructionError.unsafePath(raw) }
        return path
    }
}
