import Foundation
import SwiftUI

@MainActor
@Observable
public final class MeetingViewModel {
    private let sessionController: MeetingSessionController
    private let suggestionEngine: SuggestionEngine
    private let chatMessageRepository: ChatMessageRepository

    public var title: String = "Untitled Meeting"
    public var status: MeetingStatus = .idle
    public var transcriptSegments: [TranscriptSegmentRecord] = []
    public var suggestions: [SuggestionDisplayItem] = []
    public var duration: TimeInterval = 0
    public var micLevel: Float = 0
    public var systemAudioLevel: Float = 0
    public var errorMessage: String?
    public var isGeneratingSuggestion = false
    public var markedMoments: [TimeInterval] = []
    public var suggestionsPaused: Bool = false
    public var quickAskText: String = ""
    public var quickAskResponse: String?
    public var quickAskLoading: Bool = false
    public var copyConfirmationToken: Int = 0
    public var autoStartOnAppear = false
    public var selectedLanguage: AppLanguage = {
        if let saved = UserDefaults.standard.string(forKey: "languagePreference"),
           let lang = AppLanguage(rawValue: saved) {
            return lang
        }
        return .auto
    }()

    private var eventTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var meetingStartTime: Date?

    public init(
        sessionController: MeetingSessionController,
        suggestionEngine: SuggestionEngine,
        chatMessageRepository: ChatMessageRepository
    ) {
        self.sessionController = sessionController
        self.suggestionEngine = suggestionEngine
        self.chatMessageRepository = chatMessageRepository

        startListeningToEvents()
    }

    public func startMeeting() async {
        do {
            meetingStartTime = Date()
            startDurationTimer()
            UserDefaults.standard.set(true, forKey: "isCurrentlyRecording")
            MeetingStateTracker.shared.setMeetingTitle(title)
            try await sessionController.start(
                title: title,
                audioConfiguration: currentAudioConfiguration()
            )
            MeetingStateTracker.shared.setMeetingId(sessionController.currentMeetingId)
            startAutoSuggestions()
        } catch {
            UserDefaults.standard.set(false, forKey: "isCurrentlyRecording")
            MeetingStateTracker.shared.setMeetingId(nil)
            errorMessage = error.localizedDescription
        }
    }

