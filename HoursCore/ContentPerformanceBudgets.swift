import Foundation

public enum ContentPerformanceBudgets {
    /// Applies to the complete eight-hour 2026 development corpus.
    public static let development2026PackBytes = 256 * 1_024 * 1_024
    public static let coldRepositoryOpenSeconds = 0.75
    public static let officeReadSeconds = 0.25
    public static let residentMemoryBytes = 350 * 1_024 * 1_024
}
