import Foundation

struct LicenseAssessment: Equatable, Sendable {
    let canOfferDownload: Bool
    let name: String
    let message: String
    let licenseURL: URL?
    let attributionRequired: Bool
    let shareAlikeRequired: Bool
}

enum LicenseChecker {
    static func assess(searchLicenseURL: String?, metadataLicenseURL: String?) -> LicenseAssessment {
        let search = normalizedLicense(searchLicenseURL)
        let metadata = normalizedLicense(metadataLicenseURL)
        guard let search else { return blocked("Licença ausente ou inválida", "A pesquisa não apresentou uma licença Creative Commons reconhecida.") }
        guard let metadata else { return blocked("Licença não confirmada", "Os metadados completos não apresentam uma licença reconhecida.", search.url) }
        guard search.path == metadata.path else { return blocked("Licenças divergentes", "A licença da pesquisa é diferente da licença dos metadados. O download foi bloqueado.", metadata.url) }

        let path = metadata.path
        if path == "publicdomain/zero/1.0" {
            return accepted("CC0 1.0", "A declaração indica CC0. Verifique a origem do áudio e a titularidade dos direitos.", metadata.url, false, false)
        }
        if path == "publicdomain/mark/1.0" {
            return accepted("Public Domain Mark 1.0", "O item está marcado como domínio público. Confirme se essa classificação é válida na sua jurisdição.", metadata.url, false, false)
        }
        let parts = path.split(separator: "/")
        if parts.count == 3, parts[0] == "licenses" {
            let type = String(parts[1]); let version = String(parts[2])
            guard ["1.0", "2.0", "2.5", "3.0", "4.0"].contains(version) else {
                return blocked("Versão de licença não reconhecida", "Esta versão não está na lista automática de licenças aceitas.", metadata.url)
            }
            if type == "by" {
                return accepted("Creative Commons BY \(version)", "Exige atribuição ao autor, indicação da fonte e link para a licença. Confirme também que o uploader tinha autorização para disponibilizar o áudio.", metadata.url, true, false)
            }
            if type == "by-sa" {
                return accepted("Creative Commons BY-SA \(version)", "Exige atribuição e atenção às condições ShareAlike em eventual adaptação ou redistribuição. Confirme a autorização do uploader.", metadata.url, true, true)
            }
        }
        return blocked("Licença não aceita automaticamente", "A licença está fora da lista permitida nesta versão. O download não será oferecido.", metadata.url)
    }

    private static func accepted(_ name: String, _ message: String, _ url: URL, _ attribution: Bool, _ shareAlike: Bool) -> LicenseAssessment {
        LicenseAssessment(canOfferDownload: true, name: name, message: message, licenseURL: url, attributionRequired: attribution, shareAlikeRequired: shareAlike)
    }
    private static func blocked(_ name: String, _ message: String, _ url: URL? = nil) -> LicenseAssessment {
        LicenseAssessment(canOfferDownload: false, name: name, message: message, licenseURL: url, attributionRequired: false, shareAlikeRequired: false)
    }
    private static func normalizedLicense(_ raw: String?) -> (path: String, url: URL)? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              var c = URLComponents(string: raw), let scheme = c.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = c.host?.lowercased(), ["creativecommons.org", "www.creativecommons.org"].contains(host),
              c.query == nil, c.fragment == nil, c.user == nil, c.password == nil, c.port == nil else { return nil }
        let path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard !path.isEmpty else { return nil }
        c.scheme = "https"; c.host = "creativecommons.org"; c.path = "/\(path)/"
        guard let url = c.url else { return nil }
        return (path, url)
    }
}
