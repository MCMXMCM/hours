import CoreGraphics
import CoreText
import Foundation

public struct GregorianLayoutMetrics: Hashable, Sendable {
    public static let minimumNotationScale = 0.6
    public static let maximumNotationScale = 1.6
    public static let notationScaleRange =
        minimumNotationScale...maximumNotationScale

    public static func clampedNotationScale(_ scale: Double) -> Double {
        max(minimumNotationScale, min(maximumNotationScale, scale))
    }

    public var notationScale: Double
    public var lyricScale: Double

    public init(notationScale: Double = 1, lyricScale: Double = 1) {
        self.notationScale = notationScale
        self.lyricScale = lyricScale
    }
}

public enum GregorianGlyphKind: Hashable, Sendable {
    // Stable public cases retained for tests and accessibility consumers.
    case cClef
    case fClef
    case notehead(GregorianNoteShape)
    case flat
    case natural
    case sharp
    case mora
    case custos
    case catalog(GregorianGlyphName)

    public var catalogName: GregorianGlyphName {
        switch self {
        case .cClef: .doClef
        case .fClef: .faClef
        case let .notehead(shape):
            switch shape {
            case .punctum: .punctumQuadratum
            case .virga: .virgaShort
            case .quilisma: .quilisma
            case .liquescent: .punctumQuadratumLiquescent
            case .inclinatum: .punctumInclinatum
            case .oriscus: .oriscusAsc
            case .stropha: .stropha
            }
        case .flat: .flat
        case .natural: .natural
        case .sharp: .sharp
        case .mora: .mora
        case .custos: .custosShort
        case let .catalog(name): name
        }
    }
}

public enum GregorianStrokeKind: Hashable, Sendable {
    case staff
    case ledger
    case connector
    case episema
    case division(GregorianDivision)
}

public struct GregorianPlacedGlyph: Hashable, Sendable {
    public let kind: GregorianGlyphKind
    public let frame: CGRect
    public let eventID: String?

    public init(kind: GregorianGlyphKind, frame: CGRect, eventID: String? = nil) {
        self.kind = kind
        self.frame = frame
        self.eventID = eventID
    }
}

public struct GregorianPlacedStroke: Hashable, Sendable {
    public let kind: GregorianStrokeKind
    public let start: CGPoint
    public let end: CGPoint
    public let lineWidth: CGFloat
    public let eventID: String?

    public init(
        kind: GregorianStrokeKind,
        start: CGPoint,
        end: CGPoint,
        lineWidth: CGFloat,
        eventID: String? = nil
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.lineWidth = lineWidth
        self.eventID = eventID
    }
}

public struct GregorianPlacedLyric: Hashable, Sendable {
    public let text: String
    public let style: GregorianLyricStyle
    public let origin: CGPoint
    public let width: CGFloat
    public let fontSize: CGFloat
    public let neumeID: String

    public init(
        text: String,
        style: GregorianLyricStyle = .regular,
        origin: CGPoint,
        width: CGFloat,
        fontSize: CGFloat,
        neumeID: String
    ) {
        self.text = text
        self.style = style
        self.origin = origin
        self.width = width
        self.fontSize = fontSize
        self.neumeID = neumeID
    }
}

public struct GregorianPlacedInitial: Hashable, Sendable {
    public let text: String
    public let annotation: String?
    public let annotationOrigin: CGPoint?
    public let annotationFontSize: CGFloat
    public let origin: CGPoint
    public let width: CGFloat
    public let fontSize: CGFloat
    public let neumeID: String

    public init(
        text: String,
        annotation: String? = nil,
        annotationOrigin: CGPoint? = nil,
        annotationFontSize: CGFloat = 0,
        origin: CGPoint,
        width: CGFloat,
        fontSize: CGFloat,
        neumeID: String
    ) {
        self.text = text
        self.annotation = annotation
        self.annotationOrigin = annotationOrigin
        self.annotationFontSize = annotationFontSize
        self.origin = origin
        self.width = width
        self.fontSize = fontSize
        self.neumeID = neumeID
    }
}

public struct GregorianEventPlacement: Hashable, Sendable, Identifiable {
    public var id: String { eventID }
    public let eventID: String
    public let neumeID: String
    public let frame: CGRect
    public let lineIndex: Int

    public init(eventID: String, neumeID: String, frame: CGRect, lineIndex: Int) {
        self.eventID = eventID
        self.neumeID = neumeID
        self.frame = frame
        self.lineIndex = lineIndex
    }
}

public struct GregorianNeumePlacement: Hashable, Sendable, Identifiable {
    public let id: String
    public let eventIDs: [String]
    public let lyric: String
    public let inkFrame: CGRect
    public let hitFrame: CGRect
    public let lineIndex: Int

    public init(
        id: String,
        eventIDs: [String],
        lyric: String,
        inkFrame: CGRect,
        hitFrame: CGRect,
        lineIndex: Int
    ) {
        self.id = id
        self.eventIDs = eventIDs
        self.lyric = lyric
        self.inkFrame = inkFrame
        self.hitFrame = hitFrame
        self.lineIndex = lineIndex
    }
}

public struct GregorianStaffLayout: Hashable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let frame: CGRect
    public let systemFrame: CGRect
    public let firstEventID: String?

    public init(
        index: Int,
        frame: CGRect,
        systemFrame: CGRect? = nil,
        firstEventID: String?
    ) {
        self.index = index
        self.frame = frame
        self.systemFrame = systemFrame ?? frame
        self.firstEventID = firstEventID
    }
}

public struct GregorianLayout: Sendable {
    public let size: CGSize
    public let staffs: [GregorianStaffLayout]
    public let glyphs: [GregorianPlacedGlyph]
    public let strokes: [GregorianPlacedStroke]
    public let lyrics: [GregorianPlacedLyric]
    public let initials: [GregorianPlacedInitial]
    public let events: [GregorianEventPlacement]
    public let neumes: [GregorianNeumePlacement]

    public init(
        size: CGSize,
        staffs: [GregorianStaffLayout],
        glyphs: [GregorianPlacedGlyph],
        strokes: [GregorianPlacedStroke],
        lyrics: [GregorianPlacedLyric],
        initials: [GregorianPlacedInitial] = [],
        events: [GregorianEventPlacement],
        neumes: [GregorianNeumePlacement]
    ) {
        self.size = size
        self.staffs = staffs
        self.glyphs = glyphs
        self.strokes = strokes
        self.lyrics = lyrics
        self.initials = initials
        self.events = events
        self.neumes = neumes
    }

    public func neume(containing eventID: String) -> GregorianNeumePlacement? {
        neumes.first { $0.eventIDs.contains(eventID) }
    }
}

/// Native Gregorian engraving with the same three-stage shape as Exsurge:
/// semantic units, intrinsic measurement/line breaking, then positioned ink.
public struct GregorianEngravingLayoutEngine: Sendable {
    private static let lyricLineHeightMultiplier: CGFloat = 1.23

    public init() {}

