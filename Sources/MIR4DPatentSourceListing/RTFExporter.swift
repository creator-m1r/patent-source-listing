import Foundation
import AppKit

enum RTFExportError: LocalizedError {
    case sizeLimitExceeded(actual: Int, limit: Int)
    var errorDescription: String? {
        switch self {
        case .sizeLimitExceeded(let actual, let limit):
            return "Сформированный RTF превышает установленный лимит: \(ByteCountFormatter.string(fromByteCount: Int64(actual), countStyle: .file)) > \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))."
        }
    }
}

final class RTFExporter {
    private let commentCleaner = CommentCleaner()

    func export(metadata: ProgramMetadata, report: ScanReport, configuration: ListingConfiguration, to url: URL) throws {
        let text = NSMutableAttributedString()
        line(&text, "ЛИСТИНГ ИСХОДНОГО ТЕКСТА ПРОГРАММЫ")
        line(&text, "Подготовлено MIR4D Patent Source Listing")
        line(&text, "")
        section(&text, "СВЕДЕНИЯ О ПРОГРАММЕ")
        field(&text, "Название программы", metadata.programName)
        field(&text, "Название проекта", metadata.projectName)
        field(&text, "Версия", metadata.version)
        field(&text, "Автор", metadata.author)
        field(&text, "Правообладатель", metadata.copyrightHolder)
        field(&text, "Организация", metadata.organization)
        field(&text, "Адрес организации", metadata.organizationAddress)
        field(&text, "Контакт", metadata.contact)
        field(&text, "Языки программирования", metadata.programmingLanguages)
        field(&text, "Дата формирования", metadata.creationDate)
        field(&text, "Дата регистрации", metadata.registrationDate)
        field(&text, "Примечание", metadata.notes)

        section(&text, "СВЕДЕНИЯ О ЛИСТИНГЕ")
        field(&text, "Корневая папка", report.rootPath)
        field(&text, "Исходных файлов", "\(report.files.count)")
        field(&text, "Игнорировано объектов", "\(report.ignoredCount)")
        field(&text, "Всего строк", "\(report.totalLines)")
        field(&text, "Размер исходников", ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
        field(&text, "SHA-256 набора", report.sha256)
        field(&text, "Очистка комментариев", configuration.removeComments ? "ВКЛЮЧЕНА — только для экспортируемого листинга" : "ВЫКЛЮЧЕНА")

        section(&text, "ДРЕВОВИДНАЯ СТРУКТУРА КАТАЛОГОВ И ФАЙЛОВ")
        line(&text, TreeBuilder.build(files: report.files))
        line(&text, "")

        section(&text, "ПЕРЕЧЕНЬ ИСХОДНЫХ ФАЙЛОВ")
        for (i, f) in report.files.enumerated() {
            line(&text, String(format: "%03d  %@  —  %@", i + 1, f.relativePath, f.language))
        }

        for (i, f) in report.files.enumerated() {
            line(&text, String(repeating: "=", count: max(20, configuration.separatorWidth)))
            line(&text, "ФАЙЛ № \(String(format: "%03d", i + 1))")
            line(&text, "ФАЙЛ: \(f.relativePath)")
            line(&text, "ЯЗЫК ПРОГРАММИРОВАНИЯ: \(f.language)")
            line(&text, String(repeating: "=", count: max(20, configuration.separatorWidth)))
            let source = configuration.removeComments ? commentCleaner.clean(f.content, language: f.language).content : f.content
            line(&text, source)
            line(&text, "")
        }

        let range = NSRange(location: 0, length: text.length)
        let font = NSFont(name: configuration.fontName, size: configuration.fontSize) ?? NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        text.addAttribute(.font, value: font, range: range)
        text.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        var data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf, .characterEncoding: String.Encoding.utf8.rawValue])

        if configuration.pageNumbers, var rtf = String(data: data, encoding: .utf8), let marker = rtf.range(of: "\\pard") {
            let footer = #"\footer\pard\qc\f0\fs20 Страница {\field{\*\fldinst PAGE}{\fldrslt 1}}\par"#
            rtf.insert(contentsOf: footer, at: marker.lowerBound)
            data = Data(rtf.utf8)
        }

        let limit = max(1, configuration.outputSizeLimitMB) * 1024 * 1024
        if data.count > limit { throw RTFExportError.sizeLimitExceeded(actual: data.count, limit: limit) }
        try data.write(to: url, options: .atomic)
    }

    private func line(_ s: inout NSMutableAttributedString, _ v: String) { s.append(NSAttributedString(string: v + "\n")) }
    private func section(_ s: inout NSMutableAttributedString, _ v: String) { line(&s, "\n" + v); line(&s, "") }
    private func field(_ s: inout NSMutableAttributedString, _ k: String, _ v: String) { line(&s, "\(k): \(v)") }
}

enum TreeBuilder {
    final class Node { var children: [String: Node] = [:]; var file = false }
    static func build(files: [SourceFile]) -> String {
        let root = Node()
        for f in files {
            var node = root
            for part in f.relativePath.split(separator: "/").map(String.init) {
                node.children[part] = node.children[part] ?? Node()
                node = node.children[part]!
            }
            node.file = true
        }
        var lines: [String] = []
        let names = root.children.keys.sorted()
        for (i, name) in names.enumerated() { render(root.children[name]!, name, "", i == names.count - 1, &lines) }
        return lines.joined(separator: "\n")
    }
    private static func render(_ node: Node, _ name: String, _ prefix: String, _ last: Bool, _ lines: inout [String]) {
        lines.append(prefix + (last ? "└── " : "├── ") + name + (node.file ? "" : "/"))
        let childPrefix = prefix + (last ? "    " : "│   ")
        let children = node.children.keys.sorted()
        for (i, child) in children.enumerated() { render(node.children[child]!, child, childPrefix, i == children.count - 1, &lines) }
    }
}
