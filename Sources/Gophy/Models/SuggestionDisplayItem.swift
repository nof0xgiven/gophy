import Foundation

public struct SuggestionDisplayItem: Identifiable {
    public let id: String
    public var content: String
    public var isStreaming: Bool
    public let createdAt: Date
    public var dismissed: Bool
    public var feedback: String?

    public init(
        id: String = UUID().uuidString,
        content: String,
        isStreaming: Bool = false,
        createdAt: Date = Date(),
        dismissed: Bool = false,
        feedback: String? = nil
    ) {
        self.id = id
        self.content = content
        self.isStreaming = isStreaming
        self.createdAt = createdAt
        self.dismissed = dismissed
        self.feedback = feedback
    }

    public init(from record: ChatMessageRecord) {
        self.id = record.id
        self.content = record.content
        self.isStreaming = false
        self.createdAt = record.createdAt
        self.dismissed = record.dismissed
        self.feedback = record.feedback
    }
}
