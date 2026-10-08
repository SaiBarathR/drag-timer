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
    private var soundEndTimer: Timer?
    private var synthesizer: AVSpeechSynthesizer?
    private var sound = AlertSound.glass
    private var volume: Float = 0
    private var isLooping = false
    private var pendingAnnouncement: AVSpeechUtterance?
    /// The name being said; what happens next waits for this utterance.
    private var spokenUtterance: AVSpeechUtterance?
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

    /// How long the system beep is given before anything follows it: the
    /// length of the alert sound chosen in System Settings when that is on
    /// record, and never less than the loop interval.
    static func systemBeepDuration(
        alertSoundPath: String? = UserDefaults.standard.string(forKey: "com.apple.sound.beep.sound")
    ) -> TimeInterval {
        let duration = alertSoundPath.flatMap { NSSound(contentsOfFile: $0, byReference: true)?.duration } ?? 0
        return max(minimumLoopInterval, duration)
    }

    func play(timer: TimerRecord) {
        stop()

        sound = AlertSound(rawValue: AlertSound.normalizedName(timer.soundName)) ?? .glass
        volume = Float(timer.volume)
        isLooping = timer.loop
        pendingAnnouncement = Self.announcement(for: timer).map { text in
            let utterance = AVSpeechUtterance(string: text)
            utterance.volume = volume
            return utterance
        }
        // With a name to say, the sound is heard once, then the name, and
        // only then does a looping alert begin to repeat, so that the name
        // is never said over the sound.
        startSound(repeating: isLooping && pendingAnnouncement == nil)
    }

    func stop() {
        soundEndTimer?.invalidate()
        soundEndTimer = nil
        loopTimer?.invalidate()
        loopTimer = nil
        pendingAnnouncement = nil
        spokenUtterance = nil
        isLooping = false
        synthesizer?.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // A short repeating sound is played once per pass and kept for the next.
        guard self.player === player, loopTimer == nil else { return }
        self.player = nil
        soundDidFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechEnded(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechEnded(utterance)
    }

    private func startSound(repeating: Bool) {
        let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "aiff")
            ?? sound.fileURL
            ?? AlertSound.glass.fileURL
        guard sound != .systemBeep, let url, let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            NSSound.beep()
            let length = Self.systemBeepDuration()
            if repeating {
                repeatSound(every: length) { NSSound.beep() }
            } else {
                endSound(after: length)
            }
            return
        }

        newPlayer.delegate = self
        newPlayer.volume = volume
        if repeating {
            if newPlayer.duration >= Self.minimumLoopInterval {
                newPlayer.numberOfLoops = -1
            } else {
                repeatSound(every: Self.minimumLoopInterval) { [weak self] in
                    self?.player?.currentTime = 0
                    self?.player?.play()
                }
            }
        }
        newPlayer.prepareToPlay()
        newPlayer.play()
        player = newPlayer
    }

    private func repeatSound(every interval: TimeInterval, _ replay: @escaping () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in replay() }
        loopTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The system beep reports nothing when it ends.
    private func endSound(after interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.soundEndTimer = nil
            self?.soundDidFinish()
        }
        soundEndTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The single pass of a sound has ended: say the name if there is one to
    /// say, and otherwise the alert is over.
    private func soundDidFinish() {
        guard let utterance = pendingAnnouncement else {
            playbackFinishedHandler?()
            return
        }
        pendingAnnouncement = nil
        spokenUtterance = utterance
        let synthesizer = self.synthesizer ?? AVSpeechSynthesizer()
        synthesizer.delegate = self
        self.synthesizer = synthesizer
        synthesizer.speak(utterance)
    }

    /// The synthesizer does not promise a thread, and a cancelled utterance
    /// can report in after the next alert has started.
    private func speechEnded(_ utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.spokenUtterance === utterance else { return }
            self.spokenUtterance = nil
            if self.isLooping {
                self.startSound(repeating: true)
            } else {
                self.playbackFinishedHandler?()
            }
        }
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
