import Foundation

struct ListingConfiguration: Codable {
    var includeExtensions: Set<String> = []
    var excludedDirectories: Set<String> = [
        ".git", ".github", ".build", "build", "Build", "DerivedData",
        "Pods", "node_modules", ".swiftpm", "xcuserdata", "dist",
        "Debug", "Release", "__pycache__", ".idea", ".vscode"
    ]
    var excludedFileNames: Set<String> = ["Package.resolved", ".DS_Store"]
    var includeDocumentation: Bool = false
    var includeConfigurationFiles: Bool = false
    var includeEmptyFiles: Bool = true
    var removeComments: Bool = false
    var fontName: String = "Courier New"
    var fontSize: Double = 10
    var separatorWidth: Int = 80
    var logicalOrder: Bool = true
    var pageNumbers: Bool = true
    /// Точный предельный размер готового RTF в байтах. 4,9 МБ = 4 900 000 байт.
    var outputSizeLimitBytes: Int = 4_900_000

    static let `default` = ListingConfiguration()
}
