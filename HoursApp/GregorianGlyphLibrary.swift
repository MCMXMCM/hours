import HoursCore
import SwiftUI

/// Converts the generated, platform-neutral Exsurge display list into a
/// SwiftUI `Path`. There is no SVG parser, font lookup, JavaScript, or WebView
/// in the production rendering path.
enum GregorianGlyphLibrary {
    nonisolated static func path(for glyph: GregorianPlacedGlyph) -> Path {
        let definition = GregorianGlyphCatalog.definition(for: glyph.kind.catalogName)
        guard definition.bounds.width > 0, definition.bounds.height > 0 else {
            return Path()
        }

        var result = Path()
        for commands in definition.paths {
            var path = Path()
            for command in commands {
                switch command {
                case let .move(point):
                    path.move(to: point)
                case let .line(point):
                    path.addLine(to: point)
                case let .quadratic(control, end):
                    path.addQuadCurve(to: end, control: control)
                case let .cubic(control1, control2, end):
                    path.addCurve(to: end, control1: control1, control2: control2)
                case .close:
                    path.closeSubpath()
                @unknown default:
                    break
                }
            }
            result.addPath(path)
        }

        let sourceBounds = CGRect(
            x: -definition.origin.x,
            y: -definition.origin.y,
            width: definition.bounds.width,
            height: definition.bounds.height
        )
        let scaleX = glyph.frame.width / sourceBounds.width
        let scaleY = glyph.frame.height / sourceBounds.height
        return result.applying(
            CGAffineTransform(
                a: scaleX,
                b: 0,
                c: 0,
                d: scaleY,
                tx: glyph.frame.minX - sourceBounds.minX * scaleX,
                ty: glyph.frame.minY - sourceBounds.minY * scaleY
            )
        )
    }
}
