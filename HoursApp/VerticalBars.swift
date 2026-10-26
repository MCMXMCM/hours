import SwiftUI

extension ToolbarContent {
    /// Lets an item of the app's own drawing stand in a bar that runs down
    /// the side of the screen, where iPhone Duo sets its bars: its symbol
    /// fits the bar's width. Elsewhere nothing changes.
    @ToolbarContentBuilder
    func standsInVerticalBars() -> some ToolbarContent {
        if #available(iOS 27.1, *) {
            axisBehavior(.verticalPreferred)
        } else {
            self
        }
    }
}

/// The buttons of one toolbar item: side by side in a bar across the top of
/// the screen, and one above the other in a bar down its side, as iPhone
/// Duo's.
struct ToolbarButtonStack<Content: View>: View {
    var spacing: CGFloat = 2
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 27.1, *) {
            VerticalBarAwareStack(spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing) { content }
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarAwareStack<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    let spacing: CGFloat
    let content: Content

    var body: some View {
        let layout = verticalEdge == nil
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
        layout { content }
    }
}
