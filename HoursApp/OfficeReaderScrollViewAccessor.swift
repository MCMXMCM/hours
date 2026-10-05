import SwiftUI
import UIKit

/// Locates the native scroll view and a section's layout marker. Navigation
/// remains owned by SwiftUI; no delegate or gesture recognizer is replaced.
struct OfficeReaderScrollViewAccessor: UIViewRepresentable {
    let onResolve: (UIScrollView, UIView) -> Void

    func makeUIView(context: Context) -> ResolverView {
        let view = ResolverView()
        view.isUserInteractionEnabled = false
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: ResolverView, context: Context) {
        uiView.onResolve = onResolve
        uiView.resolveAfterLayout()
    }

    final class ResolverView: UIView {
        var onResolve: ((UIScrollView, UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolveAfterLayout()
        }

        func resolveAfterLayout() {
            DispatchQueue.main.async { [weak self] in
                guard let self, window != nil else { return }
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView {
                        onResolve?(scrollView, self)
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}

final class OfficeReaderTransientState {
    // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    var sectionJumpToken: UUID?
    var hasAppliedInitialScroll = false
    var latestScrollAnchor: OfficeReaderScrollAnchor?
    var latestScrollOffset: CGFloat = 0
    var maximumScrollOffset: CGFloat = 0
    weak var scrollView: UIScrollView? {
        didSet {
            guard scrollView !== oldValue else { return }
            observeRestorationResets()
        }
    }
    private var scrollObservation: NSKeyValueObservation?

    // SwiftUI may replace or reset the native offset after a lazy layout or
    // accessibility snapshot without reporting that reset in ScrollGeometry.
    // Protect the restored passage only until the next intentional scroll.
    var protectedAnchor: OfficeReaderScrollAnchor? {
        didSet { observeRestorationResets() }
    }

    private func observeRestorationResets() {
        scrollObservation = nil
        guard protectedAnchor != nil else { return }
        scrollObservation = scrollView?.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.preserveProtectedAnchor()
            }
        }
    }

    func preserveProtectedAnchor() {
        guard let scrollView else { return }
        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            protectedAnchor = nil
            return
        }
        guard let protectedAnchor,
              let frame = sectionFrames[protectedAnchor.sectionID] else { return }
        let delta = frame.minY - protectedAnchor.viewportY
        guard abs(delta) > 1 else { return }
        let maximum = max(
            0,
            scrollView.contentSize.height + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        )
        let target = OfficeReaderScrollRestoration.offset(
            scrollView.contentOffset.y + scrollView.adjustedContentInset.top + delta,
            maximumOffset: maximum
        )
        let nativeTarget = target - scrollView.adjustedContentInset.top
        guard abs(nativeTarget - scrollView.contentOffset.y) > 1 else { return }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: nativeTarget),
            animated: false
        )
    }

    var hasScrollGeometry = false
    // Strong-to-weak map: a wrapper class here was deallocated on every lazy
    // layout pass and tripped the iOS 26 isolated-deinit malloc abort.
    private let registeredSectionViews = NSMapTable<NSString, UIView>.strongToWeakObjects()

    func registerSectionView(_ view: UIView, for sectionID: String) {
        // A lazy SwiftUI stack can reuse a native layout marker. Its former
        // section must not retain an alias to the new section's frame.
        let keys = registeredSectionViews.keyEnumerator().allObjects.compactMap {
            $0 as? NSString
        }
        for key in keys {
            let existing = registeredSectionViews.object(forKey: key)
            if existing == nil || (key as String != sectionID && existing === view) {
                registeredSectionViews.removeObject(forKey: key)
            }
        }
        registeredSectionViews.setObject(view, forKey: sectionID as NSString)
    }

    var sectionViews: [String: UIView] {
        var views: [String: UIView] = [:]
        let keys = registeredSectionViews.keyEnumerator().allObjects.compactMap {
            $0 as? NSString
        }
        for key in keys {
            if let view = registeredSectionViews.object(forKey: key) {
                views[key as String] = view
            }
        }
        return views
    }

    var sectionFrames: [String: CGRect] {
        guard let scrollView else { return [:] }
        var frames: [String: CGRect] = [:]
        for (sectionID, view) in sectionViews {
            guard view.window != nil else { continue }
            frames[sectionID] = view.convert(view.bounds, to: scrollView).offsetBy(
                dx: 0, dy: -scrollView.contentOffset.y - scrollView.adjustedContentInset.top
            )
        }
        return frames
    }
    var savedOffset: Double?
    var savedAnchor: OfficeReaderScrollAnchor?
    var userInterruptedRestoration = false
}

nonisolated struct OfficeReaderScrollGeometry: Equatable {
    let offset: CGFloat
    let maximumOffset: CGFloat

    init(_ geometry: ScrollGeometry) {
        offset = max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        maximumOffset = max(
            0,
            geometry.contentSize.height + geometry.contentInsets.top
                + geometry.contentInsets.bottom - geometry.containerSize.height
        )
    }
}

nonisolated struct OfficeReaderScrollAnchor: Codable, Equatable, Sendable {
    let sectionID: String
    let viewportY: Double
}

nonisolated enum OfficeReaderScrollRestoration {
    static func offset(
        _ savedOffset: Double,
        maximumOffset: CGFloat
    ) -> CGFloat {
        guard savedOffset.isFinite,
              maximumOffset.isFinite,
              maximumOffset > 0 else {
            return 0
        }
        return CGFloat(
            min(max(0, savedOffset), Double(maximumOffset))
        )
    }

    static func anchor(in frames: [String: CGRect]) -> OfficeReaderScrollAnchor? {
        // Prefer the section crossing the viewport's top. If it lies in a
        // gap, retain the first section below it with its exact screen offset.
        let visible = frames.filter { $0.value.maxY > 0 && $0.value.minY.isFinite }
        guard let first = visible.min(by: { $0.value.minY < $1.value.minY }) else { return nil }
        return OfficeReaderScrollAnchor(sectionID: first.key, viewportY: Double(first.value.minY))
    }
}
