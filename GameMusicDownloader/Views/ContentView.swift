import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Biblioteca", systemImage: "music.note.list") }
            PlaylistsView()
                .tabItem { Label("Playlists", systemImage: "list.bullet") }
            FavoritesView()
                .tabItem { Label("Favoritos", systemImage: "heart.fill") }
            HistoryView()
                .tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
        .tint(Color.purple)
        .safeAreaInset(edge: .bottom) {
            MiniPlayerView()
        }
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.25))
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.purple))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.subheadline.bold()).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.fill") }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                Button { player.next() } label: { Image(systemName: "forward.fill") }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}
