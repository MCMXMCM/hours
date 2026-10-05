import Foundation

public enum ContentPerformanceBudgets {
    /// Applies to one normalized eight-hour civil year.
    public static let normalizedOneYearPackBytes = 64 * 1_024 * 1_024
    /// Applies to the reviewed previous-year-through-next-10-years App Store pack.
    public static let reviewedWindowReleasePackBytes = 128 * 1_024 * 1_024
    /// Applies only to the non-shipping 1962–2100 parity artifact.
    public static let perennialParityPackBytes = 256 * 1_024 * 1_024
    /// Both Roman editions plus their shared text and music catalog.
    public static let sharedOfficeBundleBytes = 160 * 1_024 * 1_024
    public static let perennialReleasePackBytes = reviewedWindowReleasePackBytes
    public static let coldRepositoryOpenSeconds = 0.75
    public static let corpusStartupSeconds = 1.0
    public static let availableDaysReadSeconds = 0.25
    public static let officeReadSeconds = 0.25
    public static let searchSeconds = 0.25
    public static let titleSearchSeconds = 0.25
    public static let residentMemoryBytes = 350 * 1_024 * 1_024
}
