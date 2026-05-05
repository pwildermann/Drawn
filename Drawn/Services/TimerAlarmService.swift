import AudioToolbox
import AVFoundation
import Foundation
import UIKit

/// Bundled **`m4r` / `caf`** loops until the user stops the alarm (`numberOfLoops = -1`).
/// Short **system-sound** fallbacks have no loop API — they repeat on a **2 s** timer until `stop` (not the old 0.8 s staccato).
///
/// Primary tone: **`ios_17_radial.m4r`** in the app bundle (`Drawn/Resources`).
/// Optional fallbacks: `Radar.(m4r|caf|aiff|wav)`. If nothing loads, uses a short system alert (`1005`).
@MainActor
final class TimerAlarmService {
    static let shared = TimerAlarmService()

    private init() {
        prepareBundledAlarmPlaybackIfNeeded()
    }

    private var ringingTimerID: UUID?

    /// Shipped system UI sound (Tri‑tone / SMS 1).
    private static let fallbackTone: SystemSoundID = 1005

    private var bundledAlarmSystemSoundID: SystemSoundID = 0
    private var bundledAlarmPlayer: AVAudioPlayer?

    /// Replays `AudioServicesPlayAlertSound` when not using `AVAudioPlayer` (no built-in loop).
    private var systemSoundLoopTimer: Foundation.Timer?
    /// Repeats vibration while ringing so muted devices still get ongoing haptics in-app.
    private var vibrationLoopTimer: Foundation.Timer?

    func start(for timerID: UUID) {
        stop(for: nil)
        ringingTimerID = timerID
        prepareBundledAlarmPlaybackIfNeeded()
        configureSession()
        startAlarmPlayback()
        startVibrationLoop()
    }

    /// Pass `nil` to stop regardless of which timer is ringing (e.g. app tear-down).
    func stop(for timerID: UUID?) {
        if let id = timerID, ringingTimerID != id { return }
        systemSoundLoopTimer?.invalidate()
        systemSoundLoopTimer = nil
        vibrationLoopTimer?.invalidate()
        vibrationLoopTimer = nil
        bundledAlarmPlayer?.pause()
        bundledAlarmPlayer?.stop()
        bundledAlarmPlayer = nil
        if bundledAlarmSystemSoundID != 0 {
            AudioServicesDisposeSystemSoundID(bundledAlarmSystemSoundID)
            bundledAlarmSystemSoundID = 0
        }
        ringingTimerID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func prepareBundledAlarmPlaybackIfNeeded() {
        guard bundledAlarmSystemSoundID == 0, bundledAlarmPlayer == nil else { return }

        /// `AVAudioPlayer` is audible and stoppable while the **app process is foreground**; when background / locked iOS normally
        /// suppresses playback without `UIBackgroundModes` audio — use `AudioServicesPlayAlertSound` looping there instead.
        let preferAVAudioPlayerPlayback = UIApplication.shared.applicationState == .active

        let candidates: [(String, String)] = [
            ("ios_17_radial", "m4r"),
            ("Radar", "m4r"),
            ("Radar", "caf"),
            ("Radar", "aiff"),
            ("Radar", "wav"),
        ]

        for (base, ext) in candidates {
            guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { continue }

            if preferAVAudioPlayerPlayback {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.numberOfLoops = -1
                    player.prepareToPlay()
                    bundledAlarmPlayer = player
                    return
                }
                var sid: SystemSoundID = 0
                if AudioServicesCreateSystemSoundID(url as CFURL, &sid) == noErr, sid != 0 {
                    bundledAlarmSystemSoundID = sid
                    return
                }
            } else {
                var sid: SystemSoundID = 0
                if AudioServicesCreateSystemSoundID(url as CFURL, &sid) == noErr, sid != 0 {
                    bundledAlarmSystemSoundID = sid
                    return
                }
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.numberOfLoops = -1
                    player.prepareToPlay()
                    bundledAlarmPlayer = player
                    return
                }
            }
        }
    }

    private func startAlarmPlayback() {
        systemSoundLoopTimer?.invalidate()
        systemSoundLoopTimer = nil

        if let player = bundledAlarmPlayer {
            player.stop()
            player.currentTime = 0
            player.play()
            return
        }

        playBundledOrFallbackSystemSound()
        systemSoundLoopTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.playBundledOrFallbackSystemSound()
            }
        }
        if let t = systemSoundLoopTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func startVibrationLoop() {
        vibrationLoopTimer?.invalidate()
        vibrationLoopTimer = nil
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrationLoopTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        if let t = vibrationLoopTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func playBundledOrFallbackSystemSound() {
        if bundledAlarmSystemSoundID != 0 {
            AudioServicesPlayAlertSound(bundledAlarmSystemSoundID)
        } else {
            AudioServicesPlayAlertSound(Self.fallbackTone)
        }
    }
}
