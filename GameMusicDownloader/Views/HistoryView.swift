import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: PlaybackHistoryStore
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    EmptyStateView(title: "Nada reproduzido ainda", message: "As faixas tocadas aparecerão neste histórico.", icon: "clock")
                } else {
                    List(history.entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.track.title).font(.subheadline.bold())
                                Text(entry.track.artist).font(.caption).foregroundStyle(.secondary)
                                Text(entry.playedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                player.play(entry.track)
                            } label: { Image(systemName: "play.circle.fill").font(.title2) }
                            .disabled(!entry.track.isDownloaded)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Histórico")
            .toolbar {
                if !history.entries.isEmpty {
                    Button("Limpar") { history.clear() }
                }
            }
        }
    }
}
