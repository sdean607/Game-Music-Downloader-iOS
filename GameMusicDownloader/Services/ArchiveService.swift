import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Compatibility facade used by the app's search screen.
final class ArchiveService {
    func search(query: String) async throws -> [ArchiveItem] {
        try await ArchiveAPI.search(query)
    }
}

enum ArchiveAPIError: LocalizedError {
    case invalidURL, invalidIdentifier, invalidResponse, httpStatus(Int), itemNotFound, serverMessage(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Não foi possível criar o endereço da solicitação."
        case .invalidIdentifier: return "Identificador inválido do Internet Archive."
        case .invalidResponse: return "Resposta inválida do servidor."
        case .httpStatus(let code): return "O servidor retornou o erro HTTP \(code)."
        case .itemNotFound: return "Os metadados desse item não foram encontrados."
        case .serverMessage(let message): return message
        }
    }
}

enum ArchiveAPI {
    static func search(_ term: String) async throws -> [ArchiveItem] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let lucene = "mediatype:audio AND (title:\"\(escaped)\" OR subject:\"\(escaped)\") AND licenseurl:*"
        var c = URLComponents(); c.scheme = "https"; c.host = "archive.org"; c.path = "/advancedsearch.php"
        var items = [URLQueryItem(name: "q", value: lucene), URLQueryItem(name: "rows", value: "30"), URLQueryItem(name: "output", value: "json")]
        for field in ["identifier", "title", "creator", "licenseurl"] { items.append(URLQueryItem(name: "fl[]", value: field)) }
        c.queryItems = items
        guard let url = c.url else { throw ArchiveAPIError.invalidURL }
        let data = try await requestData(from: url)
        return try JSONDecoder().decode(ArchiveSearchResponse.self, from: data).response.docs
    }

    static func getMetadata(identifier: String) async throws -> ArchiveMetadataResponse {
        guard isValidIdentifier(identifier) else { throw ArchiveAPIError.invalidIdentifier }
        guard let base = URL(string: "https://archive.org/metadata") else { throw ArchiveAPIError.invalidURL }
        let data = try await requestData(from: base.appendingPathComponent(identifier))
        let response = try JSONDecoder().decode(ArchiveMetadataResponse.self, from: data)
        if let error = response.error, !error.isEmpty { throw ArchiveAPIError.serverMessage(error) }
        guard response.metadata != nil else { throw ArchiveAPIError.itemNotFound }
        return response
    }

    static func downloadURL(identifier: String, filename: String) throws -> URL {
        guard isValidIdentifier(identifier) else { throw ArchiveAPIError.invalidIdentifier }
        let safe = !filename.isEmpty && !filename.contains("/") && !filename.contains("\\") && URL(fileURLWithPath: filename).lastPathComponent == filename
        guard safe, let base = URL(string: "https://archive.org/download") else { throw ArchiveAPIError.invalidURL }
        return base.appendingPathComponent(identifier).appendingPathComponent(filename)
    }

    static func itemPageURL(identifier: String) -> URL? {
        guard isValidIdentifier(identifier), let base = URL(string: "https://archive.org/details") else { return nil }
        return base.appendingPathComponent(identifier)
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\")
    }

    private static func requestData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ArchiveAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ArchiveAPIError.httpStatus(http.statusCode) }
        return data
    }
}
