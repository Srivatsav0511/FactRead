import SwiftUI

struct PageFlipRenderer: View {
    let palette: ReaderTheme.Palette
    let gesture: PageFlipGestureController
    let tuning: PageFlipTuning
    let reduceMotionEnabled: Bool
    let currentPage: AnyView
    let underlyingPage: AnyView?

    private var shadowStrength: Double { palette.isDark ? 0.92 : 1.0 }
    private var highlightBoost: Double { palette.isDark ? 0.16 : 0.22 }
    private var backsideTintColor: Color { palette.isDark ? Color(hex: "0D0B09") : Color(hex: "FFE3C4") }
    private var backsideSaturation: Double { palette.isDark ? 0.84 : 0.78 }
    private var backsideBrightness: Double { palette.isDark ? -0.12 : -0.07 }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let p = gesture.progress
            let curl = gesture.curlProgress
            let foldX = foldPosition(width: size.width, progress: curl)
            let grabY = min(max(gesture.startLocation.y / max(size.height, 1), 0.12), 0.88)
            let flipAngle = (gesture.direction == .next ? -1.0 : 1.0) * Double(p) * tuning.maxRotationAngle
            let frontVisibility = max(0, min(1, 1 - ((p - 0.56) / 0.22)))
            let backVisibility = max(0, min(1, (p - 0.18) / 0.46))

            ZStack {
                if let underlyingPage {
                    underlyingPage
                        .overlay {
                            UnderPageAmbientShadow(
                                direction: gesture.direction,
                                progress: p,
                                strength: shadowStrength
                            )
                        }
                        .overlay {
                            UnderPageMovingFoldShadow(
                                direction: gesture.direction,
                                foldX: foldX,
                                progress: p,
                                opacity: tuning.foldShadowOpacity * shadowStrength
                            )
                        }
                        .scaleEffect(0.988 + (0.012 * p))
                        .allowsHitTesting(false)
                }

                if gesture.isActive {
                    if reduceMotionEnabled {
                        ReducedMotionPageFlip(
                            direction: gesture.direction,
                            progress: p,
                            page: currentPage
                        )
                    } else {
                        turningSheet(
                            size: size,
                            progress: p,
                            curl: curl,
                            foldX: foldX,
                            grabY: grabY,
                            flipAngle: flipAngle,
                            frontVisibility: frontVisibility,
                            backVisibility: backVisibility
                        )
                    }
                } else {
                    currentPage
                }
            }
            .drawingGroup(opaque: false, colorMode: .linear)
        }
    }

    @ViewBuilder
    private func turningSheet(
        size: CGSize,
        progress: CGFloat,
        curl: CGFloat,
        foldX: CGFloat,
        grabY: CGFloat,
        flipAngle: Double,
        frontVisibility: CGFloat,
        backVisibility: CGFloat
    ) -> some View {
        let thickness = (0.9 + (1.7 * progress)) * tuning.paperThicknessIllusion
        let liftShadow = 0.08 + (0.18 * Double(progress))

        ZStack {
            currentPage
                .overlay {
                    FrontSheetShade(
                        direction: gesture.direction,
                        progress: progress,
                        opacity: tuning.foldShadowOpacity * shadowStrength
                    )
                }
                .opacity(frontVisibility)

            currentPage
                .scaleEffect(x: -1, y: 1)
                .saturation(backsideSaturation)
                .brightness(backsideBrightness)
                .overlay {
                    backsideTintColor.opacity((palette.isDark ? 0.90 : tuning.backsideTint) * Double(progress))
                }
                .overlay {
                    BackSheetShade(direction: gesture.direction, progress: progress, isDark: palette.isDark)
                }
                .opacity(backVisibility)
        }
        .overlay {
            FoldEdgeHighlight(
                direction: gesture.direction,
                progress: progress,
                intensity: tuning.edgeHighlightIntensity * highlightBoost,
                width: 1.2 + (3.2 * progress)
            )
        }
        .overlay {
            FoldSpecularBand(
                direction: gesture.direction,
                progress: progress,
                intensity: tuning.edgeHighlightIntensity * (highlightBoost + 0.1),
                grabY: grabY
            )
        }
        .overlay {
            PaperThicknessLine(
                direction: gesture.direction,
                progress: progress,
                width: thickness,
                tone: palette.pageGradientBottom
            )
        }
        .overlay {
            FoldDepthShadow(
                direction: gesture.direction,
                progress: progress,
                foldX: foldX,
                opacity: tuning.foldShadowOpacity * shadowStrength
            )
        }
        .clipShape(PaperCurlMask(direction: gesture.direction, progress: curl, grabY: grabY))
        .modifier(PaperBendWarp(direction: gesture.direction, progress: curl, grabY: grabY, quality: tuning.renderQuality))
        .rotation3DEffect(
            .degrees(flipAngle),
            axis: (x: (grabY - 0.5) * 0.14, y: 1, z: 0),
            anchor: gesture.direction == .next ? .leading : .trailing,
            perspective: tuning.perspectiveStrength
        )
        .offset(x: gesture.direction.dragSign * size.width * 0.020 * progress, y: (grabY - 0.5) * 11 * progress)
        .shadow(
            color: .black.opacity(liftShadow * shadowStrength),
            radius: 6 + (16 * progress),
            x: gesture.direction == .next ? -10 : 10,
            y: 5
        )
        .allowsHitTesting(false)
    }

    private func foldPosition(width: CGFloat, progress: CGFloat) -> CGFloat {
        if gesture.direction == .next {
            return width * (1 - (0.90 * progress))
        }
        return width * (0.90 * progress)
    }
}

