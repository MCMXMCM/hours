import SwiftUI
import UIKit

extension View {
    func appTourTarget(_ target: AppTourTarget) -> some View {
        modifier(AppTourTargetModifier(target: target))
    }

    func appTourOverlayHost(_ layer: AppTourLayer) -> some View {
        modifier(AppTourOverlayHostModifier(layer: layer, isEnabled: true))
    }

    func appTourOverlayHost(
        _ layer: AppTourLayer,
        when condition: Bool
    ) -> some View {
        modifier(
            AppTourOverlayHostModifier(
                layer: layer,
                isEnabled: condition
            )
        )
    }

    func appTourTarget(
        _ target: AppTourTarget,
        when condition: Bool
    ) -> some View {
        modifier(
            ConditionalAppTourTargetModifier(
                target: target,
                isEnabled: condition
            )
        )
    }
}

private struct ConditionalAppTourTargetModifier: ViewModifier {
    let target: AppTourTarget
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(AppTourTargetModifier(target: target))
        } else {
            content
        }
    }
}

private struct AppTourTargetModifier: ViewModifier {
    @Environment(AppTourCoordinator.self) private var tour
    let target: AppTourTarget

    func body(content: Content) -> some View {
        content
            .onGeometryChange(
                for: CGRect.self,
                of: { geometry in
                    geometry.frame(in: .global)
                },
                action: { frame in
                    tour.report(frame: frame, for: target)
                }
            )
    }
}

private struct AppTourOverlayHostModifier: ViewModifier {
    @Environment(AppTourCoordinator.self) private var tour
    let layer: AppTourLayer
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEnabled,
                   tour.presentsOverlay,
                   tour.currentLayer == layer,
                   let step = tour.step,
                   step.showsSpotlight {
                    AppTourSpotlightOverlay()
                        .ignoresSafeArea(edges: .vertical)
                        .allowsHitTesting(
                            !step.allowsInteractionOutsideSpotlight
                        )
                        .transition(.opacity)
                        .zIndex(10_000)
                }
            }
            .overlay {
                if isEnabled,
                   tour.presentsOverlay,
                   tour.currentLayer == layer,
                   let step = tour.step,
                   !step.usesDockedInstructions,
                   !step.usesScreenTopInstructions,
                   !step.usesScreenBottomInstructions {
                    AppTourAdaptiveInstructions()
                        .allowsHitTesting(
                            !step.requiresUnobstructedInteraction
                        )
                        .transition(.opacity)
                        .zIndex(10_001)
                }
            }
            .overlay {
                if isEnabled,
                   tour.presentsOverlay,
                   layer == .home,
                   let step = tour.step,
                   step.usesScreenTopInstructions {
                    AppTourScreenTopInstructions()
                        .transition(.opacity)
                        .zIndex(10_001)
                }
            }
            .overlay(alignment: .bottom) {
                if isEnabled,
                   tour.presentsOverlay,
                   tour.currentLayer == layer,
                   let step = tour.step,
                   step.usesScreenBottomInstructions {
                    AppTourInstructions(isFloating: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .allowsHitTesting(
                            !step.requiresUnobstructedInteraction
                        )
                        .transition(.opacity)
                        .zIndex(10_001)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEnabled,
                   tour.presentsOverlay,
                   tour.currentLayer == layer,
                   let step = tour.step,
                   step.usesDockedInstructions {
                    AppTourInstructions(isFloating: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .allowsHitTesting(
                            !step.requiresUnobstructedInteraction
                        )
                        .zIndex(10_001)
                }
            }
            .animation(
                .easeInOut(duration: 0.2),
                value: tour.presentsOverlay
            )
    }
}

private extension AppTourStep {
    var usesDockedInstructions: Bool {
        switch self {
        case .submitSearch, .changeHourDisplay,
             .changeAppearance, .restoreHourDisplay, .restoreAppearance,
             .restoreAutomaticTracking, .aboutReplay:
            true
        default:
            false
        }
    }

    var usesScreenTopInstructions: Bool {
        self == .chooseHour || self == .scrollCalendarMonth
    }

    var usesScreenBottomInstructions: Bool {
        self == .tapFirstNeume || self == .swipeDay
    }

    var showsSpotlight: Bool {
        self != .scrollCalendarMonth
    }

    var allowsInteractionOutsideSpotlight: Bool {
        switch self {
        case .enableEnglish, .closeReaderOptions,
             .returnHomeFromReader,
             .changeHourDisplay, .changeAppearance,
             .restoreHourDisplay, .restoreAppearance,
             .restoreAutomaticTracking, .openAbout,
             .chooseFirstChantSetting,
             .chooseSecondChantSetting, .returnFromFirstChant,
             .returnFromSecondChant, .returnToSearchResults,
             .closeSettings:
            true
        default:
            false
        }
    }

    var requiresUnobstructedInteraction: Bool {
        switch self {
        case .closeCantorGuide, .enableEnglish, .closeReaderOptions,
             .returnHomeFromReader, .chooseFirstChantSetting,
             .returnFromFirstChant, .chooseSecondChantSetting,
             .returnFromSecondChant, .returnToSearchResults,
             .closeSearch, .closeCalendar,
             .changeHourDisplay, .changeAppearance,
             .restoreHourDisplay, .restoreAppearance,
             .restoreAutomaticTracking,
             .closeSettings, .openAbout:
            true
        default:
            false
        }
    }
}

private struct AppTourScreenTopInstructions: View {
    @Environment(AppTourCoordinator.self) private var tour
    @State private var cardSize = CGSize(width: 358, height: 150)

    var body: some View {
        GeometryReader { geometry in
            let hostFrame = geometry.frame(in: .global)
            let cardWidth = min(390, max(0, geometry.size.width - 32))
            let desiredGlobalTop: CGFloat = tour.step == .chooseHour
                ? 112
                : 120
            let localTop = desiredGlobalTop - hostFrame.minY

            AppTourInstructions(isFloating: true)
                .frame(width: cardWidth)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    guard size.width > 0, size.height > 0 else { return }
                    cardSize = size
                }
                .position(
                    x: geometry.size.width / 2,
                    y: localTop + cardSize.height / 2
                )
        }
    }
}

