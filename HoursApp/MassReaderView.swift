import HoursCore
import SwiftUI

/// The Mass of the day in the reader, as Home's link opens it. A day with
/// several Masses (Christmas, All Souls, Maundy Thursday) names the one
/// shown in the navigation bar, and offers the others there.
struct MassReaderView: View {
    let displayMode: AppDisplayMode

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let mass = model.mass {
                OfficeReaderView(
                    office: mass,
                    displayMode: displayMode,
                    // A Mass keeps the light of the Hour chosen on Home.
                    skyHour: model.selectedHour,
                    restoredScrollOffset: model.restoredReaderScrollOffset(for: mass),
                    restoredScrollAnchor: model.restoredReaderScrollAnchor(for: mass),
                    onScrollOffsetChange: { offset, anchor in
                        model.updateReaderScrollOffset(offset, for: mass, anchor: anchor)
                    }
                )
                .id(mass.id)
            } else if let message = model.massErrorMessage, !model.isLoadingMass {
                ContentUnavailableView {
                    Label("Mass unavailable", systemImage: "book.closed")
                } description: {
                    Text(message)
                }
                .background(Color.hoursBackground)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.hoursBackground)
            }
        }
        .navigationTitle(model.readerPage == .latin ? "Missa" : "Mass")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if model.massListings.count > 1, let chosen = model.massIndex {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(model.massListings) { listing in
                            Button {
                                Task { await model.selectMass(index: listing.index) }
                            } label: {
                                if listing.index == chosen {
                                    Label(Self.name(of: listing), systemImage: "checkmark")
                                } else {
                                    Text(Self.name(of: listing))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.massListings.indices.contains(chosen)
                                ? Self.name(of: model.massListings[chosen])
                                : model.readerPage == .latin ? "Missa" : "Mass")
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.hoursPrimaryText)
                    }
                    .accessibilityIdentifier("mass-choice")
                    .accessibilityHint("Chooses among the day's Masses")
                }
            }
        }
    }

    /// A Mass as the menu names it: by the name that sets it apart, in
    /// English, with its Latin where English is lacking.
    static func name(of listing: MassListing) -> String {
        listing.labelEnglish ?? listing.label ?? listing.titleEnglish ?? listing.titleLatin
    }
}
