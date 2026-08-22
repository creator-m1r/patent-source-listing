import Foundation

/// Категория файла в контексте подготовки листинга.
enum FileCategory: String, Codable, CaseIterable {
    case source
    case metadata
    case binary
    case generated
    case unknown
}

/// Причина, по которой элемент проекта исключён из листинга.
enum ExclusionReason: String {
    case binary = "Бинарный файл"
    case generatedDirectory = "Служебный/сгенерированный каталог"
    case excludedDirectory = "Исключённый каталог"
    case excludedFile = "Исключённый файл"
    case hiddenFile = "Скрытый файл"
    case noKnownExtension = "Нет подходящего расширения"
    case documentationDisabled = "Документация отключена"
    case configurationDisabled = "Конфигурация отключена"
    case metadataDisabled = "Метаданные проекта отключены"
    case emptyFile = "Пустой файл"
    case unreadable = "Не удалось прочитать"
    case unsupportedEncoding = "Неподдерживаемая кодировка"
    case customExtensionFilter = "Не входит в список разрешённых расширений"
}

/// Надёжная классификация файлов проекта. Списки расширений являются
/// расширяемыми и используются сканером для принятия решения о включении.
struct FileClassification {
    /// Исходный код (текстовые файлы с известным языком).
    static let sourceExtensions: Set<String> = [
        "swift", "h", "m", "mm", "c", "cc", "cpp", "cxx", "hpp", "hxx",
        "cs", "java", "kt", "kts", "py", "js", "jsx", "ts", "tsx",
        "php", "go", "rs", "rb", "dart", "scala", "sh", "bash", "zsh", "fish",
        "sql", "html", "htm", "css", "scss", "sass", "less",
        "xml", "json", "yaml", "yml", "toml", "ini", "conf", "cmake",
        "md", "markdown", "txt", "rst", "adoc", "tex", "lua", "r", "pl", "pm"
    ]

    /// Текстовая документация.
    static let documentationExtensions: Set<String> = ["md", "markdown", "txt", "rst", "adoc", "tex"]

    /// Файлы конфигурации.
    static let configurationExtensions: Set<String> = ["json", "yaml", "yml", "toml", "ini", "conf", "xml", "plist", "env", "properties"]

    /// Метаданные проекта (не исполняемый исходный код).
    static let metadataExtensions: Set<String> = [
        "pbxproj", "xcconfig", "entitlements", "gpx", "xcassets",
        "xib", "storyboard", "metal", "xcpipeline", "xcworkspace", "xcodeproj",
        "sln", "csproj", "vbproj", "gradle", "lock"
    ]

    /// Бинарные форматы, которые не должны попадать в листинг.
    static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "bmp", "tiff", "heic",
        "pdf", "zip", "7z", "rar", "tar", "gz", "bz2", "xz",
        "dmg", "app", "framework", "dylib", "so", "a", "o", "exe", "dll",
        "lib", "class", "jar", "wasm", "bin", "dat", "db", "sqlite", "mp3",
        "mp4", "mov", "wav", "ttf", "otf", "woff", "woff2", "eot"
    ]

    /// Имена служебных/сгенерированных каталогов по умолчанию.
    static let generatedDirectoryNames: Set<String> = [
        ".git", ".github", ".gitlab", ".build", "build", "Build",
        "DerivedData", "Pods", "node_modules", ".swiftpm", "xcuserdata",
        "dist", "Debug", "Release", "__pycache__", ".idea", ".vscode",
        "DerivedSources", ".terraform", ".next", "vendor", "obj"
    ]

    /// Сопоставление расширения и человекочитаемого названия языка.
    static let languages: [String: String] = [
        "swift": "Swift", "m": "Objective-C", "mm": "Objective-C++",
        "cpp": "C++", "cc": "C++", "cxx": "C++", "hpp": "C++", "hxx": "C++", "h": "C/C++ Header",
        "c": "C", "cs": "C#", "java": "Java", "kt": "Kotlin", "kts": "Kotlin",
        "py": "Python", "js": "JavaScript", "jsx": "JavaScript/JSX", "ts": "TypeScript",
        "tsx": "TypeScript/TSX", "go": "Go", "rs": "Rust", "php": "PHP", "rb": "Ruby",
        "dart": "Dart", "scala": "Scala", "sh": "Shell", "bash": "Shell", "zsh": "Shell", "fish": "Shell",
        "sql": "SQL", "html": "HTML", "htm": "HTML", "css": "CSS", "scss": "SCSS", "sass": "SASS", "less": "LESS",
        "xml": "XML", "json": "JSON", "yaml": "YAML", "yml": "YAML", "toml": "TOML",
        "ini": "INI", "conf": "Configuration", "cmake": "CMake", "md": "Markdown",
        "markdown": "Markdown", "txt": "Text", "rst": "reStructuredText", "tex": "LaTeX",
        "lua": "Lua", "r": "R", "pl": "Perl", "pm": "Perl", "metal": "Metal"
    ]

    struct Classification {
        let category: FileCategory
        let language: String?
        let isDocumentation: Bool
        let isConfiguration: Bool
        let isMetadata: Bool
    }

    /// Классифицирует элемент по имени и признаку каталога.
    static func classify(fileName: String, isDirectory: Bool) -> Classification {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if isDirectory {
            let category: FileCategory = generatedDirectoryNames.contains(fileName) ? .generated : .unknown
            return Classification(category: category, language: nil, isDocumentation: false, isConfiguration: false, isMetadata: false)
        }
        if let language = languages[ext] {
            return Classification(
                category: .source,
                language: language,
                isDocumentation: documentationExtensions.contains(ext),
                isConfiguration: configurationExtensions.contains(ext),
                isMetadata: false
            )
        }
        if metadataExtensions.contains(ext) {
            return Classification(category: .metadata, language: nil, isDocumentation: false, isConfiguration: true, isMetadata: true)
        }
        if binaryExtensions.contains(ext) {
            return Classification(category: .binary, language: nil, isDocumentation: false, isConfiguration: false, isMetadata: false)
        }
        return Classification(category: .unknown, language: nil, isDocumentation: false, isConfiguration: false, isMetadata: false)
    }

    static func language(for extension ext: String) -> String? {
        languages[ext.lowercased()]
    }
}
