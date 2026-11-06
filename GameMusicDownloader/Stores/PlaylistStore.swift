import Foundation
import Combine

struct MusicPlaylist: Identifiable, Codable {
    let id: UUID
    var name: String
    var trackIDs: [String]
    var createdAt: Date

    init(name: String) {
        id = UUID()
        self.name = name
        trackIDs = []
        createdAt = Date()
    }
}

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [MusicPlaylist] = []
    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("playlists.json")
    }

    init() { load() }

    func create(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        playlists.append(MusicPlaylist(name: clean))
        save()
    }

    func delete(_ playlist: MusicPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func add(_ track: MusicTrack, to playlist: MusicPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[index].trackIDs.contains(track.id) else { return }
        playlists[index].trackIDs.append(track.id)
        save()
    }

    func tracks(in playlist: MusicPlaylist, library: [MusicTrack]) -> [MusicTrack] {
        playlist.trackIDs.compactMap { id in library.first { $0.id == id } }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode([MusicPlaylist].self, from: data) else { return }
        playlists = value
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
