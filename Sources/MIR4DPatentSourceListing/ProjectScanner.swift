import Foundation
import CryptoKit

final class ProjectScanner {
    private let languages: [String: String] = [
        "swift": "Swift", "m": "Objective-C", "mm": "Objective-C++", "cpp": "C++", "cc": "C++", "cxx": "C++", "hpp": "C++", "h": "C/C++ Header", "c": "C", "cs": "C#", "java": "Java", "kt": "Kotlin", "py": "Python", "js": "JavaScript", "jsx": "JavaScript/JSX", "ts": "TypeScript", "tsx": "TypeScript/TSX", "go": "Go", "rs": "Rust", "php": "PHP", "rb": "Ruby", "dart": "Dart", "scala": "Scala", "sql": "SQL", "sh": "Shell", "bash": "Shell", "zsh": "Shell", "fish": "Shell", "html": "HTML", "htm": "HTML", "css": "CSS", "scss": "SCSS", "xml": "XML", "json": "JSON", "yaml": "YAML", "yml": "YAML", "toml": "TOML", "ini": "INI", "conf": "Configuration", "cmake": "CMake", "md": "Markdown", "txt": "Text"
    ]

    private let documentationExtensions: Set<String> = ["md", "txt"]
    private let configurationExtensions: Set<String> = ["json", "yaml", "yml", "toml", "ini", "conf", "xml"]

    func scan(root: URL, configuration: ListingConfiguration) throws -> ScanReport {
        let excluded = configuration.excludedDirectories
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw ScannerError.noFolder
        }

        var files: [SourceFile] = []
        var ignored = 0

        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let parts = relative.split(separator: "/").map(String.init)

            if parts.dropLast().contains(where: excluded.contains) {
                if url.hasDirectoryPath { enumerator.skipDescendants() }
                ignored += 1
                continue
            }

            if url.hasDirectoryPath {
                if excluded.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            guard !configuration.excludedFileNames.contains(url.lastPathComponent) else { ignored += 1; continue }

            let ext = url.pathExtension.lowercased()
            guard let language = languages[ext] else { ignored += 1; continue }

            let isDocumentation = documentationExtensions.contains(ext)
            let isConfiguration = configurationExtensions.contains(ext)
            if isDocumentation && !configuration.includeDocumentation { ignored += 1; continue }
            if isConfiguration && !configuration.includeConfigurationFiles { ignored += 1; continue }
            if !configuration.includeExtensions.isEmpty && !configuration.includeExtensions.contains(ext) { ignored += 1; continue }

            guard let data = try? Data(contentsOf: url) else {
                ignored += 1
                continue
            }

            // Для патентного листинга принимаем только UTF-8/UTF-16 текст.
            // Содержимое не нормализуем и не меняем: это важно для проверки соответствия.
            guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                ignored += 1
                continue
            }

            let lineCount = content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count
            if lineCount == 0 && !configuration.includeEmptyFiles { ignored += 1; continue }

            let fileHash = sha256(data: Data(content.utf8))
            files.append(SourceFile(
                relativePath: relative,
                absoluteURL: url,
                language: language,
                extensionName: ext,
                size: Int64(values.fileSize ?? data.count),
                lineCount: lineCount,
                content: content,
                isDocumentation: isDocumentation,
                isConfiguration: isConfiguration,
                sha256: fileHash
            ))
        }

        if configuration.logicalOrder {
            files.sort {
                let lhs = priority($0.relativePath)
                let rhs = priority($1.relativePath)
                return lhs == rhs
                    ? $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                    : lhs < rhs
            }
        } else {
            files.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        }

        let canonical = files.map { "\($0.relativePath)\n\($0.language)\n\($0.sha256)\n" }.joined(separator: "\n")
        let hash = sha256(data: Data(canonical.utf8))

        return ScanReport(
            rootPath: root.path,
            files: files,
            ignoredCount: ignored,
            totalBytes: files.reduce(0) { $0 + $1.size },
            totalLines: files.reduce(0) { $0 + $1.lineCount },
            sha256: hash
        )
    }

    private func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
