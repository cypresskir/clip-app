import Foundation

struct DownloadHistoryEntry: Codable, Identifiable {
    let id: UUID
    let url: String
    let title: String
    let platform: String
    let filePath: String
    let fileSize: Int64?
    let resolution: String
    let format: String
    let completedAt: Date
    let version: Int

    @MainActor init(from item: DownloadItem, filePath: String) {
        self.id = item.id
        self.url = item.url
        self.title = item.metadata?.title ?? "Unknown"
        self.platform = item.platform.displayName
        self.filePath = filePath
        self.fileSize = item.estimatedFileSize
        self.resolution = item.selectedResolution.displayName
        self.format = item.selectedFormat.rawValue
        self.completedAt = Date()
        self.version = 1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        platform = try container.decode(String.self, forKey: .platform)
        filePath = try container.decode(String.self, forKey: .filePath)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        resolution = try container.decode(String.self, forKey: .resolution)
        format = try container.decode(String.self, forKey: .format)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

@MainActor
class DownloadHistoryStore: ObservableObject {
    @Published var entries: [DownloadHistoryEntry] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipDir = appSupport.appendingPathComponent("Clip", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipDir, withIntermediateDirectories: true)
        self.fileURL = clipDir.appendingPathComponent("history.json")
        load()
    }

    func add(_ entry: DownloadHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > ClipConstants.historyMaxEntries {
            entries = Array(entries.prefix(ClipConstants.historyMaxEntries))
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([DownloadHistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
