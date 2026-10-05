import CoreText
import HoursCore
import OSLog
import SwiftUI
import UIKit

nonisolated struct OfficePrintSnapshot: Sendable {
    let office: OfficeDocument
    let sections: [OfficeSection]
    let showsEnglish: Bool
    let usesCompactPsalmody: Bool
    let isPriestOrDeaconPresent: Bool
    let readerScale: Double

    init(
        office: OfficeDocument,
        showsEnglish: Bool,
        usesCompactPsalmody: Bool,
        isPriestOrDeaconPresent: Bool,
        readerScale: Double
    ) {
        self.office = office
        sections = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format,
            usesCompactPsalmody: usesCompactPsalmody
        )
        self.showsEnglish = showsEnglish
        self.usesCompactPsalmody = usesCompactPsalmody
        self.isPriestOrDeaconPresent = isPriestOrDeaconPresent
        self.readerScale = GregorianLayoutMetrics.clampedNotationScale(
            readerScale
        )
    }

    var jobName: String {
        "\(office.hour.englishTitle) — \(office.date.description)"
    }

    func adjustedPrayerText(_ text: String) -> String {
        OfficePrayerText.adjusted(
            text,
            isPriestOrDeaconPresent: isPriestOrDeaconPresent
        )
    }
}

nonisolated enum OfficePrintError: LocalizedError {
    case printingUnavailable
    case notationPreparationFailed(String)
    case presentationFailed

    var errorDescription: String? {
        switch self {
        case .printingUnavailable:
            "Printing is unavailable on this device."
        case .notationPreparationFailed(let incipit):
            "The chant notation for \(incipit) could not be prepared."
        case .presentationFailed:
            "The system print options could not be opened."
        }
    }
}

@MainActor
enum OfficePrintPresenter {
    private static let logger = Logger(
        subsystem: "com.matthewmccarty.hours",
        category: "OfficePrinting"
    )

    static var isPrintingAvailable: Bool {
        UIPrintInteractionController.isPrintingAvailable
    }

    static func present(
        snapshot: OfficePrintSnapshot,
        onError: @escaping @MainActor (String) -> Void
    ) async throws {
        guard isPrintingAvailable else {
            throw OfficePrintError.printingUnavailable
        }

        let renderer = try await OfficePrintPageRenderer.prepare(
            snapshot: snapshot
        )
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = snapshot.jobName
        printInfo.outputType = .general
        printInfo.orientation = .portrait
        printInfo.duplex = .longEdge
        controller.printInfo = printInfo
        controller.printPageRenderer = renderer

        let didPresent = controller.present(animated: true) {
            _, _, error in
            guard let error else { return }
            logger.error(
                "Print job failed: \(error.localizedDescription, privacy: .public)"
            )
            Task { @MainActor in
                onError(error.localizedDescription)
            }
        }
        guard didPresent else {
            throw OfficePrintError.presentationFailed
        }
    }
}

