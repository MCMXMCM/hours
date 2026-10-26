import HoursCore
import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(
        HoursSharedPreferences.appearanceModeKey,
        store: HoursSharedPreferences.defaults
    )
    private var displayMode = AppDisplayMode.dynamic
    @AppStorage("hourSelectionView")
    private var hourSelectionView = HourSelectionViewMode.wheel
    /// The reader over Home: an Hour's, or the Mass's.
    @State private var presentedReader: PresentedReader?
    @State private var displayedHour = OfficeHour.current()

    private enum PresentedReader: Hashable {
        case office
        case mass
    }

    var body: some View {
        NavigationStack {
            TodaySidebarView(
                displayMode: $displayMode,
                hourSelectionView: $hourSelectionView,
                displayedHour: $displayedHour
            ) { hour in
                open(hour)
            } onOpenSearchOffice: { context in
                open(context)
            } onOpenMass: { day in
                openMass(on: day)
            }
            .navigationDestination(item: $presentedReader) { presented in
                switch presented {
                case .office:
                    HourReaderView(displayMode: displayMode) {
                        presentedReader = nil
                    }
                case .mass:
                    MassReaderView(displayMode: displayMode)
                }
            }
            .environment(\.openMass, OpenMassAction { day, index in
                openMass(on: day, index: index)
            })
        }
        .appTourOverlayHost(.home)
        .appTourOverlayHost(
            .reader,
            during: .only([.returnHomeFromReader])
        )
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
        .onChange(of: model.office?.id, initial: true) {
            guard presentedReader != .mass else { return }
            playback.stop()
            restoreReaderIfNeeded()
        }
        .onChange(of: presentedReader) { closed, presented in
            guard closed != nil, presented == nil else { return }
            playback.stop()
            tour.receive(.readerClosed)
            model.endReaderSession()
            if model.automaticallySelectsCurrentOffice {
                Task {
                    await model.selectCurrentOffice()
                }
            }
        }
        .onChange(of: displayMode) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: model.officeTradition) {
            playback.stop()
            presentedReader = nil
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.refreshAfterBecomingActive()
            }
        }
        .onChange(
            of: tour.presentationRequestID,
            initial: true
        ) {
            handleTourPresentationRequest()
        }
    }

    private var appearanceHour: OfficeHour {
        Self.appearanceHour(
            presentedOfficeHour: presentedSkyHour,
            hourSelectionView: hourSelectionView,
            displayedHour: displayedHour,
            selectedHour: model.selectedHour
        )
    }

    /// The Hour whose light the reader shown takes: the Hour read, or, for
    /// a Mass, the Hour chosen on Home.
    private var presentedSkyHour: OfficeHour? {
        switch presentedReader {
        case .office: model.office?.hour
        case .mass: model.selectedHour
        case nil: nil
        }
    }

    static func appearanceHour(
        presentedOfficeHour: OfficeHour?,
        hourSelectionView: HourSelectionViewMode,
        displayedHour: OfficeHour,
        selectedHour: OfficeHour
    ) -> OfficeHour {
        if let presentedOfficeHour {
            return presentedOfficeHour
        }

        return hourSelectionView == .wheel
            ? displayedHour
            : selectedHour
    }

    private func open(_ hour: OfficeHour) {
        Task {
            await model.select(hour: hour)
            if let office = model.office {
                model.beginReaderSession(for: office)
                presentedReader = .office
            }
        }
    }

    private func open(_ context: LiturgicalUsageContext) {
        Task {
            await model.selectOffice(
                on: context.date,
                hour: context.hour
            )
            if let office = model.office,
               office.date == context.date,
               office.hour == context.hour {
                model.beginReaderSession(for: office)
                presentedReader = .office
            }
        }
    }

    private func openMass(on day: LocalDay, index: Int = 0) {
        playback.stop()
        presentedReader = .mass
        Task {
            await model.openMass(on: day, index: index)
        }
    }

    /// Opens again the reader left open when the app last closed: an Hour
    /// once Home holds its office, a Mass once Home has its day.
    private func restoreReaderIfNeeded() {
        guard presentedReader == nil, let session = model.readerSession else { return }
        switch session.target {
        case .hour:
            guard let office = model.office,
                  model.shouldRestoreReader(for: office) else { return }
            presentedReader = .office
        case .mass:
            guard model.selectedDay != nil else { return }
            presentedReader = .mass
            Task {
                await model.reloadMass()
            }
        }
    }

    private func handleTourPresentationRequest() {
        guard let request = tour.presentationRequest else { return }
        switch request {
        case .home:
            presentedReader = nil
        case .reader:
            restoreReaderIfNeeded()
        }
        tour.consumePresentationRequest()
    }
}

/// The reader of the Hour Home holds. A view of its own, so that its title
/// follows the page it is turned to.
private struct HourReaderView: View {
    let displayMode: AppDisplayMode
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(AppTourCoordinator.self) private var tour

    var body: some View {
        if let office = model.office {
            OfficeReaderView(
                office: office,
                displayMode: displayMode,
                skyHour: office.hour,
                restoredScrollOffset:
                    model.restoredReaderScrollOffset(for: office),
                restoredScrollAnchor: model.restoredReaderScrollAnchor(for: office),
                onScrollOffsetChange: { offset, anchor in
                    model.updateReaderScrollOffset(
                        offset,
                        for: office,
                        anchor: anchor
                    )
                }
            )
                .id(office.id)
                .navigationTitle(model.readerPage == .latin ? office.hour.latinTitle : office.hour.englishTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .modifier(
                    AppTourReaderBackButton(onBack: onClose)
                )
                .onAppear {
                    tour.receive(.readerOpened)
                }
                .appTourOverlayHost(
                    .reader,
                    during: .allExcept([
                        .changeCantorPitch,
                        .closeCantorOptions,
                        .chooseOratio,
                        .enableEnglish,
                        .closeReaderOptions,
                        .returnHomeFromReader,
                    ])
                )
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
}

/// While the tour is in the reader, its own Back button stands for the
/// system's, and answers only at the step that asks for it. It reads the
/// tour for itself, so that the reader beneath is not made anew at each step.
private struct AppTourReaderBackButton: ViewModifier {
    @Environment(AppTourCoordinator.self) private var tour
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(
                tour.isActive && tour.currentLayer == .reader
            )
            .toolbar {
                if tour.isActive, tour.currentLayer == .reader {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            guard tour.step == .returnHomeFromReader else {
                                return
                            }
                            onBack()
                        } label: {
                            AppTourBackLabel(target: .readerBack)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("tour-reader-back")
                    }
                    // Where the system's Back stands, down the side of the
                    // screen on iPhone Duo.
                    .standsInVerticalBars()
                }
            }
    }
}
