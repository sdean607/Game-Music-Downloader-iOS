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
                        GameArtworkView(size: 42, identifier: track.archiveIdentifier, game: track.game)
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

    var body: some View {
        NavigationStack {
            Group {
                if let track = player.currentTrack {
                    playerContent(for: track)
                } else {
                    emptyState
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fechar") { dismiss() }.foregroundStyle(.purple)
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

    private func playerContent(for track: MusicTrack) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            GameArtworkView(size: 260, identifier: track.archiveIdentifier, game: track.game)
                .frame(maxWidth: .infinity)
            trackInformation(track)
            progressSection
            transportControls
            volumeControl
            equalizerLink
            errorLabel
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(playerBackground)
    }

    private func trackInformation(_ track: MusicTrack) -> some View {
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
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(.purple)
            .disabled(player.duration <= 0)

            HStack {
                Text(timeString(player.currentTime))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            shuffleButton
            previousButton
            playPauseButton
            nextButton
            repeatButton
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var shuffleButton: some View {
        Button {
            player.setShuffle(!player.isShuffleEnabled)
        } label: {
            Image(systemName: "shuffle")
                .font(.title3)
                .foregroundStyle(player.isShuffleEnabled ? .purple : .secondary)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Aleatório")
    }

    private var previousButton: some View {
        Button { player.previous() } label: {
            Image(systemName: "backward.end.fill")
                .font(.title2)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Faixa anterior")
    }

    private var playPauseButton: some View {
        Button { player.togglePlayback() } label: {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 62))
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproduzir")
    }

    private var nextButton: some View {
        Button { player.next() } label: {
            Image(systemName: "forward.end.fill")
                .font(.title2)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Próxima faixa")
    }

    private var repeatButton: some View {
        Button {
            switch player.repeatMode {
            case .off: player.repeatMode = .all
            case .all: player.repeatMode = .one
            case .one: player.repeatMode = .off
            }
        } label: {
            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                .font(.title3)
                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.purple)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Modo de repetição")
    }

    private var volumeControl: some View {
        HStack {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: $player.volume, in: 0...1).tint(.purple)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var equalizerLink: some View {
        NavigationLink {
            EqualizerView()
        } label: {
            Label("Equalizador de 10 bandas", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let error = player.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 44))
                .foregroundStyle(.purple)
            Text("Nenhuma música em reprodução").font(.headline)
            Text("Escolha uma faixa na biblioteca para começar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private var playerBackground: some View {
        LinearGradient(
            colors: [Color.purple.opacity(0.22), Color.black, Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
