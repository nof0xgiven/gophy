import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DocumentManagerView: View {
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @State private var viewModel: DocumentManagerViewModel?
    @State private var selectedDocument: DocumentRecord?
    @State private var initError: String?
    @State private var isDragOver = false

    var body: some View {
        Group {
            if let errorMessage = initError {
                modelsRequiredView(message: errorMessage)
            } else if let viewModel = viewModel {
                NavigationStack {
                    if selectedDocument == nil {
                        documentListView(viewModel: viewModel)
                    } else {
                        DocumentDetailView(
                            document: selectedDocument!,
                            onBack: { selectedDocument = nil },
                            onDelete: { doc in
                                Task {
                                    await viewModel.deleteDocument(doc)
                                    selectedDocument = nil
                                }
                            }
                        )
                    }
                }
                .task {
                    await viewModel.loadDocuments()
                }
            } else {
                SwiftUI.ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await initializeViewModel()
        }
    }

    private func modelsRequiredView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Models Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Go to Models tab to download the required models.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func documentListView(viewModel: DocumentManagerViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Documents")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    viewModel.openFilePicker()
                }) {
                    Label("Add Document", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)
            }
            .padding()

            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }

            if viewModel.isProcessing {
                HStack {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing document...")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            if viewModel.documents.isEmpty && !viewModel.isProcessing {
                emptyStateView
            } else {
                List {
                    ForEach(viewModel.documents, id: \.id) { document in
                        DocumentRowView(
                            document: document,
                            viewModel: viewModel,
                            onSelect: { selectedDocument = document },
                            onOpenChat: {
                                Task { await navigationCoordinator.openChat(contextType: .document, contextId: document.id, title: document.name) }
                            },
                            onDelete: {
                                Task { await viewModel.deleteDocument(document) }
                            }
                        )
                        .contextMenu {
                            Button {
                                Task { await navigationCoordinator.openChat(contextType: .document, contextId: document.id, title: document.name) }
                            } label: {
                                Label("Open Chat", systemImage: "bubble.left")
                            }
                            if document.meetingId != nil {
                                Button {
                                    Task { await viewModel.unlinkDocument(document) }
                                } label: {
                                    Label("Unlink from Meeting", systemImage: "link.badge.plus")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteDocument(document)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDragOver {
                dropZoneOverlay
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers, viewModel: viewModel)
        }
    }

    private var dropZoneOverlay: some View {
        ZStack {
            Color.blue.opacity(0.1)

            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10]))
                .foregroundStyle(.blue)
                .padding(20)

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Drop files to add")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                Text("PDF, PNG, JPG, TXT, MD")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Documents")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add documents to index and search them in chat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .foregroundStyle(.blue)
                Text("Drag and drop files here")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(providers: [NSItemProvider], viewModel: DocumentManagerViewModel) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else {
                        return
                    }

                    let ext = url.pathExtension.lowercased()
                    guard ["pdf", "png", "jpg", "jpeg", "txt", "md"].contains(ext) else {
                        return
                    }

                    Task { @MainActor in
                        await viewModel.processDocument(url: url)
                    }
                }
                handled = true
            }
        }

        return handled
    }

    private func initializeViewModel() async {
        guard viewModel == nil, initError == nil else { return }

        do {
            let storageManager = StorageManager()
            let database = try GophyDatabase(storageManager: storageManager)
            let documentRepo = DocumentRepository(database: database)
            let meetingRepo = MeetingRepository(database: database)

            // OCR auto-loads when a scanned PDF or image actually needs it. Loading it here
            // makes opening the Documents tab depend on multi-GB model startup.
            let ocrEngine = OCREngine()

            // Embeddings are optional for rendering/managing documents. They load when
            // indexing is possible; indexing failures must not block the Documents tab.
            let embeddingEngine = EmbeddingEngine()
            let textGenerationEngine = TextGenerationEngine()
            let transcriptionEngine = TranscriptionEngine()
            let providerRegistry = ProviderRegistry(
                transcriptionEngine: transcriptionEngine,
                textGenerationEngine: textGenerationEngine,
                embeddingEngine: embeddingEngine,
                ocrEngine: ocrEngine
            )
            let activeEmbeddingProvider = ActiveEmbeddingProviderAdapter(
                providerResolver: providerRegistry,
                localEmbeddingEngine: embeddingEngine
            )

            let embeddingPipeline = EmbeddingPipeline(
                embeddingEngine: activeEmbeddingProvider,
                vectorSearchService: VectorSearchService(database: database),
                meetingRepository: meetingRepo,
                documentRepository: documentRepo
            )

            let documentProcessor = DocumentProcessor(
                documentRepository: documentRepo,
                ocrEngine: ocrEngine,
                embeddingPipeline: embeddingPipeline
            )

            viewModel = DocumentManagerViewModel(
                documentRepository: documentRepo,
                documentProcessor: documentProcessor
            )
        } catch {
            initError = "Failed to initialize: \(error.localizedDescription)"
        }
    }
}

@MainActor
struct DocumentRowView: View {
    let document: DocumentRecord
    let viewModel: DocumentManagerViewModel
    let onSelect: () -> Void
    var onOpenChat: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.typeIcon(for: document.type))
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        statusBadge
                        if document.pageCount > 0 {
                            Text("\(document.pageCount) pages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.formatDate(document.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if document.status == "processing" {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 8) {
                        if let onOpenChat {
                            Button(action: onOpenChat) {
                                Image(systemName: "bubble.left")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Open Chat")
                        }

                        if let onDelete {
                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Delete")
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Group {
            switch document.status {
            case "ready":
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case "processing":
                Label("Processing", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case "failed":
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            default:
                Label("Pending", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
