import SwiftUI
import UIKit

/// The words of a Mass set plainly, every line at the left edge and a space
/// between them: the mark of a line (S., M., ℣., ℟.) in red before its
/// words; the first prayer of a part opening with a red initial two lines
/// tall, the rest of its first word in small capitals; crosses and the
/// directions in parentheses in red. The English page is set as the Latin is.
struct MissalTextView: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    var lineSpacing: CGFloat = 0
    /// Whether the part's first prayer opens with a red initial two lines
    /// tall (MissalTypography.initialParagraph).
    var opensWithInitial = false
    /// Whether the text is a reading, its first line announcing it: the
    /// initial then opens the reading itself.
    var isReading = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MissalUITextView {
        let textView = MissalUITextView()
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setting = setting(for: textView)
        context.coordinator.configuration = configuration
        return textView
    }

    func updateUIView(_ textView: MissalUITextView, context: Context) {
        updateIfNeeded(textView, coordinator: context.coordinator)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MissalUITextView,
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

    private func updateIfNeeded(_ textView: MissalUITextView, coordinator: Coordinator) {
        guard coordinator.configuration != configuration else { return }
        textView.setting = setting(for: textView)
        coordinator.configuration = configuration
        coordinator.measurement = nil
    }

    private func setting(for textView: UITextView) -> MissalTypography.Setting {
        let traits = textView.traitCollection.modifyingTraits {
            $0.preferredContentSizeCategory = UIContentSizeCategory(dynamicTypeSize)
        }
        return MissalTypography.setting(
            text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            opensWithInitial: opensWithInitial,
            isReading: isReading,
            traits: traits
        )
    }

    private var configuration: Configuration {
        Configuration(
            text: text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            opensWithInitial: opensWithInitial,
            isReading: isReading,
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
        let opensWithInitial: Bool
        let isReading: Bool
        let dynamicTypeSize: DynamicTypeSize
    }
}

/// How the words of a Mass are set (MissalTextView).
enum MissalTypography {
    /// The red of the rubrics.
    static let rubric = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.87, green: 0.27, blue: 0.20, alpha: 1)
            : UIColor(red: 0.68, green: 0.12, blue: 0.09, alpha: 1)
    }

    static let primaryText = UIColor.hoursPrimaryText

    /// The marks that say who speaks a line: the priest, the server, the
    /// deacon, all; the versicle and the response.
    static let marks: Set<String> = ["℣.", "℟.", "S.", "M.", "D.", "C.", "P.", "A."]

    /// The mark that opens a line, with the space after it, if it has one.
    static func mark(of line: Substring) -> Substring? {
        guard let space = line.firstIndex(of: " ") else { return nil }
        let mark = line[..<space]
        return marks.contains(String(mark)) ? line[...space] : nil
    }

    /// A response given within a line, as a litany's ("Saint Agatha. R.
    /// Pray for us."), with its proper mark; the line keeps its length.
    static func withResponses(_ line: Substring) -> Substring {
        guard line.contains(" R. ") else { return line }
        var text = String(line)
        for ending in [".", "!", "?"] {
            text = text.replacingOccurrences(of: "\(ending) R. ", with: "\(ending) ℟. ")
        }
        return Substring(text)
    }

    /// The words that announce a reading: a lesson or an epistle, the gospel
    /// or the passion, in Latin or in English.
    static let readingAnnouncements = [
        "Léctio", "Lectio", "Sequéntia", "Sequentia", "Inítium", "Initium",
        "Pássio", "Passio", "Lesson", "Reading", "A reading", "From the",
        "Continuation", "The beginning", "Beginning", "The Passion", "Passion",
    ]

    /// The bidding before a prayer, which the prayer's initial follows.
    static let biddings: Set<String> = ["Orémus.", "Oremus.", "Let us pray.", "Orémus", "Let us pray"]

    /// Whether a line announces a reading rather than beginning it.
    static func announcesReading(_ line: Substring) -> Bool {
        readingAnnouncements.contains { opening in
            line.hasPrefix(opening)
                && line.dropFirst(opening.count).first?.isLetter != true
        }
    }

    /// The line that opens with the part's initial: its first prayer, the
    /// first line neither marked nor a direction that begins with a capital.
    /// In a reading the line that announces it is passed over, so that the
    /// initial opens the reading itself, as a missal sets it.
    static func initialParagraph(in lines: [Substring], isReading: Bool = false) -> Int? {
        let candidates = lines.indices.filter { index in
            let line = lines[index]
            return mark(of: line) == nil
                && line.first.map { $0.isUppercase && $0.isLetter } == true
                && line.count >= 12
                && !biddings.contains(line.trimmingCharacters(in: .whitespaces))
        }
        guard let first = candidates.first else { return nil }
        if isReading, candidates.count > 1, announcesReading(lines[first]) {
            return candidates[1]
        }
        return first
    }

    /// The text, its fonts, and the initial to draw beside it.
    struct Setting {
        let attributedText: NSAttributedString
        let font: UIFont
        let initial: Initial?
    }

    /// A red initial two lines tall, drawn beside the text that flows
    /// around it.
    struct Initial {
        /// Where its paragraph begins in the text.
        let location: Int
        /// The length of its paragraph.
        let length: Int
        let letter: String
        /// The face it is set in, at one point.
        let face: UIFont
    }

    static func setting(
        _ text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        opensWithInitial: Bool,
        isReading: Bool = false,
        traits: UITraitCollection
    ) -> Setting {
        let font = scaled(named: "EBGaramond-Regular", size: fontSize, traits: traits)
        let italic = font.withSymbolicTraits(.traitItalic) ?? font
        let smallCaps = font.withSmallCaps()
        let lineHeight = ceil(font.lineHeight)

        // Every line at the left edge, its turns too, with a space between
        // lines in place of indents.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.paragraphSpacing = font.pointSize * 0.45 + lineSpacing * 0.6

        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: primaryText,
            .paragraphStyle: paragraph,
        ]

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let initialLine = opensWithInitial
            ? initialParagraph(in: lines, isReading: isReading)
            : nil
        let result = NSMutableAttributedString()
        var initial: Initial?
        for (index, sourceLine) in lines.enumerated() {
            let line = withResponses(sourceLine)
            let start = result.length
            let piece = NSMutableAttributedString(string: String(line), attributes: base)
            let string = String(line) as NSString

            if let mark = mark(of: line) {
                // The mark in red, and its words after it.
                let markLength = (String(mark) as NSString).length
                piece.addAttribute(.foregroundColor, value: rubric, range: NSRange(location: 0, length: markLength))
            } else if let first = line.first, first.isLetter, first.isUppercase, index == initialLine {
                let firstLength = (String(first) as NSString).length
                // Drawn apart, two lines tall; the letter stays in the
                // text, unseen, so that it is read and copied whole.
                piece.addAttributes([
                    .foregroundColor: UIColor.clear,
                    .font: font.withSize(1),
                ], range: NSRange(location: 0, length: firstLength))
                let word = string.rangeOfCharacter(
                    from: .whitespacesAndNewlines.union(.punctuationCharacters),
                    range: NSRange(location: firstLength, length: string.length - firstLength)
                )
                let wordEnd = word.location == NSNotFound ? string.length : word.location
                if wordEnd > firstLength {
                    piece.addAttribute(.font, value: smallCaps, range: NSRange(location: firstLength, length: wordEnd - firstLength))
                }
                initial = Initial(
                    location: start,
                    length: string.length,
                    letter: String(first),
                    face: UIFont(name: "EBGaramond-Medium", size: 1)
                        ?? UIFont(name: "EBGaramond-Regular", size: 1)
                        ?? .systemFont(ofSize: 1)
                )
            }

            // Crosses, and the directions and verse numbers in parentheses,
            // in red.
            var searchStart = 0
            while searchStart < string.length {
                let open = string.range(of: "(", range: NSRange(location: searchStart, length: string.length - searchStart))
                guard open.location != NSNotFound else { break }
                let close = string.range(of: ")", range: NSRange(location: open.location, length: string.length - open.location))
                let end = close.location == NSNotFound ? string.length : NSMaxRange(close)
                piece.addAttributes([
                    .foregroundColor: rubric,
                    .font: italic,
                ], range: NSRange(location: open.location, length: end - open.location))
                searchStart = end
            }
            // Crosses, and the marks of a versicle or response within it.
            for sign in ["✠", "℣.", "℟."] {
                var signStart = 0
                while signStart < string.length {
                    let found = string.range(of: sign, range: NSRange(location: signStart, length: string.length - signStart))
                    guard found.location != NSNotFound else { break }
                    piece.addAttribute(.foregroundColor, value: rubric, range: found)
                    signStart = NSMaxRange(found)
                }
            }

            result.append(piece)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: base))
            }
        }
        return Setting(attributedText: result, font: font, initial: initial)
    }

    private static func scaled(named name: String, size: CGFloat, traits: UITraitCollection) -> UIFont {
        let base = UIFont(name: name, size: size)
            ?? UIFont(name: "EBGaramond-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)
    }
}

