import AppKit
import AVFoundation

protocol AudioAlertPlaying: AnyObject {
    func play(timer: TimerRecord)
    func stop()
    func setPlaybackFinishedHandler(_ handler: @escaping () -> Void)
}

extension AudioAlertPlaying {
    func setPlaybackFinishedHandler(_ handler: @escaping () -> Void) {}
}

final class AudioAlertPlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate, AudioAlertPlaying {
    /// A looping sound starts again no sooner than this, so a half-second
    /// sound repeats as an alarm and not as a buzz.
    private static let minimumLoopInterval: TimeInterval = 1.25

    private var player: AVAudioPlayer?
    private var loopTimer: Timer?
    private var oneShotCompletionTimer: Timer?
    private var announcementTimer: Timer?
    private var synthesizer: AVSpeechSynthesizer?
    private var isLooping = false
    private var pendingAnnouncement: AVSpeechUtterance?
    /// The name being said after a one-shot sound; the alert is over when
    /// this utterance ends.
    private var closingUtterance: AVSpeechUtterance?
    private var playbackFinishedHandler: (() -> Void)?

    func setPlaybackFinishedHandler(_ handler: @escaping () -> Void) {
        playbackFinishedHandler = handler
    }

    /// What is said after the sound, or nil when the timer does not ask for it.
    static func announcement(for timer: TimerRecord) -> String? {
        guard timer.speaksName == true else { return nil }
        let name = timer.label.split(whereSeparator: \.isNewline).joined(separator: " ")
        return "\(name) finished"
    }

    func play(timer: TimerRecord) {
        stop()

        isLooping = timer.loop
        pendingAnnouncement = Self.announcement(for: timer).map { text in
            let utterance = AVSpeechUtterance(string: text)
            utterance.volume = Float(timer.volume)
            return utterance
        }

        let sound = AlertSound(rawValue: AlertSound.normalizedName(timer.soundName)) ?? .glass
        let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "aiff")
            ?? sound.fileURL
            ?? AlertSound.glass.fileURL
        guard sound != .systemBeep, let url, let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            playSystemBeep()
            return
        }

        newPlayer.delegate = self
        newPlayer.volume = Float(timer.volume)
        if isLooping {
            if newPlayer.duration >= Self.minimumLoopInterval {
                newPlayer.numberOfLoops = -1
            } else {
                repeatWhileLooping { [weak self] in
                    self?.player?.currentTime = 0
                    self?.player?.play()
                }
            }
            // Once the sound has been heard through, and over the loop.
            announce(after: min(max(newPlayer.duration, 0.6), 3))
        }
        newPlayer.prepareToPlay()
        newPlayer.play()
        player = newPlayer
    }

    func stop() {
        oneShotCompletionTimer?.invalidate()
        oneShotCompletionTimer = nil
        loopTimer?.invalidate()
        loopTimer = nil
        announcementTimer?.invalidate()
        announcementTimer = nil
        pendingAnnouncement = nil
        closingUtterance = nil
        isLooping = false
        synthesizer?.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // A short looping sound is played once per pass and kept for the next.
        guard self.player === player, !isLooping else { return }
        self.player = nil
        soundDidFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechEnded(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechEnded(utterance)
    }

    /// The synthesizer does not promise a thread, and a cancelled utterance
    /// can report in after the next alert has started.
    private func speechEnded(_ utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.closingUtterance === utterance else { return }
            self.closingUtterance = nil
            self.playbackFinishedHandler?()
        }
    }

    private func playSystemBeep() {
        NSSound.beep()

        guard isLooping else {
            scheduleOneShotCompletion()
            return
        }
        repeatWhileLooping { NSSound.beep() }
        announce(after: 0.6)
    }

    private func repeatWhileLooping(_ replay: @escaping () -> Void) {
        let timer = Timer(timeInterval: Self.minimumLoopInterval, repeats: true) { _ in replay() }
        loopTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleOneShotCompletion() {
        let timer = Timer(timeInterval: 1.25, repeats: false) { [weak self] _ in
            self?.oneShotCompletionTimer = nil
            self?.soundDidFinish()
        }
        oneShotCompletionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// A one-shot alert is over when its sound ends, or when the name that
    /// follows the sound has been said.
    private func soundDidFinish() {
        guard pendingAnnouncement != nil else {
            playbackFinishedHandler?()
            return
        }
        closingUtterance = pendingAnnouncement
        speakPendingAnnouncement()
    }

    private func announce(after delay: TimeInterval) {
        guard pendingAnnouncement != nil else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.announcementTimer = nil
            self?.speakPendingAnnouncement()
        }
        announcementTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func speakPendingAnnouncement() {
        guard let utterance = pendingAnnouncement else { return }
        pendingAnnouncement = nil
        let synthesizer = self.synthesizer ?? AVSpeechSynthesizer()
        synthesizer.delegate = self
        self.synthesizer = synthesizer
        synthesizer.speak(utterance)
    }
}

/// Plays a sound once as it is picked in an editor, separately from any timer
/// that is ringing.
enum SoundPreview {
    private static var player: AVAudioPlayer?

    static func play(soundName: String, volume: Double) {
        player?.stop()
        player = nil
        let sound = AlertSound(rawValue: AlertSound.normalizedName(soundName)) ?? .glass
        guard let url = sound.fileURL, let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            NSSound.beep()
            return
        }
        newPlayer.volume = Float(min(max(volume, 0), 1))
        newPlayer.play()
        player = newPlayer
    }
}
