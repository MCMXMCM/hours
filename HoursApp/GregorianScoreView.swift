import HoursCore
import SwiftUI

struct ActiveNeumeFrame: Equatable {
    let eventID: String
    let scrollTargetID: String
    let frame: CGRect
}

struct GregorianScoreView: View {
    let score: ChantScore
    let preparation: GregorianScorePreparation
    let highlightedEventID: String?
    let onTapEvent: (String) -> Void
    let onActiveNeumeFrameChange: (ActiveNeumeFrame) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch preparation {
            case .ready(let preparedScore):
                scoreCanvas(preparedScore)
            case .failed(let errorMessage):
                ContentUnavailableView {
                    Label("Notation unavailable", systemImage: "music.note")
                } description: {
                    Text(errorMessage)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .accessibilityIdentifier("notation-error-\(score.id)")
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: preparation.height,
            maxHeight: preparation.height,
            alignment: .topLeading
        )
        .textSelection(.disabled)
        .accessibilityHidden(
            Self.uiTestHidesActiveScoreAccessibility
                && highlightedEventID != nil
        )
    }

    private func scoreCanvas(_ preparedScore: GregorianPreparedScore) -> some View {
        let layout = preparedScore.layout
        let drawing = preparedScore.drawing
        let ink = colorScheme == .dark
            ? Color.hoursPrimaryText
            : Color(red: 0.11, green: 0.10, blue: 0.08)
        let accent = colorScheme == .dark
            ? Color(red: 0.68, green: 0.12, blue: 0.09)
            : Color(red: 0.54, green: 0.16, blue: 0.15)
        let highlight = Color.red
        let activePlacement = highlightedEventID.flatMap {
            layout.neume(containing: $0)
        }

        return ZStack(alignment: .topLeading) {
            ForEach(Array(drawing.tiles.enumerated()), id: \.offset) { _, tile in
                scoreTile(tile, ink: ink, accent: accent)
            }

            if let highlightedEventID {
                Canvas { context, _ in
                    for stroke in layout.strokes
                        where stroke.eventID == highlightedEventID {
                        var path = Path()
                        path.move(to: stroke.start)
                        path.addLine(to: stroke.end)
                        context.stroke(
                            path,
                            with: .color(highlight),
                            lineWidth: stroke.lineWidth
                        )
                    }

                    for glyph in layout.glyphs
                        where glyph.eventID == highlightedEventID {
                        let path = GregorianGlyphLibrary.path(for: glyph)
                        context.fill(
                            path,
                            with: .color(highlight),
                            style: FillStyle(eoFill: true)
                        )
                        context.stroke(
                            path,
                            with: .color(highlight),
                            lineWidth: 1.1
                        )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            if let neume = GregorianScoreInteraction.neume(
                                at: value.location,
                                in: layout
                            ) {
                                onTapEvent(neume.id)
                            }
                        }
                )
                .accessibilityHidden(true)

            if let highlightedEventID, let activePlacement {
                let scrollTargetID = cantorScrollTargetID(
                    for: activePlacement
                )
                Color.clear
                    .frame(
                        width: activePlacement.hitFrame.width,
                        height: activePlacement.hitFrame.height
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(scrollTargetID)
                    .onGeometryChange(
                        for: CGRect.self,
                        of: { geometry in
                            geometry.frame(in: .global)
                        },
                        action: { frame in
                            onActiveNeumeFrameChange(
                                ActiveNeumeFrame(
                                    eventID: highlightedEventID,
                                    scrollTargetID: scrollTargetID,
                                    frame: frame
                                )
                            )
                        }
                    )
                    .position(
                        x: activePlacement.hitFrame.midX,
                        y: activePlacement.hitFrame.midY
                    )
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            ForEach(Array(layout.neumes.enumerated()), id: \.element.id) { index, neume in
                Button {
                    onTapEvent(neume.id)
                } label: {
                    Text(accessibilityLabel(for: neume))
                }
                .accessibilityHint("Starts the cantor guide here")
                .accessibilityIdentifier(neume.id)
                .accessibilitySortPriority(Double(layout.neumes.count - index))
            }
        }
    }

    private func scoreTile(
        _ tile: GregorianScoreDrawing.Tile,
        ink: Color,
        accent: Color
    ) -> some View {
        // Each Canvas covers one staff system rather than the full chant.
        // Offscreen systems can therefore be culled independently during a fling.
        Canvas(rendersAsynchronously: false) { context, _ in
            context.translateBy(x: -tile.frame.minX, y: -tile.frame.minY)

            for batch in tile.strokeBatches {
                context.stroke(
                    batch.path,
                    with: .color(ink),
                    lineWidth: batch.lineWidth
                )
            }

            for path in tile.glyphPaths {
                context.fill(
                    path,
                    with: .color(ink),
                    style: FillStyle(eoFill: true)
                )
            }

            for lyric in tile.lyrics {
                let color = lyric.style == .rubric ? accent : ink
                context.draw(
                    lyricText(lyric).foregroundStyle(color),
                    at: lyric.origin,
                    anchor: .topLeading
                )
            }

            for initial in tile.initials {
                if let annotation = initial.annotation,
                   let annotationOrigin = initial.annotationOrigin {
                    context.draw(
                        initialAnnotationText(
                            annotation,
                            fontSize: initial.annotationFontSize
                        )
                        .foregroundStyle(ink),
                        at: annotationOrigin,
                        anchor: .topLeading
                    )
                }
                context.draw(
                    initialText(initial).foregroundStyle(ink),
                    at: initial.origin,
                    anchor: .topLeading
                )
            }
        }
        .frame(width: tile.frame.width, height: tile.frame.height)
        .position(x: tile.frame.midX, y: tile.frame.midY)
        .accessibilityHidden(true)
    }

    private func cantorScrollTargetID(
        for placement: GregorianNeumePlacement
    ) -> String {
        "cantor-scroll-\(score.id)-\(placement.id)"
    }

    private func lyricText(_ lyric: GregorianPlacedLyric) -> Text {
        let text = Text(lyric.text)
            .font(.custom("EBGaramond-Regular", size: lyric.fontSize))
        return switch lyric.style {
        case .regular:
            text
        case .preparatory:
            text.italic()
        case .accented:
            text.bold()
        case .rubric:
            text
        @unknown default:
            text
        }
    }

    private func initialText(_ initial: GregorianPlacedInitial) -> Text {
        Text(initial.text)
            .font(.custom("EBGaramond-Regular", size: initial.fontSize))
    }

    private func initialAnnotationText(_ text: String, fontSize: CGFloat) -> Text {
        Text(text)
            .font(.custom("EBGaramond-Regular", size: fontSize))
    }

    private func accessibilityLabel(for neume: GregorianNeumePlacement) -> String {
        let lyric = neume.lyric.isEmpty ? "Chant" : neume.lyric
        let count = neume.eventIDs.count
        return count == 1 ? "\(lyric), one-note neume" : "\(lyric), \(count)-note neume"
    }

    static func lyricScale(for dynamicTypeSize: DynamicTypeSize) -> Double {
        switch dynamicTypeSize {
        case .xSmall: 0.88
        case .small: 0.94
        case .medium: 0.98
        case .large: 1
        case .xLarge: 1.08
        case .xxLarge: 1.16
        case .xxxLarge: 1.25
        case .accessibility1: 1.35
        case .accessibility2: 1.5
        case .accessibility3: 1.65
        case .accessibility4: 1.85
        case .accessibility5: 2.05
        @unknown default: 1
        }
    }

    private static var uiTestHidesActiveScoreAccessibility: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-test-cantor-follow"
        )
        #else
        false
        #endif
    }
}

struct GregorianPreparedScore: Sendable {
    let layout: GregorianLayout
    let drawing: GregorianScoreDrawing

