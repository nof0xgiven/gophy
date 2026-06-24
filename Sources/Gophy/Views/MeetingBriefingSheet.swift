import SwiftUI

@MainActor
struct MeetingBriefingSheet: View {
    @State private var viewModel: MeetingBriefingViewModel?
    @State private var initializationError: String?
    @Environment(\.dismiss) private var dismiss
    let event: UnifiedCalendarEvent
    var onStartRecording: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if let viewModel = viewModel {
                    if viewModel.isLoading {
                        loadingView
                    } else {
                        contentView(viewModel: viewModel)
                    }
                } else if let initializationError {
                    errorOnlyView(initializationError)
                } else {
                    loadingView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(width: 440, height: 520)
        .task {
            await initializeViewModel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Label(formatEventTime(event), systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let location = event.location, !location.isEmpty {
                            Label(location, systemImage: "mappin")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let viewModel {
                        Text(viewModel.formattedAttendees)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            SwiftUI.ProgressView()
                .controlSize(.large)
            Text("Loading meeting context...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contentView(viewModel: MeetingBriefingViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !viewModel.hasContext {
                    noContextView
                } else {
                    if !viewModel.pastSummary.isEmpty {
                        pastSummarySection(viewModel)
                    }

                    if !viewModel.linkedDocuments.isEmpty {
                        documentsSection(viewModel)
                    }

                    if !viewModel.ragContext.isEmpty {
                        ragSection(viewModel)
                    }

                    if !viewModel.pastMeetings.isEmpty {
                        pastMeetingsSection(viewModel)
                    }
                }

                if let error = viewModel.errorMessage {
                    errorView(error)
                }
            }
            .padding()
        }
    }

    private var noContextView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Past Context")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("No previous meetings or documents found for this event. This will be the first meeting with this context.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func pastSummarySection(_ viewModel: MeetingBriefingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.blue)
                Text("Last Meeting Summary")
                    .font(.headline)
            }

            Text(viewModel.pastSummary)
                .font(.body)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
    }

    private func documentsSection(_ viewModel: MeetingBriefingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.orange)
                Text("Linked Documents")
                    .font(.headline)
            }

            ForEach(viewModel.linkedDocuments) { doc in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        if doc.pageCount > 0 {
                            Text("\(doc.pageCount) pages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private func ragSection(_ viewModel: MeetingBriefingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundStyle(.purple)
                Text("Knowledge Base Context")
                    .font(.headline)
            }

            Text(viewModel.ragContext)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
    }

    private func pastMeetingsSection(_ viewModel: MeetingBriefingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.green)
                Text("Related Past Meetings")
                    .font(.headline)
            }

            ForEach(viewModel.pastMeetings) { meeting in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title)
                            .font(.subheadline)
                        Text(formatDate(meeting.startedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func errorOnlyView(_ message: String) -> some View {
        VStack {
            errorView(message)
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let link = event.meetingLink, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open Link", systemImage: "video")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)

            if let onStartRecording {
                Button {
                    onStartRecording()
                    dismiss()
                } label: {
                    Label("Start Recording", systemImage: "record.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
    }

    private func initializeViewModel() async {
        guard viewModel == nil else { return }

        do {
            let db = try AppDependencies.shared.database()
            let meetingRepo = MeetingRepository(database: db)
            let documentRepo = DocumentRepository(database: db)
            let chatRepo = ChatMessageRepository(database: db)
            let ragProvider = DefaultMeetingBriefingRAGProvider(
                embeddingEngine: EmbeddingEngine(),
                vectorSearch: VectorSearchService(database: db)
            )

            let vm = MeetingBriefingViewModel(
                event: event,
                meetingRepository: meetingRepo,
                documentRepository: documentRepo,
                chatMessageRepository: chatRepo,
                ragProvider: ragProvider
            )
            viewModel = vm
            await vm.loadBriefing()
        } catch {
            initializationError = "Failed to load context: \(error.localizedDescription)"
        }
    }

    private func formatEventTime(_ event: UnifiedCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
