import Foundation

struct ListingConfiguration: Codable {
    var includeExtensions: Set<String> = []
    var excludedDirectories: Set<String> = [".git", ".github", ".build", "build", "Build", "DerivedData", "Pods", "node_modules", ".swiftpm", "xcuserdata", "dist", "Debug", "Release", "__pycache__", ".idea", ".vscode"]
    var excludedFileNames: Set<String> = ["Package.resolved"]
    var includeDocumentation: Bool = false
    var includeConfigurationFiles: Bool = false
    var includeEmptyFiles: Bool = true
    var removeComments: Bool = false
    var fontName: String = "Courier New"
    var fontSize: Double = 10
    var separatorWidth: Int = 80
    var logicalOrder: Bool = true
    var pageNumbers: Bool = true
    var outputSizeLimitMB: Int = 5

    static let `default` = ListingConfiguration()
}