nonisolated final class OfficePrintPageRenderer: UIPrintPageRenderer {
    static let logicalPageWidth: CGFloat = 540
    static let logicalContentWidth: CGFloat = 500
    // Chant glyphs are visually wider than their staff strokes. Give full
    // notation an additional print-only gutter so the layout wraps before
    // either edge of the printable page.
    static let logicalScoreWidth: CGFloat = 476

    private let snapshot: OfficePrintSnapshot
    private let scorePreparations: [String: GregorianPreparedScore]
    private var cachedLayout: CachedLayout?

    private init(
        snapshot: OfficePrintSnapshot,
        scorePreparations: [String: GregorianPreparedScore]
    ) {
        self.snapshot = snapshot
        self.scorePreparations = scorePreparations
        super.init()
    }

    static func prepare(
        snapshot: OfficePrintSnapshot
    ) async throws -> OfficePrintPageRenderer {
        var seenScoreIDs: Set<String> = []
        let scores = snapshot.sections.compactMap(\.chant).filter {
            seenScoreIDs.insert($0.id).inserted
        }
        let preparations = await GregorianScorePreparer.prepare(
            scores: scores,
            width: logicalScoreWidth,
            metrics: GregorianLayoutMetrics(
                notationScale: snapshot.readerScale,
                lyricScale: 1
            )
        )
        var preparedScores: [String: GregorianPreparedScore] = [:]
        for score in scores {
            guard let preparation = preparations[score.id] else {
                throw OfficePrintError.notationPreparationFailed(score.incipit)
            }
            switch preparation {
            case .ready(let prepared):
                preparedScores[score.id] = prepared
            case .failed:
                throw OfficePrintError.notationPreparationFailed(score.incipit)
            }
        }
        return OfficePrintPageRenderer(
            snapshot: snapshot,
            scorePreparations: preparedScores
        )
    }

    override var numberOfPages: Int {
        layout().pages.count
    }

    override func prepare(forDrawingPages range: NSRange) {
        _ = layout()
    }

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        let layout = layout()
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        draw(
            pageIndex: pageIndex,
            layout: layout,
            in: printableRect,
            context: context
        )
    }

    func testPDFData(pageSize: CGSize) -> Data {
        let layout = makeLayout(printableSize: pageSize)
        let bounds = CGRect(origin: .zero, size: pageSize)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            for pageIndex in layout.pages.indices {
                renderer.beginPage()
                draw(
                    pageIndex: pageIndex,
                    layout: layout,
                    in: bounds,
                    context: renderer.cgContext
                )
            }
        }
    }

    func testTextInkBalanceWithFlippedInputMatrix() -> OfficePrintInkBalance {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 90, height: 90),
            format: format
        ).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 90, height: 90))
            renderer.cgContext.textMatrix = CGAffineTransform(
                scaleX: 1,
                y: -1
            )
            draw(
                text: OfficePrintStyle.text("L", size: 64),
                in: CGRect(x: 12, y: 8, width: 66, height: 74),
                context: renderer.cgContext
            )
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return OfficePrintInkBalance(top: 0, bottom: 0)
        }

        var inkByRow = Array(repeating: 0, count: cgImage.height)
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = y * cgImage.bytesPerRow + x * 4
                if bytes[offset] < 180
                    || bytes[offset + 1] < 180
                    || bytes[offset + 2] < 180 {
                    inkByRow[y] += 1
                }
            }
        }
        guard let first = inkByRow.firstIndex(where: { $0 > 0 }),
              let last = inkByRow.lastIndex(where: { $0 > 0 }) else {
            return OfficePrintInkBalance(top: 0, bottom: 0)
        }
        let midpoint = (first + last) / 2
        return OfficePrintInkBalance(
            top: inkByRow[first...midpoint].reduce(0, +),
            bottom: inkByRow[(midpoint + 1)...last].reduce(0, +)
        )
    }

    private func draw(
        pageIndex: Int,
        layout: CachedLayout,
        in printableRect: CGRect,
        context: CGContext
    ) {
        guard layout.pages.indices.contains(pageIndex) else { return }

        let page = layout.pages[pageIndex]
        context.saveGState()
        context.translateBy(x: printableRect.minX, y: printableRect.minY)
        context.scaleBy(x: layout.scale, y: layout.scale)
        UIColor.white.setFill()
        context.fill(
            CGRect(
                origin: .zero,
                size: CGSize(
                    width: Self.logicalPageWidth,
                    height: layout.logicalPageHeight
                )
            )
        )

        for item in page.items {
            switch item.content {
            case .text(let text, _):
                draw(text: text, in: item.frame, context: context)
            case .score(let tile):
                draw(tile: tile, in: item.frame, context: context)
            }
        }

        drawFooter(
            page: pageIndex + 1,
            pageCount: layout.pages.count,
            pageHeight: layout.logicalPageHeight
        )
        context.restoreGState()
    }

    func testLayout(
        printableSize: CGSize
    ) -> OfficePrintLayoutSummary {
        let layout = makeLayout(printableSize: printableSize)
        let scoreFrames = layout.pages
            .flatMap(\.items)
            .compactMap { item -> CGRect? in
                if case .score = item.content { return item.frame }
                return nil
            }
        let scoreAlignedTextFrames = layout.pages
            .flatMap(\.items)
            .compactMap { item -> CGRect? in
                if case .text(_, .scoreAligned) = item.content {
                    return item.frame
                }
                return nil
            }
        return OfficePrintLayoutSummary(
            pageCount: layout.pages.count,
            itemCount: layout.pages.reduce(0) { $0 + $1.items.count },
            textItemCount: layout.pages
                .flatMap(\.items)
                .filter {
                    if case .text = $0.content { return true }
                    return false
                }
                .count,
            scoreItemCount: layout.pages
                .flatMap(\.items)
                .filter {
                    if case .score = $0.content { return true }
                    return false
                }
                .count,
            maximumItemBottom: layout.pages
                .flatMap(\.items)
                .map(\.frame.maxY)
                .max() ?? 0,
            minimumScoreLeft: scoreFrames.map(\.minX).min() ?? 0,
            maximumScoreRight: scoreFrames.map(\.maxX).max() ?? 0,
            scoreAlignedTextItemCount: scoreAlignedTextFrames.count,
            minimumScoreAlignedTextLeft: scoreAlignedTextFrames
                .map(\.minX).min() ?? 0,
            maximumScoreAlignedTextRight: scoreAlignedTextFrames
                .map(\.maxX).max() ?? 0,
            logicalPageHeight: layout.logicalPageHeight
        )
    }

    private func layout() -> CachedLayout {
        let printableSize = printableRect.size
        if let cachedLayout,
           cachedLayout.printableSize == printableSize {
            return cachedLayout
        }
        let result = makeLayout(printableSize: printableSize)
        cachedLayout = result
        return result
    }

    private func makeLayout(printableSize: CGSize) -> CachedLayout {
        let safeWidth = printableSize.width > 0 ? printableSize.width : 540
        let safeHeight = printableSize.height > 0 ? printableSize.height : 720
        let scale = safeWidth / Self.logicalPageWidth
        let logicalPageHeight = safeHeight / scale
        let blocks = OfficePrintBlockBuilder(
            snapshot: snapshot,
            preparedScores: scorePreparations
        ).blocks()
        let pages = OfficePrintPaginator.paginate(
            blocks: blocks,
            pageHeight: logicalPageHeight
        )
        return CachedLayout(
            printableSize: printableSize,
            scale: scale,
            logicalPageHeight: logicalPageHeight,
            pages: pages
        )
    }

    private func draw(
        tile: GregorianScoreDrawing.Tile,
        in frame: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        // UIKit's on-screen Canvas clips score drawing automatically. The
        // print renderer draws paths directly. Keep its clip at the text
        // column instead of the narrower line-breaking width: Garamond's
        // visual glyph bounds and chant marks can overhang their measured
        // advances slightly, and must remain visible inside the safety gutter.
        let horizontalAllowance = max(
            0,
            (Self.logicalContentWidth - frame.width) / 2
        )
        context.clip(
            to: frame.insetBy(dx: -horizontalAllowance, dy: 0)
        )
        let scoreScale = min(
            frame.width / tile.frame.width,
            frame.height / tile.frame.height
        )
        context.translateBy(
            x: frame.minX,
            y: frame.minY
        )
        context.scaleBy(x: scoreScale, y: scoreScale)
        context.translateBy(x: -tile.frame.minX, y: -tile.frame.minY)
        context.setStrokeColor(OfficePrintStyle.ink.cgColor)
        context.setFillColor(OfficePrintStyle.ink.cgColor)

        for batch in tile.strokeBatches {
            context.addPath(batch.path.cgPath)
            context.setLineWidth(batch.lineWidth)
            context.strokePath()
        }
        for path in tile.glyphPaths {
            context.addPath(path.cgPath)
            context.drawPath(using: .eoFill)
        }
        for lyric in tile.lyrics {
            OfficePrintStyle.chantText(lyric).draw(at: lyric.origin)
        }
        for initial in tile.initials {
            if let annotation = initial.annotation,
               let origin = initial.annotationOrigin {
                OfficePrintStyle.text(
                    annotation,
                    size: initial.annotationFontSize
                ).draw(at: origin)
            }
            OfficePrintStyle.text(
                initial.text,
                size: initial.fontSize
            ).draw(at: initial.origin)
        }
        context.restoreGState()
    }

    private func draw(
        text: NSAttributedString,
        in frame: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        // UIKit's attributed-string drawing can leave a flipped text matrix
        // behind after a chant tile. Core Text combines that matrix with the
        // CTM below, which turns later titles and psalm text upside down.
        context.textMatrix = .identity
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        let path = CGPath(
            rect: CGRect(origin: .zero, size: frame.size),
            transform: nil
        )
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let textFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: text.length),
            path,
            nil
        )
        CTFrameDraw(textFrame, context)
        context.restoreGState()
    }

    private func drawFooter(
        page: Int,
        pageCount: Int,
        pageHeight: CGFloat
    ) {
        let footer = NSMutableAttributedString(
            attributedString: OfficePrintStyle.text(
                "Hours",
                size: 9,
                color: .secondaryLabel
            )
        )
        footer.append(
            OfficePrintStyle.text(
                "    \(page) of \(pageCount)",
                size: 9,
                color: .secondaryLabel
            )
        )
        footer.draw(
            with: CGRect(
                x: 20,
                y: pageHeight - 17,
                width: Self.logicalContentWidth,
                height: 12
            ),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
    }

    private struct CachedLayout {
        let printableSize: CGSize
        let scale: CGFloat
        let logicalPageHeight: CGFloat
        let pages: [OfficePrintPage]
    }
}

