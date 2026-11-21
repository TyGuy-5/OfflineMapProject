import Foundation
#if canImport(AudioToolbox)
import AudioToolbox
#endif

/// Service delivering offline audible alerts when a hiker deviates significantly from an active trail.
/// Enforces cooldown throttling (default 30 seconds) and operates 100% offline without cellular or Wi-Fi.
public class TrailAudioAlertService: ObservableObject {
    @Published public var isEnabled: Bool = true
    public var cooldownInterval: TimeInterval = 30.0
    
    public private(set) var lastAlertDate: Date? = nil
    public private(set) var alertCount: Int = 0
    
    /// Optional closure hook for unit testing and audio observation.
    public var onAlertTriggered: ((Double) -> Void)?
    
    public init(isEnabled: Bool = true, cooldownInterval: TimeInterval = 30.0) {
        self.isEnabled = isEnabled
        self.cooldownInterval = cooldownInterval
    }
    
    /// Triggers an off-trail audible warning if alerts are enabled and cooldown has elapsed.
    public func triggerOffTrailAlert(deviation: Double, timestamp: Date = Date()) {
        guard isEnabled else { return }
        
        let now = timestamp
        if let last = lastAlertDate {
            guard now.timeIntervalSince(last) >= cooldownInterval else {
                return
            }
        }
        
        lastAlertDate = now
        alertCount += 1
        
        if let handler = onAlertTriggered {
            handler(deviation)
        } else {
            playAlertSound()
        }
    }
    
    /// Resets the alert cooldown timer, allowing the next deviation to trigger immediately.
    public func resetCooldown() {
        lastAlertDate = nil
    }
    
    /// Plays standard device alert sound using CoreAudio/AudioToolbox system sound ID.
    private func playAlertSound() {
        #if canImport(AudioToolbox)
        AudioServicesPlayAlertSound(1005)
        #endif
    }
}
