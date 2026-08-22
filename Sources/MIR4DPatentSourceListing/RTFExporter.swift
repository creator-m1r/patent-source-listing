import Foundation
import AppKit
import CryptoKit

enum RTFExportError: LocalizedError {
    case sizeLimitExceeded(actual: Int, limit: Int)
    case emptySourceSet
    case roundTripMismatch(path: String)
    case invalidRTF

    var errorDescription: String? {
        switch self {
        case .sizeLimitExceeded(let actual, let limit):
            return "Сформированный листинг превышает установленный предел: \(ByteCountFormatter.string(fromByteCount: Int64(actual), countStyle: .file)) > \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))."
        case .emptySourceSet:
            return "Невозможно сформировать листинг: не выбран ни один исходный файл."
        case .roundTripMismatch(let path):
            return "Листинг не прошёл обратную проверку RTF: текст файла «\(path)» отличается от исходного текста."
        case .invalidRTF:
            return "Созданный RTF не удалось повторно прочитать. Экспорт отменён."
        }
    }
}

struct RTFVerificationResult {
    let checkedFiles: Int
    let matchedFiles: Int
    let errors: [String]
    let rtfSize: Int
    var isValid: Bool { errors.isEmpty && checkedFiles == matchedFiles }
}

final class RTFExporter {
    private let commentCleaner = CommentCleaner()

    func export(metadata: ProgramMetadata, report: ScanReport, configuration: ListingConfiguration, to url: URL) throws {
        guard !report.files.isEmpty else { throw RTFExportError.emptySourceSet }
        let rtf = makeRTF(metadata: metadata, report: report, configuration: configuration)
        let data = Data(rtf.utf8)
        let limit = max(1, configuration.outputSizeLimitBytes)
        if data.count > limit { throw RTFExportError.sizeLimitExceeded(actual: data.count, limit: limit) }
        let verification = verifyRTF(data: data, report: report, configuration: configuration)
        if !verification.isValid { throw RTFExportError.roundTripMismatch(path: verification.errors.first ?? "неизвестный файл") }
        try data.write(to: url, options: .atomic)
    }