private struct ReducedMotionPageFlip: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let page: AnyView

    var body: some View {
        page
            .offset(x: direction == .next ? -(progress * 68) : (progress * 68))
            .opacity(1 - (0.34 * progress))
            .shadow(color: .black.opacity(0.06 * Double(progress)), radius: 5, x: 0, y: 2)
            .allowsHitTesting(false)
    }
}

private struct UnderPageAmbientShadow: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let strength: Double

    var body: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.12 * Double(progress) * strength),
                .clear,
                .black.opacity(0.05 * Double(progress) * strength)
            ],
            startPoint: direction == .next ? .leading : .trailing,
            endPoint: direction == .next ? .trailing : .leading
        )
    }
}

private struct UnderPageMovingFoldShadow: View {
    let direction: PageFlipDirection
    let foldX: CGFloat
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let width = max(22, min(proxy.size.width * 0.26, 18 + (proxy.size.width * 0.16 * progress)))
            let x = direction == .next
                ? max(0, foldX - width)
                : min(proxy.size.width - width, foldX)

            LinearGradient(
                colors: [
                    .black.opacity(opacity * 0.85 * Double(progress)),
                    .black.opacity(opacity * 0.32 * Double(progress)),
                    .clear
                ],
                startPoint: direction == .next ? .trailing : .leading,
                endPoint: direction == .next ? .leading : .trailing
            )
            .frame(width: width, height: proxy.size.height * 0.96)
            .offset(x: x, y: proxy.size.height * 0.02)
            .blur(radius: 8 + (9 * progress))
        }
    }
}

private struct FrontSheetShade: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(opacity * 0.26 * Double(progress)),
                .black.opacity(opacity * 0.48 * Double(progress)),
                .black.opacity(opacity * 0.20 * Double(progress))
            ],
            startPoint: direction == .next ? .leading : .trailing,
            endPoint: direction == .next ? .trailing : .leading
        )
    }
}

private struct BackSheetShade: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let isDark: Bool

    var body: some View {
        LinearGradient(
            colors: isDark
                ? [
                    .black.opacity(0.36 * Double(progress)),
                    .black.opacity(0.18 * Double(progress)),
                    .white.opacity(0.004 * Double(progress))
                ]
                : [
                    .black.opacity(0.15 * Double(progress)),
                    .black.opacity(0.05 * Double(progress)),
                    .white.opacity(0.02 * Double(progress))
                ],
            startPoint: direction == .next ? .leading : .trailing,
            endPoint: direction == .next ? .trailing : .leading
        )
    }
}

