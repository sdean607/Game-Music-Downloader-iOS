import SwiftUI

struct TrackRow: View {
    let track: MusicTrack
    let onPlay: () -> Void
    let onDownload: () -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.purple.opacity(0.7), .indigo.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "waveform").font(.title2))
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
