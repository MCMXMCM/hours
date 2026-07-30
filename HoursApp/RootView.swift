import HoursCore
import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @AppStorage(
        HoursSharedPreferences.appearanceModeKey,
        store: HoursSharedPreferences.defaults
    )
    private var displayMode = AppDisplayMode.dynamic
    @AppStorage("hourSelectionView")
    private var hourSelectionView = HourSelectionViewMode.sunDial
    @State private var showsReader = false
    @State private var displayedHour = OfficeHour.current()

    var body: some View {
        NavigationStack {
            TodaySidebarView(
                displayMode: $displayMode,
                hourSelectionView: $hourSelectionView,
                displayedHour: $displayedHour
            ) { hour in
                open(hour)
            }
            .navigationDestination(isPresented: $showsReader) {
                reader
            }
        }
        .tint(Color.hoursPrimaryText)
        .preferredColorScheme(
            displayMode.preferredColorScheme(
                for: appearanceHour
            )
        )
        .animation(
            .easeInOut(duration: 0.72),
            value: displayMode.preferredColorScheme(
                for: appearanceHour
            )
        )
        .onChange(of: model.office?.id) {
            playback.stop()
        }
        .onChange(of: displayMode) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(
            of: model.selectedHour,
            initial: true
        ) { _, hour in
            if hourSelectionView != .wheel {
                displayedHour = hour
            }
        }
        .onChange(of: hourSelectionView) { _, mode in
            if mode != .wheel {
                displayedHour = model.selectedHour
            }
        }
    }

    private var appearanceHour: OfficeHour {
        hourSelectionView == .wheel
            ? displayedHour
            : model.selectedHour
    }

    @ViewBuilder
    private var reader: some View {
        if let office = model.office {
            OfficeReaderView(
                office: office,
                displayMode: displayMode
            )
                .id(office.id)
                .navigationTitle(office.hour.latinTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.hoursBackground)
        } else {
            ContentUnavailableView {
                Label("Office unavailable", systemImage: "book.closed")
            } description: {
                Text(model.errorMessage ?? "This office could not be opened.")
            }
        }
    }

    private func open(_ hour: OfficeHour) {
        Task {
            await model.select(hour: hour)
            if model.office != nil {
                showsReader = true
            }
        }
    }
}
