import Foundation
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(UserMessagingPlatform)
@preconcurrency
import UserMessagingPlatform
#endif

enum AdMobPlacement {
    static let appID = "ca-app-pub-5519379714521588~1987585889"
    private static let productionReaderInterstitialAdUnitID = "ca-app-pub-5519379714521588/6236179434"
    private static let testReaderInterstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    static var readerInterstitialAdUnitID: String {
#if DEBUG
        testReaderInterstitialAdUnitID
#else
        productionReaderInterstitialAdUnitID
#endif
    }

    static let interstitialPageFrequency = 8
    static let interstitialMinIntervalSeconds: TimeInterval = 60
}

@MainActor
final class AdMobManager: NSObject {
    static let shared = AdMobManager()

    private(set) var isConfigured = false
    private var pageAdvancesSinceInterstitial = 0
    private var hasStartedSDK = false
    private var lastInterstitialShownAt: Date?

#if canImport(GoogleMobileAds)
    private var interstitialAd: InterstitialAd?
    private var loadRetryTask: Task<Void, Never>?
    private var loadAttempt = 0
    private var isLoadingInterstitial = false
    private var nextAllowedLoadAt: Date = .distantPast
    private var hasPendingInterstitialSlot = false
#endif

    private override init() {}

    var isSDKAvailable: Bool {
#if canImport(GoogleMobileAds)
        true
#else
        false
#endif
    }

    func configureIfNeeded(presenter: UIViewController? = nil) {
        guard isSDKAvailable, isConfigured == false else { return }
#if canImport(GoogleMobileAds)
        isConfigured = true

#if DEBUG
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["SIMULATOR"]
#endif

#if canImport(UserMessagingPlatform)
        if let presenter {
            requestConsentIfNeeded(from: presenter) { [weak self] in
                guard let self else { return }
                self.startSDKIfNeeded()
                Task { await self.loadInterstitial(force: true) }
            }
        } else {
            // Don't block ad startup on a missing presenter.
            startSDKIfNeeded()
            Task { await loadInterstitial(force: true) }
        }
#else
        startSDKIfNeeded()
        Task { await loadInterstitial(force: true) }
#endif
        log("configureIfNeeded: initialized")
#endif
    }

    func trackPageAdvanceAndPresentIfNeeded(from presenter: UIViewController?) {
        guard isSDKAvailable else { return }
        pageAdvancesSinceInterstitial += 1
        log("trackPageAdvance: count=\(pageAdvancesSinceInterstitial)")
#if canImport(UserMessagingPlatform)
        if let presenter {
            refreshConsentFlowIfNeeded(from: presenter)
        }
#endif
#if canImport(GoogleMobileAds)
        if interstitialAd == nil {
            Task { await loadInterstitial(force: false) }
        }
#endif
        let minTurn = AdMobPlacement.interstitialPageFrequency
        guard pageAdvancesSinceInterstitial >= minTurn else { return }
        if let lastShown = lastInterstitialShownAt {
            let elapsed = Date().timeIntervalSince(lastShown)
            if elapsed < AdMobPlacement.interstitialMinIntervalSeconds {
                log("cooldown active: \(Int(elapsed))s elapsed")
                return
            }
        }
        guard UIApplication.shared.applicationState == .active else {
            log("skip present: app not active")
            return
        }
        guard let presenter else { return }
#if canImport(GoogleMobileAds)
        if interstitialAd == nil {
            if hasPendingInterstitialSlot == false {
                hasPendingInterstitialSlot = true
                log("interstitial pending: waiting for loaded ad")
            }
            Task { await loadInterstitial(force: false) }
            return
        }
        showInterstitialIfReady(from: presenter)
#endif
    }

    func topPresenter() -> UIViewController? {
        UIApplication.topMostViewController()
    }
}

#if canImport(UserMessagingPlatform)
@MainActor
extension AdMobManager {
    private func refreshConsentFlowIfNeeded(from presenter: UIViewController) {
        guard isConfigured else { return }
        let info = ConsentInformation.shared
        guard info.formStatus == .available, info.consentStatus == .required else { return }
        ConsentForm.load { form, _ in
            guard let form else { return }
            form.present(from: presenter) { _ in }
        }
    }

