import Foundation

struct ProgramMetadata: Codable {
    var programName: String
    var projectName: String
    var version: String
    var sourceStateIdentifier: String
    var author: String
    var copyrightHolder: String
    var organization: String
    var organizationAddress: String
    var contact: String
    var programmingLanguages: String
    var creationDate: String
    var registrationDate: String
    var notes: String

    init(
        programName: String = "",
        projectName: String = "",
        version: String = "",
        author: String = "",
        copyrightHolder: String = "",
        organization: String = "",
        organizationAddress: String = "",
        contact: String = "",
        programmingLanguages: String = "",
        creationDate: String = Self.defaultDate(),
        registrationDate: String = "",
        notes: String = "",
        sourceStateIdentifier: String = ""
    ) {
        self.programName = programName
        self.projectName = projectName
        self.version = version
        self.sourceStateIdentifier = sourceStateIdentifier
        self.author = author
        self.copyrightHolder = copyrightHolder
        self.organization = organization
        self.organizationAddress = organizationAddress
        self.contact = contact
        self.programmingLanguages = programmingLanguages
        self.creationDate = creationDate
        self.registrationDate = registrationDate
        self.notes = notes
    }

    static func defaultDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: Date())
    }

    private enum CodingKeys: String, CodingKey {
        case programName, projectName, version, sourceStateIdentifier, author, copyrightHolder
        case organization, organizationAddress, contact, programmingLanguages
        case creationDate, registrationDate, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            programName: try container.decodeIfPresent(String.self, forKey: .programName) ?? "",
            projectName: try container.decodeIfPresent(String.self, forKey: .projectName) ?? "",
            version: try container.decodeIfPresent(String.self, forKey: .version) ?? "",
            author: try container.decodeIfPresent(String.self, forKey: .author) ?? "",
            copyrightHolder: try container.decodeIfPresent(String.self, forKey: .copyrightHolder) ?? "",
            organization: try container.decodeIfPresent(String.self, forKey: .organization) ?? "",
            organizationAddress: try container.decodeIfPresent(String.self, forKey: .organizationAddress) ?? "",
            contact: try container.decodeIfPresent(String.self, forKey: .contact) ?? "",
            programmingLanguages: try container.decodeIfPresent(String.self, forKey: .programmingLanguages) ?? "",
            creationDate: try container.decodeIfPresent(String.self, forKey: .creationDate) ?? Self.defaultDate(),
            registrationDate: try container.decodeIfPresent(String.self, forKey: .registrationDate) ?? "",
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            sourceStateIdentifier: try container.decodeIfPresent(String.self, forKey: .sourceStateIdentifier) ?? ""
        )
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
