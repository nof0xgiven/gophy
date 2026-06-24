import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "ChatView")

@MainActor
struct ChatView: View {
    let initialChatId: String?

    @State private var database: GophyDatabase?
    @State private var chatListViewModel: ChatListViewModel?
    @State private var selectedChatId: String?
    @State private var initError: String?

    init(initialChatId: String? = nil) {
        self.initialChatId = initialChatId
    }

    var body: some View {
        Group {
            if let database, let chatListViewModel {
                HSplitView {
                    ChatListView(
                        viewModel: chatListViewModel,
                        selectedChatId: $selectedChatId
                    )

                    if let selectedChatId, let chat = chatListViewModel.chats.first(where: { $0.id == selectedChatId }) {
                        ChatDetailView(chat: chat, database: database)
                    } else {
                        emptySelectionView
                    }
                }
            } else if let initError {
                loadErrorView(message: initError)
            } else {
                SwiftUI.ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await initialize()
        }
        .onChange(of: initialChatId) { _, newValue in
            guard let newValue else { return }
            selectedChatId = newValue
            if let chatListViewModel {
                Task {
                    await chatListViewModel.loadChats()
                }
            }
        }
    }

    private var emptySelectionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Select a Chat")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a chat from the sidebar or create a new one")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func loadErrorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Chat Unavailable")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func initialize() async {
        guard database == nil, initError == nil else { return }

        do {
            let db = try AppDependencies.shared.database()
            let chatRepo = ChatRepository(database: db)
            let vm = ChatListViewModel(chatRepository: chatRepo)
            await vm.loadChats()

            database = db
            chatListViewModel = vm

            if let initialChatId {
                selectedChatId = initialChatId
            } else {
                selectedChatId = vm.predefinedChats.first?.id ?? "predefined-all"
            }
        } catch {
            logger.error("Failed to initialize ChatView: \(error.localizedDescription, privacy: .public)")
            initError = "Failed to initialize chat: \(error.localizedDescription)"
        }
    }
}
