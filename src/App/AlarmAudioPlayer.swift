import AVFoundation
import Foundation

/// In-app playback: previews, and the alarm that comes back when the challenge is
/// left idle. Uses the playback category so it ignores the silent switch.
@MainActor
final class AlarmAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AlarmAudioPlayer()

    @Published private(set) var playingFile: String?
    private var player: AVAudioPlayer?
    private var isRinging = false
    private var lastRingAttempt = Date.distantPast
    private let volume = SystemVolume()

    /// A preview: plays once, at the volume that is set.
    func play(_ file: String) {
        stop()
        start(file, loops: false)
    }

    /// The alarm: loops at full volume until `stop()`. Meant to be called over and over:
    /// if something stopped it (another alarm, a call), it starts again.
    func ring(_ file: String) {
        if isRinging, playingFile == file, player?.isPlaying == true { return }
        let now = Date()
        guard now.timeIntervalSince(lastRingAttempt) >= 1 else { return }
        lastRingAttempt = now
        player?.stop()
        player = nil
        playingFile = nil
        isRinging = true
        start(file, loops: true)
        volume.holdAtMaximum()
    }

    func stop() {
        isRinging = false
        volume.release()
        guard let player else { return }
        player.stop()
        self.player = nil
        playingFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start(_ file: String, loops: Bool) {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loops ? -1 : 0
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            playingFile = file
        } catch {
            player = nil
            playingFile = nil
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            // Only the player that finished: the alarm may have started since.
            if let current = self.player, ObjectIdentifier(current) == finished {
                self.stop()
            }
        }
    }
}
