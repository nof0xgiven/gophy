import SwiftUI

@MainActor
struct MeetingQuickActionBar: View {
    @Bindable var viewModel: MeetingViewModel
    @State private var showQuickAsk = false
    @State private var showCopyCheckmark = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                if showQuickAsk {
                    quickAskField
                } else {
                    actionButtons
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(.easeInOut(duration: 0.2), value: showQuickAsk)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            quickActionButton(
                icon: showCopyCheckmark ? "checkmark.circle.fill" : "doc.on.doc",
                label: "Copy",
                color: showCopyCheckmark ? .green : .secondary,
                action: {
                    viewModel.copyLastSuggestion()
                    withAnimation {
                        showCopyCheckmark = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showCopyCheckmark = false
                        }
                    }
                }
            )

            quickActionButton(
                icon: "questionmark.bubble",
                label: "Ask AI",
                color: .secondary,
                action: {
                    withAnimation { showQuickAsk = true }
                }
            )

            quickActionButton(
                icon: "star",
                label: "Mark",
                color: .secondary,
                action: {
                    viewModel.markImportant()
                }
            )

            quickActionButton(
                icon: viewModel.suggestionsPaused ? "bell.slash" : "bell",
                label: viewModel.suggestionsPaused ? "Paused" : "Pause",
                color: viewModel.suggestionsPaused ? .orange : .secondary,
                action: {
                    viewModel.toggleSuggestionsPaused()
                }
            )

            Spacer()

            if !viewModel.markedMoments.isEmpty {
                Label("\(viewModel.markedMoments.count)", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
    }

    private var quickAskField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .foregroundStyle(.blue)

                TextField("Ask about the current conversation...", text: $viewModel.quickAskText, axis: .horizontal)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await viewModel.submitQuickAsk() }
                    }

                if viewModel.quickAskLoading {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await viewModel.submitQuickAsk() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(viewModel.quickAskText.isEmpty ? Color.secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.quickAskText.isEmpty || viewModel.quickAskLoading)

                Button {
                    showQuickAsk = false
                    viewModel.quickAskResponse = nil
                    viewModel.quickAskText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let response = viewModel.quickAskResponse, !response.isEmpty {
                Text(response)
                    .font(.caption)
                    .foregroundStyle(response.hasPrefix("Error:") ? .red : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func quickActionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
