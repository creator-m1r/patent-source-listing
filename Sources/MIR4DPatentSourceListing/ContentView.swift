import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ListingViewModel
    var body: some View {
        NavigationSplitView {
            Form {
                Section("Проект") {
                    Button { model.chooseFolder() } label: { Label("Выбрать папку проекта", systemImage: "folder") }
                    if let folder = model.selectedFolder { Text(folder.path).font(.caption).textSelection(.enabled) }
                    Button { model.scan() } label: { Label("Сканировать проект", systemImage: "arrow.triangle.2.circlepath") }.disabled(model.selectedFolder == nil || model.isScanning)
                }
                Section("Сведения о программе") {
                    TextField("Название программы", text: $model.metadata.programName)
                    TextField("Название проекта", text: $model.metadata.projectName)
                    TextField("Версия", text: $model.metadata.version)
                    TextField("Автор", text: $model.metadata.author)
                    TextField("Правообладатель", text: $model.metadata.copyrightHolder)
                    TextField("Организация", text: $model.metadata.organization)
                    TextField("Адрес организации", text: $model.metadata.organizationAddress)
                    TextField("Контакт", text: $model.metadata.contact)
                    TextField("Языки программирования", text: $model.metadata.programmingLanguages)
                    TextField("Дата формирования", text: $model.metadata.creationDate)
                    TextField("Дата регистрации", text: $model.metadata.registrationDate)
                    TextField("Примечание", text: $model.metadata.notes, axis: .vertical).lineLimit(3...6)
                }
                Section("Экспорт") {
                    Button { model.exportRTF() } label: { Label("Сформировать RTF", systemImage: "doc.text") }.disabled(model.report.files.isEmpty)
                    Text("Courier New 10 pt · RTF · сквозная нумерация страниц").font(.caption)
                }
            }.formStyle(.grouped).navigationSplitViewColumnWidth(min: 350, ideal: 390, max: 460)
        } detail: { DetailView() }
        .alert("Ошибка", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }
}

private struct DetailView: View {
    @EnvironmentObject private var model: ListingViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Листинг исходного текста").font(.largeTitle.bold())
            Text("Подготовка материалов проекта для передачи патентной организации").foregroundStyle(.secondary)
            HStack {
                Metric(title: "Файлов", value: "\(model.report.files.count)")
                Metric(title: "Строк", value: "\(model.report.totalLines)")
                Metric(title: "Размер", value: ByteCountFormatter.string(fromByteCount: model.report.totalBytes, countStyle: .file))
                Metric(title: "Игнорировано", value: "\(model.report.ignoredCount)")
            }
            GroupBox("Статус") { HStack { if model.isScanning { ProgressView() } else { Image(systemName: "checkmark.circle") }; Text(model.status).frame(maxWidth: .infinity, alignment: .leading) }.padding(6) }
            GroupBox("SHA-256 исходного набора") { Text(model.report.sha256.isEmpty ? "Будет рассчитана после сканирования" : model.report.sha256).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(6) }
            Text("Файлы в логическом порядке").font(.headline)
            List(model.report.files) { file in
                VStack(alignment: .leading, spacing: 3) { Text(file.relativePath).font(.system(.body, design: .monospaced)); Text("\(file.language) · \(file.lineCount) строк · \(file.size) байт").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 3)
            }
        }.padding(24)
    }
}

private struct Metric: View {
    let title: String; let value: String
    var body: some View { VStack(alignment: .leading) { Text(value).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}
