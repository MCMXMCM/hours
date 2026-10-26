import SwiftUI
import UIKit

/// A non-editable text view that provides word-level selection on iOS 26.
///
/// SwiftUI's `textSelection(.enabled)` applies its menu actions to the entire
/// `Text` value on iOS 26. A non-scrolling `UITextView` supplies the system
/// selection highlight, draggable handles, and contextual actions while the
/// office reader's enclosing `ScrollView` remains responsible for scrolling.
struct SelectableTextView: UIViewRepresentable {
    enum Foreground: Equatable {
        case primary
        case secondary

        fileprivate var color: UIColor {
            switch self {
            case .primary:
                Self.primaryTextColor
            case .secondary:
                Self.secondaryTextColor
            }
        }

        private static let primaryTextColor = UIColor { traits in
            guard traits.userInterfaceStyle == .dark else {
                return .label
            }

            if traits.accessibilityContrast == .high {
                return .white
            }

            return UIColor(
                red: 0.85,
                green: 0.84,
                blue: 0.82,
                alpha: 1
            )
        }

        private static let secondaryTextColor = UIColor { traits in
            primaryTextColor
                .resolvedColor(with: traits)
                .withAlphaComponent(0.62)
        }
    }

    let text: String
    let fontSize: CGFloat
    var isItalic = false
    var foreground: Foreground = .primary
    var lineSpacing: CGFloat = 0
    var emphasizedRanges: [Range<String.Index>] = []
    var highlightsAsterisks = false
    /// Whether the marks a breviary prints in red are red: a versicle's and
    /// a response's, an antiphon's, the cross and the signs of the chant's
    /// pauses, each before its words at the left edge.
    var marksRubrics = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1, which sets the slant of the synthesized italic that
        // TextKit 2 leaves upright.
        let textView = StaticSelectableTextView(usingTextLayoutManager: false)
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.bounces = false
        textView.alwaysBounceHorizontal = false
        textView.alwaysBounceVertical = false
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = false
        textView.scrollsToTop = false
        textView.contentInsetAdjustmentBehavior = .never
        textView.automaticallyAdjustsScrollIndicatorInsets = false
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        textView.setContentHuggingPriority(.required, for: .vertical)

        apply(configuration, to: textView)
        context.coordinator.configuration = configuration
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        updateTextIfNeeded(textView, coordinator: context.coordinator)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else {
            return nil
        }