private struct FoldEdgeHighlight: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let intensity: Double
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if direction == .previous {
                edge
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                edge
            }
        }
    }

    private var edge: some View {
        LinearGradient(
            colors: [
                .white.opacity(intensity * 0.30 * Double(progress)),
                .white.opacity(intensity * 0.08 * Double(progress)),
                .clear
            ],
            startPoint: direction == .next ? .trailing : .leading,
            endPoint: direction == .next ? .leading : .trailing
        )
        .frame(width: width)
        .blur(radius: 0.2)
    }
}

private struct FoldSpecularBand: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let intensity: Double
    let grabY: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if direction == .previous {
                line
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                line
            }
        }
        .offset(y: (grabY - 0.5) * 16 * progress)
        .blendMode(.screen)
    }

    private var line: some View {
        LinearGradient(
            colors: [
                .white.opacity(0.22 * intensity * Double(progress)),
                .white.opacity(0.08 * intensity * Double(progress)),
                .clear
            ],
            startPoint: direction == .next ? .trailing : .leading,
            endPoint: direction == .next ? .leading : .trailing
        )
        .frame(width: 2 + (4.2 * progress))
        .blur(radius: 0.6)
    }
}

private struct FoldDepthShadow: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let foldX: CGFloat
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.58, 40 + (proxy.size.width * 0.22 * progress))
            let x = direction == .next ? max(0, foldX - width) : min(proxy.size.width - width, foldX)

            LinearGradient(
                colors: [
                    .black.opacity(opacity * 0.22 * Double(progress)),
                    .clear
                ],
                startPoint: direction == .next ? .trailing : .leading,
                endPoint: direction == .next ? .leading : .trailing
            )
            .frame(width: width)
            .offset(x: x)
        }
    }
}

private struct PaperThicknessLine: View {
    let direction: PageFlipDirection
    let progress: CGFloat
    let width: CGFloat
    let tone: Color

    var body: some View {
        HStack(spacing: 0) {
            if direction == .previous {
                tone.opacity(0.14 + (0.10 * Double(progress))).frame(width: width).blur(radius: 0.3)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                tone.opacity(0.14 + (0.10 * Double(progress))).frame(width: width).blur(radius: 0.3)
            }
        }
    }
}

private struct PaperCurlMask: Shape {
    let direction: PageFlipDirection
    let progress: CGFloat
    let grabY: CGFloat

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1)
        let curlDepth = max(14, min(130, rect.width * (0.22 * p + 0.02)))
        let peak = rect.height * grabY
        let amplitude = max(5, min(42, rect.width * 0.052 * pow(p, 0.74)))

        return Path { path in
            if direction == .next {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - curlDepth, y: rect.minY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX, y: peak),
                    control: CGPoint(x: rect.maxX - curlDepth * 0.30, y: peak - amplitude)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX - curlDepth, y: rect.maxY),
                    control: CGPoint(x: rect.maxX - curlDepth * 0.30, y: peak + amplitude)
                )
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + curlDepth, y: rect.minY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX, y: peak),
                    control: CGPoint(x: rect.minX + curlDepth * 0.30, y: peak - amplitude)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + curlDepth, y: rect.maxY),
                    control: CGPoint(x: rect.minX + curlDepth * 0.30, y: peak + amplitude)
                )
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            path.closeSubpath()
        }
    }
}

private struct PaperBendWarp: GeometryEffect {
    let direction: PageFlipDirection
    var progress: CGFloat
    let grabY: CGFloat
    let quality: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dir: CGFloat = direction == .next ? -1 : 1
        let curve = pow(progress, 0.84)
        let shear = dir * curve * 0.10 * quality
        let xScale = 1 - (curve * 0.052 * quality)
        let xShift = dir * curve * 10.5 * quality
        let yShift = (grabY - 0.5) * 17 * curve

        let transform = CGAffineTransform.identity
            .translatedBy(x: xShift, y: yShift)
            .scaledBy(x: xScale, y: 1)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: 0, ty: 0))

        return ProjectionTransform(transform)
    }
}

typealias PageTurnRenderer = PageFlipRenderer
