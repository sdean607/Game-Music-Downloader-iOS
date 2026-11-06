import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var library: LibraryStore
    @State private var newName = ""
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlists.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(playlist.name).font(.headline)
                                Text("\(playlist.trackIDs.count) faixas").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "music.note.list").foregroundStyle(.purple)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) { playlists.delete(playlist) } label: {
                            Label("Excluir", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Playlists")
            .toolbar {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
            }
            .alert("Nova playlist", isPresented: $showingCreate) {
                TextField("Nome", text: $newName)
                Button("Cancelar", role: .cancel) { newName = "" }
                Button("Criar") {
                    playlists.create(name: newName)
                    newName = ""
                }
            }
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: MusicPlaylist
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var history: PlaybackHistoryStore

    var body: some View {
        let tracks = playlists.tracks(in: playlist, library: library.tracks)
        List(tracks) { track in
            TrackRow(track: track, onPlay: {
                player.play(track, queue: tracks)
                history.record(track)
            }, onDownload: {})
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(playlist.name)
    }
}
