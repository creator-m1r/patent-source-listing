import Foundation
import CryptoKit

final class ProjectScanner {
    private let languages: [String: String] = [
        "swift":"Swift", "m":"Objective-C", "mm":"Objective-C++", "cpp":"C++", "cc":"C++", "cxx":"C++", "hpp":"C++", "h":"C/C++ Header", "c":"C", "cs":"C#", "java":"Java", "kt":"Kotlin", "py":"Python", "js":"JavaScript", "jsx":"JavaScript/JSX", "ts":"TypeScript", "tsx":"TypeScript/TSX", "go":"Go", "rs":"Rust", "php":"PHP", "rb":"Ruby", "dart":"Dart", "scala":"Scala", "sql":"SQL", "sh":"Shell", "bash":"Shell", "zsh":"Shell", "fish":"Shell", "html":"HTML", "htm":"HTML", "css":"CSS", "scss":"SCSS", "xml":"XML", "json":"JSON", "yaml":"YAML", "yml":"YAML", "toml":"TOML", "ini":"INI", "conf":"Configuration", "cmake":"CMake", "md":"Markdown", "txt":"Text"
    ]
    private let excluded: Set<String> = [".git", ".github", ".build", "build", "Build", "DerivedData", "Pods", "node_modules", ".swiftpm", "xcuserdata", "dist", "Debug", "Release", "__pycache__", ".idea", ".vscode"]

    func scan(root: URL) throws -> ScanReport {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { throw ScannerError.noFolder }
        var files: [SourceFile] = []
        var ignored = 0
        for case let url as URL in e {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if relative.split(separator: "/").dropLast().contains(where: { excluded.contains(String($0)) }) { if url.hasDirectoryPath { e.skipDescendants() }; ignored += 1; continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { if excluded.contains(url.lastPathComponent) { e.skipDescendants() }; continue }
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard let language = languages[ext] else { ignored += 1; continue }
            guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { ignored += 1; continue }
            files.append(SourceFile(relativePath: relative, absoluteURL: url, language: language, extensionName: ext, size: Int64(values?.fileSize ?? data.count), lineCount: content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count, content: content))
        }
        files.sort { priority($0.relativePath) == priority($1.relativePath) ? $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending : priority($0.relativePath) < priority($1.relativePath) }
        let canonical = files.map { "\($0.relativePath)\n\($0.language)\n\($0.content)\n" }.joined(separator: "\n")
        let hash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return ScanReport(rootPath: root.path, files: files, ignoredCount: ignored, totalBytes: files.reduce(0) { $0 + $1.size }, totalLines: files.reduce(0) { $0 + $1.lineCount }, sha256: hash)
    }

    private func priority(_ path: String) -> Int {
        let p = path.lowercased()
        if p.contains("/app/") || p.hasSuffix("app.swift") || p.contains("main.") { return 10 }
        if p.contains("/core/") || p.contains("kernel") { return 20 }
        if p.contains("/math/") || p.contains("geometry") { return 30 }
        if p.contains("/scene/") || p.contains("model") { return 40 }
        if p.contains("sketch") { return 50 }
        if p.contains("render") { return 60 }
        if p.contains("/ui/") || p.contains("view") { return 70 }
        if p.contains("event") || p.contains("bus") { return 80 }
        if p.contains("ai") || p.contains("inspector") { return 90 }
        return 100
    }
}