nonisolated struct OfficePrintLayoutSummary: Equatable {
    let pageCount: Int
    let itemCount: Int
    let textItemCount: Int
    let scoreItemCount: Int
    let maximumItemBottom: CGFloat
    let minimumScoreLeft: CGFloat
    let maximumScoreRight: CGFloat
    let scoreAlignedTextItemCount: Int
    let minimumScoreAlignedTextLeft: CGFloat
    let maximumScoreAlignedTextRight: CGFloat
    let logicalPageHeight: CGFloat
}

nonisolated struct OfficePrintInkBalance: Equatable {
    let top: Int
    let bottom: Int
}

nonisolated private struct OfficePrintBlockBuilder {
    let snapshot: OfficePrintSnapshot
    let preparedScores: [String: GregorianPreparedScore]

    func blocks() -> [OfficePrintBlock] {
        var result = headerBlocks()
        for (index, section) in snapshot.sections.enumerated() {
            result.append(contentsOf: sectionBlocks(section))
            let nextIsContinuation = snapshot.sections.indices.contains(index + 1)
                && snapshot.sections[index + 1].title.isEmpty
            result.append(.space(nextIsContinuation ? 16 : 28))
        }
        return result
    }

    private func headerBlocks() -> [OfficePrintBlock] {
        var result: [OfficePrintBlock] = []
        let rank = snapshot.office.observance?.rankLabel
            ?? snapshot.office.hour.englishTitle
        result.append(
            .text(
                OfficePrintStyle.centered(
                    rank,
                    size: 12,
                    color: OfficePrintStyle.rubric
                ),
                keepWithNext: true
            )
        )
        result.append(.space(7))
        result.append(
            .text(
                OfficePrintStyle.centered(
                    snapshot.office.titleLatin,
                    size: 30 * snapshot.readerScale,
                    weight: .semibold
                ),
                keepWithNext: true
            )
        )
        if let english = distinctEnglish(
            snapshot.office.titleEnglish,
            from: snapshot.office.titleLatin
        ) {
            result.append(.space(5))
            result.append(
                .text(
                    OfficePrintStyle.centered(
                        english,
                        size: 17 * snapshot.readerScale,
                        color: .darkGray,
                        italic: true
                    ),
                    keepWithNext: true
                )
            )
        }
        result.append(.space(8))
        let observanceTitleLatin = ObservanceTitle.latin(
            snapshot.office.observance?.titleLatin ?? snapshot.office.contextLabel
        )
        result.append(
            .text(
                OfficePrintStyle.centered(
                    observanceTitleLatin,
                    size: 14 * snapshot.readerScale,
                    color: .darkGray
                )
            )
        )
        if let english = distinctEnglish(
            snapshot.office.observance?.titleEnglish.map(ObservanceTitle.english),
            from: observanceTitleLatin
        ) {
            result.append(.space(3))
            result.append(
                .text(
                    OfficePrintStyle.centered(
                        english,
                        size: 12 * snapshot.readerScale,
                        color: .gray,
                        italic: true
                    )
                )
            )
        }
        result.append(.space(30))
        return result
    }

    private func sectionBlocks(_ section: OfficeSection) -> [OfficePrintBlock] {
        var result: [OfficePrintBlock] = []
        let usesPointedPsalmody = usesPointedPsalmodyLayout(section)
        let latin = adjusted(section.latin)
        if !section.title.isEmpty {
            let isPsalm = section.kind == .psalm
            result.append(
                .text(
                    isPsalm
                        ? OfficePrintStyle.text(
                            section.title,
                            size: 17 * snapshot.readerScale,
                            color: OfficePrintStyle.rubric,
                            weight: .semibold
                        )
                        : OfficePrintStyle.centered(
                            section.title.uppercased(),
                            size: 10 * snapshot.readerScale,
                            color: .darkGray,
                            weight: .semibold
                        ),
                    keepWithNext: true,
                    column: isPsalm ? .scoreAligned : .content
                )
            )
            if let english = distinctEnglish(
                section.titleEnglish,
                from: section.title
            ) {
                result.append(.space(3))
                result.append(
                    .text(
                        OfficePrintStyle.centered(
                            english,
                            size: 10 * snapshot.readerScale,
                            color: .gray
                        ),
                        keepWithNext: true
                    )
                )
            }
            result.append(.space(10))
        }

        if let rubric = section.userFacingRubric {
            result.append(
                .text(
                    OfficePrintStyle.centered(
                        rubric,
                        size: 12 * snapshot.readerScale,
                        color: OfficePrintStyle.rubric,
                        italic: true
                    ),
                    keepWithNext: true
                )
            )
            if let english = distinctEnglish(
                section.rubricEnglish,
                from: rubric
            ) {
                result.append(.space(4))
                result.append(
                    .text(
                        OfficePrintStyle.centered(
                            english,
                            size: 11 * snapshot.readerScale,
                            color: .darkGray,
                            italic: true
                        ),
                        keepWithNext: true
                    )
                )
            }
            result.append(.space(9))
        }

        if let score = section.chant,
           !OfficePrayerText.requiresTextFallback(section.latin, isPriestOrDeaconPresent: snapshot.isPriestOrDeaconPresent),
           let preparedScore = preparedScores[score.id] {
            for tile in preparedScore.drawing.tiles {
                result.append(.score(tile))
            }
        } else if usesPointedPsalmody {
            result.append(contentsOf: psalmBlocks(section))
        } else {
            result.append(
                .text(
                    OfficePrintStyle.body(
                        latin,
                        scale: snapshot.readerScale
                    ),
                    column: .scoreAligned
                )
            )
        }

        if !usesPointedPsalmody,
           let english = distinctEnglish(
            section.english.map {
                adjusted(section.kind == .psalm ? PsalmTextFormatter.scriptureParagraphs(from: $0) : $0)
            },
            from: latin
           ) {
            result.append(.space(12))
            result.append(
                .text(
                    OfficePrintStyle.body(
                        english,
                        scale: snapshot.readerScale,
                        color: .darkGray,
                        italic: section.chant != nil
                    ),
                    column: .scoreAligned
                )
            )
        }
        return result
    }

    private func psalmBlocks(_ section: OfficeSection) -> [OfficePrintBlock] {
        PsalmTextFormatter.lines(
            latin: adjusted(section.latin),
            english: section.english.map(adjusted),
            startsAfterScoredVerse: section.title.isEmpty
        ).flatMap { line in
            var result: [OfficePrintBlock] = []
            let latin = line.number.map { "\($0). \(line.latin)" } ?? line.latin
            let attributed = NSMutableAttributedString(
                attributedString: OfficePrintStyle.body(
                    latin,
                    scale: snapshot.readerScale,
                    size: 17
                )
            )
            let numberPrefixLength = line.number.map {
                String("\($0). ").utf16.count
            } ?? 0
            for range in line.emphasizedRanges {
                let lower = line.latin.utf16.distance(
                    from: line.latin.utf16.startIndex,
                    to: range.lowerBound.samePosition(in: line.latin.utf16)!
                )
                let upper = line.latin.utf16.distance(
                    from: line.latin.utf16.startIndex,
                    to: range.upperBound.samePosition(in: line.latin.utf16)!
                )
                attributed.addAttribute(
                    .font,
                    value: OfficePrintStyle.font(
                        size: 17 * snapshot.readerScale,
                        weight: .semibold
                    ),
                    range: NSRange(
                        location: numberPrefixLength + lower,
                        length: upper - lower
                    )
                )
            }
            result.append(.text(attributed, column: .scoreAligned))
            if let english = distinctEnglish(line.english, from: line.latin) {
                result.append(.space(4))
                result.append(
                    .text(
                        OfficePrintStyle.body(
                            english,
                            scale: snapshot.readerScale,
                            size: 15,
                            color: .darkGray,
                            italic: true
                        ),
                        column: .scoreAligned
                    )
                )
            }
            result.append(.space(10))
            return result
        }
    }

    private func adjusted(_ text: String) -> String {
        snapshot.adjustedPrayerText(text)
    }

    private func distinctEnglish(
        _ english: String?,
        from latin: String
    ) -> String? {
        guard snapshot.showsEnglish else { return nil }
        return OfficeBilingualText.distinctEnglish(english, from: latin)
    }

    private func usesPointedPsalmodyLayout(_ section: OfficeSection) -> Bool {
        section.chant == nil
            && (section.kind == .psalm
                || snapshot.usesCompactPsalmody && section.kind == .canticle)
    }
}

