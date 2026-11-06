import Foundation
import Combine
import AVFoundation
import MediaPlayer

@MainActor
final class MusicPlayer: ObservableObject {
    enum RepeatMode: String, CaseIterable, Identifiable {
        case off, all, one
        var id: String { rawValue }
    }

    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published var volume: Float = 0.85 {
        didSet { playerNode.volume = max(0, min(volume, 1)) }
    }
    @Published var equalizerGains: [Float] = Array(repeating: 0, count: 10) {
        didSet { applyEQ() }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffleEnabled = false
    @Published private(set) var errorMessage: String?

    static let equalizerBands: [(frequency: Float, label: String)] = [
        (31, "31 Hz"), (62, "62 Hz"), (125, "125 Hz"),
        (250, "250 Hz"), (500, "500 Hz"), (1_000, "1 kHz"),
        (2_000, "2 kHz"), (4_000, "4 kHz"),
        (8_000, "8 kHz"), (16_000, "16 kHz")
    ]

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var audioFile: AVAudioFile?
    private var queue: [MusicTrack] = []
    private var currentIndex = 0
    private var playbackGeneration = 0
    private var remoteCommandsConfigured = false

    init() {
        configureAudio()
        configureRemoteControls()
    }

    func play(_ track: MusicTrack, queue tracks: [MusicTrack]? = nil) {
        guard let url = track.localURL, track.isDownloaded else {
            errorMessage = "A música ainda não está disponível no armazenamento local."
            return
        }

        do {
            stop()
            if let tracks, !tracks.isEmpty {
                queue = tracks
                currentIndex = tracks.firstIndex(of: track) ?? 0
            } else {
                queue = [track]
                currentIndex = 0
            }

            let file = try AVAudioFile(forReading: url)
            audioFile = file
            currentTrack = track
            errorMessage = nil
            scheduleCurrentFile(file)

            if !engine.isRunning {
                try engine.start()
            }
            playerNode.play()
            isPlaying = true
            updateNowPlaying()
        } catch {
            isPlaying = false
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
            playerNode.play()
            isPlaying = true
            errorMessage = nil
            updateNowPlaying()
        } catch {
            isPlaying = false
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        playbackGeneration += 1
        playerNode.stop()
        isPlaying = false
        audioFile = nil
        currentTrack = nil
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            restartCurrentTrack()
            return
        }

        let nextIndex: Int
        if isShuffleEnabled && queue.count > 1 {
            let choices = queue.indices.filter { $0 != currentIndex }
            guard let choice = choices.randomElement() else { return }
            nextIndex = choice
        } else if currentIndex + 1 < queue.count {
            nextIndex = currentIndex + 1
        } else if repeatMode == .all {
            nextIndex = 0
        } else {
            stop()
            return
        }
        currentIndex = nextIndex
        play(queue[currentIndex], queue: queue)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
        } else {
            restartCurrentTrack()
            return
        }
        play(queue[currentIndex], queue: queue)
    }

    func setRepeat(_ enabled: Bool) {
        repeatMode = enabled ? .all : .off
    }

    func setShuffle(_ enabled: Bool) {
        isShuffleEnabled = enabled
    }

    func setEqualizerGain(_ gain: Float, at index: Int) {
        guard equalizerGains.indices.contains(index) else { return }
        equalizerGains[index] = max(-12, min(12, gain))
    }

    func resetEqualizer() {
        equalizerGains = Array(repeating: 0, count: 10)
    }

    private func configureAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            errorMessage = error.localizedDescription
        }

        engine.attach(playerNode)
        engine.attach(equalizer)
        engine.connect(playerNode, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)

        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Self.equalizerBands[index].frequency
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    private func applyEQ() {
        guard equalizer.bands.count == equalizerGains.count else { return }
        for index in equalizerGains.indices {
            equalizer.bands[index].gain = max(-12, min(12, equalizerGains[index]))
        }
    }

    private func scheduleCurrentFile(_ file: AVAudioFile) {
        playbackGeneration += 1
        let generation = playbackGeneration
        playerNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.handlePlaybackEnd()
            }
        }
    }

    private func restartCurrentTrack() {
        guard let track = currentTrack else { return }
        play(track, queue: queue)
    }

    private func handlePlaybackEnd() {
        guard currentTrack != nil else { return }
        if repeatMode == .one {
            restartCurrentTrack()
        } else if currentIndex + 1 < queue.count || repeatMode == .all {
            next()
        } else {
            isPlaying = false
            updateNowPlaying()
        }
    }

    private func configureRemoteControls() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.game,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
