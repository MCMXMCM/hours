import SwiftUI

struct SheetCloseButton: View {
    let accessibilityLabel: LocalizedStringKey
    let accessibilityIdentifier: String
    let appTourTarget: AppTourTarget?
    let action: () -> Void

    init(
        accessibilityLabel: LocalizedStringKey,
        accessibilityIdentifier: String,
        appTourTarget: AppTourTarget? = nil,
        action: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.appTourTarget = appTourTarget
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var label: some View {
        let image = Image(systemName: "xmark")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

        if let appTourTarget {
            image.appTourTarget(appTourTarget)
        } else {
            image
        }
    }
}
