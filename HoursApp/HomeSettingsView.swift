import HoursCore
import SwiftUI
import UIKit
import WidgetKit

struct HomeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(AppModel.self) private var model
    @Binding var displayMode: AppDisplayMode
    @Binding var hourSelectionView: HourSelectionViewMode
    let isAtLocalTime: Bool
    let onAutomaticHourSelectionChanged: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        automaticHourSelection
                        livePreviewSettings
                        officeTraditionSettings
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .task(id: tour.step) {
                    let step = tour.step
                    let anchor: String?
                    switch step {
                    case .changeHourDisplay, .restoreHourDisplay:
                        anchor = "settings-tour-hour-display"
                    case .changeAppearance, .restoreAppearance:
                        anchor = "settings-tour-appearance"
                    case .restoreAutomaticTracking:
                        anchor = "settings-tour-synchronization"
                    default:
                        anchor = nil
                    }
                    guard let anchor else { return }
                    await Task.yield()
                    guard !Task.isCancelled, tour.step == step else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(anchor, anchor: .center)
                    }
                    if step == .restoreAutomaticTracking,
                       isAtLocalTime {
                        tour.receive(
                            .automaticHourSelectionChanged(true)
                        )
                    }
                }
            }
            .background(Color.hoursBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    aboutNavigationLink
                }

                ToolbarItem(placement: .confirmationAction) {
                    SheetCloseButton(
                        accessibilityLabel: "Close Settings",
                        accessibilityIdentifier: "settings-close",
                        action: dismiss.callAsFunction
                    )
                    .appTourTarget(.settingsClose)
                }
            }
        }
        .onAppear {
            tour.receive(.settingsOpened)
        }
        .onChange(of: hourSelectionView) { _, mode in
            tour.receive(.hourDisplayChanged(mode))
        }
        .onChange(of: displayMode) { _, mode in
            tour.receive(.appearanceChanged(mode))
        }
    }

    private var officeTraditionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rubrics")
                    .font(.system(.title3, design: .serif))
                Spacer()
                if model.isChangingTradition {
                    ProgressView().accessibilityLabel("Changing office tradition")
                }
            }
            Picker("Rubrics", selection: Binding(
                get: { model.officeTradition },
                set: { tradition in
                    Task {
                        if await model.changeOfficeTradition(to: tradition) {
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                }
            )) {
                ForEach(OfficeTradition.allCases) { tradition in
                    Text(tradition.title).tag(tradition)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isChangingTradition || tour.isActive)
            .accessibilityIdentifier("office-tradition-picker")

            // All options participate in layout so the tallest description
            // determines the height at the current width and Dynamic Type size.
            ZStack(alignment: .topLeading) {
                ForEach(OfficeTradition.allCases) { tradition in
                    officeTraditionDetails(tradition)
                        .opacity(model.officeTradition == tradition ? 1 : 0)
                        .accessibilityHidden(model.officeTradition != tradition)
                        .allowsHitTesting(model.officeTradition == tradition)
                }
            }
            if let error = model.traditionErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("office-tradition-error")
            }
        }
    }

    private func officeTraditionDetails(_ tradition: OfficeTradition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tradition.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if tradition != .roman1960 {
                Text("Source edition: Latin and English from Divinum Officium. Chant is included where it can be matched to the text; some passages are text-only. Independent liturgical and musical review is pending.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("office-source-edition-note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var aboutNavigationLink: some View {
        NavigationLink {
            AboutSettingsView(
                onClose: { dismiss() },
                onAppTour: {
                    tour.requestAboutReplay()
                    dismiss()
                }
            )
            .onAppear {
                tour.receive(.aboutOpened)
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About Hours")
        .accessibilityHint(
            "Shows the canonical hour schedule, App Tour, chant guide, and contact information"
        )
        .accessibilityIdentifier("settings-about")
        .appTourTarget(.settingsAbout)
    }

    private var livePreviewSettings: some View {
        TimelineView(
            .periodic(from: .now, by: 60)
        ) { context in
            let currentHour = OfficeHour.current(
                at: context.date
            )
            let systemColorScheme =
                SystemAppearance.currentColorScheme
            let selectedDisplayColorScheme =
                displayMode.preferredColorScheme(
                    for: currentHour
                ) ?? systemColorScheme

            VStack(alignment: .leading, spacing: 12) {
                previewSection(
                    title: "Display"
                ) {
                    HStack(
                        alignment: .top,
                        spacing: SettingsPreviewLayout.cardSpacing
                    ) {
                        ForEach(
                            HourSelectionViewMode.allCases
                        ) { option in
                            PreviewSelectionCard(
                                title: option.title,
                                subtitle: nil,
                                isSelected:
                                    hourSelectionView == option,
                                identifier:
                                    option.accessibilityIdentifier,
                                previewName: option.title
                            ) {
                                hourSelectionView = option
                            } preview: {
                                LiveHourDisplayPreview(
                                    hourSelectionView: option,
                                    displayMode: displayMode,
                                    currentHour: currentHour,
                                    colorScheme:
                                    selectedDisplayColorScheme
                                )
                            }
                        }
                    }
                    .frame(
                        maxWidth: SettingsPreviewLayout.maximumRowWidth
                    )
                    .frame(maxWidth: .infinity)
                    .id("settings-tour-hour-display")
                    .appTourTarget(.settingsHourDisplay)
                }

                previewSection(
                    title: "Appearance",
                    description: """
                    Dynamic follows the canonical hours. System follows your device’s current light or dark appearance.
                    """,
                    descriptionIdentifier: "appearance-description"
                ) {
                    HStack(
                        alignment: .top,
                        spacing: SettingsPreviewLayout.cardSpacing
                    ) {
                        ForEach(AppDisplayMode.allCases) { option in
                            let previewColorScheme =
                                option.preferredColorScheme(
                                    for: currentHour
                                ) ?? systemColorScheme

                            PreviewSelectionCard(
                                title: option.title,
                                subtitle: option.previewSubtitle(
                                    currentHour: currentHour,
                                    systemColorScheme:
                                        systemColorScheme
                                ),
                                isSelected: displayMode == option,
                                identifier:
                                    option.accessibilityIdentifier,
                                previewName:
                                    hourSelectionView.title
                            ) {
                                displayMode = option
                            } preview: {
                                CrossfadingHourDisplayPreview(
                                    hourSelectionView:
                                        hourSelectionView,
                                    displayMode: option,
                                    currentHour: currentHour,
                                    colorScheme:
                                        previewColorScheme
                                )
                            }
                        }
                    }
                    .frame(
                        maxWidth: SettingsPreviewLayout.maximumRowWidth
                    )
                    .frame(maxWidth: .infinity)
                    .id("settings-tour-appearance")
                    .appTourTarget(.settingsAppearance)
                }
            }
        }
    }

    private var automaticHourSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synchronize")
                .font(.system(.title3, design: .serif))

            Picker(
                "Synchronization",
                selection: Binding(
                    get: { isAtLocalTime },
                    set: { isAutomatic in
                        onAutomaticHourSelectionChanged(isAutomatic)
                        tour.receive(
                            .automaticHourSelectionChanged(isAutomatic)
                        )
                    }
                )
            ) {
                Text("Manual").tag(false)
                Text("Automatic").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier(
                "synchronization-mode-picker"
            )
            .appTourTarget(.settingsSynchronization)

            sectionDescription(
                automaticHourSelectionDescription,
                identifier:
                    "automatic-hour-selection-description"
            )
        }
        .id("settings-tour-synchronization")
    }

    private var automaticHourSelectionDescription: String {
        if isAtLocalTime {
            "Displaying the current canonical hour for your device’s current time."
        } else {
            "Select Automatic to synchronize and automatically keep the current hour displayed."
        }
    }

    private func previewSection<Content: View>(
        title: String,
        description: String? = nil,
        descriptionIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .serif))

            content()

            if let description {
                sectionDescription(
                    description,
                    identifier: descriptionIdentifier
                )
            }
        }
    }

    @ViewBuilder
    private func sectionDescription(
        _ description: String,
        identifier: String?
    ) -> some View {
        if let identifier {
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        } else {
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutSettingsView: View {
    let onClose: () -> Void
    let onAppTour: () -> Void
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesLargeLayout: Bool {
        horizontalSizeClass == .regular
            && (UIDevice.current.userInterfaceIdiom == .pad
                || ProcessInfo.processInfo.isiOSAppOnMac)
    }

    private var brandWidth: CGFloat { usesLargeLayout ? 360 : 232 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: usesLargeLayout ? 44 : 36) {
                VStack(spacing: usesLargeLayout ? 32 : 24) {
                    HoursBrandView(scale: brandWidth / 232)
                        .frame(width: brandWidth)

                    AutomaticHourTable(
                        textStyle: usesLargeLayout ? .title3 : .subheadline,
                        rowSpacing: usesLargeLayout ? 10 : 6
                    )
                    .frame(width: brandWidth)
                    .accessibilityIdentifier(
                        "about-automatic-hour-table"
                    )
                }
                .frame(maxWidth: .infinity)

                Button {
                    if !tour.isActive {
                        onAppTour()
                    }
                } label: {
                    HStack(spacing: usesLargeLayout ? 20 : 14) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: usesLargeLayout ? 28 : 21))
                            .foregroundStyle(.secondary)
                            .frame(width: usesLargeLayout ? 40 : 30)

                        VStack(alignment: .leading, spacing: usesLargeLayout ? 6 : 2) {
                            Text("App Tour")
                                .font(usesLargeLayout ? .title2 : .body)
                            Text("Replay the guided tour of Hours")
                                .font(usesLargeLayout ? .body : .caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(usesLargeLayout ? .body.weight(.semibold) : .caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    "Closes Settings and begins the tour from Home"
                )
                .accessibilityIdentifier("about-app-tour")
                .appTourTarget(.aboutTour)

                NavigationLink {
                    ChantGuideView()
                } label: {
                    HStack(spacing: usesLargeLayout ? 20 : 14) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: usesLargeLayout ? 28 : 21))
                            .foregroundStyle(.secondary)
                            .frame(width: usesLargeLayout ? 40 : 30)
                        VStack(alignment: .leading, spacing: usesLargeLayout ? 6 : 2) {
                            Text("Guide to Chant").font(usesLargeLayout ? .title2 : .body)
                            Text("Learn to read, hear, and sing Gregorian chant")
                                .font(usesLargeLayout ? .body : .caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(usesLargeLayout ? .body.weight(.semibold) : .caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about-chant-guide")

                NavigationLink {
                    RubricsGuideView()
                } label: {
                    HStack(spacing: usesLargeLayout ? 20 : 14) {
                        Image(systemName: "book.closed")
                            .font(.system(size: usesLargeLayout ? 28 : 21))
                            .foregroundStyle(.secondary)
                            .frame(width: usesLargeLayout ? 40 : 30)
                        VStack(alignment: .leading, spacing: usesLargeLayout ? 6 : 2) {
                            Text("Rubrics").font(usesLargeLayout ? .title2 : .body)
                            Text("The order of the Office, its psalms, and its chant")
                                .font(usesLargeLayout ? .body : .caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(usesLargeLayout ? .body.weight(.semibold) : .caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about-rubrics")

                contactSection
            }
            .frame(maxWidth: usesLargeLayout ? 820 : .infinity)
            .padding(.horizontal, usesLargeLayout ? 40 : 24)
            .padding(.vertical, usesLargeLayout ? 48 : 36)
            .frame(maxWidth: .infinity)
        }
        .background(Color.hoursBackground)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SheetCloseButton(
                    accessibilityLabel: "Close Settings",
                    accessibilityIdentifier: "about-close",
                    action: onClose
                )
            }
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: usesLargeLayout ? 24 : 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Contact")
                    .font(usesLargeLayout ? .title2.weight(.semibold) : .headline)

                Text(
                    "Have a question, found a bug, or have a suggestion?"
                )
                .font(usesLargeLayout ? .title3 : .body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: usesLargeLayout ? 24 : 16) {
                AboutLinkRow(
                    title: "Website",
                    value: "horarum.com",
                    systemImage: "globe",
                    destination: URL(
                        string: "https://horarum.com"
                    )!,
                    identifier: "about-website",
                    isExpanded: usesLargeLayout
                )

                AboutLinkRow(
                    title: "Contribute",
                    value: "horarum.com/support",
                    systemImage: "heart",
                    destination: URL(
                        string: "https://horarum.com/support"
                    )!,
                    identifier: "about-contribute",
                    isExpanded: usesLargeLayout
                )

                AboutLinkRow(
                    title: "Email",
                    value: "help@horarum.com",
                    systemImage: "envelope",
                    destination: URL(
                        string: "mailto:help@horarum.com"
                    )!,
                    identifier: "about-email",
                    isExpanded: usesLargeLayout
                )

                AboutLinkRow(
                    title: "Source Code",
                    value: "MCMXMCM/hours",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    destination: URL(
                        string: "https://github.com/MCMXMCM/hours"
                    )!,
                    identifier: "about-source-code",
                    isExpanded: usesLargeLayout
                )
            }
        }
    }
}

private struct HoursBrandView: View {
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 2 * scale) {
            Image("HoursSettingsIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 104 * scale, height: 82 * scale)

            Text("OURS")
                .font(
                    .system(
                        size: 49 * scale,
                        weight: .light,
                        design: .serif
                    )
                )
                .tracking(-2 * scale)
                .offset(y: 8 * scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hours")
        .accessibilityIdentifier("hours-about-logo")
    }
}

private struct AboutLinkRow: View {
    let title: String
    let value: String
    let systemImage: String
    let destination: URL
    let identifier: String
    var isExpanded = false

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: isExpanded ? 20 : 14) {
                Image(systemName: systemImage)
                    .font(.system(size: isExpanded ? 28 : 21, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: isExpanded ? 40 : 30)

                VStack(alignment: .leading, spacing: isExpanded ? 6 : 2) {
                    Text(title)
                        .font(isExpanded ? .body : .caption)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(isExpanded ? .title2 : .body)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(isExpanded ? .body : .subheadline)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Opens \(title.lowercased())")
        .accessibilityIdentifier(identifier)
    }
}

private struct PreviewSelectionCard<Preview: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let identifier: String
    let previewName: String
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                sizedPreview
                    .allowsHitTesting(false)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay {
                        if isSelected {
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                            .stroke(
                                Color.hoursTodayAccent,
                                lineWidth: 2.5
                            )
                        }
                    }
                    .accessibilityHidden(true)

                VStack(spacing: 1) {
                    Text(title)
                        .font(
                            SettingsPreviewLayout.usesLargePreviews
                                ? .headline
                                : .subheadline.weight(.semibold)
                        )

                    if let subtitle {
                        Text(subtitle)
                            .font(
                                SettingsPreviewLayout.usesLargePreviews
                                    ? .caption
                                    : .caption2
                            )
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 34, alignment: .top)
            }
            .padding(SettingsPreviewLayout.cardPadding)
            .frame(maxWidth: .infinity)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            subtitle.map { "\(title), \($0)" } ?? title
        )
        .accessibilityValue(
            isSelected
                ? "Selected, \(previewName) preview"
                : "\(previewName) preview"
        )
        .accessibilityHint("Shows this style on the home screen")
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var sizedPreview: some View {
        if SettingsPreviewLayout.usesLargePreviews {
            preview()
                .aspectRatio(
                    SettingsPreviewLayout.homeWidth
                        / SettingsPreviewLayout.wheelSourceHeight,
                    contentMode: .fit
                )
        } else {
            preview()
                .frame(height: SettingsPreviewLayout.previewHeight)
        }
    }
}

@MainActor
private enum SettingsPreviewLayout {
    static var usesLargePreviews: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            || ProcessInfo.processInfo.isiOSAppOnMac
    }

    static let previewHeight: CGFloat = 156
    static let cardPadding: CGFloat = 6
    static let cardSpacing: CGFloat = 12
    static let homeWidth: CGFloat = 390
    static let dialDiameter = homeWidth * 1.38
    static let wheelSourceHeight = CanonicalHourDialView.visibleHeight(
        for: dialDiameter
    )
    static let maximumPreviewWidth =
        previewHeight * homeWidth / wheelSourceHeight
    static let maximumCardWidth =
        maximumPreviewWidth + 2 * cardPadding
    static var maximumRowWidth: CGFloat {
        // Grow both previews with the sheet, while keeping narrow windows usable.
        usesLargePreviews
            ? 900
            : 2 * maximumCardWidth + cardSpacing
    }
}

private struct CrossfadingHourDisplayPreview: View {
    let hourSelectionView: HourSelectionViewMode
    let displayMode: AppDisplayMode
    let currentHour: OfficeHour
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            LiveHourDisplayPreview(
                hourSelectionView: .sunDial,
                displayMode: displayMode,
                currentHour: currentHour,
                colorScheme: colorScheme
            )
            .opacity(
                hourSelectionView == .sunDial ? 1 : 0
            )

            LiveHourDisplayPreview(
                hourSelectionView: .wheel,
                displayMode: displayMode,
                currentHour: currentHour,
                colorScheme: colorScheme
            )
            .opacity(
                hourSelectionView == .wheel ? 1 : 0
            )
        }
        .animation(
            .easeInOut(duration: 0.42),
            value: hourSelectionView
        )
    }
}

private struct LiveHourDisplayPreview: View {
    let hourSelectionView: HourSelectionViewMode
    let displayMode: AppDisplayMode
    let currentHour: OfficeHour
    let colorScheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.hoursBackground

                if displayMode.showsAmbientSky {
                    AmbientSkyView(selection: currentHour)
                }

                switch hourSelectionView {
                case .sunDial:
                    scaledSundial(in: geometry.size)
                case .wheel:
                    scaledWheel(in: geometry.size)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .clipped()
        }
        .environment(\.colorScheme, colorScheme)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scaledSundial(
        in size: CGSize
    ) -> some View {
        let sourceSize = CGSize(
            width: 390,
            height: CanonicalHourSundialView.minimumHeight
        )
        let scale = min(
            size.width / sourceSize.width,
            size.height / sourceSize.height
        )

        return CanonicalHourSundialView(
            selection: .constant(currentHour),
            followsLocalTime: .constant(true),
            showsShadow:
                AppDisplayMode.showsSundialShadow(
                    in: colorScheme
                ),
            onOpenOffice: { _ in }
        )
        .frame(
            width: sourceSize.width,
            height: sourceSize.height
        )
        .scaleEffect(scale)
        .position(
            x: size.width / 2,
            y: size.height / 2
        )
    }

    private func scaledWheel(
        in size: CGSize
    ) -> some View {
        let homeWidth = SettingsPreviewLayout.homeWidth
        let dialDiameter = SettingsPreviewLayout.dialDiameter
        let sourceHeight = SettingsPreviewLayout.wheelSourceHeight
        let sourceSize = CGSize(
            width: homeWidth,
            height: sourceHeight
        )
        let scale = min(
            size.width / sourceSize.width,
            size.height / sourceSize.height
        )
        let renderedHeight = sourceHeight * scale

        return CanonicalHourDialView(
            selection: .constant(currentHour),
            followsLocalTime: .constant(true)
        )
        .frame(
            width: dialDiameter,
            height: sourceHeight
        )
        .frame(
            width: homeWidth,
            height: sourceHeight
        )
        .clipped()
        .scaleEffect(scale)
        .position(
            x: size.width / 2,
            y: size.height
                - renderedHeight / 2
        )
    }
}

@MainActor
private enum SystemAppearance {
    static var currentColorScheme: ColorScheme {
        let style = UIApplication.shared.connectedScenes
            .compactMap { scene in
                (scene as? UIWindowScene)?
                    .screen
                    .traitCollection
                    .userInterfaceStyle
            }
            .first

        return style == .dark ? .dark : .light
    }
}

private extension AppDisplayMode {
    var accessibilityIdentifier: String {
        "display-mode-\(rawValue)"
    }

    func previewSubtitle(
        currentHour: OfficeHour,
        systemColorScheme: ColorScheme
    ) -> String {
        switch self {
        case .dynamic:
            let colorScheme = preferredColorScheme(
                for: currentHour
            ) ?? systemColorScheme
            let hourPeriod =
                colorScheme == .dark ? "Night" : "Day"
            return "\(colorScheme.title) for \(hourPeriod) Hours"
        case .system:
            return "System is \(systemColorScheme.title)"
        }
    }
}

private extension HourSelectionViewMode {
    var accessibilityIdentifier: String {
        "hour-display-\(rawValue)"
    }
}

private extension ColorScheme {
    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        @unknown default: "Light"
        }
    }
}

private struct AutomaticHourTable: View {
    var textStyle = Font.TextStyle.caption2
    var rowSpacing: CGFloat = 5

    var body: some View {
        TimelineView(
            .periodic(from: .now, by: 60)
        ) { context in
            let currentHour = OfficeHour.current(
                at: context.date
            )

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(OfficeHour.allCases, id: \.self) { hour in
                    let isCurrent = hour == currentHour

                    HStack(spacing: 10) {
                        Text(hour.englishTitle)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )

                        Text(hour.customaryTimeRange)
                            .fixedSize()
                    }
                    .font(
                        .system(
                            textStyle,
                            design: .default,
                            weight: isCurrent ? .bold : .regular
                        )
                    )
                    .foregroundStyle(
                        isCurrent
                            ? Color.primary
                            : Color.secondary
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                accessibilitySummary(
                    currentHour: currentHour
                )
            )
        }
    }

    private func accessibilitySummary(
        currentHour: OfficeHour
    ) -> String {
        let schedule = OfficeHour.allCases.map { hour in
            "\(hour.englishTitle), \(hour.customaryTimeRange)"
        }
        .joined(separator: ". ")

        return "Automatic hour schedule. \(schedule). Current hour: \(currentHour.englishTitle)."
    }
}