    nonisolated init(
        layout: GregorianLayout,
        drawing: GregorianScoreDrawing
    ) {
        self.layout = layout
        self.drawing = drawing
    }
}

struct GregorianScoreDrawing: Sendable {
    struct StrokeBatch: Sendable {
        let path: Path
        let lineWidth: CGFloat

        nonisolated init(path: Path, lineWidth: CGFloat) {
            self.path = path
            self.lineWidth = lineWidth
        }
    }

    struct Tile: Sendable {
        let frame: CGRect
        let strokeBatches: [StrokeBatch]
        let glyphPaths: [Path]
        let lyrics: [GregorianPlacedLyric]
        let initials: [GregorianPlacedInitial]

        nonisolated init(
            frame: CGRect,
            strokes: [GregorianPlacedStroke],
            glyphs: [GregorianPlacedGlyph],
            lyrics: [GregorianPlacedLyric],
            initials: [GregorianPlacedInitial]
        ) {
            self.frame = frame
            strokeBatches = Dictionary(grouping: strokes, by: \.lineWidth)
                .sorted { $0.key < $1.key }
                .map { lineWidth, strokes in
                    var path = Path()
                    for stroke in strokes {
                        path.move(to: stroke.start)
                        path.addLine(to: stroke.end)
                    }
                    return StrokeBatch(path: path, lineWidth: lineWidth)
                }

            // Even-odd fill is required by some catalog glyphs. Keep intersecting
            // glyphs in separate paths so overlapping glyphs cannot cancel each
            // other's fill, while still batching the usual non-overlapping glyphs.
            struct GlyphBatch {
                var path = Path()
                var occupiedFrames: [CGRect] = []
            }

            var glyphBatches: [GlyphBatch] = []
            for glyph in glyphs {
                let occupiedFrame = glyph.frame.insetBy(dx: -0.5, dy: -0.5)
                let batchIndex = glyphBatches.firstIndex { batch in
                    batch.occupiedFrames.allSatisfy {
                        !$0.intersects(occupiedFrame)
                    }
                }

                if let batchIndex {
                    glyphBatches[batchIndex].path.addPath(
                        GregorianGlyphLibrary.path(for: glyph)
                    )
                    glyphBatches[batchIndex].occupiedFrames.append(occupiedFrame)
                } else {
                    var batch = GlyphBatch()
                    batch.path.addPath(GregorianGlyphLibrary.path(for: glyph))
                    batch.occupiedFrames.append(occupiedFrame)
                    glyphBatches.append(batch)
                }
            }
            glyphPaths = glyphBatches.map(\.path)
            self.lyrics = lyrics
            self.initials = initials
        }
    }

