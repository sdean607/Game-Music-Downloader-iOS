import Foundation

struct ArchiveCandidate: Identifiable, Sendable {
    let item: ArchiveItem
    let metadata: ArchiveItemMetadata
    let file: ArchiveFile
    let licenseAssessment: LicenseAssessment
    var id: String { "\(item.identifier)::\(file.name)" }
    var displayTitle: String {
        let title = (file.name as NSString).deletingPathExtension
        return title.isEmpty ? file.name : title
    }
    var artist: String {
        if let value = metadata.creator?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        if let value = item.creator?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        return "Desconhecido"
    }
    var gameTitle: String { metadata.title ?? item.title ?? item.identifier }
    var downloadURL: URL? { try? ArchiveAPI.downloadURL(identifier: item.identifier, filename: file.name) }
    var archivePageURL: URL? { ArchiveAPI.itemPageURL(identifier: item.identifier) }
}