        updateTextIfNeeded(uiView, coordinator: context.coordinator)
        let measurementKey = MeasurementKey(
            width: width,
            configuration: configuration
        )
        if context.coordinator.measurement?.key == measurementKey {
            return context.coordinator.measurement?.size
        }

        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let size = CGSize(width: width, height: ceil(fittingSize.height))
        context.coordinator.measurement = (measurementKey, size)
        return size
    }

    private func updateTextIfNeeded(
        _ textView: UITextView,
        coordinator: Coordinator
    ) {
        let configuration = configuration
        guard coordinator.configuration != configuration else {
            return
        }

        let preservesSelection = coordinator.configuration?.text
            == configuration.text
        let selectedRange = textView.selectedRange
        apply(configuration, to: textView)
        if preservesSelection,
           NSMaxRange(selectedRange) <= textView.attributedText.length {
            textView.selectedRange = selectedRange
        }
        coordinator.configuration = configuration
        coordinator.measurement = nil
    }

    private func apply(
        _ configuration: Configuration,
        to textView: UITextView
    ) {
        textView.attributedText = makeAttributedText(
            configuration,
            for: textView
        )
    }

    private func makeAttributedText(
        _ configuration: Configuration,
        for textView: UITextView
    ) -> NSAttributedString {
        let traitCollection = textView.traitCollection.modifyingTraits {
            $0.preferredContentSizeCategory = UIContentSizeCategory(dynamicTypeSize)
        }
        let baseFont = UIFont(
            name: "EBGaramond-Regular",
            size: configuration.fontSize
        ) ?? UIFont.systemFont(ofSize: configuration.fontSize)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: baseFont,
            compatibleWith: traitCollection
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = configuration.lineSpacing

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: configuration.foreground.color,
            .paragraphStyle: paragraphStyle,
        ]
        if configuration.isItalic {
            attributes[.obliqueness] = 0.16
        }

        let result = NSMutableAttributedString(
            string: configuration.text,
            attributes: attributes
        )
        let emphasizedBaseFont = UIFont(
            name: "EBGaramond-SemiBold",
            size: configuration.fontSize
        ) ?? UIFont.systemFont(
            ofSize: configuration.fontSize,
            weight: .semibold
        )
        let weightedFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: emphasizedBaseFont,
            compatibleWith: traitCollection
        )
        for range in configuration.emphasizedRanges {
            result.addAttribute(
                .font,
                value: weightedFont,
                range: NSRange(range, in: configuration.text)
            )
        }

        if configuration.marksRubrics {
            Self.markRubrics(
                in: result,
                font: font,
                color: configuration.foreground == .primary
                    ? MissalTypography.rubric
                    : MissalTypography.rubric.withAlphaComponent(0.78)
            )
        }

        if configuration.highlightsAsterisks {
            let string = configuration.text as NSString
            var searchRange = NSRange(location: 0, length: string.length)
            while searchRange.length > 0 {
                let range = string.range(
                    of: "*",
                    options: [],
                    range: searchRange
                )
                guard range.location != NSNotFound else { break }
                result.addAttribute(
                    .foregroundColor,
                    value: UIColor(
                        red: 0.82,
                        green: 0.13,
                        blue: 0.08,
                        alpha: 1
                    ),
                    range: range
                )
                let nextLocation = NSMaxRange(range)
                searchRange = NSRange(
                    location: nextLocation,
                    length: string.length - nextLocation
                )
            }
        }

        return result
    }

    /// The marks that open a line: a versicle's and a response's, a short
    /// responsory's, an antiphon's, and the Paschal addition's.
    private static let lineMarks = ["℟.br. ", "℣.br. ", "℣. ", "℟. ", "Ant. ", "T.P. "]
    /// The signs coloured wherever they stand.
    private static let signs = ["✠", "✙", "†", "*"]

    private static func markRubrics(
        in text: NSMutableAttributedString,
        font: UIFont,
        color: UIColor
    ) {
        let string = text.string as NSString
        var location = 0
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            let words = string.substring(with: line)
            if let mark = lineMarks.first(where: { words.hasPrefix($0) }) {
                let length = (mark as NSString).length
                text.addAttribute(
                    .foregroundColor,
                    value: color,
                    range: NSRange(location: line.location, length: length - 1)
                )
                if mark == "Ant. " {
                    // Upright in italic words, an en space after it.
                    text.removeAttribute(.obliqueness, range: NSRange(location: line.location, length: length - 1))
                    text.addAttribute(
                        .kern,
                        value: ceil(font.pointSize * 0.25),
                        range: NSRange(location: line.location + length - 1, length: 1)
                    )
                }
            }
            location = NSMaxRange(line)
        }
        for sign in signs {
            var range = NSRange(location: 0, length: string.length)
            while range.length > 0 {
                let found = string.range(of: sign, options: [], range: range)
                guard found.location != NSNotFound else { break }
                text.addAttribute(.foregroundColor, value: color, range: found)
                range = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
            }
        }
    }

    private var configuration: Configuration {
        Configuration(
            text: text,
            fontSize: fontSize,
            isItalic: isItalic,
            foreground: foreground,
            lineSpacing: lineSpacing,
            emphasizedRanges: emphasizedRanges,
            highlightsAsterisks: highlightsAsterisks,
            marksRubrics: marksRubrics,
            dynamicTypeSize: dynamicTypeSize
        )
    }


    final class Coordinator {
        // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
        // https://github.com/swiftlang/swift/issues/88036
        nonisolated deinit {}

        fileprivate var configuration: Configuration?
        fileprivate var measurement: (
            key: MeasurementKey,
            size: CGSize
        )?
    }

    fileprivate struct MeasurementKey: Equatable {
        let width: CGFloat
        let configuration: Configuration
    }

    fileprivate struct Configuration: Equatable {
        let text: String
        let fontSize: CGFloat
        let isItalic: Bool
        let foreground: Foreground
        let lineSpacing: CGFloat
        let emphasizedRanges: [Range<String.Index>]
        let highlightsAsterisks: Bool
        let marksRubrics: Bool
        let dynamicTypeSize: DynamicTypeSize
    }
}

private final class StaticSelectableTextView: UITextView {
    // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set { super.contentOffset = .zero }
    }

    override func setContentOffset(
        _ contentOffset: CGPoint,
        animated: Bool
    ) {
        super.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if super.contentOffset != .zero {
            super.setContentOffset(.zero, animated: false)
        }
    }
}
