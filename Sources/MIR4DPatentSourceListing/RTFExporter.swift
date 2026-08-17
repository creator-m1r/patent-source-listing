import Foundation
import AppKit

final class RTFExporter {
    private let fontName = "Courier New"
    private let fontSize: CGFloat = 10

    func export(metadata: ProgramMetadata, report: ScanReport, to url: URL) throws {
        let text = NSMutableAttributedString()
        line(&text, "ЛИСТИНГ ИСХОДНОГО ТЕКСТА ПРОГРАММЫ")
        line(&text, "Подготовлено MIR4D Patent Source Listing")
        line(&text, "")
        section(&text, "СВЕДЕНИЯ О ПРОГРАММЕ")
        field(&text, "Название программы", metadata.programName); field(&text, "Название проекта", metadata.projectName); field(&text, "Версия", metadata.version)
        field(&text, "Автор", metadata.author); field(&text, "Правообладатель", metadata.copyrightHolder); field(&text, "Организация", metadata.organization)
        field(&text, "Адрес организации", metadata.organizationAddress); field(&text, "Контакт", metadata.contact); field(&text, "Языки программирования", metadata.programmingLanguages)
        field(&text, "Дата формирования", metadata.creationDate); field(&text, "Дата регистрации", metadata.registrationDate); field(&text, "Примечание", metadata.notes)
        section(&text, "СВЕДЕНИЯ О ЛИСТИНГЕ")
        field(&text, "Корневая папка", report.rootPath); field(&text, "Исходных файлов", "\(report.files.count)"); field(&text, "Игнорировано объектов", "\(report.ignoredCount)")
        field(&text, "Всего строк", "\(report.totalLines)"); field(&text, "Размер исходников", ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file)); field(&text, "SHA-256 набора", report.sha256)
        section(&text, "ДРЕВОВИДНАЯ СТРУКТУРА КАТАЛОГОВ И ФАЙЛОВ")
        line(&text, TreeBuilder.build(files: report.files)); line(&text, "")
        section(&text, "ПЕРЕЧЕНЬ ИСХОДНЫХ ФАЙЛОВ")
        for (i, f) in report.files.enumerated() { line(&text, String(format: "%03d  %@  —  %@", i + 1, f.relativePath, f.language)) }
        for (i, f) in report.files.enumerated() {
            line(&text, String(repeating: "=", count: 80)); line(&text, "ФАЙЛ № \(String(format: "%03d", i + 1))"); line(&text, "ФАЙЛ: \(f.relativePath)"); line(&text, "ЯЗЫК ПРОГРАММИРОВАНИЯ: \(f.language)"); line(&text, String(repeating: "=", count: 80)); line(&text, f.content); line(&text, "")
        }
        let range = NSRange(location: 0, length: text.length)
        text.addAttribute(.font, value: NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: range)
        text.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        var data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf, .characterEncoding: String.Encoding.utf8.rawValue])
        if var rtf = String(data: data, encoding: .utf8), let marker = rtf.range(of: "\\pard") {
            let footer = #"\footer\pard\qc\f0\fs20 Страница {\field{\*\fldinst PAGE}{\fldrslt 1}}\par"#
            rtf.insert(contentsOf: footer, at: marker.lowerBound)
            data = Data(rtf.utf8)
        }
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
        for f in files { var n = root; for p in f.relativePath.split(separator: "/").map(String.init) { n.children[p] = n.children[p] ?? Node(); n = n.children[p]! }; n.file = true }
        var lines: [String] = []
        for (i, name) in root.children.keys.sorted().enumerated() { render(root.children[name]!, name, "", i == root.children.count - 1, &lines) }
        return lines.joined(separator: "\n")
    }
    private static func render(_ n: Node, _ name: String, _ prefix: String, _ last: Bool, _ lines: inout [String]) {
        lines.append(prefix + (last ? "└── " : "├── ") + name + (n.file ? "" : "/"))
        let p = prefix + (last ? "    " : "│   ")
        for (i, child) in n.children.keys.sorted().enumerated() { render(n.children[child]!, child, p, i == n.children.count - 1, &lines) }
    }
}