    public static func openingLabel(forMode mode: String?) -> String? {
        guard let mode = mode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mode.isEmpty else {
            return nil
        }

        let compact = mode
            .lowercased()
            .filter { !$0.isWhitespace }
        let modePrefixes = [
            "viii", "vii", "iii", "vi", "iv", "ii", "v", "i",
            "8", "7", "6", "5", "4", "3", "2", "1"
        ]
        guard let prefix = modePrefixes.first(where: { compact.hasPrefix($0) }) else {
            return nil
        }

        var conclusion = compact.dropFirst(prefix.count)
        if conclusion.first == "-" {
            conclusion.removeFirst()
        }
        if conclusion.hasPrefix("alt-") {
            conclusion = conclusion.dropFirst(4)
        }
        guard let concludingLetter = conclusion.first,
              ("a"..."g").contains(String(concludingLetter)) else {
            return nil
        }

        let variant = conclusion.dropFirst()
        guard variant.isEmpty
                || variant.allSatisfy(\.isNumber)
                || variant == "star"
                || variant == "-" else {
            return nil
        }
        return mode.uppercased()
    }

    public func layout(
        score: GregorianScore,
        width requestedWidth: CGFloat,
        metrics: GregorianLayoutMetrics = GregorianLayoutMetrics(),
        openingLabel: String? = nil
    ) -> GregorianLayout {
        let notationScale = CGFloat(
            GregorianLayoutMetrics.clampedNotationScale(
                metrics.notationScale
            )
        )
        let lyricScale = max(
            0.5,
            min(
                3.5,
                CGFloat(metrics.lyricScale) * notationScale
            )
        )
        let width = max(240, requestedWidth)
        let glyphScale = notationScale / 16
        let staffStep = 100 * glyphScale // one GABC pitch step / half staff-space
        let staffGap = staffStep * 2
        let sidePadding = 8 * notationScale
        let clefColumn = 18 * notationScale
        let custosColumn = 10 * notationScale
        let lyricFontSize = 21 * lyricScale
        let lyricHeight = ceil(
            lyricFontSize * Self.lyricLineHeightMultiplier
        )
        let openingInitial = openingInitial(
            in: score,
            annotation: Self.openingLabel(forMode: openingLabel)
        )
        let initialScale = max(notationScale, min(1.35, lyricScale))
        let initialFontSize = 56 * initialScale
        let initialAnnotationFontSize = 13 * max(notationScale, min(1.25, lyricScale))
        let initialWidth = openingInitial.map {
            measureLyric($0.text, fontSize: initialFontSize)
        } ?? 0
        let initialAnnotationWidth = openingInitial?.annotation.map {
            measureLyric($0, fontSize: initialAnnotationFontSize)
        } ?? 0
        let initialColumn = openingInitial.map { _ in
            max(
                38 * notationScale,
                max(initialWidth, initialAnnotationWidth) + 8 * notationScale
            )
        } ?? 0

        let units = makeUnits(
            score: score,
            glyphScale: glyphScale,
            notationScale: notationScale,
            lyricFontSize: lyricFontSize,
            openingInitial: openingInitial
        )
        let continuationAvailableWidth = width - sidePadding * 2 - clefColumn - custosColumn
        let lines = breakLines(
            units: units,
            firstAvailableWidth: continuationAvailableWidth - initialColumn,
            continuationAvailableWidth: continuationAvailableWidth
        )
        let lineVerticalMetrics = lines.enumerated().map { lineIndex, units in
            verticalMetrics(
                for: units,
                staffStep: staffStep,
                staffGap: staffGap,
                notationScale: notationScale,
                lyricHeight: lyricHeight,
                openingInitialFontSize: lineIndex == 0 && openingInitial != nil
                    ? initialFontSize
                    : nil
            )
        }
        var lineOrigins: [CGFloat] = []
        var contentHeight: CGFloat = 0
        for metrics in lineVerticalMetrics {
            lineOrigins.append(contentHeight)
            contentHeight += metrics.height
        }

        var staffs: [GregorianStaffLayout] = []
        var glyphs: [GregorianPlacedGlyph] = []
        var strokes: [GregorianPlacedStroke] = []
        var lyrics: [GregorianPlacedLyric] = []
        var initials: [GregorianPlacedInitial] = []
        var events: [GregorianEventPlacement] = []
        var rawNeumes: [RawNeumePlacement] = []
        var activeClef = GregorianClef(kind: .c, line: 4)

        for (lineIndex, lineUnits) in lines.enumerated() {
            let lineOriginY = lineOrigins[lineIndex]
            let lineMetrics = lineVerticalMetrics[lineIndex]
            let staffTop = lineOriginY + lineMetrics.topInset
            let staffBottom = staffTop + staffGap * 3
            let staffCenter = (staffTop + staffBottom) / 2
            let openingColumn = lineIndex == 0 ? initialColumn : 0
            let staffLeft = sidePadding + openingColumn
            let firstEventID = lineUnits.compactMap(\.neume?.id).first
            staffs.append(
                GregorianStaffLayout(
                    index: lineIndex,
                    frame: CGRect(
                        x: staffLeft,
                        y: staffTop,
                        width: width - sidePadding - staffLeft,
                        height: staffGap * 3
                    ),
                    systemFrame: CGRect(
                        x: 0,
                        y: lineOriginY,
                        width: width,
                        height: lineMetrics.height
                    ),
                    firstEventID: firstEventID
                )
            )

            for staffLine in 0..<4 {
                let y = staffTop + CGFloat(staffLine) * staffGap
                strokes.append(
                    GregorianPlacedStroke(
                        kind: .staff,
                        start: CGPoint(x: staffLeft, y: y),
                        end: CGPoint(x: width - sidePadding, y: y),
                        lineWidth: max(0.72, 0.78 * notationScale)
                    )
                )
            }

            var leadingClefCount = 0
            for unit in lineUnits {
                guard case let .clef(clef) = unit.element else { break }
                activeClef = clef
                leadingClefCount += 1
            }
            appendClef(
                activeClef,
                x: staffLeft + 2 * notationScale,
                staffTop: staffTop,
                staffGap: staffGap,
                glyphScale: glyphScale,
                glyphs: &glyphs
            )

            if lineIndex == 0, let openingInitial {
                initials.append(
                    GregorianPlacedInitial(
                        text: openingInitial.text,
                        annotation: openingInitial.annotation,
                        annotationOrigin: openingInitial.annotation.map { _ in
                            CGPoint(
                                x: sidePadding + (initialColumn - initialWidth) / 2,
                                y: max(0, staffTop - initialAnnotationFontSize)
                            )
                        },
                        annotationFontSize: initialAnnotationFontSize,
                        origin: CGPoint(
                            x: sidePadding + (initialColumn - initialWidth) / 2,
                            y: staffTop
                        ),
                        width: initialWidth,
                        fontSize: initialFontSize,
                        neumeID: openingInitial.neumeID
                    )
                )
            }

            let availableWidth = continuationAvailableWidth - openingColumn
            let naturalWidth = lineUnits.reduce(0) { $0 + $1.width }
            var gapAdjustments = Array(
                repeating: CGFloat.zero,
                count: max(0, lineUnits.count - 1)
            )
            let visibleGaps = gapAdjustments.indices.filter {
                lineUnits[$0].width > 0 && lineUnits[$0 + 1].width > 0
            }
            let condensibleGaps = visibleGaps.filter {
                !lineUnits[$0 + 1].showsInlineHyphenFromPrevious
            }
            if naturalWidth > availableWidth, !condensibleGaps.isEmpty {
                let adjustment = max(
                    -2.5 * notationScale,
                    (availableWidth - naturalWidth) / CGFloat(condensibleGaps.count)
                )
                for index in condensibleGaps {
                    gapAdjustments[index] = adjustment
                }
            }
            var x = staffLeft + clefColumn

            for (unitIndex, unit) in lineUnits.enumerated() {
                switch unit.element {
                case let .clef(clef):
                    if unitIndex < leadingClefCount { continue }
                    activeClef = clef
                    appendClef(
                        clef,
                        x: x,
                        staffTop: staffTop,
                        staffGap: staffGap,
                        glyphScale: glyphScale,
                        glyphs: &glyphs
                    )

                case let .accidental(accidental):
                    let kind: GregorianGlyphKind = switch accidental.kind {
                    case .flat: .flat
                    case .natural: .natural
                    case .sharp: .sharp
                    }
                    let y = staffCenter - CGFloat(accidental.pitch - 6) * staffStep
                    glyphs.append(
                        placedGlyph(
                            kind: kind,
                            anchor: CGPoint(x: x + unit.anchorOffset, y: y),
                            scale: glyphScale * 0.9
                        )
                    )

                case let .division(division):
                    appendDivision(
                        division,
                        x: x + unit.anchorOffset,
                        staffTop: staffTop,
                        staffGap: staffGap,
                        notationScale: notationScale,
                        strokes: &strokes
                    )

                case .forcedBreak:
                    break

                case let .lyricMark(mark):
                    lyrics.append(
                        GregorianPlacedLyric(
                            text: mark.text,
                            style: mark.style,
                            origin: CGPoint(
                                x: x + unit.anchorOffset - unit.lyricFocus,
                                y: staffBottom + lineMetrics.lyricOffset
                            ),
                            width: unit.lyricWidth,
                            fontSize: lyricFontSize,
                            neumeID: mark.id
                        )
                    )

                case let .neume(neume):
                    let notationLeft = x + unit.anchorOffset - unit.notationWidth / 2
                    let composition = compose(
                        neume: neume,
                        originX: notationLeft,
                        staffCenter: staffCenter,
                        staffTop: staffTop,
                        staffBottom: staffBottom,
                        staffStep: staffStep,
                        glyphScale: glyphScale,
                        notationScale: notationScale,
                        lineIndex: lineIndex
                    )
                    glyphs.append(contentsOf: composition.glyphs)
                    strokes.append(contentsOf: composition.strokes)
                    events.append(contentsOf: composition.events)

                    if !unit.lyricText.isEmpty {
                        lyrics.append(
                            GregorianPlacedLyric(
                                text: unit.lyricText,
                                style: neume.lyricStyle,
                                origin: CGPoint(
                                    x: x + unit.anchorOffset - unit.lyricFocus,
                                    y: staffBottom + lineMetrics.lyricOffset
                                ),
                                width: unit.lyricWidth,
                                fontSize: lyricFontSize,
                                neumeID: neume.id
                            )
                        )
                    }
                    rawNeumes.append(
                        RawNeumePlacement(
                            neume: neume,
                            inkFrame: composition.inkFrame,
                            lineIndex: lineIndex,
                            staffTop: staffTop,
                            staffBottom: staffBottom + lineMetrics.lyricOffset + lyricHeight
                        )
                    )
                }
                x += unit.width
                if gapAdjustments.indices.contains(unitIndex) {
                    x += gapAdjustments[unitIndex]
                }
            }

            if lineIndex + 1 < lines.count,
               let nextNote = lines[lineIndex + 1].compactMap(\.neume).first?.notes.first {
                let nextY = staffCenter - CGFloat(nextNote.pitch - 6) * staffStep
                glyphs.append(
                    placedGlyph(
                        kind: .custos,
                        anchor: CGPoint(x: width - sidePadding - 7 * notationScale, y: nextY),
                        scale: glyphScale
                    )
                )
            }
        }

        lyrics.append(
            contentsOf: automaticLyricHyphens(
                lines: lines,
                lyrics: lyrics,
                width: width,
                sidePadding: sidePadding,
                notationScale: notationScale,
                lyricFontSize: lyricFontSize
            )
        )
        strokes = mergeLedgerLines(strokes, scale: notationScale)
        let neumes = makeHitFrames(rawNeumes, width: width, scale: notationScale)
        return GregorianLayout(
            size: CGSize(width: width, height: max(64, contentHeight)),
            staffs: staffs,
            glyphs: glyphs,
            strokes: strokes,
            lyrics: lyrics,
            initials: initials,
            events: events,
            neumes: neumes
        )
    }