private extension AppTourTarget {
    var spotlightPadding: CGSize {
        switch self {
        case .readerOratio:
            CGSize(width: 12, height: 14)
        case .readerEnglish:
            CGSize(width: 10, height: 12)
        case .searchChantSetting:
            CGSize(width: 10, height: 10)
        default:
            CGSize(width: 5, height: 5)
        }
    }

    var spotlightOffset: CGSize { .zero }
}

private struct AppTourAdaptiveInstructions: View {
    @Environment(AppTourCoordinator.self) private var tour
    @State private var cardSize = CGSize(width: 358, height: 150)

    var body: some View {
        GeometryReader { geometry in
            let hostFrame = geometry.frame(in: .global)
            let target = localTargetFrame(in: hostFrame)
            let cardWidth = min(390, max(0, geometry.size.width - 32))
            let origin = cardOrigin(
                cardSize: CGSize(width: cardWidth, height: cardSize.height),
                target: target,
                geometry: geometry
            )

            AppTourInstructions(isFloating: true)
                .frame(width: cardWidth)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    guard size.width > 0, size.height > 0 else { return }
                    cardSize = size
                }
                .position(
                    x: origin.x + cardWidth / 2,
                    y: origin.y + cardSize.height / 2
                )
        }
    }

    private func localTargetFrame(in hostFrame: CGRect) -> CGRect? {
        guard let target = tour.currentTarget,
              let frame = tour.frame(for: target),
              frame.intersects(hostFrame.insetBy(dx: -2, dy: -2)) else {
            return nil
        }
        let local = frame.offsetBy(
            dx: -hostFrame.minX,
            dy: -hostFrame.minY
        )
        let padding = target.spotlightPadding
        let offset = target.spotlightOffset
        return CGRect(
            x: local.minX - padding.width,
            y: local.minY - padding.height,
            width: local.width + padding.width * 2,
            height: local.height + padding.height * 2
        )
        .offsetBy(dx: offset.width, dy: offset.height)
    }

    private func cardOrigin(
        cardSize: CGSize,
        target: CGRect?,
        geometry: GeometryProxy
    ) -> CGPoint {
        let margin: CGFloat = 16
        let gap: CGFloat = 14
        let top = max(margin, geometry.safeAreaInsets.top + margin)
        let bottom = geometry.size.height
            - max(margin, geometry.safeAreaInsets.bottom + margin)
        let left = margin
        let right = geometry.size.width - margin
        let fallbackX = max(left, (geometry.size.width - cardSize.width) / 2)
        let fallbackY = max(top, bottom - cardSize.height)

        guard let target else {
            return CGPoint(x: fallbackX, y: fallbackY)
        }

        let availableAbove = target.minY - gap - top
        let availableBelow = bottom - target.maxY - gap
        let fitsAbove = availableAbove >= cardSize.height
        let fitsBelow = availableBelow >= cardSize.height
        let placeBelow: Bool
        if fitsAbove, fitsBelow {
            placeBelow = target.midY < geometry.size.height / 2
        } else if fitsBelow {
            placeBelow = true
        } else {
            placeBelow = false
        }

        let proposedY = placeBelow
            ? target.maxY + gap
            : target.minY - gap - cardSize.height
        let x = min(
            max(target.midX - cardSize.width / 2, left),
            max(left, right - cardSize.width)
        )
        let y = min(
            max(proposedY, top),
            max(top, bottom - cardSize.height)
        )
        return CGPoint(x: x, y: y)
    }
}

