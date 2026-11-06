import SwiftUI

@main
struct GameMusicDownloaderApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var downloader = DownloadManager()
    @StateObject private var player = MusicPlayer()
    @StateObject private var playlists = PlaylistStore()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var history = PlaybackHistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(downloader)
                .environmentObject(player)
                .environmentObject(playlists)
                .environmentObject(favorites)
                .environmentObject(history)
                .preferredColorScheme(.dark)
        }
    }
}
