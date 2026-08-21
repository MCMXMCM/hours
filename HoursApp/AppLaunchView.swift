import SwiftUI

struct AppLaunchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = SplashPhase.initial

    var body: some View {
        ZStack {
            RootView()
                .allowsHitTesting(phase == .complete)
                .accessibilityHidden(phase != .complete)

            if phase != .complete {
                splash
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            await animateSplash()
        }
        .sheet(
            isPresented: Binding(
                get: { tour.isWelcomePresented },
                set: { isPresented in
                    if !isPresented,
                       tour.isWelcomePresented {
                        tour.requestWelcomeClose()
                    }
                }
            ),
            onDismiss: {
                tour.welcomeDidDismiss(model: model)
            }
        ) {
            AppTourWelcomeView()
        }
    }

    private var splash: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            Image("HoursSettingsIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 188)
                .scaleEffect(phase == .initial ? 0.96 : 1)
                .opacity(phase == .initial ? 0 : 1)
                .accessibilityHidden(true)
        }
    }

    @MainActor
    private func animateSplash() async {
        guard phase == .initial else { return }

        guard !reduceMotion else {
            phase = .complete
            tour.launchAnimationCompleted()
            return
        }

        withAnimation(.easeOut(duration: 0.48)) {
            phase = .visible
        }

        try? await Task.sleep(for: .milliseconds(680))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.34)) {
            phase = .complete
        }
        tour.launchAnimationCompleted()
    }
}

private enum SplashPhase {
    case initial
    case visible
    case complete
}

#Preview {
    AppLaunchView()
        .environment(AppModel())
        .environment(ChantPlaybackController())
        .environment(AppTourCoordinator())
}