struct AppTourSpotlightOverlay: View {
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            let hostFrame = geometry.frame(in: .global)
            let targetFrame = localTargetFrame(
                in: hostFrame
            )

            ZStack {
                if let targetFrame {
                    spotlight(
                        around: targetFrame,
                        in: geometry.size
                    )
                    .allowsHitTesting(false)
                    spotlightEmphasis(
                        around: targetFrame,
                        in: geometry.size
                    )
                    dimmedHitRegions(
                        around: targetFrame,
                        in: geometry.size
                    )
                } else {
                    dimColor
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2),
                value: tour.accessibilityFocusID
            )
        }
    }

    private var dimColor: Color {
        reduceTransparency
            ? Color.black.opacity(0.82)
            : Color.black.opacity(0.62)
    }

    private func localTargetFrame(
        in hostFrame: CGRect
    ) -> CGRect? {
        guard let target = tour.currentTarget else { return nil }
        if target == .readerBack
            || target == .searchChantBack
            || target == .searchDetailBack {
            return navigationBackFrame(
                in: hostFrame
            )
        }
        guard
              let frame = tour.frame(for: target),
              frame.intersects(hostFrame.insetBy(dx: -2, dy: -2)) else {
            return nil
        }
        let horizontalOrigin: CGFloat = switch target {
        case .calendarIcon, .calendarClose:
            0
        default:
            hostFrame.minX
        }
        let local = frame.offsetBy(
            dx: -horizontalOrigin,
            dy: -hostFrame.minY
        )
        let padding = target.spotlightPadding
        let offset = target.spotlightOffset
        let compactSheetToolbarOffset: CGFloat =
            target == .calendarClose
                ? min(hostFrame.minX, 6)
                : 0
        return CGRect(
            x: local.minX - padding.width,
            y: local.minY - padding.height,
            width: local.width + padding.width * 2,
            height: local.height + padding.height * 2
        )
        .offsetBy(
            dx: offset.width + compactSheetToolbarOffset,
            dy: offset.height
        )
    }

    private func navigationBackFrame(
        in hostFrame: CGRect
    ) -> CGRect {
        let globalTop: CGFloat = hostFrame.minY < 24
            ? 60
            : hostFrame.minY + 16
        return CGRect(
            x: 16,
            y: globalTop - hostFrame.minY,
            width: 44,
            height: 44
        )
    }

    private func spotlight(
        around target: CGRect,
        in size: CGSize
    ) -> some View {
        let clipped = target.intersection(
            CGRect(origin: .zero, size: size)
        )
        let cornerRadius = spotlightCornerRadius(for: clipped)
        return Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRoundedRect(
                in: clipped,
                cornerSize: CGSize(
                    width: cornerRadius,
                    height: cornerRadius
                ),
                style: .continuous
            )
        }
        .fill(dimColor, style: FillStyle(eoFill: true))
    }

    @ViewBuilder
    private func spotlightEmphasis(
        around target: CGRect,
        in size: CGSize
    ) -> some View {
        if let label = toolbarSpotlightLabel {
            let cornerRadius = spotlightCornerRadius(for: target)
            ZStack {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(Color.white, lineWidth: 8)
                .frame(width: target.width, height: target.height)
                .position(x: target.midX, y: target.midY)

                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(Color.hoursTodayAccent, lineWidth: 4.5)
                .frame(width: target.width, height: target.height)
                .position(x: target.midX, y: target.midY)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .black))
                    Text(label)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.hoursTodayAccent)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white, lineWidth: 2)
                        }
                }
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .position(
                    x: min(max(target.midX, 70), size.width - 70),
                    y: min(target.maxY + 43, size.height - 40)
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var toolbarSpotlightLabel: String? {
        switch tour.currentTarget {
        case .readerContents:
            "CONTENTS"
        case .readerOptions:
            "SETTINGS"
        default:
            nil
        }
    }

    @ViewBuilder
    private func dimmedHitRegions(
        around target: CGRect,
        in size: CGSize
    ) -> some View {
        let clipped = target.intersection(
            CGRect(origin: .zero, size: size)
        )
        dimHitRegion(
            CGRect(x: 0, y: 0, width: size.width, height: max(0, clipped.minY))
        )
        dimHitRegion(
            CGRect(
                x: 0,
                y: clipped.minY,
                width: max(0, clipped.minX),
                height: max(0, clipped.height)
            )
        )
        dimHitRegion(
            CGRect(
                x: clipped.maxX,
                y: clipped.minY,
                width: max(0, size.width - clipped.maxX),
                height: max(0, clipped.height)
            )
        )
        dimHitRegion(
            CGRect(
                x: 0,
                y: clipped.maxY,
                width: size.width,
                height: max(0, size.height - clipped.maxY)
            )
        )
    }

    private func dimHitRegion(_ frame: CGRect) -> some View {
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .position(x: frame.midX, y: frame.midY)
            .accessibilityHidden(true)
    }

    private func spotlightCornerRadius(for frame: CGRect) -> CGFloat {
        guard let target = tour.currentTarget else { return 16 }
        let maximum = min(frame.width, frame.height) / 2
        let preferred: CGFloat = switch target {
        case .searchButton, .settingsButton, .readerContents,
             .readerOptions, .calendarIcon, .calendarClose, .searchClose,
             .cantorClose, .readerBack, .searchChantBack,
             .searchDetailBack, .settingsClose, .settingsAbout:
            maximum
        case .searchField, .searchCategoryChants, .cantorPitch,
             .settingsSynchronization:
            maximum
        case .hourSelector, .settingsHourDisplay, .settingsAppearance:
            28
        case .readerFirstChant:
            10
        default:
            16
        }
        return min(maximum, preferred)
    }

}

