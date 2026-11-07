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
    @State private var showingFullPlayer = false

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                Button {
                    showingFullPlayer = true
                } label: {
                    HStack(spacing: 10) {
                        ArtworkPlaceholder(size: 42, game: track.game)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir player completo")

                Spacer(minLength: 4)
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Faixa anterior")

                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproduzir")

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("Próxima faixa")
            }
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .sheet(isPresented: $showingFullPlayer) {
                FullPlayerView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}

private struct FullPlayerView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dismiss) private var dismiss

    private var progressBinding: Binding<Double> {
        Binding(
            get: { player.currentTime },
            set: { player.seek(to: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let track = player.currentTrack {
                    VStack(spacing: 22) {
                        Spacer(minLength: 8)

                        ArtworkPlaceholder(size: 280, game: track.game)
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 6) {
                            Text(track.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(track.artist)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(track.game)
                                .font(.subheadline)
                                .foregroundStyle(.purple)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 6) {
                            Slider(
                                value: progressBinding,
                                in: 0...max(player.duration, 1)
                            )
                            .tint(.purple)
                            .disabled(player.duration <= 0)

                            HStack {
                                Text(Self.timeString(player.currentTime))
                                Spacer()
                                Text(Self.timeString(player.duration))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)

                        HStack(spacing: 34) {
                            Button {
                                player.setShuffle(!player.isShuffleEnabled)
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.title3)
                                    .foregroundStyle(player.isShuffleEnabled ? .purple : .secondary)
                            }
                            .accessibilityLabel("Aleatório")

                            Button { player.previous() } label: {
                                Image(systemName: "backward.end.fill")
                                    .font(.title2)
                            }
                            .accessibilityLabel("Faixa anterior")

                            Button { player.togglePlayback() } label: {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 66))
                                    .foregroundStyle(.purple)
                            }
                            .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproduzir")

                            Button { player.next() } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.title2)
                            }
                            .accessibilityLabel("Próxima faixa")

                            Button {
                                switch player.repeatMode {
                                case .off: player.repeatMode = .all
                                case .all: player.repeatMode = .one
                                case .one: player.repeatMode = .off
                                }
                            } label: {
                                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                    .font(.title3)
                                    .foregroundStyle(player.repeatMode == .off ? .secondary : .purple)
                            }
                            .accessibilityLabel("Modo de repetição")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)

                        HStack {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: $player.volume, in: 0...1)
                                .tint(.purple)
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)

                        NavigationLink {
                            EqualizerView()
                        } label: {
                            Label("Equalizador de 10 bandas", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.purple)
                        }

                        if let error = player.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        LinearGradient(
                            colors: [Color.purple.opacity(0.22), Color.black, Color.black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note").font(.system(size: 44)).foregroundStyle(.purple)
                        Text("Nenhuma música em reprodução").font(.headline)
                        Text("Escolha uma faixa na biblioteca para começar.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(.purple)
                }
                ToolbarItem(placement: .principal) {
                    Text("TOCANDO AGORA")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(.secondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private static func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct ArtworkPlaceholder: View {
    let size: CGFloat
    let game: String

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.9), .indigo.opacity(0.75), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: size * 0.06) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: size * 0.32, weight: .light))
                    Text(game.isEmpty ? "GAME MUSIC" : game.uppercased())
                        .font(.system(size: max(9, size * 0.055), weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: size, height: size)
            .shadow(color: .purple.opacity(0.25), radius: 24, y: 12)
            .accessibilityLabel("Arte ilustrativa de \(game)")
    }
}
