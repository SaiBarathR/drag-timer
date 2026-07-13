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

final class AudioAlertPlayer: NSObject, AVAudioPlayerDelegate, AudioAlertPlaying {
    private var player: AVAudioPlayer?
    private var systemBeepTimer: Timer?
    private var oneShotCompletionTimer: Timer?
    private var playbackFinishedHandler: (() -> Void)?

    func setPlaybackFinishedHandler(_ handler: @escaping () -> Void) {
        playbackFinishedHandler = handler
    }

    func play(timer: TimerRecord) {
        stop()

        if AlertSound.normalizedName(timer.soundName) == AlertSound.systemBeep.rawValue {
            playSystemBeep(looping: timer.loop)
            return
        }

        let bundledURL = Bundle.main.url(forResource: timer.soundName, withExtension: "aiff")
        let systemURL = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        let fallbackURL = FileManager.default.fileExists(atPath: systemURL.path) ? systemURL : nil

        guard let url = bundledURL ?? fallbackURL else {
            NSSound.beep()
            if !timer.loop { scheduleOneShotCompletion() }
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.volume = Float(timer.volume)
            newPlayer.numberOfLoops = timer.loop ? -1 : 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            NSSound.beep()
            if !timer.loop { scheduleOneShotCompletion() }
        }
    }

    func stop() {
        oneShotCompletionTimer?.invalidate()
        oneShotCompletionTimer = nil
        systemBeepTimer?.invalidate()
        systemBeepTimer = nil
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player {
            self.player = nil
            playbackFinishedHandler?()
        }
    }

    private func playSystemBeep(looping: Bool) {
        NSSound.beep()

        guard looping else {
            scheduleOneShotCompletion()
            return
        }
        let timer = Timer(timeInterval: 1.25, repeats: true) { _ in
            NSSound.beep()
        }
        systemBeepTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleOneShotCompletion() {
        let timer = Timer(timeInterval: 1.25, repeats: false) { [weak self] _ in
            self?.oneShotCompletionTimer = nil
            self?.playbackFinishedHandler?()
        }
        oneShotCompletionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
