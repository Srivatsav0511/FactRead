import SwiftUI
import UIKit

struct BooksPageCurlView: UIViewControllerRepresentable {
    let pages: [FactViewModel.PageSnapshot]
    @Binding var index: Int
    let palette: ReaderTheme.Palette
    let topSafeAreaInset: CGFloat
    let hapticsEnabled: Bool
    let typingSoundEnabled: Bool
    let appLanguage: AppLanguage
    let readerFontScale: Double
    let readerTypographyStyle: ReaderTypographyStyle
    let categoryTintIntensity: Double
    let pageTextAnimationsEnabled: Bool
    let isDailyLimitReached: Bool
    let dailyLimitCount: Int
    let cooldownEndsAt: Date?
    let cooldownMessage: String
    let controlsVisible: Bool
    let canAccessFact: (Fact) -> Bool
    let onDoubleTapCurrent: (Fact) -> Void
    let onReaderTap: () -> Void
    let onDailyLimitHit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.backgroundColor = UIColor(palette.pageBackground)
        container.view.isOpaque = true

        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [UIPageViewController.OptionsKey.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )

        pageVC.view.backgroundColor = UIColor(palette.pageBackground)
        pageVC.view.isOpaque = true
        pageVC.isDoubleSided = false
        pageVC.delegate = context.coordinator
        pageVC.dataSource = context.coordinator
        context.coordinator.configurePagingScrollView(for: pageVC)
        pageVC.gestureRecognizers
            .compactMap { $0 as? UITapGestureRecognizer }
            .forEach { $0.isEnabled = false }

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.require(toFail: doubleTap)

        pageVC.view.addGestureRecognizer(doubleTap)
        pageVC.view.addGestureRecognizer(singleTap)

        context.coordinator.pageViewController = pageVC