private extension UIFont {
    func withSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: pointSize) }
    }

    /// The face with its small capitals for lower-case letters, where it
    /// has them.
    func withSmallCaps() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kLowerCaseType,
                UIFontDescriptor.FeatureKey.selector: kLowerCaseSmallCapsSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// The text view of a Mass's words, with the initial it draws beside them.
final class MissalUITextView: UITextView {
    // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    private let initialLabel = UILabel()
    private var arrangedWidth: CGFloat = -1
    /// How far down the initial reaches: a little below its baseline.
    private var initialBottom: CGFloat = 0

    var setting: MissalTypography.Setting? {
        didSet {
            let selection = selectedRange
            attributedText = setting?.attributedText
            if NSMaxRange(selection) <= attributedText.length {
                selectedRange = selection
            }
            arrangedWidth = -1
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
        initialLabel.isAccessibilityElement = false
        initialLabel.isUserInteractionEnabled = false
        addSubview(initialLabel)
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

    /// The height the text takes at a width, its initial included.
    func height(forWidth width: CGFloat) -> CGFloat {
        arrange(width: width)
        let used = layoutManager.usedRect(for: textContainer)
        return ceil(max(used.maxY, initialLabel.isHidden ? 0 : initialBottom))
    }

    /// Lays the text out at a width, around the initial where there is one.
    private func arrange(width: CGFloat) {
        guard width > 0, width != arrangedWidth else { return }
        arrangedWidth = width
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textContainer.exclusionPaths = []
        guard let setting, let initial = setting.initial,
              initial.location < textStorage.length else {
            initialLabel.isHidden = true
            initialBottom = 0
            return
        }
        // Undo what was changed for another width: the paragraph's spacing.
        let paragraphRange = NSRange(location: initial.location, length: initial.length)
        let source = setting.attributedText as NSAttributedString
        let nextStart = NSMaxRange(paragraphRange) + 1
        let nextEnd = nextStart < source.length
            ? (source.string as NSString).range(
                of: "\n",
                range: NSRange(location: nextStart, length: source.length - nextStart)
            ).location
            : NSNotFound
        let nextRange = nextStart < source.length
            ? NSRange(location: nextStart, length: (nextEnd == NSNotFound ? source.length : nextEnd) - nextStart)
            : NSRange(location: NSNotFound, length: 0)
        let restored = NSRange(
            location: paragraphRange.location,
            length: (nextRange.location == NSNotFound ? NSMaxRange(paragraphRange) : NSMaxRange(nextRange)) - paragraphRange.location
        )
        source.enumerateAttributes(in: restored) { attributes, range, _ in
            textStorage.setAttributes(attributes, range: range)
        }
        layoutManager.ensureLayout(for: textContainer)

        let font = setting.font
        let glyph = layoutManager.glyphIndexForCharacter(at: initial.location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let paragraph = textStorage.attribute(.paragraphStyle, at: initial.location, effectiveRange: nil) as? NSParagraphStyle
        let pitch = (paragraph?.maximumLineHeight ?? font.lineHeight) + (paragraph?.lineSpacing ?? 0)
        let firstBaseline = line.minY + layoutManager.location(forGlyphAt: glyph).y
        let secondBaseline = firstBaseline + pitch
        let capTop = firstBaseline - font.capHeight
        let capHeightPerPoint = max(initial.face.capHeight, 0.1)
        let initialFont = initial.face.withSize((secondBaseline - capTop) / capHeightPerPoint)
        let letterWidth = ceil((initial.letter as NSString).size(withAttributes: [.font: initialFont]).width)
        let gap = ceil(font.pointSize * 0.3)

        initialLabel.text = initial.letter
        initialLabel.font = initialFont
        initialLabel.textColor = MissalTypography.rubric
        initialLabel.frame = CGRect(
            x: 0,
            y: secondBaseline - initialFont.ascender,
            width: letterWidth,
            height: ceil(initialFont.lineHeight)
        )
        initialLabel.isHidden = false

        // The two lines beside the initial begin at one place.
        let firstLine = CGRect(x: 0, y: line.minY, width: letterWidth + gap, height: pitch)
        let secondLine = CGRect(
            x: 0,
            y: line.minY + pitch,
            width: letterWidth + gap,
            height: pitch - (paragraph?.lineSpacing ?? 0) / 2
        )
        let excluded = firstLine.union(secondLine)
        textContainer.exclusionPaths = [UIBezierPath(rect: firstLine), UIBezierPath(rect: secondLine)]
        layoutManager.ensureLayout(for: textContainer)

        let lastGlyph = layoutManager.glyphIndexForCharacter(at: max(initial.location, NSMaxRange(paragraphRange) - 1))
        let lastLine = layoutManager.lineFragmentUsedRect(forGlyphAt: lastGlyph, effectiveRange: nil)
        initialBottom = max(excluded.maxY, secondBaseline - initialFont.descender * 0.2)
        guard lastLine.maxY < initialBottom - 1, let paragraph else { return }
        let nextIsMarked = nextRange.location != NSNotFound
            && MissalTypography.mark(of: Substring((source.string as NSString).substring(with: nextRange))) != nil
        if nextRange.location != NSNotFound, nextRange.length > 0, !nextIsMarked {
            // A paragraph shorter than the initial has the next stand
            // beside the initial too, as a drop cap's does: on the second
            // line, with no space before it, its words where the first
            // line's begin.
            let close = NSMutableParagraphStyle()
            close.setParagraphStyle(paragraph)
            close.paragraphSpacing = 0
            textStorage.addAttribute(.paragraphStyle, value: close, range: paragraphRange)
            layoutManager.ensureLayout(for: textContainer)
        } else {
            // With nothing after it, or a line with a mark, which is
            // another's part, a paragraph shorter than the initial leaves
            // room for it, and the next begins below at the left edge.
            let roomy = NSMutableParagraphStyle()
            roomy.setParagraphStyle(paragraph)
            roomy.paragraphSpacing = paragraph.paragraphSpacing + (initialBottom - lastLine.maxY)
            textStorage.addAttribute(.paragraphStyle, value: roomy, range: paragraphRange)
            layoutManager.ensureLayout(for: textContainer)
        }
    }
}