    private func requestConsentIfNeeded(from presenter: UIViewController, completion: @escaping () -> Void) {
        let consentInfo = ConsentInformation.shared
        let params = RequestParameters()
        consentInfo.requestConsentInfoUpdate(with: params) { [weak self] error in
            guard self != nil else { return }
            if error != nil {
                completion()
                return
            }
            if consentInfo.formStatus == .available {
                ConsentForm.load { form, _ in
                    guard let form else {
                        completion()
                        return
                    }
                    if consentInfo.consentStatus == .required {
                        form.present(from: presenter) { _ in completion() }
                    } else {
                        completion()
                    }
                }
            } else {
                completion()
            }
        }
    }
}
#endif

#if canImport(GoogleMobileAds)
@MainActor
extension AdMobManager {
    private func startSDKIfNeeded() {
        guard hasStartedSDK == false else { return }
        hasStartedSDK = true
        MobileAds.shared.start()
    }

    private func scheduleReload() {
        loadRetryTask?.cancel()
        let delay: Int
        switch loadAttempt {
        case 0...1:
            delay = 10
        case 2...3:
            delay = 20
        case 4...6:
            delay = 40
        default:
            delay = 120
        }
        nextAllowedLoadAt = Date().addingTimeInterval(TimeInterval(delay))
        log("scheduleReload: attempt=\(loadAttempt) delay=\(delay)s")
        loadRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            await self.loadInterstitial(force: false)
        }
    }

    private func loadInterstitial(force: Bool) async {
        if force == false {
            if interstitialAd != nil { return }
            if isLoadingInterstitial { return }
            if Date() < nextAllowedLoadAt { return }
        } else if isLoadingInterstitial {
            return
        }

        log("loadInterstitial: force=\(force)")
        isLoadingInterstitial = true
        do {
            interstitialAd = try await InterstitialAd.load(
                with: AdMobPlacement.readerInterstitialAdUnitID,
                request: Request()
            )
            interstitialAd?.fullScreenContentDelegate = self
            loadAttempt = 0
            isLoadingInterstitial = false
            nextAllowedLoadAt = .distantPast
            loadRetryTask?.cancel()
            loadRetryTask = nil
            log("loadInterstitial: success")
            presentPendingInterstitialIfAllowed()
        } catch {
            interstitialAd = nil
            loadAttempt += 1
            isLoadingInterstitial = false
            // Too many failed requests -> apply a hard cooldown to avoid SDK throttle loops.
            if error.localizedDescription.localizedCaseInsensitiveContains("Too many recently failed requests") {
                nextAllowedLoadAt = Date().addingTimeInterval(180)
                log("loadInterstitial: throttle cooldown 180s")
            }
            log("loadInterstitial: failed attempt=\(loadAttempt) error=\(error.localizedDescription)")
            scheduleReload()
        }
    }

    private func showInterstitialIfReady(from presenter: UIViewController) {
        guard let interstitialAd else {
            log("showInterstitialIfReady: not ready")
            Task { await loadInterstitial(force: false) }
            return
        }
        self.interstitialAd = nil
        log("showInterstitialIfReady: presenting")
        interstitialAd.present(from: presenter)
        pageAdvancesSinceInterstitial = 0
        hasPendingInterstitialSlot = false
        lastInterstitialShownAt = Date()
    }

    private func presentPendingInterstitialIfAllowed() {
        guard hasPendingInterstitialSlot || pageAdvancesSinceInterstitial >= AdMobPlacement.interstitialPageFrequency else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        if let lastShown = lastInterstitialShownAt {
            let elapsed = Date().timeIntervalSince(lastShown)
            guard elapsed >= AdMobPlacement.interstitialMinIntervalSeconds else { return }
        }
        guard let presenter = topPresenter() else { return }
        showInterstitialIfReady(from: presenter)
    }
}

@MainActor
extension AdMobManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        log("adDidDismissFullScreenContent")
        Task { await loadInterstitial(force: true) }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        log("didFailToPresentFullScreenContentWithError: \(error.localizedDescription)")
        Task { await loadInterstitial(force: true) }
    }
}
#endif

extension AdMobManager {
    private func log(_ message: String) {
        print("[AdMob] \(message)")
    }
}

extension UIApplication {
    static func topMostViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topMostViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}
