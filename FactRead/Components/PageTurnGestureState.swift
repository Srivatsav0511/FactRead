import CoreGraphics
import Foundation
import SwiftUI

enum PageFlipDirection: Int {
    case next = 1
    case previous = -1

    var dragSign: CGFloat {
        self == .next ? -1 : 1
    }
}

enum PageFlipPhase {
    case idle
    case tracking
    case settlingCommit
    case settlingCancel
}

enum PageFlipPhysicsPreset: String, CaseIterable, Identifiable {
    case editorialPaper
    var id: String { rawValue }
}

struct PageFlipTuning {
    var edgeActivationWidth: CGFloat = 30
    var maxCurlAmount: CGFloat = 0.95
    var maxRotationAngle: Double = 168
    var perspectiveStrength: CGFloat = 0.92
    var initialDragResistance: CGFloat = 0.31
    var velocityInfluence: CGFloat = 0.40
    var commitThreshold: CGFloat = 0.48
    var completionSpring: Animation = .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.12)
    var cancelSpring: Animation = .spring(response: 0.26, dampingFraction: 0.90, blendDuration: 0.08)
    var foldShadowOpacity: Double = 0.36
    var edgeHighlightIntensity: Double = 0.31
    var backsideTint: Double = 0.11
    var paperThicknessIllusion: CGFloat = 1.0
    var hapticTriggerThreshold: CGFloat = 0.52
    var hapticThresholdHysteresis: CGFloat = 0.05
    var settleDurationRange: ClosedRange<TimeInterval> = 0.16...0.34
    var cancelDurationRange: ClosedRange<TimeInterval> = 0.16...0.28
    var renderQuality: CGFloat = 1.0

    static func make(
        preset: PageFlipPhysicsPreset,
        highRefresh: Bool,
        lowPower: Bool
    ) -> PageFlipTuning {
        var tuning = PageFlipTuning()

        switch preset {
        case .editorialPaper:
            tuning.maxRotationAngle = 168
            tuning.initialDragResistance = 0.31
            tuning.commitThreshold = 0.48
            tuning.velocityInfluence = 0.40
        }

        if lowPower {
            tuning.renderQuality = 0.82
            tuning.foldShadowOpacity *= 0.84
            tuning.edgeHighlightIntensity *= 0.78
        } else if highRefresh {
            tuning.renderQuality = 1.06
        } else {
            tuning.renderQuality = 0.94
        }

        return tuning
    }
}

struct PageFlipReleaseDecision {
    let shouldCommit: Bool
    let completionScore: CGFloat
    let duration: TimeInterval
}

struct PageFlipPhysicsModel {
    let tuning: PageFlipTuning

    func mapDragToProgress(rawProgress: CGFloat, edgeEngagement: CGFloat) -> CGFloat {
        let raw = min(max(rawProgress * edgeEngagement, 0), 1)
        let resisted = max(0, raw - (tuning.initialDragResistance * (1 - exp(-raw * 6))))
        let earlyWeighted = resisted <= 0.35
            ? pow(resisted / 0.35, 1.65) * 0.35
            : 0.35 + ((resisted - 0.35) / 0.65) * 0.65
        let releaseCurve = 1 - pow(1 - earlyWeighted, 1.45)
        return min(max(releaseCurve, 0), 1)
    }

    func curlProgress(for progress: CGFloat, velocity: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        let velocityKick = min(max(velocity, 0), 1) * 0.08
        let stiffnessCurve = pow(clamped, 0.82) * (1 - (0.10 * pow(clamped, 2.1)))
        return min(max(stiffnessCurve + velocityKick, 0), tuning.maxCurlAmount)
    }

    func releaseDecision(
        dragProgress: CGFloat,
        predictedProgress: CGFloat,
        velocityNormalized: CGFloat,
        edgeEngagement: CGFloat
    ) -> PageFlipReleaseDecision {
        let speedBoost = max(0, velocityNormalized) * tuning.velocityInfluence
        let projected = max(dragProgress, predictedProgress + speedBoost)
        let dynamicThreshold = min(0.70, tuning.commitThreshold + ((1 - edgeEngagement) * 0.12))
        let shouldCommit = projected >= dynamicThreshold
        let durationSource = shouldCommit ? (1 - dragProgress) : dragProgress
        let duration = shouldCommit
            ? lerp(from: tuning.settleDurationRange.lowerBound, to: tuning.settleDurationRange.upperBound, t: durationSource)
            : lerp(from: tuning.cancelDurationRange.lowerBound, to: tuning.cancelDurationRange.upperBound, t: durationSource)
        return PageFlipReleaseDecision(shouldCommit: shouldCommit, completionScore: projected, duration: duration)
    }

    private func lerp(from start: TimeInterval, to end: TimeInterval, t: CGFloat) -> TimeInterval {
        let clamped = min(max(t, 0), 1)
        return start + (end - start) * Double(clamped)
    }
}

struct PageFlipGestureController {
    var phase: PageFlipPhase = .idle
    var direction: PageFlipDirection = .next
    var startLocation: CGPoint = .zero
    var rawTranslation: CGFloat = 0
    var progress: CGFloat = 0
    var curlProgress: CGFloat = 0
    var edgeEngagement: CGFloat = 1
    var intentResolved: Bool = false
    var intentRejected: Bool = false
    var commitCrossed: Bool = false

    var isActive: Bool {
        phase == .tracking || phase == .settlingCommit || phase == .settlingCancel
    }

    var dragSign: CGFloat { direction.dragSign }

    mutating func begin(at location: CGPoint, direction: PageFlipDirection, edgeEngagement: CGFloat) {
        self.phase = .tracking
        self.direction = direction
        self.startLocation = location
        self.edgeEngagement = min(max(edgeEngagement, 0.56), 1)
        self.rawTranslation = 0
        self.progress = 0
        self.curlProgress = 0
        self.intentResolved = true
        self.intentRejected = false
        self.commitCrossed = false
    }

    mutating func update(translation: CGFloat, width: CGFloat, velocityNormalized: CGFloat, physics: PageFlipPhysicsModel) {
        rawTranslation = min(max(translation, 0), width)
        let rawProgress = rawTranslation / max(width, 1)
        progress = physics.mapDragToProgress(rawProgress: rawProgress, edgeEngagement: edgeEngagement)
        curlProgress = physics.curlProgress(for: progress, velocity: velocityNormalized)
    }

    mutating func beginCommitSettle(width: CGFloat, physics: PageFlipPhysicsModel) {
        phase = .settlingCommit
        update(translation: width, width: width, velocityNormalized: 0.9, physics: physics)
    }

    mutating func beginCancelSettle(width: CGFloat, physics: PageFlipPhysicsModel) {
        phase = .settlingCancel
        update(translation: 0, width: width, velocityNormalized: 0, physics: physics)
    }

    mutating func reset() {
        phase = .idle
        startLocation = .zero
        rawTranslation = 0
        progress = 0
        curlProgress = 0
        edgeEngagement = 1
        intentResolved = false
        intentRejected = false
        commitCrossed = false
    }
}

typealias PageTurnDirection = PageFlipDirection
typealias TurnPhysicsPreset = PageFlipPhysicsPreset
typealias PageTurnTuning = PageFlipTuning
typealias PageTurnGestureState = PageFlipGestureController