nonisolated private enum OfficePrintBlock {
    case text(
        NSAttributedString,
        keepWithNext: Bool = false,
        column: OfficePrintTextColumn = .content
    )
    case score(GregorianScoreDrawing.Tile)
    case space(CGFloat)
}

nonisolated private enum OfficePrintTextColumn {
    case content
    case scoreAligned

    var x: CGFloat {
        (OfficePrintPageRenderer.logicalPageWidth - width) / 2
    }

    var width: CGFloat {
        switch self {
        case .content:
            OfficePrintPageRenderer.logicalContentWidth
        case .scoreAligned:
            OfficePrintPageRenderer.logicalScoreWidth
        }
    }
}

nonisolated private struct OfficePrintPage {
    let items: [OfficePrintPageItem]
}

nonisolated private struct OfficePrintPageItem {
    enum Content {
        case text(NSAttributedString, OfficePrintTextColumn)
        case score(GregorianScoreDrawing.Tile)
    }

    let content: Content
    let frame: CGRect
}

nonisolated private enum OfficePrintPaginator {
    private static let contentTop: CGFloat = 12
    private static let footerClearance: CGFloat = 30

    static func paginate(
        blocks: [OfficePrintBlock],
        pageHeight: CGFloat
    ) -> [OfficePrintPage] {
        let contentBottom = max(contentTop + 1, pageHeight - footerClearance)
        var pages: [OfficePrintPage] = []
        var items: [OfficePrintPageItem] = []
        var y = contentTop

        func finishPage() {
            pages.append(OfficePrintPage(items: items))
            items = []
            y = contentTop
        }

        for (index, block) in blocks.enumerated() {
            switch block {
            case .space(let height):
                y = min(contentBottom, y + height)

            case .score(let tile):
                if y + tile.frame.height > contentBottom, !items.isEmpty {
                    finishPage()
                }
                let available = max(1, contentBottom - y)
                let scoreScale = min(1, available / tile.frame.height)
                let frame = CGRect(
                    x: (OfficePrintPageRenderer.logicalPageWidth
                        - tile.frame.width * scoreScale) / 2,
                    y: y,
                    width: tile.frame.width * scoreScale,
                    height: tile.frame.height * scoreScale
                )
                items.append(
                    OfficePrintPageItem(content: .score(tile), frame: frame)
                )
                y = frame.maxY

            case .text(let attributed, let keepWithNext, let column):
                if keepWithNext,
                   !items.isEmpty,
                   contentBottom - y < minimumKeptHeight(
                    current: attributed,
                    currentWidth: column.width,
                    next: blocks.indices.contains(index + 1)
                        ? blocks[index + 1]
                        : nil
                   ) {
                    finishPage()
                }
                var location = 0
                while location < attributed.length {
                    let availableHeight = contentBottom - y
                    if availableHeight < 16, !items.isEmpty {
                        finishPage()
                        continue
                    }
                    let range = visibleRange(
                        in: attributed,
                        from: location,
                        width: column.width,
                        height: max(16, contentBottom - y)
                    )
                    guard range.length > 0 else {
                        if !items.isEmpty {
                            finishPage()
                            continue
                        }
                        break
                    }
                    let fragment = attributed.attributedSubstring(from: range)
                    let height = min(
                        contentBottom - y,
                        ceil(
                            textHeight(
                                fragment,
                                width: column.width
                            )
                        )
                    )
                    let frame = CGRect(
                        x: column.x,
                        y: y,
                        width: column.width,
                        height: height
                    )
                    items.append(
                        OfficePrintPageItem(
                            content: .text(fragment, column),
                            frame: frame
                        )
                    )
                    y = frame.maxY
                    location = NSMaxRange(range)
                    if location < attributed.length {
                        finishPage()
                    }
                }
            }
        }
        if !items.isEmpty || pages.isEmpty {
            finishPage()
        }
        return pages
    }

    private static func visibleRange(
        in text: NSAttributedString,
        from location: Int,
        width: CGFloat,
        height: CGFloat
    ) -> NSRange {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: location, length: 0),
            path,
            nil
        )
        let visible = CTFrameGetVisibleStringRange(frame)
        return NSRange(location: visible.location, length: visible.length)
    }

    private static func textHeight(
        _ text: NSAttributedString,
        width: CGFloat
    ) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: text.length),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        ).height
    }

    private static func minimumKeptHeight(
        current: NSAttributedString,
        currentWidth: CGFloat,
        next: OfficePrintBlock?
    ) -> CGFloat {
        let currentHeight = current.boundingRect(
            with: CGSize(
                width: currentWidth,
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        let nextHeight: CGFloat = switch next {
        case .text(let value, _, let column): min(
            36,
            value.boundingRect(
                with: CGSize(
                    width: column.width,
                    height: .greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
        )
        case .score(let tile): min(60, tile.frame.height)
        case .space(let height): height
        case nil: 0
        }
        return currentHeight + nextHeight
    }
}

nonisolated private enum OfficePrintStyle {
    static let ink = UIColor(red: 0.11, green: 0.10, blue: 0.08, alpha: 1)
    static let rubric = UIColor(red: 0.54, green: 0.16, blue: 0.15, alpha: 1)

    static func font(
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        italic: Bool = false
    ) -> UIFont {
        let base = UIFont(name: "EBGaramond-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.traitItalic) }
        if weight >= .semibold { traits.insert(.traitBold) }
        guard !traits.isEmpty,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func text(
        _ value: String,
        size: CGFloat,
        color: UIColor = ink,
        weight: UIFont.Weight = .regular,
        italic: Bool = false,
        alignment: NSTextAlignment = .left,
        lineSpacing: CGFloat = 2
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = lineSpacing * 2
        return NSAttributedString(
            string: value,
            attributes: [
                .font: font(size: size, weight: weight, italic: italic),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
    }

    static func centered(
        _ value: String,
        size: CGFloat,
        color: UIColor = ink,
        weight: UIFont.Weight = .regular,
        italic: Bool = false
    ) -> NSAttributedString {
        text(
            value,
            size: size,
            color: color,
            weight: weight,
            italic: italic,
            alignment: .center
        )
    }

    static func body(
        _ value: String,
        scale: Double,
        size: CGFloat = 18,
        color: UIColor = ink,
        italic: Bool = false
    ) -> NSAttributedString {
        text(
            PsalmTextFormatter.removingEmphasisMarkers(from: value),
            size: size * scale,
            color: color,
            italic: italic,
            lineSpacing: 3 * scale
        )
    }

    static func chantText(
        _ lyric: GregorianPlacedLyric
    ) -> NSAttributedString {
        switch lyric.style {
        case .regular:
            text(lyric.text, size: lyric.fontSize)
        case .preparatory:
            text(lyric.text, size: lyric.fontSize, italic: true)
        case .accented:
            text(lyric.text, size: lyric.fontSize, weight: .semibold)
        case .rubric:
            text(lyric.text, size: lyric.fontSize, color: rubric)
        @unknown default:
            text(lyric.text, size: lyric.fontSize)
        }
    }
}