    let tiles: [Tile]

    nonisolated init(layout: GregorianLayout) {
        let frames = layout.staffs.isEmpty
            ? [CGRect(origin: .zero, size: layout.size)]
            : layout.staffs.map(\.systemFrame)
        var strokes = Array(repeating: [GregorianPlacedStroke](), count: frames.count)
        var glyphs = Array(repeating: [GregorianPlacedGlyph](), count: frames.count)
        var lyrics = Array(repeating: [GregorianPlacedLyric](), count: frames.count)
        var initials = Array(repeating: [GregorianPlacedInitial](), count: frames.count)

        func tileIndex(for y: CGFloat) -> Int {
            frames.firstIndex { y < $0.maxY } ?? frames.index(before: frames.endIndex)
        }

        for stroke in layout.strokes {
            let centerY = (stroke.start.y + stroke.end.y) / 2
            strokes[tileIndex(for: centerY)].append(stroke)
        }
        for glyph in layout.glyphs {
            glyphs[tileIndex(for: glyph.frame.midY)].append(glyph)
        }
        for lyric in layout.lyrics {
            lyrics[tileIndex(for: lyric.origin.y)].append(lyric)
        }
        for initial in layout.initials {
            initials[tileIndex(for: initial.origin.y)].append(initial)
        }

        tiles = frames.indices.map { index in
            Tile(
                frame: frames[index],
                strokes: strokes[index],
                glyphs: glyphs[index],
                lyrics: lyrics[index],
                initials: initials[index]
            )
        }
    }
}

enum GregorianScorePreparation: Sendable {
    case ready(GregorianPreparedScore)
    case failed(String)

