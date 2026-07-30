import HoursCore
import SwiftUI

extension Color {
    static let hoursBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
    )

    static let hoursPrimaryText = Color(
        uiColor: UIColor { traits in
            guard traits.userInterfaceStyle == .dark else {
                return .label
            }

            if traits.accessibilityContrast == .high {
                return .white
            }

            return UIColor(
                red: 0.85,
                green: 0.84,
                blue: 0.82,
                alpha: 1
            )
        }
    )

    static let hoursTodayAccent = Color(
        red: 0.68,
        green: 0.12,
        blue: 0.09
    )
}

@main
struct HoursApp: App {
    @State private var model = AppModel()
    @State private var playback = ChantPlaybackController()

    init() {
        HoursSharedPreferences
            .migrateAppearanceModeFromStandardDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .foregroundStyle(Color.hoursPrimaryText)
                .environment(model)
                .environment(playback)
                .task {
                    await model.start()
                }
        }
    }
}
