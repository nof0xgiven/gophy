import SwiftUI

@MainActor
struct CompactOverlayView: View {
    @State private var viewModel = CompactOverlayViewModel()
    @State private var isExpanded = true
    var onClose: (() -> Void)? = nil
    var onExpand: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if isExpanded {
                Divider()

                if !viewModel.latestSuggestion.isEmpty {
                    suggestionPreview
                    Divider()
                }

                transcriptPreview
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(radius: 8)
        .frame(maxWidth: 320)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.statusColor)
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse, isActive: viewModel.isActive)

            Text(viewModel.meetingTitle.isEmpty ? "Gophy" : viewModel.meetingTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Text(viewModel.formattedDuration)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Toggle size")

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Close overlay")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var suggestionPreview: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.caption)

            Text(viewModel.latestSuggestion)
                .font(.caption)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.recentSegments.isEmpty {
                Text("Waiting for transcript...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.recentSegments, id: \.id) { segment in
                    HStack(alignment: .top, spacing: 6) {
                        Text(segment.speaker)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Text(segment.text)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