    public func stopMeeting() async {
        do {
            suggestionTask?.cancel()
            suggestionTask = nil
            try await sessionController.stop()
            stopDurationTimer()
            UserDefaults.standard.set(false, forKey: "isCurrentlyRecording")
            MeetingStateTracker.shared.setMeetingId(nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func pauseMeeting() async {
        await sessionController.pause()
        stopDurationTimer()
    }

    public func resumeMeeting() async {
        do {
            try await sessionController.resume(audioConfiguration: currentAudioConfiguration())
            startDurationTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateLanguage(_ language: AppLanguage) async {
        selectedLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "languagePreference")
        await sessionController.setTranscriptionLanguage(language)
    }

    // MARK: - Quick Actions

    public func copyLastSuggestion() {
        guard let last = suggestions.last else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(last.content, forType: .string)
        copyConfirmationToken += 1
    }

    public func markImportant() {
        markedMoments.append(duration)
    }

    public func toggleSuggestionsPaused() {
        suggestionsPaused.toggle()
    }

    public func dismissSuggestion(id: String) async {
        if let index = suggestions.firstIndex(where: { $0.id == id }) {
            suggestions[index].dismissed = true
        }

        do {
            try await chatMessageRepository.setDismissed(id: id, dismissed: true)
        } catch {
            errorMessage = "Failed to dismiss suggestion: \(error.localizedDescription)"
        }
    }

    public func setSuggestionFeedback(id: String, feedback: String) async {
        if let index = suggestions.firstIndex(where: { $0.id == id }) {
            suggestions[index].feedback = feedback
        }

        do {
            try await chatMessageRepository.setFeedback(id: id, feedback: feedback)
        } catch {
            errorMessage = "Failed to save suggestion feedback: \(error.localizedDescription)"
        }
    }

    public func submitQuickAsk() async {
        let question = quickAskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        quickAskLoading = true
        quickAskResponse = nil
        defer { quickAskLoading = false }

        guard getCurrentMeetingId() != nil else { return }

        do {
            let recentTranscript = transcriptSegments.suffix(15).map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")
            let prompt = "Question: \(question)\n\nRecent transcript:\n\(recentTranscript)\n\nAnswer:"

            let provider = await suggestionEngine.activeTextGenProviderForQuickAsk()
            var fullResponse = ""
            let stream = provider.generate(prompt: prompt, systemPrompt: "You are a meeting assistant. Answer the user's question concisely based on the recent transcript.", maxTokens: 200, temperature: 0.7)
            for try await token in stream {
                fullResponse += token
                quickAskResponse = fullResponse
            }
        } catch {
            quickAskResponse = "Error: \(error.localizedDescription)"
        }

        quickAskText = ""
    }

    public func refreshSuggestions() async {
        guard status == .active, let meetingId = getCurrentMeetingId() else {
            return
        }

        isGeneratingSuggestion = true
        defer { isGeneratingSuggestion = false }

        let streamItemId = UUID().uuidString
        let displayItem = SuggestionDisplayItem(
            id: streamItemId,
            content: "",
            isStreaming: true
        )
        suggestions.append(displayItem)

        var fullSuggestion = ""
        let stream = suggestionEngine.generateSuggestionStream(meetingId: meetingId)
        for await token in stream {
            fullSuggestion += token
            if let index = suggestions.firstIndex(where: { $0.id == streamItemId }) {
                suggestions[index].content = fullSuggestion
            }
        }

        let trimmedSuggestion = fullSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSuggestion.isEmpty else {
            suggestions.removeAll { $0.id == streamItemId }
            return
        }

        if let index = suggestions.firstIndex(where: { $0.id == streamItemId }) {
            suggestions[index].isStreaming = false
        }

        SuggestionNotificationService.shared.sendSuggestion(fullSuggestion, meetingTitle: title)
        await MeetingEventBroadcaster.shared.broadcast(.suggestion(fullSuggestion))
    }

    private func startListeningToEvents() {
        eventTask = Task { [weak self] in
            guard let self = self else { return }

            for await event in sessionController.eventStream {
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: MeetingEvent) async {
        switch event {
        case .transcriptSegment(let segment):
            let record = TranscriptSegmentRecord(
                id: UUID().uuidString,
                meetingId: getCurrentMeetingId() ?? "",
                text: segment.text,
                speaker: segment.speaker,
                startTime: segment.startTime,
                endTime: segment.endTime,
                createdAt: Date()
            )
            transcriptSegments.append(record)

        case .suggestion(let suggestionText):
            suggestions.append(SuggestionDisplayItem(
                content: suggestionText,
                isStreaming: false
            ))

        case .statusChange(let newStatus):
            status = newStatus

        case .playbackProgress:
            break

        case .automation:
            break

        case .error(let error):
            if let errorWrapper = error as? MeetingEvent.ErrorWrapper {
                errorMessage = errorWrapper.underlyingError
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func getCurrentMeetingId() -> String? {
        return sessionController.currentMeetingId
    }

    private func startAutoSuggestions() {
        guard let meetingId = getCurrentMeetingId() else { return }

        // Create a transcript stream that mirrors segments as they arrive
        let transcriptStream = AsyncStream<TranscriptSegment> { [weak self] continuation in
            let task = Task { [weak self] in
                // Watch for new segments by polling the array
                var lastCount = 0
                while !Task.isCancelled {
                    guard let self else {
                        continuation.finish()
                        return
                    }
                    let currentSegments = await MainActor.run { self.transcriptSegments }
                    if currentSegments.count > lastCount {
                        for segment in currentSegments[lastCount...] {
                            continuation.yield(TranscriptSegment(
                                text: segment.text,
                                startTime: segment.startTime,
                                endTime: segment.endTime,
                                speaker: segment.speaker
                            ))
                        }
                        lastCount = currentSegments.count
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5s
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        // Filter the transcript stream based on suggestionsPaused
        let pausedAwareStream = AsyncStream<TranscriptSegment> { [weak self] continuation in
            let task = Task { [weak self] in
                for await segment in transcriptStream {
                    guard let self else {
                        continuation.finish()
                        return
                    }
                    let paused = await MainActor.run { self.suggestionsPaused }
                    if !paused {
                        continuation.yield(segment)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        let suggestionEngine = suggestionEngine
        suggestionTask = Task { [weak self, suggestionEngine] in
            let stream = suggestionEngine.autoSuggestionStream(
                meetingId: meetingId,
                transcriptStream: pausedAwareStream
            )
            for await (suggestionId, token, isComplete) in stream {
                guard !token.isEmpty || isComplete else { continue }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let index = self.suggestions.firstIndex(where: { $0.id == suggestionId }) {
                        self.suggestions[index].content += token
                        if isComplete {
                                let finalText = self.suggestions[index].content
                                guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                    self.suggestions.remove(at: index)
                                    return
                                }
                                self.suggestions[index].isStreaming = false
                                SuggestionNotificationService.shared.sendSuggestion(finalText, meetingTitle: self.title)
                                Task { await MeetingEventBroadcaster.shared.broadcast(.suggestion(finalText)) }
                            }
                        } else {
                            guard !isComplete || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                return
                            }
                            let item = SuggestionDisplayItem(
                                id: suggestionId,
                                content: token,
                                isStreaming: !isComplete
                            )
                            self.suggestions.append(item)
                            if isComplete {
                                guard !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                    self.suggestions.removeAll { $0.id == suggestionId }
                                    return
                                }
                                SuggestionNotificationService.shared.sendSuggestion(item.content, meetingTitle: self.title)
                                Task { await MeetingEventBroadcaster.shared.broadcast(.suggestion(item.content)) }
                            }
                        }
                }
            }
        }
    }

    private func loadSuggestions(meetingId: String) async {
        do {
            let records = try await chatMessageRepository.listForMeeting(meetingId: meetingId)
            suggestions = records.map { SuggestionDisplayItem(from: $0) }
        } catch {
            errorMessage = "Failed to load suggestions: \(error.localizedDescription)"
        }
    }

    private func startDurationTimer() {
        let startTime = meetingStartTime
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = startTime else { return }
            Task { @MainActor in
                self.duration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func currentAudioConfiguration() -> AudioCaptureConfiguration {
        AudioCaptureConfiguration(
            preferredInputDeviceUID: UserDefaults.standard.string(forKey: "selectedAudioDeviceUID"),
            systemAudioEnabled: UserDefaults.standard.object(forKey: "systemAudioEnabled") as? Bool ?? true
        )
    }
}
