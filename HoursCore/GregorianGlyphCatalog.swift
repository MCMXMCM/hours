import CoreGraphics
import Foundation

/// Names from Exsurge's canonical Gregorian SVG glyph set.
///
/// The generated catalog deliberately contains geometry rather than font
/// characters so engraving is deterministic across OS and font versions.
public enum GregorianGlyphName: String, CaseIterable, Hashable, Sendable {
    case none = "None"
    case acuteAccent = "AcuteAccent"
    case graveAccent = "GraveAccent"
    case circle = "Circle"
    case semicircle = "Semicircle"
    case reversedSemicircle = "ReversedSemicircle"
    case stropha = "Stropha"
    case beginningAscLiquescent = "BeginningAscLiquescent"
    case beginningDesLiquescent = "BeginningDesLiquescent"
    case custosDescLong = "CustosDescLong"
    case custosDescShort = "CustosDescShort"
    case custosLong = "CustosLong"
    case custosShort = "CustosShort"
    case doClef = "DoClef"
    case faClef = "FaClef"
    case trebleClef = "TrebleClef"
    case trebleClefSmall = "TrebleClefSmall"
    case chiRhoClef = "ChiRhoClef"
    case chiRhoClefSans = "ChiRhoClefSans"
    case flat = "Flat"
    case mora = "Mora"
    case natural = "Natural"
    case sharp = "Sharp"
    case oriscusAsc = "OriscusAsc"
    case oriscusDes = "OriscusDes"
    case oriscusLiquescent = "OriscusLiquescent"
    case podatusLower = "PodatusLower"
    case podatusLowerShort = "PodatusLowerShort"
    case podatusUpper = "PodatusUpper"
    case podatusUpperShort = "PodatusUpperShort"
    case porrectus1 = "Porrectus1"
    case porrectus2 = "Porrectus2"
    case porrectus3 = "Porrectus3"
    case porrectus4 = "Porrectus4"
    case punctumCavum = "PunctumCavum"
    case punctumQuadratum = "PunctumQuadratum"
    case punctumQuadratumLiquescent = "PunctumQuadratumLiquescent"
    case punctumQuadratumAscLiquescent = "PunctumQuadratumAscLiquescent"
    case punctumQuadratumDesLiquescent = "PunctumQuadratumDesLiquescent"
    case punctumInclinatum = "PunctumInclinatum"
    case punctumInclinatumLiquescent = "PunctumInclinatumLiquescent"
    case quilisma = "Quilisma"
    case terminatingAscLiquescent = "TerminatingAscLiquescent"
    case terminatingDesLiquescent = "TerminatingDesLiquescent"
    case verticalEpisemaAbove = "VerticalEpisemaAbove"
    case verticalEpisemaBelow = "VerticalEpisemaBelow"
    case virgaLong = "VirgaLong"
    case virgaShort = "VirgaShort"
    case virgula = "Virgula"
}

public enum GregorianGlyphAlignment: String, Hashable, Sendable {
    case left
    case center
    case right
    case undefined
}

/// A platform-neutral display-list command. SVG parsing and arc flattening
/// happen in the checked-in generator, never in the app.
public enum GregorianPathCommand: Hashable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quadratic(control: CGPoint, end: CGPoint)
    case cubic(control1: CGPoint, control2: CGPoint, end: CGPoint)
    case close
}

public struct GregorianGlyphDefinition: Hashable, Sendable {
    public let paths: [[GregorianPathCommand]]
    public let bounds: CGRect
    public let origin: CGPoint
    public let alignment: GregorianGlyphAlignment

    public init(
        paths: [[GregorianPathCommand]],
        bounds: CGRect,
        origin: CGPoint,
        alignment: GregorianGlyphAlignment
    ) {
        self.paths = paths
        self.bounds = bounds
        self.origin = origin
        self.alignment = alignment
    }
}

public enum GregorianGlyphCatalog {
    public static func definition(for name: GregorianGlyphName) -> GregorianGlyphDefinition {
        definitions[name] ?? definitions[.none]!
    }
}
