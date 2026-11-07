import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [MusicTrack] = []
    @Published var isDownloading = false
    @Published var downloadMessage: String?

    nonisolated static var musicDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("GameMusic", isDirectory: true)
    }
    private var indexURL: URL { Self.musicDirectory.appendingPathComponent("library.json") }

    init() { createDirectory(); load() }
    func contains(_ track: MusicTrack) -> Bool { tracks.contains { $0.id == track.id } && track.isDownloaded }

    var totalStorageBytes: Int64 {
        tracks.reduce(Int64.zero) { total, track in
            guard let url = track.localURL,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize else {
                return total
            }
            return total + Int64(fileSize)
        }
    }

    func add(_ track: MusicTrack) throws {
        guard track.isDownloaded else { throw LibraryStoreError.missingAudioFile }
        guard !tracks.contains(where: { $0.archiveIdentifier == track.archiveIdentifier && $0.filename == track.filename }) else {
            throw LibraryStoreError.duplicateTrack
        }
        var updated = tracks; updated.insert(track, at: 0)
        try persist(updated); tracks = updated
    }

    func delete(_ track: MusicTrack) {
        do { try remove(track) } catch { downloadMessage = error.localizedDescription }
    }
    func remove(_ track: MusicTrack) throws {
        let updated = tracks.filter { $0.id != track.id }
        try persist(updated)
        if let url = track.localURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        tracks = updated
    }
    private func createDirectory() { try? FileManager.default.createDirectory(at: Self.musicDirectory, withIntermediateDirectories: true) }
    private func load() {
        do {
            try createDirectoryThrowing()
            guard FileManager.default.fileExists(atPath: indexURL.path) else { tracks = []; return }
            let saved = try JSONDecoder().decode([MusicTrack].self, from: Data(contentsOf: indexURL))
            let valid = saved.filter { $0.isDownloaded }; tracks = valid
            if valid.count != saved.count { try persist(valid) }
        } catch { downloadMessage = error.localizedDescription }
    }
    private func createDirectoryThrowing() throws { try FileManager.default.createDirectory(at: Self.musicDirectory, withIntermediateDirectories: true) }
    private func persist(_ values: [MusicTrack]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try createDirectoryThrowing(); try encoder.encode(values).write(to: indexURL, options: .atomic)
    }
}

enum LibraryStoreError: LocalizedError {
    case duplicateTrack, missingAudioFile
    var errorDescription: String? {
        switch self {
        case .duplicateTrack: return "Esta música já está na biblioteca."
        case .missingAudioFile: return "O arquivo de áudio não foi encontrado no armazenamento local."
        }
    }
}
