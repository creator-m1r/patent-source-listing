import Foundation
import AppKit

enum RTFExportError: LocalizedError {
    case sizeLimitExceeded(actual: Int, limit: Int)
    case emptySourceSet

    var errorDescription: String? {
        switch self {
        case .sizeLimitExceeded(let actual, let limit):
            return "Сформированный листинг превышает установленный предел: \(ByteCountFormatter.string(fromByteCount: Int64(actual), countStyle: .file)) > \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))."
        case .emptySourceSet:
            return "Невозможно сформировать листинг: не выбран ни один исходный файл."
        }
    }
}

final class RTFExporter {
    private let commentCleaner = CommentCleaner()

    func export(metadata: ProgramMetadata, report: ScanReport, configuration: ListingConfiguration, to url: URL) throws {
        guard !report.files.isEmpty else { throw RTFExportError.emptySourceSet }

        let text = NSMutableAttributedString()
        let title = metadata.programName.isEmpty ? "Программа для ЭВМ" : metadata.programName
        line(&text, "ЛИСТИНГ ИСХОДНОГО ТЕКСТА ПРОГРАММЫ")
        line(&text, title)
        field(&text, "Правообладатель", metadata.copyrightHolder)
        field(&text, "Автор(ы)", metadata.author)
        field(&text, "Организация", metadata.organization)
        line(&text, "")
        section(&text, "ДРЕВОВИДНАЯ СТРУКТУРА КАТАЛОГОВ И ФАЙЛОВ")
        line(&text, TreeBuilder.build(files: report.files))
        line(&text, "")
        line(&text, "Перечень и исходные тексты файлов приведены далее в том же документе.")
        pageBreak(&text)

        section(&text, "СВЕДЕНИЯ О ПРОГРАММЕ")
        field(&text, "Название программы", metadata.programName)
        field(&text, "Название проекта", metadata.projectName)
        field(&text, "Версия", metadata.version)
        field(&text, "Автор(ы)", metadata.author)
        field(&text, "Правообладатель", metadata.copyrightHolder)
        field(&text, "Организация", metadata.organization)
        field(&text, "Адрес организации", metadata.organizationAddress)
        field(&text, "Контактные сведения", metadata.contact)
        field(&text, "Языки программирования", metadata.programmingLanguages)
        field(&text, "Дата формирования", metadata.creationDate)
        field(&text, "Дата регистрации", metadata.registrationDate)
        field(&text, "Примечание", metadata.notes)

        section(&text, "СВЕДЕНИЯ О ЛИСТИНГЕ")
        field(&text, "Корневая папка проекта", report.rootPath)
        field(&text, "Количество исходных файлов", "\(report.files.count)")
        field(&text, "Количество проигнорированных объектов", "\(report.ignoredCount)")
        field(&text, "Общее количество строк", "\(report.totalLines)")
        field(&text, "Размер исходных текстов", ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
        field(&text, "Контрольная сумма исходного набора SHA-256", report.sha256)
        field(&text, "Очистка комментариев", configuration.removeComments ? "ВКЛЮЧЕНА. Текст в листинге отличается от исходных файлов только удалением распознанных комментариев." : "ВЫКЛЮЧЕНА. Текст листинга соответствует прочитанному исходному тексту.")

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

        var data = try text.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf,
            .characterEncoding: String.Encoding.utf8.rawValue
        ])

        if configuration.pageNumbers {
            data = addPageNumbers(to: data)
        }

        let limit = max(1, configuration.outputSizeLimitMB) * 1024 * 1024
        if data.count > limit {
            throw RTFExportError.sizeLimitExceeded(actual: data.count, limit: limit)
        }
        try data.write(to: url, options: .atomic)
    }

    private func addPageNumbers(to data: Data) -> Data {
        guard var rtf = String(data: data, encoding: .utf8), let marker = rtf.range(of: "\\pard") else { return data }
        let footer = #"\footer\pard\qc\f0\fs20 Страница {\field{\*\fldinst PAGE}{\fldrslt 1}}\par"#
        rtf.insert(contentsOf: footer, at: marker.lowerBound)
        return Data(rtf.utf8)
    }

    private func line(_ s: inout NSMutableAttributedString, _ value: String) {
        s.append(NSAttributedString(string: value + "\n"))
    }

    private func section(_ s: inout NSMutableAttributedString, _ value: String) {
        line(&s, "\n" + value)
        line(&s, "")
    }

    private func field(_ s: inout NSMutableAttributedString, _ key: String, _ value: String) {
        line(&s, "\(key): \(value)")
    }

    private func pageBreak(_ s: inout NSMutableAttributedString) {
        s.append(NSAttributedString(string: "\n\u{000C}\n"))
    }
}

enum TreeBuilder {
    final class Node { var children: [String: Node] = [:]; var file = false }

    static func build(files: [SourceFile]) -> String {
        let root = Node()
        for file in files {
            var node = root
            for part in file.relativePath.split(separator: "/").map(String.init) {
                node.children[part] = node.children[part] ?? Node()
                node = node.children[part]!
            }
            node.file = true
        }
        var lines: [String] = []
        let names = root.children.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for (index, name) in names.enumerated() {
            render(root.children[name]!, name, "", index == names.count - 1, &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func render(_ node: Node, _ name: String, _ prefix: String, _ last: Bool, _ lines: inout [String]) {
        lines.append(prefix + (last ? "└── " : "├── ") + name + (node.file ? "" : "/"))
        let childPrefix = prefix + (last ? "    " : "│   ")
        let children = node.children.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for (index, child) in children.enumerated() {
            render(node.children[child]!, child, childPrefix, index == children.count - 1, &lines)
        }
    }
}
