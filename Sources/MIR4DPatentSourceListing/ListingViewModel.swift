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

    private let scanner = ProjectScanner()
    private let exporter = RTFExporter()
    private let profileStore = ListingProfileStore()

    init() {
        profiles = profileStore.profiles
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Выберите корневую папку проекта"
        panel.message = "Все разрешенные текстовые файлы во вложенных каталогах будут обработаны."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFolder = url
        if metadata.projectName.isEmpty { metadata.projectName = url.lastPathComponent }
        status = "Папка выбрана. Нажмите «Сканировать проект»."
    }

    func scan() {
        guard let folder = selectedFolder else { errorMessage = ScannerError.noFolder.localizedDescription; return }
        isScanning = true
        status = "Сканирование проекта…"
        let scanner = self.scanner
        let configuration = self.configuration

        Task.detached(priority: .userInitiated) {
            do {
                let result = try scanner.scan(root: folder, configuration: configuration)
                await MainActor.run {
                    self.report = result
                    self.status = "Готово: \(result.files.count) исходных файлов, \(result.totalLines) строк."
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.status = "Ошибка сканирования."
                    self.isScanning = false
                }
            }
        }
    }

    func exportRTF() {
        guard !report.files.isEmpty else { errorMessage = "Сначала выполните сканирование проекта."; return }
        let panel = NSSavePanel()
        panel.title = "Сохранить листинг"
        panel.nameFieldStringValue = safeFileName((metadata.projectName.isEmpty ? "Program" : metadata.projectName) + "_Source_Listing.rtf")
        panel.allowedContentTypes = [.rtf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exporter.export(metadata: metadata, report: report, configuration: configuration, to: url)
            status = "RTF сохранен: \(url.lastPathComponent)"
        } catch {
            errorMessage = "Ошибка экспорта: \(error.localizedDescription)"
        }
    }

    func saveProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profileStore.save(ListingProfile(name: trimmed, metadata: metadata))
        profiles = profileStore.profiles
    }

    func loadProfile(_ profile: ListingProfile) {
        metadata = profile.metadata
        status = "Профиль «\(profile.name)» загружен."
    }

    func deleteProfile(_ profile: ListingProfile) {
        profileStore.delete(profile)
        profiles = profileStore.profiles
    }

    private func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    }
}
