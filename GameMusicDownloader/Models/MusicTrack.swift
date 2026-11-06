import Foundation

struct MusicTrack: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(archiveIdentifier)::\(filename)" }
    let title: String
    let artist: String
    let game: String
    let archiveIdentifier: String
    let filename: String
    let license: String?
    let attributionURL: String?

    var localURL: URL? {
        LibraryStore.musicDirectory.appendingPathComponent(filename)
    }

    var isDownloaded: Bool {
        guard let url = localURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

}
