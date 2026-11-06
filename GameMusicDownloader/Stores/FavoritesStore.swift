import Foundation
import Combine

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var ids: Set<String> = []
    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("favorites.json")
    }

    init() { load() }
    func contains(_ track: MusicTrack) -> Bool { ids.contains(track.id) }
    func toggle(_ track: MusicTrack) {
        if ids.contains(track.id) { ids.remove(track.id) } else { ids.insert(track.id) }
        save()
    }
    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return }
        ids = Set(values)
    }
    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(Array(ids)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