    var height: CGFloat {
        switch self {
        case .ready(let preparedScore):
            preparedScore.layout.size.height
        case .failed:
            112
        }
    }
}

enum GregorianScoreInteraction {
    static func neume(
        at location: CGPoint,
        in layout: GregorianLayout
    ) -> GregorianNeumePlacement? {
        layout.neumes
            .filter { $0.hitFrame.contains(location) }
            .min {
                squaredDistance(from: location, to: $0.hitFrame.center)
                    < squaredDistance(from: location, to: $1.hitFrame.center)
            }
    }

    private static func squaredDistance(
        from point: CGPoint,
        to target: CGPoint
    ) -> CGFloat {
        let deltaX = point.x - target.x
        let deltaY = point.y - target.y
        return deltaX * deltaX + deltaY * deltaY
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

actor GregorianLayoutCache {
    struct Key: Hashable, Sendable {
        let scoreID: String
        let gabcHash: Int
        let eventCount: Int
        let openingLabel: String?
        let width: Int
        let notationScale: Int
        let lyricScale: Int
    }

    static let shared = GregorianLayoutCache()

    private var parsed: [String: GregorianScore] = [:]
    private var parsedOrder: [String] = []
    private var layouts: [Key: GregorianLayout] = [:]
    private var layoutOrder: [Key] = []

    nonisolated static func openingLabel(for score: ChantScore) -> String? {
        GregorianEngravingLayoutEngine.openingLabel(forMode: score.mode)
    }

    func layout(
        score: ChantScore,
        width: CGFloat,
        metrics: GregorianLayoutMetrics
    ) throws -> GregorianLayout {
        let openingLabel = Self.openingLabel(for: score)
        let key = Key(
            scoreID: score.id,
            gabcHash: score.gabc.hashValue,
            eventCount: score.timeline.events.count,
            openingLabel: openingLabel,
            width: Int(width.rounded()),
            notationScale: Int((metrics.notationScale * 100).rounded()),
            lyricScale: Int((metrics.lyricScale * 100).rounded())
        )
        if let cached = layouts[key] {
            Self.touch(key, in: &layoutOrder)
            return cached
        }

        let parseKey = "\(score.id):\(score.gabc.hashValue):\(score.timeline.events.count)"
        let parsedScore: GregorianScore
        if let cached = parsed[parseKey] {
            Self.touch(parseKey, in: &parsedOrder)
            parsedScore = cached
        } else {
            parsedScore = try GregorianScoreParser.parse(
                gabc: score.gabc,
                timeline: score.timeline
            )
            parsed[parseKey] = parsedScore
            parsedOrder.append(parseKey)
            Self.evictOldest(from: &parsed, order: &parsedOrder, limit: 128)
        }

        let result = GregorianEngravingLayoutEngine().layout(
            score: parsedScore,
            width: width,
            metrics: metrics,
            openingLabel: openingLabel
        )
        layouts[key] = result
        layoutOrder.append(key)
        Self.evictOldest(from: &layouts, order: &layoutOrder, limit: 96)
        return result
    }

    func preparedScore(
        score: ChantScore,
        width: CGFloat,
        metrics: GregorianLayoutMetrics
    ) throws -> GregorianPreparedScore {
        let layout = try layout(
            score: score,
            width: width,
            metrics: metrics
        )
        return GregorianPreparedScore(
            layout: layout,
            drawing: GregorianScoreDrawing(layout: layout)
        )
    }

    private static func touch<Key: Hashable>(_ key: Key, in order: inout [Key]) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private static func evictOldest<Key: Hashable, Value>(
        from values: inout [Key: Value],
        order: inout [Key],
        limit: Int
    ) {
        while values.count > limit, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}

enum GregorianScorePreparer {
    static func prepare(
        scores: [ChantScore],
        width: CGFloat,
        metrics: GregorianLayoutMetrics
    ) async -> [String: GregorianScorePreparation] {
        var preparations: [String: GregorianScorePreparation] = [:]
        preparations.reserveCapacity(scores.count)

        for score in scores {
            guard !Task.isCancelled else { return preparations }
            do {
                let preparedScore = try await GregorianLayoutCache.shared.preparedScore(
                    score: score,
                    width: width,
                    metrics: metrics
                )
                preparations[score.id] = .ready(preparedScore)
            } catch {
                preparations[score.id] = .failed(error.localizedDescription)
            }
        }

        return preparations
    }
}
