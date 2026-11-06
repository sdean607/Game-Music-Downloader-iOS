import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Combine

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var statusMessage: String?
    private var activeTask: Task<MusicTrack, Error>?
    private let maximumDownloadBytes: Int64 = 150 * 1024 * 1024

    func download(_ candidate: ArchiveCandidate, library: LibraryStore) async throws -> MusicTrack {
        guard candidate.licenseAssessment.canOfferDownload else { throw DownloadManagerError.licenseBlocked }
        guard candidate.file.isMP3 else { throw DownloadManagerError.invalidMP3 }
        guard let remoteURL = candidate.downloadURL else { throw DownloadManagerError.invalidURL }
        if let size = candidate.file.sizeInBytes, size > maximumDownloadBytes { throw DownloadManagerError.fileTooLarge }
        let duplicate = library.tracks.contains { $0.archiveIdentifier == candidate.item.identifier && $0.title == candidate.displayTitle }
        guard !duplicate else { throw DownloadManagerError.duplicateTrack }

        isDownloading = true; statusMessage = nil
        defer { isDownloading = false; activeTask = nil }
        let task = Task<MusicTrack, Error> {
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw DownloadManagerError.invalidHTTPResponse }
            guard (200...299).contains(http.statusCode) else { throw DownloadManagerError.httpStatus(http.statusCode) }
            let accepted: Set<String> = ["audio/mpeg", "audio/mp3", "audio/x-mpeg", "audio/x-mp3", "application/octet-stream", "binary/octet-stream"]
            if let mime = http.mimeType?.lowercased(), !accepted.contains(mime) { throw DownloadManagerError.invalidContentType(mime) }
            let attrs = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard bytes > 0 else { throw DownloadManagerError.emptyFile }
            guard bytes <= self.maximumDownloadBytes else { throw DownloadManagerError.fileTooLarge }
            try FileManager.default.createDirectory(at: LibraryStore.musicDirectory, withIntermediateDirectories: true)
            let localName = "\(UUID().uuidString)_\(candidate.file.name)"
            let destination = LibraryStore.musicDirectory.appendingPathComponent(localName)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            let track = MusicTrack(title: candidate.displayTitle, artist: candidate.artist, game: candidate.gameTitle,
                                   archiveIdentifier: candidate.item.identifier, filename: localName,
                                   license: candidate.licenseAssessment.licenseURL?.absoluteString,
                                   attributionURL: candidate.archivePageURL?.absoluteString)
            do { try library.add(track) } catch { try? FileManager.default.removeItem(at: destination); throw error }
            return track
        }
        activeTask = task
        do {
            let track = try await task.value
            statusMessage = "Música salva na biblioteca offline."
            return track
        } catch {
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            statusMessage = cancelled ? "Download cancelado." : error.localizedDescription
            throw error
        }
    }
    func cancel() { activeTask?.cancel() }
}

enum DownloadManagerError: LocalizedError {
    case licenseBlocked, invalidMP3, invalidURL, invalidHTTPResponse, httpStatus(Int), invalidContentType(String), emptyFile, fileTooLarge, duplicateTrack
    var errorDescription: String? {
        switch self {
        case .licenseBlocked: return "A licença não permite o download automático."
        case .invalidMP3: return "O arquivo selecionado não é um MP3 válido."
        case .invalidURL: return "O endereço de download é inválido."
        case .invalidHTTPResponse: return "O servidor retornou uma resposta inválida."
        case .httpStatus(let code): return "Falha no download. Código HTTP: \(code)."
        case .invalidContentType(let type): return "O servidor retornou um tipo de arquivo inesperado: \(type)."
        case .emptyFile: return "O arquivo baixado está vazio."
        case .fileTooLarge: return "O arquivo ultrapassa o limite de 150 MB."
        case .duplicateTrack: return "Esta música já está na biblioteca."
        }
    }
}
