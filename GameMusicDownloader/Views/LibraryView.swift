import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var history: PlaybackHistoryStore

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    EmptyStateView(title: "Sua biblioteca está vazia", message: "Pesquise músicas e baixe arquivos MP3 para ouvir offline.", icon: "music.note.list")
                } else {
                    List(library.tracks) { track in
                        TrackRow(track: track, onPlay: {
                            player.play(track, queue: library.tracks)
                            history.record(track)
                        }, onDownload: {})
                        .swipeActions {
                            Button(role: .destructive) { library.delete(track) } label: {
                                Label("Excluir", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Biblioteca")
        }
    }
}
