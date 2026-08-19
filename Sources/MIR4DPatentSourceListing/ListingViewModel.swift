import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ListingViewModel: ObservableObject {
    @Published var metadata = ProgramMetadata()
    @Published var configuration = ListingConfiguration.default
    @Published var selectedFolder: URL?
    @Published var report = ScanReport()
    @Published var isScanning = false
    @Published var status = "Выберите папку проекта."
    @Published var errorMessage: String?
    @Published var profiles: [ListingProfile] = []
    @Published var restoreReport: DiffRestoreReport?

    private let scanner = ProjectScanner()
    private let exporter = RTFExporter()
    private let restorer = DiffProjectRestorer()
    private let profileStore = ListingProfileStore()

    init() { profiles = profileStore.profiles }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.title = "Выберите корневую папку проекта"
        panel.message = "Все разрешенные текстовые файлы во вложенных каталогах будут обработаны."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFolder = url
        if metadata.projectName.isEmpty { metadata.projectName = url.lastPathComponent }
        status = "Папка выбрана. Нажмите «Сканировать проект»."
    }

    func restoreFromDiff() {
        let open = NSOpenPanel(); open.title = "Выберите Git/unified diff"
        open.message = "Будет создана папка проекта и все новые файлы, присутствующие в diff. Для изменяемых файлов нужна исходная папка."
        open.canChooseFiles = true; open.canChooseDirectories = false; open.allowsMultipleSelection = false
        open.allowedContentTypes = [.data]
        guard open.runModal() == .OK, let diffURL = open.url else { return }

        let destinationPanel = NSOpenPanel(); destinationPanel.title = "Выберите папку для восстановления проекта"
        destinationPanel.message = "Выберите родительскую папку. Программа создаст внутри новую папку проекта."
        destinationPanel.canChooseDirectories = true; destinationPanel.canChooseFiles = false; destinationPanel.allowsMultipleSelection = false
        guard destinationPanel.runModal() == .OK, let parent = destinationPanel.url else { return }

        let projectName = diffURL.deletingPathExtension().lastPathComponent.isEmpty ? "RestoredProject" : diffURL.deletingPathExtension().lastPathComponent
        let destination = uniqueDirectory(parent: parent, name: projectName)
        do {
            let result = try restorer.restore(diffURL: diffURL, destination: destination)
            restoreReport = result
            selectedFolder = destination
            metadata.projectName = destination.lastPathComponent
            status = "Восстановление завершено: \(result.summary)."
        } catch { errorMessage = "Ошибка восстановления: \(error.localizedDescription)" }
    }

    func scan() {
        guard let folder = selectedFolder else { errorMessage = ScannerError.noFolder.localizedDescription; return }
        isScanning = true; status = "Сканирование проекта…"
        let scanner = self.scanner; let configuration = self.configuration
        Task.detached(priority: .userInitiated) {
            do {
                let result = try scanner.scan(root: folder, configuration: configuration)
                await MainActor.run { self.report = result; self.status = "Готово: \(result.files.count) исходных файлов, \(result.totalLines) строк."; self.isScanning = false }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription; self.status = "Ошибка сканирования."; self.isScanning = false }
            }
        }
    }

    func exportRTF() {
        guard !report.files.isEmpty else { errorMessage = "Сначала выполните сканирование проекта."; return }
        let panel = NSSavePanel(); panel.title = "Сохранить листинг"
        panel.nameFieldStringValue = safeFileName((metadata.projectName.isEmpty ? "Program" : metadata.projectName) + "_Source_Listing.rtf")
        panel.allowedContentTypes = [.rtf]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try exporter.export(metadata: metadata, report: report, configuration: configuration, to: url); status = "RTF сохранен: \(url.lastPathComponent)" }
        catch { errorMessage = "Ошибка экспорта: \(error.localizedDescription)" }
    }

    func saveProfile(named name: String) { let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { return }; profileStore.save(ListingProfile(name: trimmed, metadata: metadata)); profiles = profileStore.profiles }
    func loadProfile(_ profile: ListingProfile) { metadata = profile.metadata; status = "Профиль «\(profile.name)» загружен." }
    func deleteProfile(_ profile: ListingProfile) { profileStore.delete(profile); profiles = profileStore.profiles }

    private func uniqueDirectory(parent: URL, name: String) -> URL {
        var candidate = parent.appendingPathComponent(name, isDirectory: true); var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) { candidate = parent.appendingPathComponent("\(name)-\(index)", isDirectory: true); index += 1 }
        return candidate
    }

    private func safeFileName(_ value: String) -> String { value.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_") }
}
