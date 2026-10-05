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
            } onOpenSearchOffice: { context in
                open(context)
            }
            .navigationDestination(isPresented: $showsReader) {
                reader
            }
        }
        .appTourOverlayHost(.home)
        .appTourOverlayHost(
            .reader,
            when: tour.step == .returnHomeFromReader
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
            playback.stop()
            restoreReaderIfNeeded()
        }
        .onChange(of: showsReader) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
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
            showsReader = false
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
            presentedOfficeHour: showsReader
                ? model.office?.hour
                : nil,
            hourSelectionView: hourSelectionView,
            displayedHour: displayedHour,
            selectedHour: model.selectedHour
        )
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

    @ViewBuilder
    private var reader: some View {
        if let office = model.office {
            OfficeReaderView(
                office: office,
                displayMode: displayMode,
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
                .navigationTitle(office.hour.latinTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
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
                                showsReader = false
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .appTourTarget(.readerBack)
                            }
                            .accessibilityIdentifier("tour-reader-back")
                        }
                    }
                }
                .onAppear {
                    tour.receive(.readerOpened)
                }
                .appTourOverlayHost(
                    .reader,
                    when: tour.step != .chooseOratio
                        && tour.step != .enableEnglish
                        && tour.step != .closeReaderOptions
                        && tour.step != .returnHomeFromReader
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

    private func open(_ hour: OfficeHour) {
        Task {
            await model.select(hour: hour)
            if let office = model.office {
                model.beginReaderSession(for: office)
                showsReader = true
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
                showsReader = true
            }
        }
    }

    private func restoreReaderIfNeeded() {
        guard let office = model.office,
              model.shouldRestoreReader(for: office) else {
            return
        }
        showsReader = true
    }

    private func handleTourPresentationRequest() {
        guard let request = tour.presentationRequest else { return }
        switch request {
        case .home:
            showsReader = false
        case .reader:
            restoreReaderIfNeeded()
        }
        tour.consumePresentationRequest()
    }
}
