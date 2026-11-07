import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Combine

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64?

    private var activeTask: Task<MusicTrack, Error>?
    private var activeDownload: DownloadProgressDelegate?
    private let maximumDownloadBytes: Int64 = 150 * 1024 * 1024

    func download(_ candidate: ArchiveCandidate, library: LibraryStore) async throws -> MusicTrack {
        guard !isDownloading else { throw DownloadManagerError.downloadAlreadyRunning }
        guard candidate.licenseAssessment.canOfferDownload else { throw DownloadManagerError.licenseBlocked }
        guard candidate.file.isMP3 else { throw DownloadManagerError.invalidMP3 }
        guard let remoteURL = candidate.downloadURL else { throw DownloadManagerError.invalidURL }
        if let size = candidate.file.sizeInBytes, size > maximumDownloadBytes { throw DownloadManagerError.fileTooLarge }
        let duplicate = library.tracks.contains { $0.archiveIdentifier == candidate.item.identifier && $0.title == candidate.displayTitle }
        guard !duplicate else { throw DownloadManagerError.duplicateTrack }

        isDownloading = true
        statusMessage = "Preparando download..."
        progress = 0
        downloadedBytes = 0
        expectedBytes = candidate.file.sizeInBytes
        defer {
            isDownloading = false
            activeTask = nil
            activeDownload = nil
        }

        let delegate = DownloadProgressDelegate()
        activeDownload = delegate
        delegate.onProgress = { [weak self] received, expected in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.downloadedBytes = received
                if expected > 0 { self.expectedBytes = expected }
                if let total = self.expectedBytes, total > 0 {
                    self.progress = min(Double(received) / Double(total), 1)
                }
                self.statusMessage = "Baixando música..."
            }
        }

        let task = Task<MusicTrack, Error> {
            let (temporaryURL, response) = try await withTaskCancellationHandler {
                try await delegate.download(from: remoteURL)
            } onCancel: {
                delegate.cancel()
            }
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
            do { try library.add(track) } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            return track
        }

        activeTask = task
        do {
            let track = try await task.value
            progress = 1
            if expectedBytes == nil { expectedBytes = downloadedBytes }
            statusMessage = "Música salva na biblioteca offline."
            return track
        } catch {
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            statusMessage = cancelled ? "Download cancelado." : error.localizedDescription
            throw error
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeDownload?.cancel()
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Int64, Int64) -> Void)?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var session: URLSession?

    func download(from url: URL) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            self.continuation = continuation
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
            session?.downloadTask(with: url).resume()
        }
    }

    func cancel() {
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            let savedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("GameMusic-\(UUID().uuidString).mp3")
            try FileManager.default.moveItem(at: location, to: savedURL)
            guard let response = downloadTask.response else {
                throw DownloadManagerError.invalidHTTPResponse
            }
            continuation?.resume(returning: (savedURL, response))
            continuation = nil
            session.finishTasksAndInvalidate()
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
        session.invalidateAndCancel()
    }
}

enum DownloadManagerError: LocalizedError {
    case licenseBlocked, invalidMP3, invalidURL, invalidHTTPResponse, httpStatus(Int)
    case invalidContentType(String), emptyFile, fileTooLarge, duplicateTrack, downloadAlreadyRunning

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
        case .downloadAlreadyRunning: return "Já existe um download em andamento."
        }
    }
}
