import Foundation

@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    private let storageManager: StorageManager
    private var cachedDatabase: GophyDatabase?

    init(storageManager: StorageManager = .shared) {
        self.storageManager = storageManager
    }

    func database() throws -> GophyDatabase {
        if let cachedDatabase {
            return cachedDatabase
        }

        let database = try GophyDatabase(storageManager: storageManager)
        cachedDatabase = database
        return database
    }

    func meetingRepository() throws -> MeetingRepository {
        MeetingRepository(database: try database())
    }

    func documentRepository() throws -> DocumentRepository {
        DocumentRepository(database: try database())
    }

    func chatMessageRepository() throws -> ChatMessageRepository {
        ChatMessageRepository(database: try database())
    }

    func chatRepository() throws -> ChatRepository {
        ChatRepository(database: try database())
    }
}
