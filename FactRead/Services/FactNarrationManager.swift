import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

private enum NarrationPersona: String {
    case automatic = "voice.auto"
    case male = "voice.male"
    case female = "voice.female"
}

struct NarrationVoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let languageCode: String
    let qualityLabel: String
}

@MainActor
@Observable
final class FactNarrationManager: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    enum PageTurnDirection {
        case next
        case previous
    }

    static let shared = FactNarrationManager()

    var isSpeaking = false
    var isPaused = false
    var currentFactID: UUID?
    var currentTitle: String = ""
    var currentCategory: String = ""
    var isAutoPageTransitioning = false

    var onAutoAdvanceToNext: (() -> (fact: Fact, pageNumber: Int)?)?
    var onAutoAdvanceToPrevious: (() -> (fact: Fact, pageNumber: Int)?)?

    private let synthesizer = AVSpeechSynthesizer()
    private var currentText: String = ""
    private var currentLanguageCode: String = "en"
    private var selectedVoiceIdentifier: String?
    private var remoteConfigured = false
    private var playbackTimer: Timer?
    private var startedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var estimatedDuration: TimeInterval = 0
    private var playbackElapsedLive: TimeInterval = 0
    private var notificationObservers: [NSObjectProtocol] = []
    private var suppressNextCancelReset = false
    private var transitionResetTask: Task<Void, Never>?
    private var currentNarrationSessionID: UUID?
    private var expectedUtteranceCount = 0
    private var completedUtteranceCount = 0
    private var utteranceSessionByObjectID: [ObjectIdentifier: UUID] = [:]

    private let baseNarrationRate: Float = 0.46

    var hasActiveSession: Bool {
        currentFactID != nil
    }

    var playbackProgress: Double {
        guard estimatedDuration > 0 else { return 0 }
        return min(max(playbackElapsedLive / estimatedDuration, 0), 1)
    }

    var playbackElapsed: TimeInterval {
        min(max(playbackElapsedLive, 0), max(estimatedDuration, 0))
    }

    var playbackDuration: TimeInterval {
        max(estimatedDuration, 0)
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioLifecycleObservers()
    }

    func play(fact: Fact, pageNumber: Int?, languageCode: String, voiceIdentifier: String?) {
        configureAudioSessionIfNeeded()
        configureRemoteCommandsIfNeeded()
        let resolvedVoiceIdentifier = normalizedVoiceIdentifier(voiceIdentifier)
        let resolvedLanguageCode = AppLanguage.canonicalLanguageCode(languageCode)

        currentFactID = fact.id
        currentTitle = fact.title
        currentCategory = fact.category
        currentLanguageCode = resolvedLanguageCode
        selectedVoiceIdentifier = resolvedVoiceIdentifier
        currentText = narrationText(for: fact, pageNumber: pageNumber)

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        accumulatedElapsed = 0
        startedAt = Date()
        estimatedDuration = estimateDuration(for: currentText, voiceIdentifier: resolvedVoiceIdentifier)
        playbackElapsedLive = 0

        let utterances = makeNarrationUtterances(
            text: currentText,
            languageCode: resolvedLanguageCode,
            voiceIdentifier: resolvedVoiceIdentifier
        )
        beginNarrationSession(with: utterances)
        for utterance in utterances {
            synthesizer.speak(utterance)
        }

        isSpeaking = true
        isPaused = false
        startNowPlayingProgressTimer()
        updateNowPlayingInfo(playbackRate: 1.0)
    }

    func playPreview(voiceIdentifier: String?, languageCode: String, sampleText: String) {
        configureAudioSessionIfNeeded()
        let resolvedVoiceIdentifier = normalizedVoiceIdentifier(voiceIdentifier)
        let resolvedLanguageCode = AppLanguage.canonicalLanguageCode(languageCode)
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        currentFactID = nil
        currentTitle = ""
        currentCategory = ""
        currentText = ""
        currentLanguageCode = resolvedLanguageCode
        selectedVoiceIdentifier = resolvedVoiceIdentifier

        let utterance = AVSpeechUtterance(string: normalizedSpokenText(sampleText, newlineSeparator: ". "))
        utterance.voice = preferredVoice(for: resolvedLanguageCode, identifier: resolvedVoiceIdentifier)
        let tuning = voiceTuning(for: resolvedVoiceIdentifier)
        utterance.rate = narrationRate(for: resolvedVoiceIdentifier)
        utterance.pitchMultiplier = tuning.pitch
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)

        isSpeaking = true
        isPaused = false
    }

    func togglePlayPause(currentFact: Fact?, currentPageNumber: Int?, languageCode: String, voiceIdentifier: String?) {
        let resolvedVoiceIdentifier = normalizedVoiceIdentifier(voiceIdentifier)
        if synthesizer.isSpeaking {
            let paused = synthesizer.pauseSpeaking(at: .word)
            if paused {
                isPaused = true
                accumulatedElapsed = elapsedPlayback
                playbackElapsedLive = accumulatedElapsed
                startedAt = nil
                stopNowPlayingProgressTimer()
                updateNowPlayingInfo(playbackRate: 0.0)
            }
            return
        }

        if synthesizer.isPaused {
            let resumed = synthesizer.continueSpeaking()
            if resumed {
                isPaused = false
                isSpeaking = true
                startedAt = Date()
                playbackElapsedLive = accumulatedElapsed
                startNowPlayingProgressTimer()
                updateNowPlayingInfo(playbackRate: 1.0)
                return
            }

            // Recovery path: if continue fails but user tapped play, restart current fact.
            if let currentFact {
                play(
                    fact: currentFact,
                    pageNumber: currentPageNumber,
                    languageCode: languageCode,
                    voiceIdentifier: resolvedVoiceIdentifier
                )
            } else {
                resetSessionState()
            }
            return
        }

        if let currentFact {
            play(
                fact: currentFact,
                pageNumber: currentPageNumber,
                languageCode: languageCode,
                voiceIdentifier: resolvedVoiceIdentifier
            )
        }
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resetSessionState()
    }

    func seek(to progress: Double) {
        guard hasActiveSession else { return }
        guard currentText.isEmpty == false else { return }

        let clamped = min(max(progress, 0), 1)
        restartUtterance(atProgress: clamped, preservePausedState: isPaused)
    }

    func availableVoices(for languageCode: String) -> [NarrationVoiceOption] {
        let canonicalCode = AppLanguage.canonicalLanguageCode(languageCode)
        let systemVoice = preferredVoice(for: canonicalCode, identifier: NarrationPersona.automatic.rawValue)
        let primaryLanguage = systemVoice?.language ?? canonicalCode
        return [
            NarrationVoiceOption(
                id: NarrationPersona.automatic.rawValue,
                name: "Device Voice",
                languageCode: primaryLanguage,
                qualityLabel: systemVoice.map { qualityText(for: $0.quality) } ?? "Default"
            )
        ]
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Do not auto-turn pages on completion; keep narration scoped to current fact.
        guard isAutoPageTransitioning == false else { return }
        let utteranceID = ObjectIdentifier(utterance)
        guard let sessionID = utteranceSessionByObjectID.removeValue(forKey: utteranceID),
              sessionID == currentNarrationSessionID else {
            resetSessionState()
            return
        }

        completedUtteranceCount += 1
        if completedUtteranceCount >= expectedUtteranceCount {
            resetSessionState()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if suppressNextCancelReset {
            suppressNextCancelReset = false
            return
        }
        resetSessionState()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        isPaused = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        isPaused = true
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        isPaused = false
        isSpeaking = true
    }

    @discardableResult
    func requestManualPageTurn(_ direction: PageTurnDirection) -> Bool {
        guard hasActiveSession else { return false }
        guard isAutoPageTransitioning == false else { return false }
        let next: (fact: Fact, pageNumber: Int)?
        switch direction {
        case .next:
            next = onAutoAdvanceToNext?()
        case .previous:
            next = onAutoAdvanceToPrevious?()
        }

        guard let next else { return false }
        let wasPaused = isPaused
        beginPageTransition()
        suppressNextCancelReset = true
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        play(
            fact: next.fact,
            pageNumber: next.pageNumber,
            languageCode: currentLanguageCode,
            voiceIdentifier: selectedVoiceIdentifier
        )
        if wasPaused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                guard let self else { return }
                guard self.synthesizer.isSpeaking else { return }
                self.synthesizer.pauseSpeaking(at: .word)
                self.isPaused = true
                self.accumulatedElapsed = self.elapsedPlayback
                self.startedAt = nil
                self.stopNowPlayingProgressTimer()
                self.updateNowPlayingInfo(playbackRate: 0.0)
            }
        }
        scheduleTransitionReset()
        return true
    }

    private func resetSessionState() {
        transitionResetTask?.cancel()
        transitionResetTask = nil
        suppressNextCancelReset = false
        currentNarrationSessionID = nil
        expectedUtteranceCount = 0
        completedUtteranceCount = 0
        utteranceSessionByObjectID.removeAll()
        isSpeaking = false
        isPaused = false
        isAutoPageTransitioning = false
        currentFactID = nil
        currentTitle = ""
        currentCategory = ""
        currentText = ""
        selectedVoiceIdentifier = nil
        startedAt = nil
        accumulatedElapsed = 0
        estimatedDuration = 0
        playbackElapsedLive = 0
        stopNowPlayingProgressTimer()
        clearNowPlayingInfo()
        deactivateAudioSession()
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Best-effort deactivation only.
        }
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    private func beginPageTransition() {
        transitionResetTask?.cancel()
        transitionResetTask = nil
        isAutoPageTransitioning = true
    }

    private func scheduleTransitionReset(after delay: Duration = .milliseconds(280)) {
        transitionResetTask?.cancel()
        transitionResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard Task.isCancelled == false else { return }
            self?.isAutoPageTransitioning = false
            self?.transitionResetTask = nil
        }
    }

    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothHFP, .duckOthers])
            try session.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            // Keep app usable even if session activation fails.
        }
    }

    private func configureAudioLifecycleObservers() {
        let center = NotificationCenter.default

        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let info = notification.userInfo
                let rawType = info?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0

                Task { @MainActor [weak self, rawType, optionsRaw] in
                    guard let self else { return }
                    guard
                        let rawType,
                        let type = AVAudioSession.InterruptionType(rawValue: rawType)
                    else { return }

                    switch type {
                    case .began:
                        if self.synthesizer.isSpeaking {
                            self.synthesizer.pauseSpeaking(at: .word)
                            self.isPaused = true
                            self.accumulatedElapsed = self.elapsedPlayback
                            self.playbackElapsedLive = self.accumulatedElapsed
                            self.startedAt = nil
                            self.stopNowPlayingProgressTimer()
                            self.updateNowPlayingInfo(playbackRate: 0.0)
                        }
                    case .ended:
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                        if options.contains(.shouldResume), self.synthesizer.isPaused {
                            self.synthesizer.continueSpeaking()
                            self.isPaused = false
                            self.isSpeaking = true
                            self.startedAt = Date()
                            self.playbackElapsedLive = self.accumulatedElapsed
                            self.startNowPlayingProgressTimer()
                            self.updateNowPlayingInfo(playbackRate: 1.0)
                        }
                    @unknown default:
                        break
                    }
                }
            }
        )
    }

    private func configureRemoteCommandsIfNeeded() {
        guard remoteConfigured == false else { return }
        remoteConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.synthesizer.isPaused {
                let resumed = self.synthesizer.continueSpeaking()
                guard resumed else { return .commandFailed }
                self.isPaused = false
                self.isSpeaking = true
                self.startedAt = Date()
                self.playbackElapsedLive = self.accumulatedElapsed
                self.startNowPlayingProgressTimer()
                self.updateNowPlayingInfo(playbackRate: 1.0)
                return .success
            }
            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.synthesizer.isSpeaking {
                let paused = self.synthesizer.pauseSpeaking(at: .word)
                guard paused else { return .commandFailed }
                self.isPaused = true
                self.accumulatedElapsed = self.elapsedPlayback
                self.playbackElapsedLive = self.accumulatedElapsed
                self.startedAt = nil
                self.stopNowPlayingProgressTimer()
                self.updateNowPlayingInfo(playbackRate: 0.0)
                return .success
            }
            return .commandFailed
        }

        commandCenter.stopCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.stop()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard self.requestManualPageTurn(.next) else { return .commandFailed }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard self.requestManualPageTurn(.previous) else { return .commandFailed }
            return .success
        }
    }

    private func updateNowPlayingInfo(playbackRate: Double) {
        guard currentFactID != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: "FactRead",
            MPMediaItemPropertyAlbumTitle: currentCategory,
            MPMediaItemPropertyGenre: "Facts",
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue,
            MPMediaItemPropertyPlaybackDuration: max(estimatedDuration, 1),
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: min(playbackElapsedLive, max(estimatedDuration, 1)),
            MPNowPlayingInfoPropertyDefaultPlaybackRate: narrationRate(for: selectedVoiceIdentifier),
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let icon = UIImage(named: "LaunchIcon") {
            let artwork = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = playbackRate > 0 ? .playing : .paused
        }
    }

    private var elapsedPlayback: TimeInterval {
        accumulatedElapsed + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startNowPlayingProgressTimer() {
        stopNowPlayingProgressTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isSpeaking, self.isPaused == false else { return }
                self.playbackElapsedLive = min(max(self.elapsedPlayback, 0), max(self.estimatedDuration, 0))
                self.updateNowPlayingInfo(playbackRate: 1.0)
            }
        }
        RunLoop.main.add(playbackTimer!, forMode: .common)
    }

    private func stopNowPlayingProgressTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func restartUtterance(atProgress progress: Double, preservePausedState: Bool) {
        let clamped = min(max(progress, 0), 1)
        let seekText = textForSeekProgress(clamped)
        guard seekText.isEmpty == false else { return }

        suppressNextCancelReset = true
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        accumulatedElapsed = estimatedDuration * clamped
        startedAt = Date()
        playbackElapsedLive = accumulatedElapsed

        let utterances = makeNarrationUtterances(
            text: seekText,
            languageCode: currentLanguageCode,
            voiceIdentifier: selectedVoiceIdentifier
        )
        beginNarrationSession(with: utterances)
        for utterance in utterances {
            synthesizer.speak(utterance)
        }

        isSpeaking = true
        isPaused = false
        startNowPlayingProgressTimer()
        updateNowPlayingInfo(playbackRate: 1.0)

        if preservePausedState {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                guard self.synthesizer.isSpeaking else { return }
                self.synthesizer.pauseSpeaking(at: .word)
                self.isPaused = true
                self.accumulatedElapsed = self.elapsedPlayback
                self.playbackElapsedLive = self.accumulatedElapsed
                self.startedAt = nil
                self.stopNowPlayingProgressTimer()
                self.updateNowPlayingInfo(playbackRate: 0.0)
            }
        }
    }

    private func estimateDuration(for text: String, voiceIdentifier: String?) -> TimeInterval {
        let words = max(1, text.split { $0.isWhitespace || $0.isNewline }.count)
        let wordsPerMinute: Double = switch narrationRate(for: voiceIdentifier) {
        case ..<0.46: 120
        case 0.46..<0.58: 165
        case 0.58..<0.68: 215
        default: 260
        }
        return (Double(words) / wordsPerMinute) * 60.0
    }

    private func narrationRate(for voiceIdentifier: String?) -> Float {
        let tuning = voiceTuning(for: voiceIdentifier)
        return max(0.36, min(0.72, baseNarrationRate + tuning.rateOffset))
    }
    
    private func narrationText(for fact: Fact, pageNumber: Int?) -> String {
        let intro: String
        if let pageNumber {
            intro = "Page \(pageNumber). "
        } else {
            intro = ""
        }
        let spokenTitle = normalizedSpokenText(fact.title, newlineSeparator: ", ")
        let spokenBody = normalizedSpokenText(fact.body, newlineSeparator: ". ")
        if spokenBody.isEmpty {
            return "\(intro)\(spokenTitle)"
        }
        return "\(intro)\(spokenTitle). \(spokenBody)"
    }

    private func textForSeekProgress(_ progress: Double) -> String {
        let ns = currentText as NSString
        let totalLength = ns.length
        guard totalLength > 0 else { return currentText }

        if progress <= 0.01 {
            return currentText
        }
        if progress >= 0.995 {
            return String(currentText.suffix(min(160, currentText.count)))
        }

        let rawIndex = Int(Double(totalLength) * progress)
        var start = min(max(rawIndex, 0), max(totalLength - 1, 0))
        let boundaries = CharacterSet(charactersIn: ".!?;:\n ")

        while start < totalLength {
            let value = ns.character(at: start)
            if let scalar = UnicodeScalar(value), boundaries.contains(scalar) {
                start += 1
                break
            }
            start += 1
        }
        if start >= totalLength {
            start = min(max(rawIndex, 0), max(totalLength - 1, 0))
        }

        return ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func qualityText(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .enhanced: return "Enhanced"
        case .premium: return "Premium"
        default: return "Default"
        }
    }

    private func normalizedSpokenText(_ input: String, newlineSeparator: String) -> String {
        let lines = input
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }
        guard lines.isEmpty == false else { return "" }
        let merged = lines.joined(separator: newlineSeparator)
        return merged
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "/", with: " or ")
            .replacingOccurrences(of: "•", with: ". ")
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sentenceChunks(from text: String, maxLength: Int = 220) -> [String] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return [] }

        var rawSentences: [String] = []
        let lines = normalized.split(whereSeparator: \.isNewline)
        for lineSub in lines {
            let line = String(lineSub)
            let parts = line.split(separator: ".", omittingEmptySubsequences: false)
            for partSub in parts {
                var sentence = String(partSub).trimmingCharacters(in: .whitespacesAndNewlines)
                guard sentence.isEmpty == false else { continue }
                if let last = sentence.last, ".!?".contains(last) == false {
                    sentence.append(".")
                }
                rawSentences.append(sentence)
            }
        }

        guard rawSentences.isEmpty == false else { return [normalized] }

        var chunks: [String] = []
        var current = ""
        for sentence in rawSentences {
            let proposed = current.isEmpty ? sentence : "\(current) \(sentence)"
            if proposed.count <= maxLength {
                current = proposed
            } else {
                if current.isEmpty == false {
                    chunks.append(current)
                }
                current = sentence
            }
        }
        if current.isEmpty == false {
            chunks.append(current)
        }
        return chunks
    }

    private func makeNarrationUtterances(
        text: String,
        languageCode: String,
        voiceIdentifier: String?
    ) -> [AVSpeechUtterance] {
        let chunks = sentenceChunks(from: text)
        let tuning = voiceTuning(for: voiceIdentifier)
        let voice = preferredVoice(for: languageCode, identifier: voiceIdentifier)

        return chunks.enumerated().map { index, chunk in
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            utterance.rate = narrationRate(for: voiceIdentifier)
            utterance.pitchMultiplier = tuning.pitch
            utterance.preUtteranceDelay = index == 0 ? 0.01 : 0
            utterance.postUtteranceDelay = 0.08
            utterance.prefersAssistiveTechnologySettings = false
            return utterance
        }
    }

    private func beginNarrationSession(with utterances: [AVSpeechUtterance]) {
        let sessionID = UUID()
        currentNarrationSessionID = sessionID
        expectedUtteranceCount = max(1, utterances.count)
        completedUtteranceCount = 0
        utteranceSessionByObjectID.removeAll()
        for utterance in utterances {
            utteranceSessionByObjectID[ObjectIdentifier(utterance)] = sessionID
        }
    }

    private func preferredLanguageCodes(for code: String) -> [String] {
        switch code.lowercased() {
        case "pt-br": return ["pt-BR", "pt"]
        case "zh-hans", "zh-cn": return ["zh-CN", "zh-Hans", "zh"]
        case "system":
            let localeCode = Locale.current.identifier
            return [localeCode, String(localeCode.prefix(2))]
        default:
            return [code, String(code.prefix(2))]
        }
    }

    private func preferredVoice(for code: String, identifier: String?) -> AVSpeechSynthesisVoice? {
        let normalized = normalizedVoiceIdentifier(identifier)
        if normalized != NarrationPersona.automatic.rawValue,
           let explicit = AVSpeechSynthesisVoice(identifier: normalized) {
            return explicit
        }
        for preferredCode in preferredLanguageCodes(for: code) {
            if let systemDefault = AVSpeechSynthesisVoice(language: preferredCode) {
                return systemDefault
            }
        }
        return fallbackVoice(for: code)
    }

    private func resolvePersonaVoices(for code: String) -> (male: AVSpeechSynthesisVoice?, female: AVSpeechSynthesisVoice?) {
        let ranked = rankedVoicesForClarity(for: code)
        let fallback = fallbackVoice(for: code)
        let primary = ranked.first ?? fallback
        let secondary = ranked.first(where: { voice in
            guard let primary else { return true }
            return voice.identifier != primary.identifier
        }) ?? primary
        return (primary, secondary)
    }

    private func fallbackVoice(for code: String) -> AVSpeechSynthesisVoice? {
        for preferredCode in preferredLanguageCodes(for: code) {
            if let exact = AVSpeechSynthesisVoice(language: preferredCode) {
                return exact
            }
        }
        let all = AVSpeechSynthesisVoice.speechVoices()
        for preferredCode in preferredLanguageCodes(for: code) {
            let lowered = preferredCode.lowercased()
            if let match = all.first(where: { voice in
                let voiceCode = voice.language.lowercased()
                return voiceCode == lowered || voiceCode.hasPrefix(lowered + "-")
            }) {
                return match
            }
        }
        if let englishUS = AVSpeechSynthesisVoice(language: "en-US") {
            return englishUS
        }
        if let first = all.first {
            return first
        }
        // If the system unexpectedly reports no voices, return nil and allow AVSpeechUtterance
        // to use automatic default voice behavior.
        return nil
    }

    private func voiceTuning(for identifier: String?) -> (rateOffset: Float, pitch: Float) {
        switch identifier {
        case NarrationPersona.automatic.rawValue:
            return (0.0, 1.0)
        case NarrationPersona.male.rawValue:
            return (0.0, 1.0)
        case NarrationPersona.female.rawValue:
            return (0.0, 1.0)
        default:
            return (0.0, 1.0)
        }
    }

    private func rankedVoicesForClarity(for code: String) -> [AVSpeechSynthesisVoice] {
        curatedVoices(for: code).sorted { lhs, rhs in
            let l = clarityScore(for: lhs)
            let r = clarityScore(for: rhs)
            if l != r { return l > r }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func clarityScore(for voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        let name = voice.name.lowercased()
        let identifier = voice.identifier.lowercased()

        switch voice.quality {
        case .premium: score += 1000
        case .enhanced: score += 700
        default: score += 250
        }

        if identifier.contains(".premium.") { score += 220 }
        if identifier.contains("neural") { score += 140 }
        if identifier.contains("compact") { score -= 200 }
        if name.contains("compact") { score -= 160 }
        if name.contains("siri") { score -= 80 }

        return score
    }

    private func curatedVoices(for code: String) -> [AVSpeechSynthesisVoice] {
        let preferred = preferredLanguageCodes(for: code)
        let all = AVSpeechSynthesisVoice.speechVoices()

        let filtered = all.filter { voice in
            let voiceCode = voice.language.lowercased()
            let matchesLanguage = preferred.contains { preferredCode in
                voiceCode == preferredCode.lowercased() || voiceCode.hasPrefix(preferredCode.lowercased() + "-")
            }
            guard matchesLanguage else { return false }

            let name = voice.name.lowercased()
            let blockedTokens = ["ringtone", "alarm", "beep", "sound", "effect", "novelty"]
            return blockedTokens.contains(where: { name.contains($0) }) == false
        }

        return filtered.sorted { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func normalizedVoiceIdentifier(_ identifier: String?) -> String {
        _ = identifier
        return NarrationPersona.automatic.rawValue
    }

}
