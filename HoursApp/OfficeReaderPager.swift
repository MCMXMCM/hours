import Observation
import OSLog
import SwiftUI
import UIKit

/// The turning of a reader's pages, where it shows both languages: the
/// Latin on one page and the English on another, the reader's place carried
/// from each to the other.
nonisolated enum OfficeReaderPageTurn {
    static let signposter = OSSignposter(
        subsystem: "com.matthewmccarty.hours",
        category: "OfficeReader"
    )

    /// The rest of a psalm that compact psalmody sets after the verse sung
    /// from its score. A page without the chant reads it in the psalm itself.
    static let continuationSuffix = OfficeReaderSectionBuilder.compactContinuationSuffix

    /// The width along the screen's leading edge that is left to the
    /// system's swipe back.
    static let edgeWidth: CGFloat = 28

    /// How much farther across than up or down a drag must run to turn the
    /// page: twice, within some 27° of the horizontal. A drag nearer the
    /// vertical scrolls.
    static let horizontalRatio: CGFloat = 2

    /// The section of a page that stands for a section of the other: the
    /// same section, or, for the rest of a psalm in compact psalmody, the
    /// psalm.
    static func counterpart(
        of sectionID: String,
        among sectionIDs: Set<String>
    ) -> String? {
        if sectionIDs.contains(sectionID) { return sectionID }
        guard sectionID.hasSuffix(continuationSuffix) else { return nil }
        let base = String(sectionID.dropLast(continuationSuffix.count))
        return sectionIDs.contains(base) ? base : nil
    }

    /// How far down the reading area the reading line lies, where the eye
    /// rests on what is being read: a quarter of the way.
    static let readingLineFraction: CGFloat = 0.25

    /// Where the reader reads on a page: the part the reading line falls
    /// in, and how far into it, so that the facing page can show the same
    /// words there, however much longer or shorter its part runs. A psalm
    /// that compact psalmody divides is read as one, its sung first verse
    /// and the rest together.
    struct ReadingPlace: Equatable, Sendable {
        let sectionID: String
        /// How far into the part the line falls: 0 at its top, 1 at its foot.
        let progress: Double
        /// Where the line falls between two parts, how far below the top of
        /// the next it lies (a negative distance).
        var offset: Double = 0
    }

    /// The reading place on a page whose parts stand at `frames`, the
    /// reading line at `lineY`.
    static func readingPlace(
        in frames: [String: CGRect],
        lineY: CGFloat
    ) -> ReadingPlace? {
        var parts: [String: CGRect] = [:]
        for (sectionID, frame) in frames where frame.height > 0 && frame.minY.isFinite {
            let id = sectionID.hasSuffix(continuationSuffix)
                ? String(sectionID.dropLast(continuationSuffix.count))
                : sectionID
            parts[id] = parts[id].map { $0.union(frame) } ?? frame
        }
        if let (id, frame) = parts.first(where: { $0.value.minY <= lineY && lineY < $0.value.maxY }) {
            return ReadingPlace(
                sectionID: id,
                progress: Double((lineY - frame.minY) / frame.height)
            )
        }
        guard let (id, frame) = parts
            .filter({ $0.value.minY > lineY })
            .min(by: { $0.value.minY < $1.value.minY }) else { return nil }
        return ReadingPlace(sectionID: id, progress: 0, offset: Double(lineY - frame.minY))
    }

    /// Where the parts of a page should stand for the reader to read at a
    /// place: the part that stands for the place's own, and its top's height
    /// on the screen; the height is nil until the part is laid out. A psalm
    /// this page divides is placed by its first verse, the whole psalm
    /// running on from it.
    static func placement(
        of place: ReadingPlace,
        in frames: [String: CGRect],
        among sectionIDs: Set<String>,
        lineY: CGFloat
    ) -> (sectionID: String, top: CGFloat?)? {
        guard let id = counterpart(of: place.sectionID, among: sectionIDs) else { return nil }
        guard let frame = frames[id] else { return (id, nil) }
        var height = frame.height
        let rest = id + continuationSuffix
        if sectionIDs.contains(rest) {
            guard let restFrame = frames[rest] else { return (rest, nil) }
            height += restFrame.height
        }
        return (id, lineY - CGFloat(place.progress) * height - CGFloat(place.offset))
    }

    /// Whether a drag turns the page: begun away from the leading edge,
    /// clearly horizontal, and toward the facing page, right to left to the
    /// English and left to right back to the Latin.
    static func isTurn(
        translation: CGPoint,
        from page: ReaderPage,
        startX: CGFloat,
        width: CGFloat,
        isRightToLeft: Bool = false
    ) -> Bool {
        let fromLeadingEdge = isRightToLeft ? width - startX : startX
        guard fromLeadingEdge > edgeWidth,
              translation.x != 0,
              abs(translation.x) >= horizontalRatio * abs(translation.y) else {
            return false
        }
        return page == .latin ? translation.x < 0 : translation.x > 0
    }

    /// Where the pages stand as a drag moves them: 0 with the Latin shown,
    /// 1 with the English. Past either page they give way, as a page held
    /// at its edge.
    static func position(
        from page: ReaderPage,
        translation: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let start: CGFloat = page == .latin ? 0 : 1
        guard width > 0 else { return start }
        let position = start - translation / width
        if position < 0 { return position / 3 }
        if position > 1 { return 1 + (position - 1) / 3 }
        return position
    }

    /// Whether a drag let go completes the turn: flung toward the facing
    /// page, or carried a third of the way there and not flung back.
    static func completes(
        from page: ReaderPage,
        translation: CGFloat,
        velocity: CGFloat,
        width: CGFloat
    ) -> Bool {
        let toward: CGFloat = page == .latin ? -1 : 1
        let speed = velocity * toward
        if speed > 320 { return true }
        if speed < -320 { return false }
        return translation * toward > width / 3
    }
}

