import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "MeetingBriefing")

@MainActor
@Observable
public final class MeetingBriefingViewModel {
    let event: UnifiedCalendarEvent

    var isLoading = true
    var pastMeetings: [MeetingRecord] = []
    var pastSummary: String = ""
    var linkedDocuments: [DocumentRecord] = []
    var ragContext: String = ""
    var errorMessage: String?

    private let meetingRepository: MeetingRepository
    private let documentRepository: DocumentRepository
    private let chatMessageRepository: ChatMessageRepository
    private let ragProvider: (any MeetingBriefingRAGProviding)?

    init(
        event: UnifiedCalendarEvent,
        meetingRepository: MeetingRepository,
        documentRepository: DocumentRepository,
        chatMessageRepository: ChatMessageRepository,
        ragProvider: (any MeetingBriefingRAGProviding)? = nil
    ) {
        self.event = event
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.chatMessageRepository = chatMessageRepository
        self.ragProvider = ragProvider
    }

    func loadBriefing() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allMeetings = try await meetingRepository.listAll(limit: 50, offset: 0)

            let titleMatch = allMeetings.filter { meeting in
                let similarity = titleSimilarity(meeting.title, event.title)
                return similarity > 0.5
            }

            let calendarMatch = allMeetings.filter { meeting in
                if let googleEventId = event.googleEventId, !googleEventId.isEmpty,
                   meeting.calendarEventId == googleEventId {
                    return true
                }
                return meeting.calendarEventId == event.id
            }

            let matchingMeetingIds = Set((titleMatch + calendarMatch).map(\.id))
            let orderedMatches = allMeetings.filter { matchingMeetingIds.contains($0.id) }
            pastMeetings = Array(orderedMatches.prefix(3))

            if let mostRecent = pastMeetings.first {
                let messages = try await chatMessageRepository.listForMeeting(meetingId: mostRecent.id)
                if let firstSuggestion = messages.first(where: { $0.role == "assistant" }) {
                    pastSummary = firstSuggestion.content
                }

                let docs = try await documentRepository.listAll()
                linkedDocuments = docs.filter { $0.meetingId == mostRecent.id }
            }

            if pastMeetings.isEmpty {
                let matched = try await meetingRepository.search(query: event.title)
                if let first = matched.first {
                    pastMeetings = [first]
                    let messages = try await chatMessageRepository.listForMeeting(meetingId: first.id)
                    if let suggestion = messages.first(where: { $0.role == "assistant" }) {
                        pastSummary = suggestion.content
                    }
                }
            }

            if !pastMeetings.isEmpty {
                await generateRAGSummary()
            }
        } catch {
            logger.error("Failed to load briefing: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Failed to load briefing context"
        }
    }

    private func generateRAGSummary() async {
        guard !pastMeetings.isEmpty, let ragProvider else { return }

        ragContext = await ragProvider.ragContext(
            for: event,
            meetingRepository: meetingRepository
        )
    }

    private func titleSimilarity(_ a: String, _ b: String) -> Double {
        let lowerA = a.lowercased()
        let lowerB = b.lowercased()

        if lowerA == lowerB { return 1.0 }

        let wordsA = Set(lowerA.split(separator: " ").map(String.init))
        let wordsB = Set(lowerB.split(separator: " ").map(String.init))

        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0.0 }

        let intersection = wordsA.intersection(wordsB)
        let union = wordsA.union(wordsB)
        return Double(intersection.count) / Double(union.count)
    }

    var hasContext: Bool {
        !pastMeetings.isEmpty || !linkedDocuments.isEmpty
    }

    var formattedAttendees: String {
        let names = event.attendees.compactMap { $0.displayName ?? $0.email }
        if names.isEmpty { return "No attendees" }
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.prefix(3).joined(separator: ", ")) +\(names.count - 3) more"
    }
}

protocol MeetingBriefingRAGProviding: Sendable {
    func ragContext(
        for event: UnifiedCalendarEvent,
        meetingRepository: any MeetingRepositoryProtocol
    ) async -> String
}

struct DefaultMeetingBriefingRAGProvider: MeetingBriefingRAGProviding {
    private let embeddingEngine: any EmbeddingProviding
    private let vectorSearch: any VectorSearching

    init(
        embeddingEngine: any EmbeddingProviding,
        vectorSearch: any VectorSearching
    ) {
        self.embeddingEngine = embeddingEngine
        self.vectorSearch = vectorSearch
    }

    func ragContext(
        for event: UnifiedCalendarEvent,
        meetingRepository: any MeetingRepositoryProtocol
    ) async -> String {
        do {
            let queryText = "What do I need to know about \(event.title)?"
            let embedding = try await embeddingEngine.embed(text: queryText, mode: .query)
            let results = try await vectorSearch.search(query: embedding, limit: 3)

            var contextLines: [String] = []
            for result in results {
                if let segment = try? await meetingRepository.getSegment(id: result.id) {
                    contextLines.append("[\(segment.speaker)] \(segment.text)")
                }
            }

            if contextLines.isEmpty {
                return "No additional context found in knowledge base."
            }

            return contextLines.joined(separator: "\n")
        } catch {
            logger.warning("RAG summary failed: \(error.localizedDescription, privacy: .public)")
            return "Context search unavailable."
        }
    }
}
