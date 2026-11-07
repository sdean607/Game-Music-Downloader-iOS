import SwiftUI

struct TrackRow: View {
    let track: MusicTrack
    let onPlay: () -> Void
    let onDownload: () -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        HStack(spacing: 12) {
            GameArtworkView(size: 52, identifier: track.archiveIdentifier, game: track.game)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.subheadline.bold()).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(track.isDownloaded ? "Disponível offline" : "Internet Archive · MP3")
                    .font(.caption2).foregroundStyle(track.isDownloaded ? .green : .secondary)
            }
            Spacer(minLength: 4)
            Button(action: onPlay) { Image(systemName: "play.circle.fill").font(.title2) }
                .disabled(!track.isDownloaded)
            Button(action: onDownload) {
                Image(systemName: track.isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.title2)
            }
            .disabled(track.isDownloaded || library.isDownloading)
            Button { favorites.toggle(track) } label: {
                Image(systemName: favorites.contains(track) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.contains(track) ? .pink : .secondary)
            }
        }
        .padding(.vertical, 5)
        .foregroundStyle(.white)
    }
}


struct GameArtworkView: View {
    let size: CGFloat
    let identifier: String
    let game: String

    private var artworkURL: URL? {
        guard !identifier.isEmpty,
              let baseURL = URL(string: "https://archive.org/services/img") else {
            return nil
        }
        return baseURL.appendingPathComponent(identifier)
    }

    var body: some View {
        AsyncImage(url: artworkURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty, .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.09), style: .continuous))
        .accessibilityLabel("Capa de \(game.isEmpty ? "Game Music" : game)")
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: max(8, size * 0.09), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.85), .indigo.opacity(0.65), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: size * 0.38, weight: .light))
                    .foregroundStyle(.white.opacity(0.92))
            }
    }
}