/// What the reader asks of one of its pages while the page is laid out.
struct OfficeReaderPageHandle {
    /// Where the reader reads on the page.
    let readingPlace: () -> OfficeReaderPageTurn.ReadingPlace?
    /// Whether the page is being scrolled.
    let isScrolling: () -> Bool
    /// Sets the page at a reading place at once, where the place is laid
    /// out; says whether the page now stands there.
    let placeNow: (OfficeReaderPageTurn.ReadingPlace) -> Bool
    /// Brings the page to a reading place; says whether it now stands there.
    let align: (OfficeReaderPageTurn.ReadingPlace) async -> Bool
    /// Brings a section to the head of the page, as the contents do.
    let jump: (String) -> Void
}

/// What the pages of a reader share: how far the reader is turned, which
/// pages are ready, and where the reader reads, so that the facing page
/// shows the same words when it is turned to.
@MainActor
@Observable
final class OfficeReaderPager {
    // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    /// How far the reader is turned: 0 with the Latin page shown, 1 with
    /// the English. Read only where each page is placed, so that a page is
    /// not laid out anew as the other moves.
    var position: CGFloat = 0
    /// Whether a page is being turned, by a drag or after it.
    var isTurning = false
    /// How far a page moves as it turns: the screen's width.
    @ObservationIgnored var turnDistance: CGFloat = 0
    /// The pages laid out and brought to their place.
    private(set) var readyPages: Set<ReaderPage> = []
    /// The contents of each page, for the list of the Office's sections.
    private(set) var outlines: [ReaderPage: [OfficeReaderOutlineEntry]] = [:]

    /// Where the reader was left in the page it opens on, if anywhere.
    @ObservationIgnored let openingAnchor: OfficeReaderScrollAnchor?
    /// Where the reader last read on the page shown.
    @ObservationIgnored var reading: OfficeReaderPageTurn.ReadingPlace?
    /// The page a drag began on, while it lasts.
    @ObservationIgnored var dragOrigin: ReaderPage?
    @ObservationIgnored private var handles: [ReaderPage: OfficeReaderPageHandle] = [:]
    @ObservationIgnored private var presentations: [OfficeReaderPresentationKey: OfficeReaderPresentation] = [:]
    @ObservationIgnored private var alignment: Task<Void, Never>?

    /// A reader opened at the place it was left at, if any.
    init(openingAnchor: OfficeReaderScrollAnchor? = nil) {
        self.openingAnchor = openingAnchor
    }

    func register(_ page: ReaderPage, handle: OfficeReaderPageHandle) {
        handles[page] = handle
    }

    func unregister(_ page: ReaderPage) {
        handles[page] = nil
        readyPages.remove(page)
        outlines[page] = nil
    }

    func markReady(_ page: ReaderPage) {
        guard !readyPages.contains(page) else { return }
        readyPages.insert(page)
    }

    func setOutline(_ entries: [OfficeReaderOutlineEntry], for page: ReaderPage) {
        guard outlines[page] != entries else { return }
        outlines[page] = entries
    }

    /// A presentation prepared before, for a page laid out anew.
    func presentation(for key: OfficeReaderPresentationKey) -> OfficeReaderPresentation? {
        presentations[key]
    }

    /// Keeps a page's presentation: the two pages', and no more.
    func keep(_ presentation: OfficeReaderPresentation, for key: OfficeReaderPresentationKey) {
        if presentations.count >= 2, presentations[key] == nil {
            presentations = presentations.filter { $0.key.showsScores != key.showsScores }
        }
        presentations[key] = presentation
    }

    /// Brings a page to where the reader reads on another.
    @discardableResult
    func align(_ page: ReaderPage, to place: OfficeReaderPageTurn.ReadingPlace?) async -> Bool {
        guard let handle = handles[page], let place else { return false }
        return await handle.align(place)
    }