private struct AppTourInstructions: View {
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @AccessibilityFocusState private var instructionFocused: Bool
    let isFloating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(tour.title)
                    .font(.headline)
                Spacer(minLength: 12)
                Text(tour.progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(tour.instruction)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip Tour", action: finishTour)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("app-tour-skip")

                Spacer()

                if tour.isFinalStep {
                    Button("Finish Tour", action: finishTour)
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("app-tour-finish")
                }
            }
        }
        .padding(isFloating ? 18 : 12)
        .padding(.horizontal, isFloating ? 0 : 6)
        .frame(
            maxWidth: isFloating ? 390 : .infinity,
            alignment: .leading
        )
        .background {
            if isFloating {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(
                        color: .black.opacity(0.24),
                        radius: 18,
                        y: 8
                    )
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(tour.title). \(tour.instruction)"
        )
        .accessibilityFocused($instructionFocused)
        .accessibilityIdentifier("app-tour-overlay")
        .task(id: tour.accessibilityFocusID) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            instructionFocused = true
            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch {
                return
            }
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    private func finishTour() {
        Task {
            await tour.finish(model: model, playback: playback)
        }
    }
}

struct AppTourWelcomeView: View {
    @Environment(AppTourCoordinator.self) private var tour

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Image("HoursSettingsIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 142)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Welcome to Hours")
                        .font(.system(.largeTitle, design: .serif))
                        .multilineTextAlignment(.center)
                    Text(
                        "Take a guided tour through the app's main features."
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Skip Tour") {
                        tour.requestWelcomeSkip()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("app-tour-welcome-skip")

                    Button("Start Tour") {
                        tour.requestWelcomeStart()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("app-tour-start")
                }
            }
            .frame(maxWidth: 520)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hoursBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        tour.requestWelcomeClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close tour offer")
                    .accessibilityIdentifier("app-tour-welcome-close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.hoursBackground)
    }
}
