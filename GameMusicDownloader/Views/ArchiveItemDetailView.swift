import SwiftUI

@MainActor
struct ArchiveItemDetailView: View {
    let item: ArchiveItem
    @StateObject private var model: ArchiveItemDetailViewModel
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloader: DownloadManager
    @State private var pendingCandidate: ArchiveCandidate?
    @State private var showingConfirmation = false
    @State private var downloadMessage: String?

    init(item: ArchiveItem) {
        self.item = item
        _model = StateObject(wrappedValue: ArchiveItemDetailViewModel(item: item))
    }

    var body: some View {
        List {
            Section("Informações do item") {
                Text(item.title ?? item.identifier)
                Text(item.creator ?? "Autor não informado").foregroundStyle(.secondary)
                Text(item.identifier).font(.caption).foregroundStyle(.secondary)
            }
            if model.isLoading { Section { ProgressView("Consultando arquivos...") } }
            if let error = model.errorMessage {
                Section("Erro") {
                    Text(error).foregroundStyle(.red)
                    Button("Tentar novamente") { Task { await model.reload() } }
                }
            }
            if let info = model.infoMessage { Section { Text(info) } }
            Section("Arquivos MP3") {
                ForEach(model.candidates) { candidate in candidateRow(candidate) }
            }
            if downloader.isDownloading {
                Section("Download") {
                    ProgressView("Baixando para o iPhone...")
                    Button("Cancelar download", role: .destructive) { downloader.cancel() }
                }
            }
            if let message = downloadMessage { Section("Resultado") { Text(message) } }
        }
        .navigationTitle(item.title ?? item.identifier)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .confirmationDialog("Confirme os direitos de uso", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Cancelar", role: .cancel) { pendingCandidate = nil }
            Button("Confirmar e baixar") { downloadPendingCandidate() }
        } message: {
            Text((pendingCandidate?.licenseAssessment.message ?? "") + "\n\nConfirme que verificou a página do item, a licença e que o uploader tinha autorização para disponibilizar este áudio.")
        }
    }

    @ViewBuilder private func candidateRow(_ candidate: ArchiveCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate.displayTitle).font(.headline)
            Text(readableSize(candidate.file.sizeInBytes)).font(.caption).foregroundStyle(.secondary)
            Text(candidate.licenseAssessment.name).font(.subheadline)
            Text(candidate.licenseAssessment.message).font(.caption).foregroundStyle(candidate.licenseAssessment.canOfferDownload ? .secondary : .orange)
            HStack {
                if let url = candidate.licenseAssessment.licenseURL { Link("Abrir licença", destination: url) }
                if let url = candidate.archivePageURL { Link("Página do item", destination: url) }
            }.font(.caption)
            if candidate.licenseAssessment.canOfferDownload {
                Button("Verificar e baixar") { pendingCandidate = candidate; showingConfirmation = true }
                    .buttonStyle(.borderedProminent).disabled(downloader.isDownloading)
            } else {
                Label("Download bloqueado", systemImage: "lock.fill").foregroundStyle(.orange)
            }
        }.padding(.vertical, 6)
    }

    private func readableSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "Tamanho não informado" }
        let formatter = ByteCountFormatter(); formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func downloadPendingCandidate() {
        guard let candidate = pendingCandidate else { return }
        Task {
            do {
                let track = try await downloader.download(candidate, library: library)
                downloadMessage = "Salvo na biblioteca: \(track.title)"
            } catch { downloadMessage = "Não foi possível baixar: \(error.localizedDescription)" }
            pendingCandidate = nil
        }
    }
}
