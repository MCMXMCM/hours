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
        #if DEBUG
        // UI tests begin each case from a fresh install's settings; the
        // launch arguments then set only what that case needs.
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset-defaults") {
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            }
            HoursSharedPreferences.defaults.removePersistentDomain(
                forName: HoursSharedPreferences.appGroupIdentifier
            )
        }
        #endif
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
                    let build = HoursWidgetReloadPolicy.currentBuild()
                    if HoursWidgetReloadPolicy.shouldReload(
                        calendarSnapshotChanged:
                            didUpdateCalendarSnapshot,
                        appearancePreferenceMigrated:
                            didMigrateAppearanceMode,
                        lastReloadedBuild: UserDefaults.standard.string(
                            forKey: HoursWidgetReloadPolicy.lastReloadedBuildKey
                        ),
                        currentBuild: build
                    ) {
                        WidgetCenter.shared.reloadAllTimelines()
                        UserDefaults.standard.set(
                            build,
                            forKey: HoursWidgetReloadPolicy.lastReloadedBuildKey
                        )
                    }
                }
        }
    }
}

enum HoursWidgetReloadPolicy {
    nonisolated static let lastReloadedBuildKey = "widgetLastReloadedBuild"

    /// A new build reloads once, so a widget left stale by an earlier install recovers.
    nonisolated static func shouldReload(
        calendarSnapshotChanged: Bool,
        appearancePreferenceMigrated: Bool,
        lastReloadedBuild: String?,
        currentBuild: String
    ) -> Bool {
        calendarSnapshotChanged
            || appearancePreferenceMigrated
            || lastReloadedBuild != currentBuild
    }

    nonisolated static func currentBuild(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }
}
