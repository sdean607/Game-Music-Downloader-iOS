import Foundation
import Combine

@MainActor
final class ArchiveItemDetailViewModel: ObservableObject {
    let item: ArchiveItem
    @Published private(set) var candidates: [ArchiveCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var infoMessage: String?
    private var hasLoaded = false

    init(item: ArchiveItem) { self.item = item }

    func load() async {
        guard !isLoading && !hasLoaded else { return }
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        do {
            let response = try await ArchiveAPI.getMetadata(identifier: item.identifier)
            guard let metadata = response.metadata else {
                throw ArchiveAPIError.itemNotFound
            }
            let assessment = LicenseChecker.assess(searchLicenseURL: item.licenseurl, metadataLicenseURL: metadata.licenseurl)
            let files = (response.files ?? []).filter { $0.isMP3 }
            candidates = files.map { ArchiveCandidate(item: item, metadata: metadata, file: $0, licenseAssessment: assessment) }
            if files.isEmpty { infoMessage = "Este item não possui arquivos MP3 disponíveis para download." }
            hasLoaded = true
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() async { hasLoaded = false; await load() }
}
