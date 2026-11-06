import Foundation

struct ArchiveItem: Codable, Identifiable, Hashable, Sendable {
    let identifier: String
    let title: String?
    let creator: String?
    let licenseurl: String?

    var id: String { identifier }

    private enum CodingKeys: String, CodingKey {
        case identifier, title, creator, licenseurl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        title = container.flexibleString(forKey: .title)
        creator = container.flexibleString(forKey: .creator)
        licenseurl = container.flexibleString(forKey: .licenseurl)
    }
}

struct ArchiveSearchResponse: Decodable {
    let response: ArchiveSearchResults
}

struct ArchiveSearchResults: Decodable {
    let docs: [ArchiveItem]
}

struct ArchiveMetadataResponse: Decodable, Sendable {
    let metadata: ArchiveItemMetadata?
    let files: [ArchiveFile]?
    let error: String?
}

struct ArchiveItemMetadata: Decodable, Sendable {
    let title: String?
    let creator: String?
    let licenseurl: String?
    let rights: String?
    let subject: String?

    private enum CodingKeys: String, CodingKey {
        case title, creator, licenseurl, rights, subject
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.flexibleString(forKey: .title)
        creator = c.flexibleString(forKey: .creator)
        licenseurl = c.flexibleString(forKey: .licenseurl)
        rights = c.flexibleString(forKey: .rights)
        subject = c.flexibleString(forKey: .subject)
    }
}

struct ArchiveFile: Decodable, Sendable {
    let name: String
    let format: String?
    let source: String?
    let size: String?
    let privateFlag: String?
    let md5: String?
    let sha1: String?

    private enum CodingKeys: String, CodingKey {
        case name, format, source, size, md5, sha1
        case privateFlag = "private"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexibleString(forKey: .name) ?? ""
        format = c.flexibleString(forKey: .format)
        source = c.flexibleString(forKey: .source)
        size = c.flexibleString(forKey: .size)
        privateFlag = c.flexibleString(forKey: .privateFlag)
        md5 = c.flexibleString(forKey: .md5)
        sha1 = c.flexibleString(forKey: .sha1)
    }

    var isPrivate: Bool {
        ["true", "1", "yes"].contains(privateFlag?.lowercased() ?? "")
    }

    var isSafeFileName: Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") &&
        name != "." && name != ".." &&
        URL(fileURLWithPath: name).lastPathComponent == name
    }

    var isMP3: Bool {
        isSafeFileName && !isPrivate && source?.lowercased() != "metadata" &&
        name.lowercased().hasSuffix(".mp3")
    }

    var sizeInBytes: Int64? {
        guard let size, let value = Int64(size), value >= 0 else { return nil }
        return value
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        if let values = try? decode([String].self, forKey: key) { return values.joined(separator: ", ") }
        return nil
    }
}
