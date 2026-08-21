import HoursCore
import SwiftUI
import WidgetKit

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
    @State private var model: AppModel
    @State private var playback: ChantPlaybackController
    @State private var tour: AppTourCoordinator
    private let didMigrateAppearanceMode: Bool

    init() {
        let recoveredSnapshot =
            AppTourPersistence.recoverInterruptedSnapshot()
        _model = State(initialValue: AppModel())
        _playback = State(
            initialValue: ChantPlaybackController()
        )
        _tour = State(
            initialValue: AppTourCoordinator(
                recoveredSnapshot: recoveredSnapshot
            )
        )
        didMigrateAppearanceMode = HoursSharedPreferences
            .migrateAppearanceModeFromStandardDefaults()
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .foregroundStyle(Color.hoursPrimaryText)
                .environment(model)
                .environment(playback)
                .environment(tour)
                .task {
                    let didUpdateCalendarSnapshot = await model.start()
                    await tour.recoverAfterModelStart(model: model)
                    if HoursWidgetReloadPolicy.shouldReload(
                        calendarSnapshotChanged:
                            didUpdateCalendarSnapshot,
                        appearancePreferenceMigrated:
                            didMigrateAppearanceMode
                    ) {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
        }
    }
}

enum HoursWidgetReloadPolicy {
    nonisolated static func shouldReload(
        calendarSnapshotChanged: Bool,
        appearancePreferenceMigrated: Bool
    ) -> Bool {
        calendarSnapshotChanged || appearancePreferenceMigrated
    }
}