    private func makeRTF(metadata: ProgramMetadata, report: ScanReport, configuration: ListingConfiguration) -> String {
        var out = "{\\rtf1\\ansi\\deff0\\uc1"
        out += "{\\fonttbl{\\f0\\fmodern \(escapeRTF(configuration.fontName));}}"
        out += "\\viewkind4\\f0\\fs\(max(1, Int(configuration.fontSize * 2)))\\pard\\ql "
        if configuration.pageNumbers { out += "{\\footer\\pard\\qc\\f0\\fs20 \(escapeRTF("Страница ")){\\field{\\*\\fldinst PAGE}{\\fldrslt 1}}\\par}" }

        appendLine(&out, "ЛИСТИНГ ИСХОДНОГО ТЕКСТА ПРОГРАММЫ")
        appendField(&out, "НАИМЕНОВАНИЕ ПРОГРАММЫ", metadata.programName.isEmpty ? "Программа для ЭВМ" : metadata.programName)
        appendField(&out, "НАИМЕНОВАНИЕ ПРОЕКТА", metadata.projectName)
        appendField(&out, "ПРАВООБЛАДАТЕЛЬ", metadata.copyrightHolder)
        appendField(&out, "АВТОР(Ы)", metadata.author)
        appendField(&out, "ОРГАНИЗАЦИЯ", metadata.organization)
        appendField(&out, "ВЕРСИЯ ПРОГРАММЫ", metadata.version)
        appendField(&out, "ИДЕНТИФИКАТОР ИСХОДНОГО СОСТОЯНИЯ", metadata.sourceStateIdentifier.isEmpty ? metadata.version : metadata.sourceStateIdentifier)
        appendField(&out, "ДАТА ФОРМИРОВАНИЯ", metadata.creationDate)
        appendField(&out, "ОЧИСТКА КОММЕНТАРИЕВ", configuration.removeComments ? "ВКЛЮЧЕНА" : "ВЫКЛЮЧЕНА")

        appendSection(&out, "ДРЕВОВИДНАЯ СТРУКТУРА КАТАЛОГОВ И ФАЙЛОВ")
        appendLine(&out, TreeBuilder.build(files: report.files))
        out += "\\page "

        appendSection(&out, "СВЕДЕНИЯ О ПРОГРАММЕ")
        appendField(&out, "Название программы", metadata.programName)
        appendField(&out, "Название проекта", metadata.projectName)
        appendField(&out, "Версия программы", metadata.version)
        appendField(&out, "Идентификатор исходного состояния", metadata.sourceStateIdentifier.isEmpty ? metadata.version : metadata.sourceStateIdentifier)
        appendField(&out, "Автор(ы)", metadata.author)
        appendField(&out, "Правообладатель", metadata.copyrightHolder)
        appendField(&out, "Организация", metadata.organization)
        appendField(&out, "Адрес организации", metadata.organizationAddress)
        appendField(&out, "Контактные сведения", metadata.contact)
        appendField(&out, "Языки программирования", metadata.programmingLanguages)
        appendField(&out, "Дата формирования", metadata.creationDate)
        appendField(&out, "Дата регистрации", metadata.registrationDate)
        appendField(&out, "Примечание", metadata.notes)

        appendSection(&out, "СВЕДЕНИЯ О ЛИСТИНГЕ")
        appendField(&out, "Корневая папка проекта", report.rootPath)
        appendField(&out, "Количество исходных файлов", "\(report.files.count)")
        appendField(&out, "Количество проигнорированных объектов", "\(report.ignoredCount)")
        appendField(&out, "Общее количество строк", "\(report.totalLines)")
        appendField(&out, "Размер исходных текстов", ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
        appendField(&out, "Контрольная сумма набора исходных файлов SHA-256", report.sha256)
        appendField(&out, "Лимит размера RTF", ByteCountFormatter.string(fromByteCount: Int64(configuration.outputSizeLimitBytes), countStyle: .file))

        appendSection(&out, "ПЕРЕЧЕНЬ ИСХОДНЫХ ФАЙЛОВ")
        for (i, file) in report.files.enumerated() { appendLine(&out, String(format: "%03d  %@  —  %@  —  SHA-256 текста: %@  —  SHA-256 исходных байтов: %@", i + 1, file.relativePath, file.language, file.sha256, file.sourceDataSHA256)) }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        for (i, file) in report.files.enumerated() {
            let separator = String(repeating: "=", count: max(20, configuration.separatorWidth))
            appendLine(&out, separator)
            appendLine(&out, "ФАЙЛ № \(String(format: "%03d", i + 1))")
            appendLine(&out, "ФАЙЛ: \(file.relativePath)")
            appendLine(&out, "ЯЗЫК ПРОГРАММИРОВАНИЯ: \(file.language)")
            appendLine(&out, "КОДИРОВКА ИСХОДНОГО ФАЙЛА: \(file.encodingName)")
            appendLine(&out, "SHA-256 ИСХОДНОГО ТЕКСТА: \(file.sha256)")
            appendLine(&out, "SHA-256 ИСХОДНЫХ БАЙТОВ: \(file.sourceDataSHA256)")
            appendLine(&out, separator)
            let source = configuration.removeComments ? commentCleaner.clean(file.content, language: file.language).content : file.content
            appendLine(&out, "[[M1R-НАЧАЛО-\(token)-\(i + 1)]]")
            appendRawSource(&out, source)
            appendLine(&out, "[[M1R-КОНЕЦ-\(token)-\(i + 1)]]")
            appendLine(&out, "")
        }
        out += "}"
        return out
    }

    private func appendSection(_ out: inout String, _ value: String) { appendLine(&out, ""); appendLine(&out, value); appendLine(&out, "") }
    private func appendField(_ out: inout String, _ key: String, _ value: String) { appendLine(&out, "\(key): \(value)") }
    private func appendLine(_ out: inout String, _ value: String) { out += escapeRTF(value); out += "\\line " }

    private func appendRawSource(_ out: inout String, _ value: String) {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        out += escapeRTF(normalized)
        if !normalized.hasSuffix("\n") { out += "\\line " }
    }

    private func escapeRTF(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count + 32)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 10: result += "\\line "
            case 13: continue
            case 9: result += "\\tab "
            case 92: result += "\\\\"
            case 123: result += "\\{"
            case 125: result += "\\}"
            case 32...126: result.append(Character(scalar))
            default:
                var value = scalar.value
                if value > 32767 { value -= 65536 }
                result += "\\u\(value)?"
            }
        }
        return result
    }

    private func verifyRTF(data: Data, report: ScanReport, configuration: ListingConfiguration) -> RTFVerificationResult {
        guard let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
            return RTFVerificationResult(checkedFiles: report.files.count, matchedFiles: 0, errors: ["RTF не удалось повторно прочитать"], rtfSize: data.count)
        }
        let plain = attributed.string
        guard let token = extractToken(from: plain) else {
            return RTFVerificationResult(checkedFiles: report.files.count, matchedFiles: 0, errors: ["В RTF отсутствуют контрольные маркеры файлов"], rtfSize: data.count)
        }
        var errors: [String] = []
        var matched = 0
        for (index, file) in report.files.enumerated() {
            let begin = "[[M1R-НАЧАЛО-\(token)-\(index + 1)]]"
            let end = "[[M1R-КОНЕЦ-\(token)-\(index + 1)]]"
            guard let beginRange = plain.range(of: begin), let endRange = plain.range(of: end, range: beginRange.upperBound..<plain.endIndex) else { errors.append(file.relativePath); continue }
            let extracted = String(plain[beginRange.upperBound..<endRange.lowerBound])
            let source = configuration.removeComments ? commentCleaner.clean(file.content, language: file.language).content : file.content
            if canonicalText(extracted) == canonicalText(source) { matched += 1 } else { errors.append(file.relativePath) }
        }
        return RTFVerificationResult(checkedFiles: report.files.count, matchedFiles: matched, errors: errors, rtfSize: data.count)
    }

    private func extractToken(from text: String) -> String? {
        let prefix = "[[M1R-НАЧАЛО-"
        guard let start = text.range(of: prefix) else { return nil }
        let remainder = text[start.upperBound...]
        guard let end = remainder.range(of: "]]"), let marker = remainder[..<end.lowerBound].split(separator: "-").first else { return nil }
        return String(marker)
    }

    private func canonicalText(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for char in value {
            if char.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) {
                result.append("\n")
            } else {
                result.append(char)
            }
        }
        return result.trimmingCharacters(in: .newlines)
    }
}

enum TreeBuilder {
    final class Node { var children: [String: Node] = [:]; var file = false }
    static func build(files: [SourceFile]) -> String {
        let root = Node()
        for file in files {
            var node = root
            for part in file.relativePath.split(separator: "/").map(String.init) { node.children[part] = node.children[part] ?? Node(); node = node.children[part]! }
            node.file = true
        }
        var lines: [String] = []
        let names = root.children.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for (index, name) in names.enumerated() { render(root.children[name]!, name, "", index == names.count - 1, &lines) }
        return lines.joined(separator: "\n")
    }
    private static func render(_ node: Node, _ name: String, _ prefix: String, _ last: Bool, _ lines: inout [String]) {
        lines.append(prefix + (last ? "└── " : "├── ") + name + (node.file ? "" : "/"))
        let childPrefix = prefix + (last ? "    " : "│   ")
        let children = node.children.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for (index, child) in children.enumerated() { render(node.children[child]!, child, childPrefix, index == children.count - 1, &lines) }
    }
}
