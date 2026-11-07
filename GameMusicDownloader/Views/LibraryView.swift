import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var history: PlaybackHistoryStore

    private var formattedStorage: String {
        ByteCountFormatter.string(fromByteCount: library.totalStorageBytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    EmptyStateView(title: "Sua biblioteca está vazia", message: "Pesquise músicas e baixe arquivos MP3 para ouvir offline.", icon: "music.note.list")
                } else {
                    List {
                        Section {
                            ForEach(library.tracks) { track in
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
                        } header: {
                            HStack(spacing: 8) {
                                Label("\(library.tracks.count) músicas", systemImage: "music.note.list")
                                Spacer()
                                Label(formattedStorage, systemImage: "internaldrive")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .textCase(nil)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Biblioteca")
        }
    }
}