        container.addChild(pageVC)
        container.view.addSubview(pageVC.view)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageVC.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            pageVC.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            pageVC.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor)
        ])
        pageVC.didMove(toParent: container)

        if let initial = context.coordinator.controller(at: clampedIndex) {
            pageVC.setViewControllers([initial], direction: .forward, animated: false)
            context.coordinator.currentIndex = clampedIndex
        }
        context.coordinator.applyDarkBacksideFixIfNeeded()

        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        let clamped = clampedIndex
        uiViewController.view.backgroundColor = UIColor(palette.pageBackground)
        context.coordinator.pageViewController?.view.backgroundColor = UIColor(palette.pageBackground)
        context.coordinator.applyDarkBacksideFixIfNeeded()

        if context.coordinator.isShowingLockPage {
            context.coordinator.refreshCachedControllers()
            return
        }

        if context.coordinator.isTransitioning {
            context.coordinator.refreshCachedControllers()
            return
        }

        if clamped != context.coordinator.currentIndex {
            let direction: UIPageViewController.NavigationDirection = clamped >= context.coordinator.currentIndex ? .forward : .reverse
            context.coordinator.navigate(to: clamped, direction: direction, animated: true)
        } else {
            context.coordinator.refreshCachedControllers()
        }
    }

    private var clampedIndex: Int {
        guard pages.isEmpty == false else { return 0 }
        return min(max(index, 0), pages.count - 1)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: BooksPageCurlView
        weak var pageViewController: UIPageViewController?
        var cachedControllers: [Int: FactHostingController] = [:]
        var currentIndex: Int = 0
        var isProgrammaticUpdate = false
        var isTransitioning = false
        private var cachedLockController: DailyLimitHostingController?

        init(parent: BooksPageCurlView) {
            self.parent = parent
            self.currentIndex = min(max(parent.index, 0), max(parent.pages.count - 1, 0))
        }

        private var lockPageIndex: Int {
            parent.pages.count
        }

        var isShowingLockPage: Bool {
            currentIndex == lockPageIndex
        }

        func refreshCachedControllers() {
            for (pageIndex, controller) in cachedControllers {
                guard parent.pages.indices.contains(pageIndex) else { continue }
                controller.view.backgroundColor = UIColor(parent.palette.pageBackground)
                controller.view.isOpaque = true
                controller.rootView = makePageView(pageIndex: pageIndex)
            }
            if let cachedLockController {
                cachedLockController.view.backgroundColor = UIColor(parent.palette.pageBackground)
                cachedLockController.view.isOpaque = true
                cachedLockController.rootView = makeLockPageView()
            }
        }

        func controller(at pageIndex: Int) -> FactHostingController? {
            guard parent.pages.indices.contains(pageIndex) else { return nil }

            if let cached = cachedControllers[pageIndex] {
                cached.rootView = makePageView(pageIndex: pageIndex)
                return cached
            }

            let controller = FactHostingController(rootView: makePageView(pageIndex: pageIndex), pageIndex: pageIndex)
            controller.view.backgroundColor = UIColor(parent.palette.pageBackground)
            controller.view.isOpaque = true
            cachedControllers[pageIndex] = controller
            return controller
        }

        func lockController() -> DailyLimitHostingController {
            if let cachedLockController {
                cachedLockController.rootView = makeLockPageView()
                return cachedLockController
            }
            let controller = DailyLimitHostingController(rootView: makeLockPageView(), pageIndex: lockPageIndex)
            controller.view.backgroundColor = UIColor(parent.palette.pageBackground)
            controller.view.isOpaque = true
            cachedLockController = controller
            return controller
        }

        func applyDarkBacksideFixIfNeeded() {
            guard parent.palette.isDark else { return }
            guard let pageView = pageViewController?.view else { return }
            let bg = UIColor(parent.palette.pageBackground)
            forceBackgroundColor(bg, on: pageView)
            if let superview = pageView.superview {
                forceBackgroundColor(bg, on: superview)
            }
        }

        private func forceBackgroundColor(_ color: UIColor, on view: UIView) {
            view.backgroundColor = color
            view.isOpaque = true
            view.layer.backgroundColor = color.cgColor
            for subview in view.subviews {
                forceBackgroundColor(color, on: subview)
            }
        }

        func configurePagingScrollView(for pageVC: UIPageViewController) {
            guard let scrollView = pageVC.view.subviews.compactMap({ $0 as? UIScrollView }).first else { return }
            scrollView.isDirectionalLockEnabled = true
            scrollView.alwaysBounceVertical = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
        }

        @objc
        func handleDoubleTap() {
            guard isTransitioning == false else { return }
            guard parent.pages.indices.contains(currentIndex) else { return }
            parent.onDoubleTapCurrent(parent.pages[currentIndex].fact)
        }

        @objc
        func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            guard isTransitioning == false else { return }
            parent.onReaderTap()
        }

        func navigate(to targetIndex: Int, direction: UIPageViewController.NavigationDirection, animated: Bool) {
            guard targetIndex != currentIndex else { return }
            guard let pageVC = pageViewController else { return }

            let targetController: UIViewController?
            if targetIndex == lockPageIndex {
                targetController = lockController()
            } else {
                targetController = controller(at: targetIndex)
            }
            guard let target = targetController else { return }

            isProgrammaticUpdate = true
            isTransitioning = animated

            pageVC.setViewControllers([target], direction: direction, animated: animated) { [weak self] (finished: Bool) in
                guard let self else { return }
                self.isProgrammaticUpdate = false
                self.isTransitioning = false
                self.applyDarkBacksideFixIfNeeded()
                guard finished || animated == false else { return }
                self.currentIndex = targetIndex
                if targetIndex < self.parent.pages.count, self.parent.index != targetIndex {
                    self.parent.index = targetIndex
                }
                self.preloadControllers(around: targetIndex)
                self.refreshCachedControllers()
            }
        }

        private func goToNextPage(animated: Bool) {
            if currentIndex == lockPageIndex { return }
            let nextIndex = currentIndex + 1
            guard parent.pages.indices.contains(nextIndex) else {
                if parent.isDailyLimitReached {
                    parent.onDailyLimitHit()
                    navigate(to: lockPageIndex, direction: .forward, animated: animated)
                }
                return
            }
            let nextFact = parent.pages[nextIndex].fact

            if parent.canAccessFact(nextFact) == false {
                parent.onDailyLimitHit()
                navigate(to: lockPageIndex, direction: .forward, animated: animated)
                return
            }

            navigate(to: nextIndex, direction: .forward, animated: animated)
        }

        private func goToPreviousPage(animated: Bool) {
            if currentIndex == lockPageIndex {
                guard parent.pages.indices.contains(parent.pages.count - 1) else { return }
                navigate(to: parent.pages.count - 1, direction: .reverse, animated: animated)
            } else {
                let previousIndex = currentIndex - 1
                guard parent.pages.indices.contains(previousIndex) else { return }
                navigate(to: previousIndex, direction: .reverse, animated: animated)
            }
        }

        private func makePageView(pageIndex: Int) -> FactPageView {
            let page = parent.pages[pageIndex]
            let canAnimateText = parent.pageTextAnimationsEnabled
                && pageIndex == currentIndex

            return FactPageView(
                page: page,
                pageNumber: pageIndex + 1,
                palette: parent.palette,
                topSafeAreaInset: parent.topSafeAreaInset,
                language: parent.appLanguage,
                readerFontScale: parent.readerFontScale,
                readerTypographyStyle: parent.readerTypographyStyle,
                categoryTintIntensity: parent.categoryTintIntensity,
                isPreview: pageIndex != currentIndex,
                pageTextAnimationsEnabled: canAnimateText,
                hapticsEnabled: parent.hapticsEnabled,
                typingSoundEnabled: parent.typingSoundEnabled
            )
        }

        private func pageIndex(for viewController: UIViewController) -> Int? {
            if let vc = viewController as? FactHostingController {
                return vc.pageIndex
            }
            if let vc = viewController as? DailyLimitHostingController {
                return vc.pageIndex
            }
            return nil
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let pageIndex = pageIndex(for: viewController) else { return nil }
            if pageIndex == lockPageIndex {
                return controller(at: lastAccessiblePageIndex())
            }
            let previousIndex = pageIndex - 1
            guard parent.pages.indices.contains(previousIndex) else { return nil }
            let previousFact = parent.pages[previousIndex].fact
            guard parent.canAccessFact(previousFact) else { return nil }
            return controller(at: previousIndex)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let pageIndex = pageIndex(for: viewController) else { return nil }
            if pageIndex == lockPageIndex { return nil }
            let nextIndex = pageIndex + 1
            guard parent.pages.indices.contains(nextIndex) else {
                if parent.isDailyLimitReached {
                    parent.onDailyLimitHit()
                    return lockController()
                }
                return nil
            }
            let nextFact = parent.pages[nextIndex].fact
            if parent.canAccessFact(nextFact) == false {
                parent.onDailyLimitHit()
                return lockController()
            }
            return controller(at: nextIndex)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isTransitioning = false
            guard finished, completed, isProgrammaticUpdate == false else { return }
            guard let visible = pageViewController.viewControllers?.first,
                  let newIndex = pageIndex(for: visible) else { return }

            currentIndex = newIndex

            if parent.pages.indices.contains(newIndex), parent.index != newIndex {
                parent.index = newIndex
            }

            preloadControllers(around: newIndex)
            refreshCachedControllers()
            applyDarkBacksideFixIfNeeded()
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            applyDarkBacksideFixIfNeeded()
        }

        private func makeLockPageView() -> DailyLimitPageView {
            DailyLimitPageView(
                palette: parent.palette,
                language: parent.appLanguage,
                limit: parent.dailyLimitCount,
                cooldownEndsAt: parent.cooldownEndsAt,
                message: parent.cooldownMessage
            )
        }

        private func preloadControllers(around centerIndex: Int) {
            let neighborIndices = [centerIndex - 1, centerIndex + 1, centerIndex + 2]
            for idx in neighborIndices where parent.pages.indices.contains(idx) {
                _ = controller(at: idx)
            }
        }

        private func lastAccessiblePageIndex() -> Int {
            guard parent.pages.isEmpty == false else { return 0 }
            return parent.pages.indices.last(where: { parent.canAccessFact(parent.pages[$0].fact) }) ?? max(0, parent.pages.count - 1)
        }
    }
}

