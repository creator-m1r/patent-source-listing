import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ListingViewModel
    @State private var newProfileName = ""
    @State private var showProfileSheet = false
    @State private var showTree = true
    @State private var showValidation = false
    @State private var showRestoreReport = false

    var body: some View {
        NavigationSplitView {
            Form {
                Section("Проект") {
                    Button { model.chooseFolder() } label: { Label("Выбрать папку проекта", systemImage: "folder") }
                    if let folder = model.selectedFolder { Text(folder.path).font(.caption).textSelection(.enabled) }
                    Button { model.scan() } label: { Label("Сканировать проект", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(model.selectedFolder == nil || model.isScanning || model.isRestoring)
                    Button { model.restoreFromDiff() } label: { Label("Восстановить проект из diff…", systemImage: "arrow.down.doc") }
                        .disabled(model.isScanning || model.isRestoring)
                    if model.isRestoring { ProgressView("Восстановление…") }
                    Text("Создается новая папка проекта. При необходимости можно выбрать исходную папку как базу для применения patch.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.restoreReport != nil {
                        Button { showRestoreReport = true } label: { Label("Показать отчет восстановления", systemImage: "doc.plaintext") }
                    }
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
                Section("Профили") {
                    if model.profiles.isEmpty { Text("Сохраненных профилей нет.").foregroundStyle(.secondary) }
                    ForEach(model.profiles) { profile in
                        HStack {
                            Button(profile.name) { model.loadProfile(profile) }.buttonStyle(.plain)
                            Spacer()
                            Button { model.deleteProfile(profile) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                    Button { showProfileSheet = true } label: { Label("Сохранить текущие данные как профиль", systemImage: "person.crop.circle.badge.plus") }
                }
                Section("Состав листинга") {
                    Toggle("Включать документацию (.md, .txt)", isOn: $model.configuration.includeDocumentation)
                    Toggle("Включать конфигурации (.json, .yaml, .xml…)", isOn: $model.configuration.includeConfigurationFiles)
                    Toggle("Включать пустые файлы", isOn: $model.configuration.includeEmptyFiles)
                    Toggle("Логический порядок файлов", isOn: $model.configuration.logicalOrder)
                    Toggle("Нумерация страниц", isOn: $model.configuration.pageNumbers)
                    Toggle("🧹 Удалять комментарии при экспорте", isOn: $model.configuration.removeComments)
                    Text("Оригинальные файлы на диске не изменяются. Комментарии удаляются только из текста, попадающего в RTF.")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("Шрифт: \(Int(model.configuration.fontSize)) pt", value: $model.configuration.fontSize, in: 8...14, step: 1)
                    Stepper("Разделитель: \(model.configuration.separatorWidth) символов", value: $model.configuration.separatorWidth, in: 40...120, step: 10)
                    Stepper("Контрольный лимит: \(model.configuration.outputSizeLimitMB) МБ", value: $model.configuration.outputSizeLimitMB, in: 1...50)
                }
                Section("Проверка") {
                    Button { showValidation = true } label: { Label("Проверить листинг", systemImage: "checkmark.shield") }
                }
                Section("Экспорт") {
                    Button { model.exportRTF() } label: { Label("Сформировать RTF", systemImage: "doc.text") }.disabled(model.report.files.isEmpty)
                    Text("Courier New · RTF · Unicode-дерево · сквозная нумерация страниц").font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationSplitViewColumnWidth(min: 360, ideal: 400, max: 480)
        } detail: { DetailView(showTree: $showTree) }
        .sheet(isPresented: $showProfileSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Новый профиль").font(.title2.bold())
                TextField("Название профиля", text: $newProfileName)
                HStack {
                    Spacer()
                    Button("Отмена") { showProfileSheet = false }
                    Button("Сохранить") {
                        model.saveProfile(named: newProfileName)
                        newProfileName = ""
                        showProfileSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 420)
        }
        .sheet(isPresented: $showValidation) { ValidationView() }
        .sheet(isPresented: $showRestoreReport) { RestoreReportView() }
        .alert("Ошибка", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct DetailView: View {
    @EnvironmentObject private var model: ListingViewModel
    @Binding var showTree: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Листинг исходного текста").font(.largeTitle.bold())
                    Text("Подготовка материалов проекта для передачи патентной организации").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Дерево", isOn: $showTree).toggleStyle(.switch)
            }
            HStack {
                Metric(title: "Файлов", value: "\(model.report.files.count)")
                Metric(title: "Строк", value: "\(model.report.totalLines)")
                Metric(title: "Размер", value: ByteCountFormatter.string(fromByteCount: model.report.totalBytes, countStyle: .file))
                Metric(title: "Игнорировано", value: "\(model.report.ignoredCount)")
            }
            GroupBox("Статус") {
                HStack {
                    if model.isScanning || model.isRestoring { ProgressView() } else { Image(systemName: "checkmark.circle") }
                    Text(model.status).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(6)
            }
            if showTree && !model.report.files.isEmpty {
                GroupBox("Древовидная структура") {
                    ScrollView {
                        Text(TreeBuilder.build(from: model.report.files))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }.frame(maxHeight: 260)
            }
            GroupBox("SHA-256 исходного набора") {
                Text(model.report.sha256.isEmpty ? "Будет рассчитана после сканирования" : model.report.sha256)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(6)
            }
            if model.configuration.removeComments {
                Label("При экспорте комментарии будут удалены из текста, но оригинальные файлы останутся неизменными.", systemImage: "eraser")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Файлы в логическом порядке").font(.headline)
            List(model.report.files) { file in
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.relativePath).font(.system(.body, design: .monospaced))
                    Text("\(file.language) · \(file.lineCount) строк · \(file.size) байт")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 3)
            }
        }.padding(24)
    }
}

private struct ValidationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: ListingViewModel

    private var checks: [(String, Bool)] {
        [
            ("Корневая папка выбрана", model.selectedFolder != nil),
            ("Название программы заполнено", !model.metadata.programName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ("Автор заполнен", !model.metadata.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ("Правообладатель заполнен", !model.metadata.copyrightHolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ("Организация заполнена", !model.metadata.organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ("Дерево проекта сформировано", !model.report.files.isEmpty),
            ("Относительные пути присутствуют", !model.report.files.contains { $0.relativePath.isEmpty }),
            ("SHA-256 рассчитан", !model.report.sha256.isEmpty)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Проверка листинга").font(.title2.bold())
            ForEach(Array(checks.enumerated()), id: \.offset) { _, item in
                Label(item.0, systemImage: item.1 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            }
            Divider()
            Text("Проверка является технической и не заменяет юридическую проверку комплекта документов.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Закрыть") { dismiss() } }
        }.padding(24).frame(width: 520)
    }
}

private struct RestoreReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: ListingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Отчет восстановления проекта").font(.title2.bold())
            if let report = model.restoreReport {
                Text(report.summary).font(.headline)
                reportGroup("Созданные файлы", report.filesCreated, maxHeight: 180)
                reportGroup("Восстановленные файлы", report.filesReconstructed, maxHeight: 120)
                reportGroup("Измененные файлы", report.filesPatched, maxHeight: 120)
                reportGroup("Удаленные файлы", report.filesDeleted, maxHeight: 100)
                if !report.warnings.isEmpty {
                    GroupBox("Предупреждения") {
                        ScrollView { Text(report.warnings.joined(separator: "\n")).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140)
                    }
                }
            }
            HStack { Spacer(); Button("Закрыть") { dismiss() } }
        }.padding(24).frame(width: 620)
    }

    @ViewBuilder
    private func reportGroup(_ title: String, _ values: [String], maxHeight: CGFloat) -> some View {
        if !values.isEmpty {
            GroupBox(title) {
                ScrollView { Text(values.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: maxHeight)
            }
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
