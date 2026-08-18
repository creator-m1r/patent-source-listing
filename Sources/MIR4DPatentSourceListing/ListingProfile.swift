import Foundation

struct ListingProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var metadata: ProgramMetadata

    init(id: UUID = UUID(), name: String, metadata: ProgramMetadata) {
        self.id = id
        self.name = name
        self.metadata = metadata
    }
}

@MainActor
final class ListingProfileStore: ObservableObject {
    @Published private(set) var profiles: [ListingProfile] = []

    private let url: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MIR4DPatentSourceListing", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("profiles.json")
        load()
    }

    func save(_ profile: ListingProfile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        persist()
    }

    func delete(_ profile: ListingProfile) {
        profiles.removeAll { $0.id == profile.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ListingProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
