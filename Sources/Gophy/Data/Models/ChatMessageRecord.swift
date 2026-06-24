import Foundation
import GRDB

public struct ChatMessageRecord: Codable, Sendable {
    public let id: String
    public let role: String
    public let content: String
    public let meetingId: String?
    public let chatId: String?
    public let createdAt: Date
    public var dismissed: Bool
    public var feedback: String?

    public init(
        id: String,
        role: String,
        content: String,
        meetingId: String?,
        chatId: String? = nil,
        createdAt: Date,
        dismissed: Bool = false,
        feedback: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.meetingId = meetingId
        self.chatId = chatId
        self.createdAt = createdAt
        self.dismissed = dismissed
        self.feedback = feedback
    }
}

extension ChatMessageRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "chat_messages"
}
