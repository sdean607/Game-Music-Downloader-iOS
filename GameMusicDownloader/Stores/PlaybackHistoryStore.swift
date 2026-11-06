import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let track: MusicTrack
    let playedAt: Date
}

@MainActor
final class PlaybackHistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("history.json")
    }

    init() { load() }
    func record(_ track: MusicTrack) {
        entries.removeAll { $0.track.id == track.id }
        entries.insert(HistoryEntry(id: UUID(), track: track, playedAt: Date()), at: 0)
        entries = Array(entries.prefix(100))
        save()
    }
    func clear() { entries = []; save() }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = values
    }
    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
