import HoursCore
import SwiftUI
import UIKit

struct HomeSettingsView: View {
    @Binding var displayMode: AppDisplayMode
    @Binding var hourSelectionView: HourSelectionViewMode
    let isAtLocalTime: Bool
    let onAutomaticHourSelectionChanged: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    automaticHourSelection
                    livePreviewSettings
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(Color.hoursBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var livePreviewSettings: some View {
        TimelineView(
            .periodic(from: .now, by: 1)
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
                }
            }
        }
    }

    private var automaticHourSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Synchronize")
                    .font(.system(.title3, design: .serif))

                Spacer()

                NavigationLink {
                    AboutSettingsView {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Hours")
                .accessibilityHint(
                    "Shows the canonical hour schedule and contact information"
                )
                .accessibilityIdentifier("settings-about")
            }

            Picker(
                "Synchronization",
                selection: Binding(
                    get: { isAtLocalTime },
                    set: { isAutomatic in
                        onAutomaticHourSelectionChanged(isAutomatic)
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

            sectionDescription(
                automaticHourSelectionDescription,
                identifier:
                    "automatic-hour-selection-description"
            )
        }
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
    private static let brandWidth: CGFloat = 232

    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(spacing: 24) {
                    HoursBrandView()
                        .frame(width: Self.brandWidth)

                    AutomaticHourTable(
                        textStyle: .subheadline,
                        rowSpacing: 6
                    )
                    .frame(width: Self.brandWidth)
                    .accessibilityIdentifier(
                        "about-automatic-hour-table"
                    )
                }
                .frame(maxWidth: .infinity)

                contactSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 36)
        }
        .background(Color.hoursBackground)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone)
                    .accessibilityIdentifier("about-done")
            }
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Contact")
                    .font(.headline)

                Text(
                    "Have a question, found a bug, or have a suggestion?"
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 16) {
                AboutLinkRow(
                    title: "Website",
                    value: "horarum.com",
                    systemImage: "globe",
                    destination: URL(
                        string: "https://horarum.com"
                    )!,
                    identifier: "about-website"
                )

                AboutLinkRow(
                    title: "Contribute",
                    value: "horarum.com/support",
                    systemImage: "heart",
                    destination: URL(
                        string: "https://horarum.com/support"
                    )!,
                    identifier: "about-contribute"
                )

                AboutLinkRow(
                    title: "Email",
                    value: "help@horarum.com",
                    systemImage: "envelope",
                    destination: URL(
                        string: "mailto:help@horarum.com"
                    )!,
                    identifier: "about-email"
                )
            }
        }
    }
}

private struct HoursBrandView: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Image("HoursSettingsIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 82)

            Text("OURS")
                .font(
                    .system(
                        size: 49,
                        weight: .light,
                        design: .serif
                    )
                )
                .tracking(-2)
                .offset(y: 8)
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

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.subheadline)
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
                preview()
                    .frame(height: SettingsPreviewLayout.previewHeight)
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
                        .font(.subheadline.weight(.semibold))

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
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
}

private enum SettingsPreviewLayout {
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
    static let maximumRowWidth =
        2 * maximumCardWidth + cardSpacing
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
