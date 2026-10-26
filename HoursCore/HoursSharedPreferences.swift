import Foundation

public enum HoursSharedPreferences {
    public static let appGroupIdentifier =
        "group.com.matthewmccarty.hours"
    public static let appearanceModeKey = "appearanceMode"
    public static let defaultAppearanceMode = "dynamic"
    public static let officeTraditionKey = "officeTradition"

    public static var officeTradition: OfficeTradition {
        defaults.string(forKey: officeTraditionKey)
            .flatMap(OfficeTradition.init(rawValue:)) ?? .roman1960
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    public static var appearanceModeRawValue: String {
        defaults.string(forKey: appearanceModeKey)
            ?? defaultAppearanceMode
    }

    @discardableResult
    public static func migrateAppearanceModeFromStandardDefaults() -> Bool {
        let sharedDefaults = defaults
        guard sharedDefaults.object(forKey: appearanceModeKey) == nil else {
            return false
        }

        let savedValue = UserDefaults.standard.string(
            forKey: appearanceModeKey
        ) ?? defaultAppearanceMode
        sharedDefaults.set(savedValue, forKey: appearanceModeKey)
        return true
    }
}
