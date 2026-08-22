import Foundation

struct ProgramMetadata: Codable {
    var programName = ""
    var projectName = ""
    var version = ""
    var sourceStateIdentifier = ""
    var author = ""
    var copyrightHolder = ""
    var organization = ""
    var organizationAddress = ""
    var contact = ""
    var programmingLanguages = ""
    var creationDate = Self.defaultDate()
    var registrationDate = ""
    var notes = ""

    static func defaultDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: Date())
    }
}

struct SourceFile: Identifiable {
    let id = UUID()
    let relativePath: String
    let absoluteURL: URL
    let language: String
    let extensionName: String
    let size: Int64
    let lineCount: Int
    let content: String
    let isDocumentation: Bool
    let isConfiguration: Bool
    let sha256: String
    let sourceDataSHA256: String
    let encodingName: String
}

struct ScanReport {
    var rootPath = ""
    var files: [SourceFile] = []
    var ignoredCount = 0
    var totalBytes: Int64 = 0
    var totalLines = 0
    var sha256 = ""
}

enum ScannerError: LocalizedError {
    case noFolder
    case unsupportedEncoding(URL)

    var errorDescription: String? {
        switch self {
        case .noFolder:
            return "Папка проекта не выбрана."
        case .unsupportedEncoding(let url):
            return "Не удалось определить текстовую кодировку: \(url.path)"
        }
    }
}
