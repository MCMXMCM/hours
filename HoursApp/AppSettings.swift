import HoursCore
import SwiftUI

enum AppDisplayMode: String, CaseIterable, Identifiable {
    case dynamic
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .dynamic: "Dynamic"
        case .system: "System"
        }
    }

    func preferredColorScheme(
        for hour: OfficeHour
    ) -> ColorScheme? {
        switch self {
        case .dynamic:
            SundialTimeMath.prefersDarkAppearance(for: hour)
                ? .dark
                : .light
        case .system:
            nil
        }
    }

    var showsAmbientSky: Bool {
        self == .dynamic
    }

    static func showsSundialShadow(
        in colorScheme: ColorScheme
    ) -> Bool {
        colorScheme == .light
    }
}

enum HourSelectionViewMode: String, CaseIterable, Identifiable {
    case sunDial
    case wheel

    var id: Self { self }

    var title: String {
        switch self {
        case .wheel: "Wheel"
        case .sunDial: "Dial"
        }
    }
}
