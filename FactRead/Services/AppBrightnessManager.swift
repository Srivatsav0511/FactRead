import Foundation
import UIKit

@MainActor
final class AppBrightnessManager {
    static let shared = AppBrightnessManager()

    private enum Keys {
        static let preferredAppBrightness = "preferredAppBrightness"
    }

    private var systemBrightnessBeforeOverride: CGFloat?

    var preferredBrightness: CGFloat? {
        get {
            guard UserDefaults.standard.object(forKey: Keys.preferredAppBrightness) != nil else { return nil }
            let value = UserDefaults.standard.double(forKey: Keys.preferredAppBrightness)
            return CGFloat(min(max(value, 0.2), 1.0))
        }
        set {
            if let newValue {
                let clamped = min(max(newValue, 0.2), 1.0)
                UserDefaults.standard.set(Double(clamped), forKey: Keys.preferredAppBrightness)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.preferredAppBrightness)
            }
        }
    }

    var displayedBrightness: CGFloat {
        preferredBrightness ?? UIScreen.main.brightness
    }

    func setPreferredBrightness(_ brightness: CGFloat) {
        preferredBrightness = brightness
        applyForAppIfNeeded()
    }

    func applyForAppIfNeeded() {
        guard let preferred = preferredBrightness else { return }
        if systemBrightnessBeforeOverride == nil {
            systemBrightnessBeforeOverride = UIScreen.main.brightness
        }
        UIScreen.main.brightness = preferred
    }

    func restoreSystemBrightnessIfNeeded() {
        guard let original = systemBrightnessBeforeOverride else { return }
        UIScreen.main.brightness = original
        systemBrightnessBeforeOverride = nil
    }
}
