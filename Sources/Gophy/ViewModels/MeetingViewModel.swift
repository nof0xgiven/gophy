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
    public var suggestions: [ChatMessageRecord] = []
    public var duration: TimeInterval = 0
    public var micLevel: Float = 0
    public var systemAudioLevel: Float = 0
    public var errorMessage: String?
    public var isGeneratingSuggestion = false
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
            try await sessionController.start(
                title: title,
                audioConfiguration: currentAudioConfiguration()
            )
            startAutoSuggestions()
        } catch {
            UserDefaults.standard.set(false, forKey: "isCurrentlyRecording")
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

    public func refreshSuggestions() async {
        guard status == .active, let meetingId = getCurrentMeetingId() else {
            return
        }

        isGeneratingSuggestion = true
        defer { isGeneratingSuggestion = false }

        do {
            _ = try await suggestionEngine.generateSuggestion(meetingId: meetingId)
            await loadSuggestions(meetingId: meetingId)
        } catch {
            errorMessage = "Failed to generate suggestion: \(error.localizedDescription)"
        }
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
            if let meetingId = getCurrentMeetingId() {
                let message = ChatMessageRecord(
                    id: UUID().uuidString,
                    role: "assistant",
                    content: suggestionText,
                    meetingId: meetingId,
                    createdAt: Date()
                )
                suggestions.append(message)
            }

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
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                // Watch for new segments by polling the array
                var lastCount = 0
                while !Task.isCancelled {
                    let currentSegments = await self.transcriptSegments
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
        }

        suggestionTask = Task { [weak self] in
            guard let self = self else { return }
            for await suggestion in suggestionEngine.startAutoSuggestions(
                meetingId: meetingId,
                transcriptStream: transcriptStream
            ) {
                guard !suggestion.isEmpty else { continue }
                let message = ChatMessageRecord(
                    id: UUID().uuidString,
                    role: "assistant",
                    content: suggestion,
                    meetingId: meetingId,
                    createdAt: Date()
                )
                await MainActor.run {
                    self.suggestions.append(message)
                    SuggestionNotificationService.shared.sendSuggestion(suggestion, meetingTitle: self.title)
                }
            }
        }
    }

    private func loadSuggestions(meetingId: String) async {
        do {
            suggestions = try await chatMessageRepository.listForMeeting(meetingId: meetingId)
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
