import SwiftUI
import UIKit

/// A verse of a psalm or canticle read without its chant, set plainly: a
/// paragraph of its own, every line at the left edge and ragged at the
/// right, a red asterisk at its pause, kept to the word before it. A verse
/// of two lines breaks at its pause where its halves fit, a half-verse to a
/// line. A hymn's stanza is set a line to a paragraph, its turns at the left
/// edge too.
struct PsalterVerseView: UIViewRepresentable {
    enum Form: Equatable {
        case verse
        case stanza
    }

    let text: String
    let fontSize: CGFloat
    var lineSpacing: CGFloat = 0
    var form: Form = .verse

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PsalterUITextView {
        let textView = PsalterUITextView()
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setting = setting(for: textView)
        context.coordinator.configuration = configuration
        return textView
    }

    func updateUIView(_ textView: PsalterUITextView, context: Context) {
        updateIfNeeded(textView, coordinator: context.coordinator)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: PsalterUITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }
        updateIfNeeded(uiView, coordinator: context.coordinator)
        let key = MeasurementKey(width: width, configuration: configuration)
        if context.coordinator.measurement?.key == key {
            return context.coordinator.measurement?.size
        }
        let size = CGSize(width: width, height: uiView.height(forWidth: width))
        context.coordinator.measurement = (key, size)
        return size
    }

    private func updateIfNeeded(_ textView: PsalterUITextView, coordinator: Coordinator) {
        guard coordinator.configuration != configuration else { return }
        textView.setting = setting(for: textView)
        coordinator.configuration = configuration
        coordinator.measurement = nil
    }

    private func setting(for textView: UITextView) -> PsalterTypography.Setting {
        let traits = textView.traitCollection.modifyingTraits {
            $0.preferredContentSizeCategory = UIContentSizeCategory(dynamicTypeSize)
        }
        return PsalterTypography.setting(
            text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            form: form,
            traits: traits
        )
    }

    private var configuration: Configuration {
        Configuration(
            text: text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            form: form,
            dynamicTypeSize: dynamicTypeSize
        )
    }


    final class Coordinator {
        // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
        // https://github.com/swiftlang/swift/issues/88036
        nonisolated deinit {}

        fileprivate var configuration: Configuration?
        fileprivate var measurement: (key: MeasurementKey, size: CGSize)?
    }

    fileprivate struct MeasurementKey: Equatable {
        let width: CGFloat
        let configuration: Configuration
    }

    fileprivate struct Configuration: Equatable {
        let text: String
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let form: Form
        let dynamicTypeSize: DynamicTypeSize
    }
}

/// How a psalter's verses are set (PsalterVerseView); paper breaks them as
/// the screen does (`broken`).
enum PsalterTypography {
    /// A verse's words, and where its pause falls.
    nonisolated struct Setting {
        let attributedText: NSAttributedString
        /// The space after the asterisk, where a verse of two lines breaks.
        let pause: Int?
    }

    /// The marks that open a verse: a versicle's and a response's.
    private static let marks = ["℣. ", "℟. "]

    static func setting(
        _ text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        form: PsalterVerseView.Form,
        traits: UITraitCollection
    ) -> Setting {
        // The asterisk keeps to the word before it, so it never opens a line.
        let words = text.replacingOccurrences(of: " *", with: "\u{00A0}*")
        let base = UIFont(name: "EBGaramond-Regular", size: fontSize)
            ?? UIFont.systemFont(ofSize: fontSize)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let result = NSMutableAttributedString(string: words, attributes: [
            .font: font,
            .foregroundColor: MissalTypography.primaryText,
            .paragraphStyle: paragraph,
        ])
        let red = MissalTypography.rubric
        let string = words as NSString

        // The asterisk at the pause, the cross, and a versicle's or a
        // response's mark, in red.
        for sign in ["*", "✠"] {
            var range = NSRange(location: 0, length: string.length)
            while range.length > 0 {
                let found = string.range(of: sign, options: [], range: range)
                guard found.location != NSNotFound else { break }
                result.addAttribute(.foregroundColor, value: red, range: found)
                range = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
            }
        }
        if let mark = marks.first(where: { words.hasPrefix($0) }) {
            let length = (mark as NSString).length
            result.addAttribute(.foregroundColor, value: red, range: NSRange(location: 0, length: length - 1))
        }

        var pause: Int?
        if form == .verse {
            let asterisk = string.range(of: "*")
            if asterisk.location != NSNotFound,
               NSMaxRange(asterisk) < string.length,
               string.character(at: NSMaxRange(asterisk)) == 32 {
                pause = NSMaxRange(asterisk)
            }
        }
        return Setting(attributedText: result, pause: pause)
    }

    /// The verse as it is set at a width: a verse of two lines broken at
    /// its pause where each half fits a line.
    nonisolated static func broken(_ setting: Setting, atWidth width: CGFloat) -> NSAttributedString {
        let text = setting.attributedText
        guard let pause = setting.pause, pause < text.length else { return text }
        func measured(_ range: NSRange) -> CGFloat {
            ceil(text.attributedSubstring(from: range).boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).width)
        }
        let whole = measured(NSRange(location: 0, length: text.length))
        let first = measured(NSRange(location: 0, length: pause))
        let second = measured(NSRange(location: pause + 1, length: text.length - pause - 1))
        // On one line, or with a half too long for a line, the verse runs on.
        guard whole > width, first <= width, second <= width else { return text }
        let broken = NSMutableAttributedString(attributedString: text)
        broken.replaceCharacters(in: NSRange(location: pause, length: 1), with: "\u{2028}")
        return broken
    }
}

/// The text view of a psalter's verse, broken at its pause for the width it
/// is given.
final class PsalterUITextView: UITextView {
    // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    private var arrangedWidth: CGFloat = -1

    var setting: PsalterTypography.Setting? {
        didSet {
            arrangedWidth = -1
            attributedText = setting?.attributedText
            setNeedsLayout()
        }
    }

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        bounces = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        scrollsToTop = false
        contentInsetAdjustmentBehavior = .never
        textContainerInset = .zero
        contentInset = .zero
        adjustsFontForContentSizeCategory = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set { super.contentOffset = .zero }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if super.contentOffset != .zero {
            super.setContentOffset(.zero, animated: false)
        }
        arrange(width: bounds.width)
    }

    /// The height the verse takes at a width.
    func height(forWidth width: CGFloat) -> CGFloat {
        arrange(width: width)
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).maxY)
    }

    /// Sets the verse at a width, broken at its pause where it should be.
    private func arrange(width: CGFloat) {
        guard width > 0, width != arrangedWidth, let setting else { return }
        arrangedWidth = width
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let text = PsalterTypography.broken(setting, atWidth: width)
        guard text != attributedText else { return }
        let selection = selectedRange
        attributedText = text
        if NSMaxRange(selection) <= attributedText.length {
            selectedRange = selection
        }
    }
}