    private func automaticLyricHyphens(
        lines: [[LayoutUnit]],
        lyrics: [GregorianPlacedLyric],
        width: CGFloat,
        sidePadding: CGFloat,
        notationScale: CGFloat,
        lyricFontSize: CGFloat
    ) -> [GregorianPlacedLyric] {
        struct Syllable {
            let unit: LayoutUnit
            let neume: GregorianNeume
            let lyric: GregorianPlacedLyric
        }

        let lyricsByNeumeID = Dictionary(
            uniqueKeysWithValues: lyrics.map { ($0.neumeID, $0) }
        )
        let syllablesByLine = lines.map { line in
            line.compactMap { unit -> Syllable? in
                guard let neume = unit.neume,
                      !unit.lyricText.isEmpty,
                      let lyric = lyricsByNeumeID[neume.id] else {
                    return nil
                }
                return Syllable(unit: unit, neume: neume, lyric: lyric)
            }
        }
        let hyphenText = "-"
        let hyphenFontSize = lyricFontSize * 0.72
        let hyphenWidth = measureLyric(hyphenText, fontSize: hyphenFontSize)
        let minimumInlineHyphenGap = hyphenWidth - notationScale
        let minimumUnreservedHyphenGap = hyphenWidth + 1.5 * notationScale
        let lineEndClearance = max(1, 1.5 * notationScale)
        var hyphens: [GregorianPlacedLyric] = []

        func boundaryWordHasMultipleSyllables(
            _ previous: Syllable,
            _ next: Syllable
        ) -> Bool {
            let left = previous.unit.lyricText
                .split(whereSeparator: \.isWhitespace)
                .last
                .map { String($0.filter(\.isLetter)) } ?? ""
            let right = next.unit.lyricText
                .split(whereSeparator: \.isWhitespace)
                .first
                .map { String($0.filter(\.isLetter)) } ?? ""
            let folded = (left + right)
                .folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "la")
                )
                .lowercased()
                .replacingOccurrences(of: "æ", with: "ae")
                .replacingOccurrences(of: "œ", with: "oe")
            let letters = Array(folded)
            let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
            let diphthongs: Set<String> = ["ae", "au", "oe"]
            var nuclei = 0
            var index = 0
            while index < letters.count {
                let letter = letters[index]
                guard vowels.contains(letter) else {
                    index += 1
                    continue
                }
                if letter == "u", index > 0, letters[index - 1] == "q" {
                    index += 1
                    continue
                }
                nuclei += 1
                if index + 1 < letters.count,
                   diphthongs.contains(String([letter, letters[index + 1]])) {
                    index += 2
                } else {
                    index += 1
                }
            }
            return nuclei > 1
        }

        func shouldHyphenate(_ previous: Syllable, _ next: Syllable) -> Bool {
            next.unit.hyphenatesFromPrevious
                && previous.neume.syllableID != next.neume.syllableID
                && !previous.unit.lyricText.hasSuffix("-")
                && !next.unit.lyricText.hasPrefix("-")
                && boundaryWordHasMultipleSyllables(previous, next)
        }

        func makeHyphen(
            between previous: Syllable,
            and next: Syllable,
            originX: CGFloat,
            renderedWidth: CGFloat,
            renderedFontSize: CGFloat
        ) -> GregorianPlacedLyric {
            let verticalOffset = (
                lyricFontSize - renderedFontSize
            ) * Self.lyricLineHeightMultiplier / 2
            return GregorianPlacedLyric(
                text: hyphenText,
                origin: CGPoint(
                    x: originX,
                    y: previous.lyric.origin.y + verticalOffset
                ),
                width: renderedWidth,
                fontSize: renderedFontSize,
                neumeID: "lyric-hyphen-\(previous.neume.id)-\(next.neume.id)"
            )
        }

        for syllables in syllablesByLine {
            for (previous, next) in zip(syllables, syllables.dropFirst())
                where shouldHyphenate(previous, next) {
                let gapStart = previous.lyric.origin.x + previous.lyric.width
                let gapEnd = next.lyric.origin.x
                let availableWidth = gapEnd - gapStart
                // The unit-building pass reserves a connector lane when the
                // intrinsic musical spacing predicts one. Recheck the final
                // placed lyrics as well: wide neumes can leave additional
                // daylight even when the intrinsic pair looked compact.
                let hasReservedLane = next.unit.showsInlineHyphenFromPrevious
                guard hasReservedLane
                        ? availableWidth >= minimumInlineHyphenGap
                        : availableWidth >= minimumUnreservedHyphenGap else {
                    continue
                }
                hyphens.append(
                    makeHyphen(
                        between: previous,
                        and: next,
                        originX: gapStart + (availableWidth - hyphenWidth) / 2,
                        renderedWidth: hyphenWidth,
                        renderedFontSize: hyphenFontSize
                    )
                )
            }
        }

        guard syllablesByLine.count > 1 else { return hyphens }
        // The custos occupies the staff, while this mark is on the lyric
        // baseline, so the otherwise reserved custos column remains usable.
        let lineEnd = width - sidePadding
        for lineIndex in 0..<(syllablesByLine.count - 1) {
            guard let previous = syllablesByLine[lineIndex].last,
                  let next = syllablesByLine[lineIndex + 1].first,
                  shouldHyphenate(previous, next) else {
                continue
            }
            let gapStart = previous.lyric.origin.x + previous.lyric.width
            guard lineEnd - gapStart >= hyphenWidth + lineEndClearance else {
                continue
            }
            hyphens.append(
                makeHyphen(
                    between: previous,
                    and: next,
                    originX: gapStart + lineEndClearance,
                    renderedWidth: hyphenWidth,
                    renderedFontSize: hyphenFontSize
                )
            )
        }
        return hyphens
    }

    private struct LayoutUnit {
        let element: GregorianNotationElement
        let width: CGFloat
        let anchorOffset: CGFloat
        let notationWidth: CGFloat
        let lyricText: String
        let lyricWidth: CGFloat
        let lyricFocus: CGFloat
        let hyphenatesFromPrevious: Bool
        let showsInlineHyphenFromPrevious: Bool
        let breakPenalty: Int
        let forcesBreak: Bool

        var neume: GregorianNeume? {
            guard case let .neume(neume) = element else { return nil }
            return neume
        }
    }

    private struct RawNeumePlacement {
        let neume: GregorianNeume
        let inkFrame: CGRect
        let lineIndex: Int
        let staffTop: CGFloat
        let staffBottom: CGFloat
    }

    private struct Composition {
        var glyphs: [GregorianPlacedGlyph] = []
        var strokes: [GregorianPlacedStroke] = []
        var events: [GregorianEventPlacement] = []
        var inkFrame = CGRect.null
    }

    private struct LineVerticalMetrics {
        let topInset: CGFloat
        let lyricOffset: CGFloat
        let height: CGFloat
    }

    private struct OpeningInitial {
        let text: String
        let annotation: String?
        let remainder: String
        let neumeID: String
    }

    private func openingInitial(
        in score: GregorianScore,
        annotation: String?
    ) -> OpeningInitial? {
        guard let annotation,
              let neume = score.neumes.first(where: { !$0.lyric.isEmpty }),
              let initialIndex = neume.lyric.firstIndex(where: \.isUppercase) else {
            return nil
        }
        let prefix = neume.lyric[..<initialIndex]
        guard prefix.allSatisfy({
            $0.isWhitespace || $0.isNumber || $0 == "."
        }) else {
            return nil
        }
        return OpeningInitial(
            text: String(neume.lyric[initialIndex]),
            annotation: annotation,
            remainder: String(neume.lyric[neume.lyric.index(after: initialIndex)...]),
            neumeID: neume.id
        )
    }

    private func verticalMetrics(
        for units: [LayoutUnit],
        staffStep: CGFloat,
        staffGap: CGFloat,
        notationScale: CGFloat,
        lyricHeight: CGFloat,
        openingInitialFontSize: CGFloat?
    ) -> LineVerticalMetrics {
        let notes = units.compactMap(\.neume).flatMap(\.notes)
        let accidentalPitches = units.compactMap { unit -> Int? in
            guard case let .accidental(accidental) = unit.element else { return nil }
            return accidental.pitch
        }
        let pitches = notes.map(\.pitch) + accidentalPitches
        let highestPitch = pitches.max() ?? 9
        let lowestPitch = pitches.min() ?? 3
        let topInset = max(
            11 * notationScale,
            CGFloat(max(0, highestPitch - 9)) * staffStep + 10 * notationScale
        )
        let belowStaff = lowestPitch < 3
            ? CGFloat(3 - lowestPitch) * staffStep + 10 * notationScale
            : 0
        let lyricOffset = belowStaff > 0
            ? belowStaff + 6 * notationScale
            : 2 * notationScale
        let systemGap = 4 * notationScale
        let notationHeight = topInset + staffGap * 3 + lyricOffset + lyricHeight + systemGap
        let initialHeight = openingInitialFontSize.map {
            topInset + ceil($0 * 1.15) + systemGap
        } ?? 0
        let height = max(notationHeight, initialHeight)
        return LineVerticalMetrics(
            topInset: topInset,
            lyricOffset: lyricOffset,
            height: height
        )
    }

    private func makeUnits(
        score: GregorianScore,
        glyphScale: CGFloat,
        notationScale: CGFloat,
        lyricFontSize: CGFloat,
        openingInitial: OpeningInitial?
    ) -> [LayoutUnit] {
        var hasEngravedContent = false
        var previousWasAccidental = false
        var previousWasLyricMark = false
        var previousLyricSyllableID: String?
        var previousLyricText: String?
        var previousLyricNotationHalf: CGFloat?
        var previousLyricRightExtent: CGFloat?
        var interveningNotationWidth: CGFloat = 0
        var interveningUnitCount = 0
        let automaticHyphenFontSize = lyricFontSize * 0.72
        let automaticHyphenWidth = measureLyric(
            "-",
            fontSize: automaticHyphenFontSize
        )
        // Exsurge starts with normal inter-syllabic notation spacing, then
        // joins lyric fragments only when they would collide after modest
        // condensation. Keep this collision test conservative with CoreText's
        // EB Garamond metrics; the later line pass can still condense ordinary
        // (non-connector) gaps further. A connector is retained when the
        // musical spacing still leaves daylight between the fragments.
        let interSyllabicSpacing = 7.8125 * notationScale
        let condensedInterSyllabicSpacing = interSyllabicSpacing * 0.8
        let lyricCollisionTolerance = 0.1 * notationScale
        return score.elements.map { element in
            switch element {
            case .clef:
                previousWasAccidental = false
                previousWasLyricMark = false
                let width = hasEngravedContent ? 24 * notationScale : 0
                if previousLyricText != nil {
                    interveningNotationWidth += width
                    interveningUnitCount += 1
                }
                return LayoutUnit(
                    element: element,
                    width: width,
                    anchorOffset: 0,
                    notationWidth: 18 * notationScale,
                    lyricText: "",
                    lyricWidth: 0,
                    lyricFocus: 0,
                    hyphenatesFromPrevious: false,
                    showsInlineHyphenFromPrevious: false,
                    breakPenalty: 1_000,
                    forcesBreak: false
                )
            case let .accidental(accidental):
                hasEngravedContent = true
                previousWasAccidental = true
                previousWasLyricMark = false
                let kind: GregorianGlyphKind = switch accidental.kind {
                case .flat: .flat
                case .natural: .natural
                case .sharp: .sharp
                }
                let definition = GregorianGlyphCatalog.definition(for: kind.catalogName)
                let width = definition.bounds.width * glyphScale * 0.9
                    + 4 * notationScale
                if previousLyricText != nil {
                    interveningNotationWidth += width
                    interveningUnitCount += 1
                }
                return LayoutUnit(
                    element: element,
                    width: width,
                    anchorOffset: width / 2,
                    notationWidth: width,
                    lyricText: "",
                    lyricWidth: 0,
                    lyricFocus: 0,
                    hyphenatesFromPrevious: false,
                    showsInlineHyphenFromPrevious: false,
                    // Permit wrapping before an accidental, but never between
                    // the accidental and the neume it governs.
                    breakPenalty: 18,
                    forcesBreak: false
                )
            case let .division(division):
                hasEngravedContent = true
                previousWasAccidental = false
                previousWasLyricMark = false
                let width = (division == .final ? 17 : 12) * notationScale
                if previousLyricText != nil {
                    interveningNotationWidth += width
                    interveningUnitCount += 1
                }
                return LayoutUnit(
                    element: element,
                    width: width,
                    anchorOffset: width / 2,
                    notationWidth: width,
                    lyricText: "",
                    lyricWidth: 0,
                    lyricFocus: 0,
                    hyphenatesFromPrevious: false,
                    showsInlineHyphenFromPrevious: false,
                    // A division belongs at the end of a phrase, not at the
                    // beginning of the next staff. The following word offers
                    // the usable break point after the bar.
                    breakPenalty: 1_000,
                    forcesBreak: false
                )
            case .forcedBreak:
                previousWasAccidental = false
                previousWasLyricMark = false
                return LayoutUnit(
                    element: element,
                    width: 0,
                    anchorOffset: 0,
                    notationWidth: 0,
                    lyricText: "",
                    lyricWidth: 0,
                    lyricFocus: 0,
                    hyphenatesFromPrevious: false,
                    showsInlineHyphenFromPrevious: false,
                    breakPenalty: 0,
                    forcesBreak: true
                )
            case let .lyricMark(mark):
                hasEngravedContent = true
                previousWasAccidental = false
                previousWasLyricMark = true
                let lyric = lyricMetrics(
                    mark.text,
                    style: mark.style,
                    fontSize: lyricFontSize
                )
                let leadingPadding = (mark.startsWord ? 5 : 2) * notationScale
                let trailingPadding = 5 * notationScale
                let width = leadingPadding + lyric.width + trailingPadding
                if previousLyricText != nil {
                    interveningNotationWidth += width
                    interveningUnitCount += 1
                }
                return LayoutUnit(
                    element: element,
                    width: width,
                    anchorOffset: leadingPadding + lyric.focus,
                    notationWidth: 0,
                    lyricText: mark.text,
                    lyricWidth: lyric.width,
                    lyricFocus: lyric.focus,
                    hyphenatesFromPrevious: false,
                    showsInlineHyphenFromPrevious: false,
                    // A note-less rubric belongs between the neighboring
                    // syllables and should not begin a staff by itself.
                    breakPenalty: 1_000,
                    forcesBreak: false
                )
            case let .neume(neume):
                hasEngravedContent = true
                let followsUnbreakableElement = previousWasAccidental
                    || previousWasLyricMark
                let notationWidth = estimatedNotationWidth(neume, glyphScale: glyphScale)
                let lyricText = neume.id == openingInitial?.neumeID
                    ? openingInitial?.remainder ?? neume.lyric
                    : neume.lyric
                let followsDifferentSyllable = previousLyricSyllableID.map {
                    $0 != neume.syllableID
                } ?? false
                let followsExplicitHyphen = previousLyricText.map {
                    $0.hasSuffix("-")
                } ?? false
                let hyphenatesFromPrevious = !lyricText.isEmpty
                    && !neume.startsWord
                    && !previousWasLyricMark
                    && followsDifferentSyllable
                    && !followsExplicitHyphen
                    && !lyricText.hasPrefix("-")
                previousWasAccidental = false
                previousWasLyricMark = false
                let lyric = lyricMetrics(
                    lyricText,
                    style: neume.lyricStyle,
                    fontSize: lyricFontSize
                )
                let notationHalf = notationWidth / 2
                let leftExtent = max(notationHalf, lyric.focus)
                let rightExtent = max(notationHalf, lyric.width - lyric.focus)
                let leadingPadding: CGFloat
                let showsInlineHyphenFromPrevious: Bool
                if neume.startsWord {
                    leadingPadding = 5 * notationScale
                    showsInlineHyphenFromPrevious = false
                } else {
                    let condensedNaturalDistance = (
                        previousLyricNotationHalf.map {
                            $0
                                + condensedInterSyllabicSpacing
                                + interveningNotationWidth
                                + notationHalf
                        }
                    )
                    let lyricTouchDistance = previousLyricRightExtent.map {
                        $0 + leftExtent
                    }
                    let needsConnector: Bool
                    if hyphenatesFromPrevious,
                       let condensedNaturalDistance,
                       let lyricTouchDistance {
                        needsConnector = condensedNaturalDistance
                            - lyricTouchDistance
                            > lyricCollisionTolerance
                            || interveningUnitCount > 0
                    } else {
                        needsConnector = false
                    }
                    showsInlineHyphenFromPrevious = needsConnector
                    if needsConnector,
                       let previousNotationHalf = previousLyricNotationHalf,
                       let previousRightExtent = previousLyricRightExtent {
                        let naturalDistance = previousNotationHalf
                            + interSyllabicSpacing
                            + interveningNotationWidth
                            + notationHalf
                        let naturalGap = naturalDistance
                            - previousRightExtent
                            - leftExtent
                        // Line fitting may condense every intervening unit
                        // boundary. Reserve that allowance as part of the
                        // connector lane so melismas do not squeeze the
                        // hyphen back out after it has been selected.
                        leadingPadding = max(
                            automaticHyphenWidth
                                + 2.5 * notationScale
                                    * CGFloat(interveningUnitCount),
                            naturalGap
                        )
                    } else {
                        leadingPadding = 0
                    }
                }
                let trailingPadding: CGFloat = 0
                let contentWidth = leadingPadding + leftExtent + rightExtent + trailingPadding
                let width = neume.startsWord
                    ? max(24 * notationScale, contentWidth)
                    : contentWidth
                let centeringInset = (width - contentWidth) / 2
                if !lyricText.isEmpty {
                    previousLyricSyllableID = neume.syllableID
                    previousLyricText = lyricText
                    previousLyricNotationHalf = notationHalf
                    previousLyricRightExtent = rightExtent
                    interveningNotationWidth = 0
                    interveningUnitCount = 0
                } else if previousLyricText != nil {
                    interveningNotationWidth += width
                    interveningUnitCount += 1
                }
                return LayoutUnit(
                    element: element,
                    width: width,
                    anchorOffset: centeringInset + leadingPadding + leftExtent,
                    notationWidth: notationWidth,
                    lyricText: lyricText,
                    lyricWidth: lyric.width,
                    lyricFocus: lyric.focus,
                    hyphenatesFromPrevious: hyphenatesFromPrevious,
                    showsInlineHyphenFromPrevious: showsInlineHyphenFromPrevious,
                    // Chant may wrap between syllables when that produces a
                    // fuller staff (for example "pró-" / "ximos").
                    breakPenalty: followsUnbreakableElement ? 1_000 : 18,
                    forcesBreak: false
                )
            }
        }
    }

    private func estimatedNotationWidth(_ neume: GregorianNeume, glyphScale: CGFloat) -> CGFloat {
        let punctum = 100 * glyphScale
        switch neume.form {
        case .podatus, .pesQuassus:
            return punctum * 1.15
        case .porrectus, .porrectusFlexus:
            let interval = max(1, min(4, abs((neume.notes.first?.pitch ?? 0) - (neume.notes.dropFirst().first?.pitch ?? 0))))
            let name: GregorianGlyphName = switch interval {
            case 1: .porrectus1
            case 2: .porrectus2
            case 3: .porrectus3
            default: .porrectus4
            }
            let swash = GregorianGlyphCatalog.definition(for: name).bounds.width * glyphScale
            return swash + punctum * CGFloat(max(1, neume.notes.count - 2))
        case .climacus, .ancus, .punctaInclinata:
            return punctum + CGFloat(max(0, neume.notes.count - 1)) * punctum * 0.72
        default:
            return punctum + CGFloat(max(0, neume.notes.count - 1)) * punctum * 0.92
        }
    }

    private func breakLines(
        units: [LayoutUnit],
        firstAvailableWidth: CGFloat,
        continuationAvailableWidth: CGFloat
    ) -> [[LayoutUnit]] {
        guard !units.isEmpty else { return [[]] }
        var lines: [[LayoutUnit]] = []
        var current: [LayoutUnit] = []
        var currentWidth: CGFloat = 0
        var candidates: [(index: Int, penalty: Int)] = []

        func availableWidth() -> CGFloat {
            lines.isEmpty ? firstAvailableWidth : continuationAvailableWidth
        }

        func commit(_ count: Int? = nil) {
            let split = count ?? current.count
            let prefix = current.prefix(split).filter {
                if case .forcedBreak = $0.element { return false }
                return true
            }
            if !prefix.isEmpty { lines.append(Array(prefix)) }
            current = Array(current.dropFirst(split))
            currentWidth = current.reduce(0) { $0 + $1.width }
            candidates = current.enumerated().compactMap { index, unit in
                guard index > 0,
                      current.prefix(index).contains(where: { $0.neume != nil }) else {
                    return nil
                }
                return (index, unit.breakPenalty)
            }
        }

        for unit in units {
            current.append(unit)
            currentWidth += unit.width
            let splitBeforeUnit = current.count - 1
            if splitBeforeUnit > 0,
               current.prefix(splitBeforeUnit).contains(where: { $0.neume != nil }) {
                candidates.append((splitBeforeUnit, unit.breakPenalty))
            }
            if unit.forcesBreak {
                commit()
            } else if currentWidth > availableWidth(), current.count > 1 {
                // Permit modest condensation before wrapping, as Exsurge does.
                let condensible = CGFloat(current.count - 1) * 2.5
                if currentWidth - availableWidth() <= condensible { continue }
                let fallback = current.count - 1
                let earliest = max(1, fallback / 2)
                let split = candidates
                    .filter { $0.index >= earliest && $0.index < current.count }
                    .min { lhs, rhs in
                        lhs.penalty == rhs.penalty ? lhs.index > rhs.index : lhs.penalty < rhs.penalty
                    }?.index ?? fallback
                commit(split)
            }
        }
        commit()
        return lines.isEmpty ? [[]] : lines
    }

    private func compose(
        neume: GregorianNeume,
        originX: CGFloat,
        staffCenter: CGFloat,
        staffTop: CGFloat,
        staffBottom: CGFloat,
        staffStep: CGFloat,
        glyphScale: CGFloat,
        notationScale: CGFloat,
        lineIndex: Int
    ) -> Composition {
        var result = Composition()
        let punctumWidth = 100 * glyphScale
        var noteOrigins: [CGFloat] = []

        switch neume.form {
        case .podatus where neume.notes.count >= 2,
             .pesQuassus where neume.notes.count >= 2:
            noteOrigins = Array(repeating: originX, count: neume.notes.count)
            if neume.notes.count > 2 {
                for index in 2..<neume.notes.count {
                    noteOrigins[index] = originX + punctumWidth * CGFloat(index - 1)
                }
            }
        case .climacus, .ancus, .punctaInclinata:
            noteOrigins = neume.notes.indices.map { originX + CGFloat($0) * punctumWidth * 0.72 }
        case .porrectus where neume.notes.count >= 3,
             .porrectusFlexus where neume.notes.count >= 3:
            let interval = max(1, min(4, abs(neume.notes[0].pitch - neume.notes[1].pitch)))
            let name: GregorianGlyphName = switch interval {
            case 1: .porrectus1
            case 2: .porrectus2
            case 3: .porrectus3
            default: .porrectus4
            }
            let swashWidth = GregorianGlyphCatalog.definition(for: name).bounds.width * glyphScale
            noteOrigins = [originX, originX + swashWidth - punctumWidth]
            for index in 2..<neume.notes.count {
                noteOrigins.append(originX + swashWidth + CGFloat(index - 2) * punctumWidth * 0.92)
            }
        default:
            noteOrigins = neume.notes.indices.map { originX + CGFloat($0) * punctumWidth * 0.92 }
        }

        for (index, note) in neume.notes.enumerated() {
            let y = staffCenter - CGFloat(note.pitch - 6) * staffStep
            let noteOriginX = noteOrigins[index]
            var glyphName = glyphName(for: note)
            if note.shape == .oriscus, note.liquescence == .none,
               index + 1 < neume.notes.count {
                glyphName = neume.notes[index + 1].pitch < note.pitch ? .oriscusDes : .oriscusAsc
            }

            if [.apostropha, .distropha, .tristropha].contains(neume.form) {
                glyphName = .stropha
            } else if neume.form == .pesQuassus, neume.notes.count >= 2 {
                glyphName = index == 0 ? .oriscusAsc : (index == 1 ? .podatusUpper : glyphName)
            } else if neume.form == .podatus, neume.notes.count >= 2 {
                glyphName = index == 0 ? .podatusLower : (index == 1 ? .podatusUpper : glyphName)
            } else if (neume.form == .porrectus || neume.form == .porrectusFlexus), index == 0 {
                let interval = max(1, min(4, abs(neume.notes[0].pitch - neume.notes[1].pitch)))
                glyphName = switch interval {
                case 1: .porrectus1
                case 2: .porrectus2
                case 3: .porrectus3
                default: .porrectus4
                }
            } else if (neume.form == .porrectus || neume.form == .porrectusFlexus), index == 1 {
                // The porrectus swash already engraves the first two notes.
                let frame = CGRect(
                    x: noteOriginX,
                    y: y - punctumWidth / 2,
                    width: punctumWidth,
                    height: punctumWidth
                )
                appendEvent(note, neume: neume, frame: frame, lineIndex: lineIndex, to: &result)
                continue
            }

            let definition = GregorianGlyphCatalog.definition(for: glyphName)
            let anchorX: CGFloat
            if glyphName == .podatusUpper {
                anchorX = noteOriginX + definition.bounds.width * glyphScale
            } else {
                anchorX = noteOriginX + definition.origin.x * glyphScale
            }
            let placed = placedGlyph(
                kind: .catalog(glyphName),
                anchor: CGPoint(x: anchorX, y: y),
                scale: glyphScale,
                eventID: note.id
            )

            if let accidental = note.accidental {
                let accidentalKind: GregorianGlyphKind = switch accidental {
                case .flat: .flat
                case .natural: .natural
                case .sharp: .sharp
                }
                let accidentalScale = glyphScale * 0.9
                let accidentalDefinition = GregorianGlyphCatalog.definition(
                    for: accidentalKind.catalogName
                )
                let accidentalMinX = placed.frame.minX
                    - accidentalDefinition.bounds.width * accidentalScale
                    - 2 * notationScale
                let accidentalGlyph = placedGlyph(
                    kind: accidentalKind,
                    anchor: CGPoint(
                        x: accidentalMinX + accidentalDefinition.origin.x * accidentalScale,
                        y: y
                    ),
                    scale: accidentalScale,
                    eventID: note.id
                )
                result.glyphs.append(accidentalGlyph)
                result.inkFrame = result.inkFrame.union(accidentalGlyph.frame)
            }

            if index > 0,
               ![GregorianNeumeForm.podatus, .pesQuassus, .porrectus, .porrectusFlexus]
                .contains(neume.form) {
                let previous = neume.notes[index - 1]
                if previous.pitch != note.pitch {
                    let previousY = staffCenter - CGFloat(previous.pitch - 6) * staffStep
                    let connectorX = noteOriginX + 0.7 * glyphScale
                    result.strokes.append(
                        GregorianPlacedStroke(
                            kind: .connector,
                            start: CGPoint(x: connectorX, y: previousY),
                            end: CGPoint(x: connectorX, y: y),
                            lineWidth: max(1, 18 * glyphScale),
                            eventID: note.id
                        )
                    )
                }
            }

            result.glyphs.append(placed)
            result.inkFrame = result.inkFrame.union(placed.frame)

            if note.moraCount > 0 {
                for moraIndex in 0..<note.moraCount {
                    let mora = placedGlyph(
                        kind: .mora,
                        anchor: CGPoint(
                            x: placed.frame.maxX + (5 + CGFloat(moraIndex) * 3.5) * notationScale,
                            y: y
                        ),
                        scale: glyphScale * 0.72,
                        eventID: note.id
                    )
                    result.glyphs.append(mora)
                    result.inkFrame = result.inkFrame.union(mora.frame)
                }
            }
            if note.hasEpisema {
                let above = note.episemaPosition == .above
                let episemaY = above ? placed.frame.minY - 3 * notationScale : placed.frame.maxY + 3 * notationScale
                result.strokes.append(
                    GregorianPlacedStroke(
                        kind: .episema,
                        start: CGPoint(x: placed.frame.minX - notationScale, y: episemaY),
                        end: CGPoint(x: placed.frame.maxX + notationScale, y: episemaY),
                        lineWidth: max(1, 1.3 * notationScale),
                        eventID: note.id
                    )
                )
            }
            if note.hasIctus {
                let above = note.episemaPosition == .above
                let ictusName: GregorianGlyphName = above
                    ? .verticalEpisemaAbove
                    : .verticalEpisemaBelow
                let ictus = placedGlyph(
                    kind: .catalog(ictusName),
                    anchor: CGPoint(
                        x: placed.frame.midX,
                        y: above
                            ? placed.frame.minY - 2 * notationScale
                            : placed.frame.maxY + 2 * notationScale
                    ),
                    scale: glyphScale,
                    eventID: note.id
                )
                result.glyphs.append(ictus)
                result.inkFrame = result.inkFrame.union(ictus.frame)
            }

            appendLedgerLines(
                for: placed.frame,
                staffTop: staffTop,
                staffBottom: staffBottom,
                staffGap: staffStep * 2,
                scale: notationScale,
                eventID: note.id,
                strokes: &result.strokes
            )
            appendEvent(note, neume: neume, frame: placed.frame, lineIndex: lineIndex, to: &result)
        }
        return result
    }

    private func glyphName(for note: GregorianNote) -> GregorianGlyphName {
        if note.isCavum { return .punctumCavum }
        switch note.shape {
        case .punctum:
            return switch note.liquescence {
            case .ascending: .punctumQuadratumAscLiquescent
            case .descending: .punctumQuadratumDesLiquescent
            case .small: .punctumQuadratumLiquescent
            case .none: .punctumQuadratum
            }
        case .virga: return .virgaShort
        case .quilisma: return .quilisma
        case .liquescent:
            return note.liquescence == .ascending
                ? .terminatingAscLiquescent
                : .terminatingDesLiquescent
        case .inclinatum:
            return note.liquescence == .none ? .punctumInclinatum : .punctumInclinatumLiquescent
        case .oriscus:
            return note.liquescence == .none ? .oriscusAsc : .oriscusLiquescent
        case .stropha: return .stropha
        }
    }

    private func appendEvent(
        _ note: GregorianNote,
        neume: GregorianNeume,
        frame: CGRect,
        lineIndex: Int,
        to result: inout Composition
    ) {
        result.events.append(
            GregorianEventPlacement(
                eventID: note.id,
                neumeID: neume.id,
                frame: frame.insetBy(dx: -2, dy: -4),
                lineIndex: lineIndex
            )
        )
        result.inkFrame = result.inkFrame.union(frame)
    }

    private func appendClef(
        _ clef: GregorianClef,
        x: CGFloat,
        staffTop: CGFloat,
        staffGap: CGFloat,
        glyphScale: CGFloat,
        glyphs: inout [GregorianPlacedGlyph]
    ) {
        let lineY = staffTop + CGFloat(4 - clef.line) * staffGap
        let kind: GregorianGlyphKind = clef.kind == .c ? .cClef : .fClef
        glyphs.append(
            placedGlyph(
                kind: kind,
                anchor: CGPoint(x: x, y: lineY),
                scale: glyphScale
            )
        )
        if clef.flattensB {
            let staffCenter = staffTop + staffGap * 1.5
            let bPitchY = staffCenter - CGFloat(1 - 6) * (staffGap / 2)
            glyphs.append(
                placedGlyph(
                    kind: .flat,
                    anchor: CGPoint(x: x + 11 * glyphScale, y: bPitchY),
                    scale: glyphScale * 0.9
                )
            )
        }
    }

    private func appendDivision(
        _ division: GregorianDivision,
        x: CGFloat,
        staffTop: CGFloat,
        staffGap: CGFloat,
        notationScale: CGFloat,
        strokes: inout [GregorianPlacedStroke]
    ) {
        let height: CGFloat = switch division {
        case .minima: staffGap
        case .minor: staffGap * 2
        case .major, .final: staffGap * 3
        }
        let top = division == .minima
            ? staffTop + staffGap
            : staffTop + (staffGap * 3 - height) / 2
        let count = division == .final ? 2 : 1
        for index in 0..<count {
            let barX = x + CGFloat(index) * 4 * notationScale
            strokes.append(
                GregorianPlacedStroke(
                    kind: .division(division),
                    start: CGPoint(x: barX, y: top),
                    end: CGPoint(x: barX, y: top + height),
                    lineWidth: max(1.2, 1.45 * notationScale)
                )
            )
        }
    }

    private func placedGlyph(
        kind: GregorianGlyphKind,
        anchor: CGPoint,
        scale: CGFloat,
        eventID: String? = nil
    ) -> GregorianPlacedGlyph {
        let definition = GregorianGlyphCatalog.definition(for: kind.catalogName)
        return GregorianPlacedGlyph(
            kind: kind,
            frame: CGRect(
                x: anchor.x - definition.origin.x * scale,
                y: anchor.y - definition.origin.y * scale,
                width: definition.bounds.width * scale,
                height: definition.bounds.height * scale
            ),
            eventID: eventID
        )
    }

    private func lyricMetrics(
        _ lyric: String,
        style: GregorianLyricStyle,
        fontSize: CGFloat
    ) -> (width: CGFloat, focus: CGFloat) {
        guard !lyric.isEmpty else { return (0, 0) }
        let width = measureLyric(lyric, style: style, fontSize: fontSize)
        let characters = Array(lyric)
        let vowelSet = CharacterSet(charactersIn: "aeiouyæœáéíóúýAEIOUYÆŒÁÉÍÓÚÝ")
        let nucleusStart = characters.firstIndex {
            $0.unicodeScalars.contains { vowelSet.contains($0) }
        } ?? characters.startIndex
        var nucleusEnd = nucleusStart
        while nucleusEnd + 1 < characters.count,
              characters[nucleusEnd + 1].unicodeScalars.contains(where: vowelSet.contains) {
            nucleusEnd += 1
        }
        let prefix = String(characters.prefix(nucleusStart))
        let nucleus = String(characters[nucleusStart...nucleusEnd])
        let focus = measureLyric(prefix, style: style, fontSize: fontSize)
            + measureLyric(nucleus, style: style, fontSize: fontSize) / 2
        return (width, focus)
    }

    private func measureLyric(
        _ lyric: String,
        style: GregorianLyricStyle = .regular,
        fontSize: CGFloat
    ) -> CGFloat {
        guard !lyric.isEmpty else { return 0 }
        let regularFont = CTFontCreateWithName(
            "EBGaramond-Regular" as CFString,
            fontSize,
            nil
        )
        let traits: CTFontSymbolicTraits = switch style {
        case .accented:
            .boldTrait
        case .preparatory:
            .italicTrait
        case .regular, .rubric:
            []
        }
        let font = traits.isEmpty
            ? regularFont
            : CTFontCreateCopyWithSymbolicTraits(
                regularFont,
                fontSize,
                nil,
                traits,
                traits
            ) ?? regularFont
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, lyric as CFString, attributes)!
        let line = CTLineCreateWithAttributedString(attributed)
        return ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    private func appendLedgerLines(
        for frame: CGRect,
        staffTop: CGFloat,
        staffBottom: CGFloat,
        staffGap: CGFloat,
        scale: CGFloat,
        eventID: String,
        strokes: inout [GregorianPlacedStroke]
    ) {
        if frame.midY <= staffTop - staffGap / 2 {
            var y = staffTop - staffGap
            while y >= frame.midY - 1 {
                strokes.append(
                    GregorianPlacedStroke(
                        kind: .ledger,
                        start: CGPoint(x: frame.minX - 3 * scale, y: y),
                        end: CGPoint(x: frame.maxX + 3 * scale, y: y),
                        lineWidth: scale,
                        eventID: eventID
                    )
                )
                y -= staffGap
            }
        } else if frame.midY >= staffBottom + staffGap / 2 {
            var y = staffBottom + staffGap
            while y <= frame.midY + 1 {
                strokes.append(
                    GregorianPlacedStroke(
                        kind: .ledger,
                        start: CGPoint(x: frame.minX - 3 * scale, y: y),
                        end: CGPoint(x: frame.maxX + 3 * scale, y: y),
                        lineWidth: scale,
                        eventID: eventID
                    )
                )
                y += staffGap
            }
        }
    }

    private func mergeLedgerLines(
        _ strokes: [GregorianPlacedStroke],
        scale: CGFloat
    ) -> [GregorianPlacedStroke] {
        let nonLedger = strokes.filter {
            if case .ledger = $0.kind { return false }
            return true
        }
        let ledgers = strokes.filter {
            if case .ledger = $0.kind { return true }
            return false
        }.sorted {
            abs($0.start.y - $1.start.y) < 0.1
                ? $0.start.x < $1.start.x
                : $0.start.y < $1.start.y
        }
        var merged: [GregorianPlacedStroke] = []
        for ledger in ledgers {
            if let last = merged.last,
               abs(last.start.y - ledger.start.y) < 0.1,
               ledger.start.x <= last.end.x + 2 * scale {
                merged[merged.count - 1] = GregorianPlacedStroke(
                    kind: .ledger,
                    start: last.start,
                    end: CGPoint(x: max(last.end.x, ledger.end.x), y: last.end.y),
                    lineWidth: max(last.lineWidth, ledger.lineWidth),
                    eventID: last.eventID
                )
            } else {
                merged.append(ledger)
            }
        }
        return nonLedger + merged
    }

    private func makeHitFrames(
        _ raw: [RawNeumePlacement],
        width: CGFloat,
        scale: CGFloat
    ) -> [GregorianNeumePlacement] {
        var result: [GregorianNeumePlacement] = []
        let grouped = Dictionary(grouping: raw, by: \.lineIndex)
        for lineIndex in grouped.keys.sorted() {
            let placements = (grouped[lineIndex] ?? []).sorted { $0.inkFrame.midX < $1.inkFrame.midX }
            for (index, placement) in placements.enumerated() {
                let previousMid = index > 0 ? placements[index - 1].inkFrame.midX : 0
                let nextMid = index + 1 < placements.count
                    ? placements[index + 1].inkFrame.midX
                    : width
                let leftBoundary = index > 0
                    ? (previousMid + placement.inkFrame.midX) / 2
                    : max(0, placement.inkFrame.midX - 22 * scale)
                let rightBoundary = index + 1 < placements.count
                    ? (placement.inkFrame.midX + nextMid) / 2
                    : min(width, placement.inkFrame.midX + 22 * scale)
                let desiredWidth = max(44, placement.inkFrame.width + 14 * scale)
                let centeredLeft = placement.inkFrame.midX - desiredWidth / 2
                let hitLeft = max(leftBoundary, centeredLeft)
                let hitRight = min(rightBoundary, hitLeft + desiredWidth)
                result.append(
                    GregorianNeumePlacement(
                        id: placement.neume.id,
                        eventIDs: placement.neume.eventIDs,
                        lyric: placement.neume.lyric,
                        inkFrame: placement.inkFrame,
                        hitFrame: CGRect(
                            x: hitLeft,
                            y: placement.staffTop - 7 * scale,
                            width: max(1, hitRight - hitLeft),
                            height: max(44, placement.staffBottom - placement.staffTop + 7 * scale)
                        ),
                        lineIndex: lineIndex
                    )
                )
            }
        }
        return result
    }
}
