import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [ArchiveItem] = []
    @State private var searching = false
    @State private var errorMessage: String?
    private let service = ArchiveService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GAME MUSIC").font(.system(size: 12, weight: .black, design: .rounded)).tracking(3).foregroundStyle(.purple)
                    Text("Sua trilha sonora,\nsem limites.").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Pesquise itens no Internet Archive. Os arquivos e as licenças serão conferidos antes de oferecer o download.").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Nome do jogo, trilha ou artista", text: $query).submitLabel(.search).onSubmit { Task { await search() } }
                    Button { Task { await search() } } label: { Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(.purple) }
                        .disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(13).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                if searching { ProgressView("Pesquisando no Internet Archive...").tint(.purple) }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                List(results) { item in
                    NavigationLink {
                        ArchiveItemDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title ?? item.identifier).font(.headline)
                            Text(item.creator ?? "Autor não informado").font(.caption).foregroundStyle(.secondary)
                            Text("Consultar arquivos e licença").font(.caption2).foregroundStyle(.purple)
                        }.padding(.vertical, 4)
                    }.listRowBackground(Color.clear)
                }.listStyle(.plain)
            }.padding(.horizontal).background(Color.black.ignoresSafeArea())
                .navigationTitle("Game Music Downloader").navigationBarTitleDisplayMode(.inline)
        }
    }

    @MainActor private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { errorMessage = "Digite o nome de um jogo ou música."; return }
        searching = true; errorMessage = nil
        defer { searching = false }
        do {
            results = try await service.search(query: term)
            if results.isEmpty { errorMessage = "Nenhum item compatível foi encontrado. Tente outro termo." }
        } catch { results = []; errorMessage = error.localizedDescription }
    }
}
