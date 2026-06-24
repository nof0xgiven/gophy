import SwiftUI

@MainActor
struct SuggestionPanelView: View {
    let suggestions: [SuggestionDisplayItem]
    let isGenerating: Bool
    let onRefresh: () async -> Void
    var ttsPlaybackService: TTSPlaybackService?
    var onDismiss: ((String) -> Void)?
    var onFeedback: ((String, String) -> Void)?

    @State private var collapsedSuggestions: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Suggestions")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: {
                    Task {
                        await onRefresh()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
            }

            if isGenerating {
                HStack(spacing: 8) {
                    SwiftUI.ProgressView()
                        .controlSize(.small)

                    Text("Generating suggestion...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if suggestions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.title)
                                .foregroundStyle(.secondary)

                            Text("No suggestions yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("Click Refresh to generate")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(suggestions.reversed(), id: \.id) { suggestion in
                            SuggestionItemView(
                                suggestion: suggestion,
                                isExpanded: !collapsedSuggestions.contains(suggestion.id),
                                onToggle: {
                                    toggleCollapsed(suggestion.id)
                                },
                                ttsPlaybackService: ttsPlaybackService,
                                onDismiss: onDismiss,
                                onFeedback: onFeedback
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.25), value: suggestions.count)
            }
        }
        .padding()
        .frame(width: 300)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func toggleCollapsed(_ id: String) {
        if collapsedSuggestions.contains(id) {
            collapsedSuggestions.remove(id)
        } else {
            collapsedSuggestions.insert(id)
        }
    }
}

@MainActor
struct SuggestionItemView: View {
    let suggestion: SuggestionDisplayItem
    let isExpanded: Bool
    let onToggle: () -> Void
    var ttsPlaybackService: TTSPlaybackService?
    var onDismiss: ((String) -> Void)?
    var onFeedback: ((String, String) -> Void)?

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(suggestion.createdAt)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }

    private var isPlayingThis: Bool {
        guard let service = ttsPlaybackService else { return false }
        return service.isPlaying && service.currentText == suggestion.content
    }

    private var isLoadingThis: Bool {
        guard let service = ttsPlaybackService else { return false }
        return service.isLoading && service.currentText == suggestion.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)

                Text(timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let service = ttsPlaybackService {
                    ttsButton(service: service)
                }

                if suggestion.isStreaming {
                    Text("streaming")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    MarkdownTextView(text: suggestion.content, font: .callout)
                        .textSelection(.enabled)
                    if suggestion.isStreaming {
                        Text("|\u{2060}")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .blink()
                    }
                }
            } else {
                Text(suggestion.content)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            if !suggestion.isStreaming {
                HStack(spacing: 12) {
                    if let onFeedback {
                        feedbackButtons(onFeedback)
                    }
                    Spacer()
                    if let onDismiss {
                        Button {
                            onDismiss(suggestion.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss")
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(suggestion.isStreaming ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                .animation(.easeInOut(duration: 0.3), value: suggestion.isStreaming)
        )
    }

    @ViewBuilder
    private func feedbackButtons(_ onFeedback: @escaping (String, String) -> Void) -> some View {
        HStack(spacing: 6) {
            Button {
                onFeedback(suggestion.id, "helpful")
            } label: {
                Image(systemName: suggestion.feedback == "helpful" ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.caption2)
                    .foregroundStyle(suggestion.feedback == "helpful" ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Helpful")

            Button {
                onFeedback(suggestion.id, "not_relevant")
            } label: {
                Image(systemName: suggestion.feedback == "not_relevant" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.caption2)
                    .foregroundStyle(suggestion.feedback == "not_relevant" ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help("Not relevant")
        }
    }

    @ViewBuilder
    private func ttsButton(service: TTSPlaybackService) -> some View {
        if isLoadingThis {
            SwiftUI.ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        } else if isPlayingThis {
            Button(action: {
                service.stop()
            }) {
                Image(systemName: "stop.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Stop reading")
        } else {
            Button(action: {
                service.play(text: suggestion.content)
            }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.isPlaying || service.isLoading)
            .help("Read aloud")
        }
    }
}

extension View {
    @ViewBuilder
    func blink() -> some View {
        modifier(BlinkModifier())
    }
}

struct BlinkModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}

#Preview {
    SuggestionPanelView(
        suggestions: [
            SuggestionDisplayItem(
                id: "1",
                content: "The project timeline was discussed in the last meeting with the same stakeholders. Q3 deadline was confirmed.",
                isStreaming: false,
                createdAt: Date().addingTimeInterval(-300)
            ),
            SuggestionDisplayItem(
                id: "2",
                content: "Based on the discussion, the budget constraints were clarified at $50K max.",
                isStreaming: true,
                createdAt: Date().addingTimeInterval(-60)
            )
        ],
        isGenerating: false,
        onRefresh: {}
    )
    .frame(height: 500)
}
