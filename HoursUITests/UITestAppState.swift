import XCTest

enum UITestAppState {
    /// Settings persist between launches, and several cases change them on
    /// purpose (the edition, prayer options, the hour display, the tour).
    /// Each case therefore starts from a fresh install's settings.
    @MainActor
    static func reset() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-reset-defaults", "--suppress-app-tour"]
        app.launch()
        app.terminate()
    }
}
