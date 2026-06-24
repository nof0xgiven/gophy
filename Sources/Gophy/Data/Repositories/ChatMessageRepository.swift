import Foundation
import GRDB

public final class ChatMessageRepository: Sendable {
    private let database: GophyDatabase

    public init(database: GophyDatabase) {
        self.database = database
    }

    public func create(_ message: ChatMessageRecord) async throws {
        try await database.dbQueue.write { db in
            try message.insert(db)
        }
    }

    public func listForMeeting(meetingId: String) async throws -> [ChatMessageRecord] {
        try await database.dbQueue.read { db in
            try ChatMessageRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func listGlobal() async throws -> [ChatMessageRecord] {
        try await database.dbQueue.read { db in
            try ChatMessageRecord
                .filter(Column("meetingId") == nil)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func listForChat(chatId: String) async throws -> [ChatMessageRecord] {
        try await database.dbQueue.read { db in
            try ChatMessageRecord
                .filter(Column("chatId") == chatId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func deleteAllForChat(chatId: String) async throws {
        try await database.dbQueue.write { db in
            _ = try ChatMessageRecord
                .filter(Column("chatId") == chatId)
                .deleteAll(db)
        }
    }

    public func delete(id: String) async throws {
        try await database.dbQueue.write { db in
            _ = try ChatMessageRecord.deleteOne(db, key: id)
        }
    }

    public func setDismissed(id: String, dismissed: Bool) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE chat_messages SET dismissed = ? WHERE id = ?",
                arguments: [dismissed, id]
            )
        }
    }

    public func setFeedback(id: String, feedback: String) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE chat_messages SET feedback = ? WHERE id = ?",
                arguments: [feedback, id]
            )
        }
    }
}

extension ChatMessageRepository: ChatMessageRepoForSuggestion {}
