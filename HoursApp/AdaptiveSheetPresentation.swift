import SwiftUI

struct AdaptiveSheetPresentation: ViewModifier {
    let phoneDetents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad
            || ProcessInfo.processInfo.isiOSAppOnMac {
            // Let the system fit a larger sheet to the available iPad or Mac window.
            content
                .presentationSizing(.page)
                .presentationDetents([.large])
        } else {
            content
                .presentationDetents(phoneDetents)
        }
    }
}
