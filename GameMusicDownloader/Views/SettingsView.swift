import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { EqualizerView() } label: {
                    Label("Equalizador", systemImage: "slider.horizontal.3")
                }
                Section("Fonte de áudio") {
                    Label("Internet Archive", systemImage: "globe")
                    Text("O aplicativo pesquisa itens públicos do Internet Archive e procura arquivos MP3 originais.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Aviso de direitos") {
                    Text("A disponibilidade de um arquivo no Internet Archive não significa que ele seja livre de direitos autorais. Verifique a licença e as permissões do titular antes de baixar, compartilhar ou usar qualquer conteúdo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Ajustes")
        }
    }
}