final class FactHostingController: UIHostingController<FactPageView> {
    let pageIndex: Int

    init(rootView: FactPageView, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }
}

final class DailyLimitHostingController: UIHostingController<DailyLimitPageView> {
    let pageIndex: Int

    init(rootView: DailyLimitPageView, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }
}

struct DailyLimitPageView: View {
    let palette: ReaderTheme.Palette
    let language: AppLanguage
    let limit: Int
    let cooldownEndsAt: Date?
    let message: String

    var body: some View {
        ZStack {
            palette.pageBackground
            VStack(spacing: 0) {
                Spacer(minLength: 64)

                Text(titleText.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(palette.inkSecondary.opacity(0.92))

                Text("\(limit)")
                    .font(.system(size: 92, weight: .bold, design: .serif))
                    .foregroundStyle(palette.inkPrimary)
                    .padding(.top, 8)

                Text("facts today")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.inkSecondary)

                Rectangle()
                    .fill(palette.separator.opacity(0.72))
                    .frame(width: 72, height: 1)
                    .padding(.top, 22)

                Text(message)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.top, 18)
                    .padding(.horizontal, 36)

                timerView
                    .padding(.top, 26)

                Spacer(minLength: 72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var timerView: some View {
        if let cooldownEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 6) {
                    Text("Next unlock")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(palette.inkSecondary.opacity(0.85))
                    Text(remainingText(until: cooldownEndsAt))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.markerTint)
                }
            }
        } else {
            VStack(spacing: 6) {
                Text("Next unlock")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(palette.inkSecondary.opacity(0.85))
                Text("Resetting soon")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.markerTint)
            }
        }
    }

    private func remainingText(until end: Date) -> String {
        let remaining = max(0, Int(end.timeIntervalSinceNow))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d:%02d until reset", hours, minutes, seconds)
    }

    private var titleText: String {
        "Cooling Window Active"
    }
}