    /// The page shown has come to rest: the facing page is brought to the
    /// same words while the reader reads, so that they are there when it is
    /// turned to.
    func settle(_ page: ReaderPage, reading place: OfficeReaderPageTurn.ReadingPlace?) {
        reading = place ?? reading
        alignment?.cancel()
        guard let place, handles[page.facing] != nil else { return }
        alignment = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled,
                  self.handles[page]?.isScrolling() != true else { return }
            await self.align(page.facing, to: place)
        }
    }

    /// The page shown is being scrolled: the facing page is left alone.
    func pageBeganScrolling() {
        alignment?.cancel()
        alignment = nil
    }

    func jump(to sectionID: String, on page: ReaderPage) {
        handles[page]?.jump(sectionID)
    }

    /// A drag has begun to turn from a page: the facing page is set at once
    /// at the words being read, before the drag shows it, and sought
    /// further if the lazy stack has yet to lay them out.
    func bringFacingPage(of page: ReaderPage) {
        alignment?.cancel()
        let place = handles[page]?.readingPlace() ?? reading
        reading = place
        guard let place,
              let handle = handles[page.facing],
              !handle.placeNow(place) else { return }
        alignment = Task {
            _ = await handle.align(place)
        }
    }

    /// Before a turn from the indicator: the page turned to is laid out, if
    /// it is not yet, and brought to the words being read.
    func prepareTurn(from page: ReaderPage, to target: ReaderPage) async {
        alignment?.cancel()
        let place = handles[page]?.readingPlace() ?? reading
        reading = place
        // A page first turned to is prepared now; it is waited for a moment.
        for _ in 0..<40 where !readyPages.contains(target) {
            do { try await Task.sleep(for: .milliseconds(25)) }
            catch { return }
        }
        await align(target, to: place)
    }

    /// The page turned to is shown: the reader reads on it from now on.
    func turnCompleted(to page: ReaderPage) {
        if let place = handles[page]?.readingPlace() {
            reading = place
        }
    }
}

/// The turn of a reader's pages by a drag: a pan that begins only when the
/// drag is clearly horizontal, away from the leading edge, toward the
/// facing page. A drag nearer the vertical is left to the page's scrolling,
/// and the system's swipe back from the edge comes first. Nothing is
/// attached to the page's rows; the one recognizer serves the whole reader.
struct ReaderPageTurnGesture: UIGestureRecognizerRepresentable {
    /// The page shown, from which a drag turns.
    let page: ReaderPage
    let isEnabled: Bool
    let onBegan: () -> Void
    let onChanged: (_ translation: CGFloat, _ width: CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ velocity: CGFloat, _ width: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        context.coordinator.page = page
        context.coordinator.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.page = page
        context.coordinator.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let width = recognizer.view?.bounds.width ?? 0
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(translation, width)
        case .changed:
            onChanged(translation, width)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x, width)
        case .cancelled, .failed:
            onEnded(0, 0, width)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
        // https://github.com/swiftlang/swift/issues/88036
        nonisolated deinit {}

        var page = ReaderPage.latin
        var isEnabled = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view,
                  let window = view.window else { return false }
            let translation = pan.translation(in: window)
            return OfficeReaderPageTurn.isTurn(
                translation: translation,
                from: page,
                startX: pan.location(in: window).x - translation.x,
                width: window.bounds.width,
                isRightToLeft: view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            )
        }

        /// The system's swipe back from the leading edge comes first.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer === Self.navigationController(of: gestureRecognizer.view)?
                .interactivePopGestureRecognizer
        }

        /// A swipe back begun within the page waits on a turn: from the
        /// English page it turns back to the Latin, and from the Latin it
        /// goes back.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer === Self.navigationController(of: gestureRecognizer.view)?
                .interactiveContentPopGestureRecognizer
        }

        private static func navigationController(of view: UIView?) -> UINavigationController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController,
                   let navigationController = controller as? UINavigationController
                    ?? controller.navigationController {
                    return navigationController
                }
                responder = current.next
            }
            return nil
        }
    }
}

/// The page indicator of a reader of both languages, beneath its title:
/// the page shown, and the facing page, which a tap turns to. VoiceOver
/// reads it as the page shown, with actions to turn to either.
struct ReaderPageIndicator: View {
    let page: ReaderPage
    let onTurn: (ReaderPage) -> Void

    var body: some View {
        Button {
            onTurn(page.facing)
        } label: {
            HStack(spacing: 6) {
                title(of: .latin)
                Text("·")
                    .foregroundStyle(.tertiary)
                title(of: .english)
            }
            .font(.footnote)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(page.title) page")
        .accessibilityHint("Turns to the \(page.facing.title) page")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Turn to the \(page.facing.title) page") {
            onTurn(page.facing)
        }
        .accessibilityIdentifier("reader-page-indicator")
    }

    private func title(of page: ReaderPage) -> some View {
        Text(page.title)
            .fontWeight(page == self.page ? .semibold : .regular)
            .foregroundStyle(page == self.page ? Color.hoursPrimaryText : Color.secondary)
    }
}
