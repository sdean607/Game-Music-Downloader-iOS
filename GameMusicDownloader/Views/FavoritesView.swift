import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var history: PlaybackHistoryStore

    var body: some View {
        NavigationStack {
            let tracks = library.tracks.filter { favorites.contains($0) }
            Group {
                if tracks.isEmpty {
                    EmptyStateView(title: "Sem favoritos", message: "Toque no coração de uma faixa para guardá-la aqui.", icon: "heart")
                } else {
                    List(tracks) { track in
                        TrackRow(track: track, onPlay: {
                            player.play(track, queue: tracks)
                            history.record(track)
                        }, onDownload: {})
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Favoritos")
        }
    }
}
