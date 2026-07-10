import AppKit
import AVFoundation

protocol AudioAlertPlaying: AnyObject {
    func play(timer: TimerRecord)
    func stop()
}

final class AudioAlertPlayer: NSObject, AVAudioPlayerDelegate, AudioAlertPlaying {
    private var player: AVAudioPlayer?
    private var systemBeepTimer: Timer?

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
        }
    }

    func stop() {
        systemBeepTimer?.invalidate()
        systemBeepTimer = nil
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player {
            self.player = nil
        }
    }

    private func playSystemBeep(looping: Bool) {
        NSSound.beep()

        guard looping else { return }
        let timer = Timer(timeInterval: 1.25, repeats: true) { _ in
            NSSound.beep()
        }
        systemBeepTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
