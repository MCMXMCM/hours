import SwiftUI

struct RubricsGuideView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rubrics")
                        .font(.system(.largeTitle, design: .serif))
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose an edition of the Roman Office to consult its principles and sources.")
                        .font(.system(.body, design: .serif))
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(RubricsEdition.allCases) { edition in
                    NavigationLink {
                        RubricsEditionGuideView(edition: edition)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(edition.year)
                                .font(.system(.title2, design: .serif))
                            Text(edition.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("rubrics-edition-\(edition.year)")
                }
            } header: {
                Text("Editions")
            } footer: {
                Text("Consulting a reference does not change the edition selected for prayer.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.hoursBackground)
        .navigationTitle("Rubrics")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("rubrics-editions")
    }
}

private struct RubricsEditionGuideView: View {
    let edition: RubricsEdition
    @State private var searchText = ""
    @State private var selectedTopicID: String?

    private var topics: [RubricsTopic] {
        edition.topics.filter { $0.matches(searchText) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rubrics")
                        .font(.system(.largeTitle, design: .serif))
                        .accessibilityAddTraits(.isHeader)
                    Text("The Roman Office · \(edition.year)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(edition.introduction)
                        .font(.system(.body, design: .serif))
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("rubrics-introduction")
            }

            Section {
                ForEach(topics) { topic in
                    Button {
                        selectedTopicID = topic.id
                    } label: {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(topic.title)
                                    .font(.system(.headline, design: .serif))
                                    .foregroundStyle(.primary)
                                Text(topic.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .accessibilityHint("Opens this rubric reference")
                    .accessibilityIdentifier("rubrics-topic-\(topic.id)")
                }
                if topics.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("rubrics-no-results")
                }
            } header: {
                Text(searchText.isEmpty ? "Topics" : "Matching topics")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.hoursBackground)
        .navigationTitle("\(edition.year) Rubrics")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search rubrics")
        .accessibilityIdentifier("rubrics-topics")
        .navigationDestination(item: $selectedTopicID) { id in
            if let topic = edition.topics.first(where: { $0.id == id }) {
                RubricsTopicView(topic: topic, edition: edition)
                    .id(topic.id)
            }
        }
    }
}

private struct RubricsTopicView: View {
    let topic: RubricsTopic
    let edition: RubricsEdition

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(topic.title)
                        .font(.system(.largeTitle, design: .serif))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("rubrics-topic-title")
                    Text("Roman Office · \(edition.year) rubrics")
                        .accessibilityIdentifier("rubrics-reader-edition")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(topic.rules) { rule in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(rule.title)
                            .font(.system(.title2, design: .serif))
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 16) {
                            // Preserve paragraph boundaries for reading and VoiceOver.
                            ForEach(Array(rule.text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.system(.body, design: .serif))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(rule.citations) { citation in
                            Link(destination: citation.url) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(citation.label)
                                        .multilineTextAlignment(.leading)
                                    Image(systemName: "arrow.up.right")
                                        .accessibilityHidden(true)
                                }
                                .font(.footnote)
                                .padding(.vertical, 4)
                                .frame(minHeight: 44, alignment: .leading)
                            }
                            .accessibilityHint("Opens the source online")
                            .accessibilityIdentifier("rubrics-source-\(rule.id)-\(citation.id)")
                        }
                    }
                }

                if topic.id == "chant" {
                    NavigationLink {
                        ChantGuideView()
                    } label: {
                        Label("Study the examples in Guide to Chant", systemImage: "music.note.list")
                    }
                    .accessibilityIdentifier("rubrics-chant-guide")
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.hoursBackground)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("rubrics-reader")
    }
}

#Preview {
    NavigationStack { RubricsGuideView() }
}
