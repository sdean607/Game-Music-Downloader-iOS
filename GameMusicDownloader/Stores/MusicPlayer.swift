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
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

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
    private var shouldResumeAfterInterruption = false
    private var progressTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    init() {
        configureAudio()
        configureRemoteControls()
        observeAudioSessionChanges()
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
            duration = Double(file.length) / file.processingFormat.sampleRate
            currentTime = 0
            errorMessage = nil

            scheduleSegment(from: 0, startPlayback: true)
        } catch {
            isPlaying = false
            errorMessage = error.localizedDescription
            updateNowPlaying()
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        guard currentTrack != nil else { return }
        playerNode.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack != nil else { return }
        do {
            try activateAudioSessionAndEngine()
            playerNode.play()
            isPlaying = true
            errorMessage = nil
            startProgressTimer()
            updateNowPlaying()
        } catch {
            isPlaying = false
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        playbackGeneration += 1
        progressTimer?.invalidate()
        progressTimer = nil
        playerNode.stop()
        isPlaying = false
        audioFile = nil
        currentTrack = nil
        currentTime = 0
        duration = 0
        updateNowPlaying()
    }

    /// Seeks to a position in seconds. Used by the player UI and lock-screen controls.
    func seek(to time: TimeInterval) {
        guard audioFile != nil, duration > 0 else { return }
        let target = min(max(0, time), duration)
        let shouldResume = isPlaying
        currentTime = target
        scheduleSegment(from: target, startPlayback: shouldResume)
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
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        if isShuffleEnabled && queue.count > 1 {
            let choices = queue.indices.filter { $0 != currentIndex }
            if let choice = choices.randomElement() {
                currentIndex = choice
            }
        } else if currentIndex > 0 {
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
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
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

    private func activateAudioSessionAndEngine() throws {
        try AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func applyEQ() {
        guard equalizer.bands.count == equalizerGains.count else { return }
        for index in equalizerGains.indices {
            equalizer.bands[index].gain = max(-12, min(12, equalizerGains[index]))
        }
    }

    private func scheduleSegment(from time: TimeInterval, startPlayback: Bool) {
        guard let file = audioFile else { return }

        playbackGeneration += 1
        let generation = playbackGeneration
        playerNode.stop()

        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, time) * sampleRate)
        let remainingFrames = max(0, file.length - startFrame)
        guard remainingFrames > 0 else {
            handlePlaybackEnd()
            return
        }

        let frameCount = AVAudioFrameCount(min(remainingFrames, Int64(UInt32.max)))
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.handlePlaybackEnd()
            }
        }

        do {
            try activateAudioSessionAndEngine()
            if startPlayback {
                playerNode.play()
                isPlaying = true
                startProgressTimer()
            } else {
                isPlaying = false
                progressTimer?.invalidate()
                progressTimer = nil
            }
        } catch {
            isPlaying = false
            errorMessage = error.localizedDescription
        }
    }

    private func restartCurrentTrack() {
        guard let track = currentTrack else { return }
        play(track, queue: queue)
    }

    private func handlePlaybackEnd() {
        guard currentTrack != nil else { return }
        progressTimer?.invalidate()
        progressTimer = nil

        if repeatMode == .one {
            restartCurrentTrack()
        } else if currentIndex + 1 < queue.count || repeatMode == .all || isShuffleEnabled {
            next()
        } else {
            currentTime = duration
            isPlaying = false
            updateNowPlaying()
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.currentTime = min(self.currentTime + 0.5, self.duration)
                self.updateNowPlaying()
            }
        }
    }

    private func configureRemoteControls() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
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
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
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
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
    }

    private func observeAudioSessionChanges() {
        let center = NotificationCenter.default

        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(notification)
            }
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioRouteChange(notification)
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            shouldResumeAfterInterruption = isPlaying
            if shouldResumeAfterInterruption {
                pause()
            }
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            let shouldResume = shouldResumeAfterInterruption && options.contains(.shouldResume)
            shouldResumeAfterInterruption = false
            if shouldResume {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else { return }

        if reason == .oldDeviceUnavailable && isPlaying {
            pause()
        }
    }
}
