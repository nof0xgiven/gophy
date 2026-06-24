import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "MeetingSession")

// MARK: - Protocols for Dependencies

public protocol ModeControllerProtocol: Sendable {
    func switchMode(_ mode: Mode) async throws
}

extension ModeController: ModeControllerProtocol {}

public protocol TranscriptionPipelineProtocol: Sendable {
    nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment>
    func stop() async
    func setLanguageHint(_ hint: String?) async
}

extension TranscriptionPipeline: TranscriptionPipelineProtocol {}

public protocol MeetingRepositoryProtocol: Sendable {
    func create(_ meeting: MeetingRecord) async throws
    func update(_ meeting: MeetingRecord) async throws
    func get(id: String) async throws -> MeetingRecord?
    func listAll(limit: Int?, offset: Int) async throws -> [MeetingRecord]
    func delete(id: String) async throws
    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws
    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord]
    func getSegment(id: String) async throws -> TranscriptSegmentRecord?
    func search(query: String) async throws -> [MeetingRecord]
    func findOrphaned() async throws -> [MeetingRecord]
    func getSpeakerLabels(meetingId: String) async throws -> [SpeakerLabelRecord]
    func upsertSpeakerLabel(_ label: SpeakerLabelRecord) async throws
}

extension MeetingRepository: MeetingRepositoryProtocol {}

public protocol EmbeddingPipelineProtocol: Sendable {
    func indexMeeting(meetingId: String) async throws
    func indexDocument(documentId: String) async throws
    func indexTranscriptSegment(segment: TranscriptSegmentRecord) async throws
    func indexDocumentChunk(chunk: DocumentChunkRecord) async throws
}

extension EmbeddingPipeline: EmbeddingPipelineProtocol {}

public protocol AudioMixerProtocol: Sendable {
    func start() -> AsyncStream<LabeledAudioChunk>
}

extension AudioMixer: AudioMixerProtocol {}

// MARK: - MeetingSessionController

public protocol MeetingSummaryWritebackProtocol: Sendable {
    func writeBack(
        meetingId: String,
        calendarEventId: String?,
        calendarId: String?,
        existingDescription: String?
    ) async throws
}

extension MeetingSummaryWritebackService: MeetingSummaryWritebackProtocol {}

public actor MeetingSessionController {
    private let modeController: any ModeControllerProtocol
    private let transcriptionPipeline: any TranscriptionPipelineProtocol
    private let meetingRepository: any MeetingRepositoryProtocol
    private let embeddingPipeline: any EmbeddingPipelineProtocol
    private let microphoneCapture: any MicrophoneCaptureProtocol
    private let systemAudioCapture: any SystemAudioCaptureProtocol
    private let writebackService: (any MeetingSummaryWritebackProtocol)?
    private let automationManager: (any AutomationManaging)?

    public nonisolated(unsafe) var currentMeetingId: String?
    private var currentCalendarEventId: String?
    private var currentStatus: MeetingStatus = .idle
    private var eventContinuation: AsyncStream<MeetingEvent>.Continuation?
    private var transcriptionTask: Task<Void, Never>?
    private var automationTask: Task<Void, Never>?
    private var currentAudioConfiguration = AudioCaptureConfiguration()

    public nonisolated let eventStream: AsyncStream<MeetingEvent>

    private func setEventContinuation(_ continuation: AsyncStream<MeetingEvent>.Continuation) {
        self.eventContinuation = continuation
    }

    public init(
        modeController: any ModeControllerProtocol,
        transcriptionPipeline: any TranscriptionPipelineProtocol,
        meetingRepository: any MeetingRepositoryProtocol,
        embeddingPipeline: any EmbeddingPipelineProtocol,
        microphoneCapture: any MicrophoneCaptureProtocol,
        systemAudioCapture: any SystemAudioCaptureProtocol,
        writebackService: (any MeetingSummaryWritebackProtocol)? = nil,
        automationManager: (any AutomationManaging)? = nil
    ) {
        self.modeController = modeController
        self.transcriptionPipeline = transcriptionPipeline
        self.meetingRepository = meetingRepository
        self.embeddingPipeline = embeddingPipeline
        self.microphoneCapture = microphoneCapture
        self.systemAudioCapture = systemAudioCapture
        self.writebackService = writebackService
        self.automationManager = automationManager

        var continuation: AsyncStream<MeetingEvent>.Continuation?
        self.eventStream = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    public func recoverOrphanedMeetings() async throws -> [MeetingRecord] {
        let orphanedMeetings = try await meetingRepository.findOrphaned()
        let currentTime = Date()

        for meeting in orphanedMeetings {
            let updatedMeeting = MeetingRecord(
                id: meeting.id,
                title: meeting.title,
                startedAt: meeting.startedAt,
                endedAt: currentTime,
                mode: meeting.mode,
                status: "interrupted",
                createdAt: meeting.createdAt
            )
            try await meetingRepository.update(updatedMeeting)
        }

        return orphanedMeetings
    }

    public func start(
        title: String,
        calendarEventId: String? = nil,
        audioConfiguration: AudioCaptureConfiguration = .init()
    ) async throws {
        logger.info("Starting meeting: \(title, privacy: .public)")

        guard currentStatus == .idle || currentStatus == .completed else {
            logger.error("Session already active")
            throw MeetingSessionError.sessionAlreadyActive
        }

        currentAudioConfiguration = audioConfiguration

        updateStatus(.starting)
        logger.info("Status: starting")

        do {
            logger.info("Switching to meeting mode...")
            try await modeController.switchMode(.meeting)
            logger.info("Meeting mode active")

            let mixedStream = try await makeMixedAudioStream(using: audioConfiguration)

            let meetingId = UUID().uuidString
            let meeting = MeetingRecord(
                id: meetingId,
                title: title,
                startedAt: Date(),
                endedAt: nil,
                mode: "meeting",
                status: "active",
                createdAt: Date(),
                calendarEventId: calendarEventId
            )
            logger.info("Creating meeting record...")
            try await meetingRepository.create(meeting)
            currentMeetingId = meetingId
            currentCalendarEventId = calendarEventId
            logger.info("Meeting record created: \(meetingId, privacy: .public)")

            if let savedLanguage = UserDefaults.standard.string(forKey: "languagePreference"),
               let language = AppLanguage(rawValue: savedLanguage) {
                await transcriptionPipeline.setLanguageHint(language.isoCode)
            } else {
                await transcriptionPipeline.setLanguageHint(nil)
            }

            logger.info("Starting transcription pipeline...")
            let transcriptStream = transcriptionPipeline.start(mixedStream: mixedStream)
            logger.info("Transcription pipeline started")

            let (automationTranscriptStream, automationTranscriptContinuation) =
                AsyncStream<TranscriptSegment>.makeStream()

            transcriptionTask = Task {
                for await segment in transcriptStream {
                    await handleTranscriptSegment(segment, meetingId: meetingId)
                    automationTranscriptContinuation.yield(segment)
                }
                automationTranscriptContinuation.finish()
            }

            if let automationManager {
                let automationEvents = await automationManager.activateForMeeting(
                    meetingId: meetingId,
                    transcriptStream: automationTranscriptStream
                )
                automationTask = Task {
                    for await event in automationEvents {
                        eventContinuation?.yield(.automation(event))
                        await MeetingEventBroadcaster.shared.broadcast(.automation(event))
                    }
                }
            }

            updateStatus(.active)
            logger.info("Meeting started successfully!")
        } catch {
            logger.error("Failed to start meeting: \(error.localizedDescription, privacy: .public)")
            await microphoneCapture.stop()
            await systemAudioCapture.stop()
            await transcriptionPipeline.stop()
            transcriptionTask?.cancel()
            transcriptionTask = nil
            currentMeetingId = nil
            currentCalendarEventId = nil
            currentAudioConfiguration = AudioCaptureConfiguration()
            updateStatus(.idle)
            throw error
        }
    }

    public func stop() async throws {
        guard let meetingId = currentMeetingId else {
            throw MeetingSessionError.noActiveSession
        }

        updateStatus(.stopping)

        automationTask?.cancel()
        automationTask = nil
        await automationManager?.deactivate()

        await microphoneCapture.stop()
        await systemAudioCapture.stop()

        await transcriptionPipeline.stop()

        transcriptionTask?.cancel()
        transcriptionTask = nil

        guard let meeting = try await meetingRepository.get(id: meetingId) else {
            throw MeetingSessionError.meetingNotFound
        }

        let updatedMeeting = MeetingRecord(
            id: meeting.id,
            title: meeting.title,
            startedAt: meeting.startedAt,
            endedAt: Date(),
            mode: meeting.mode,
            status: "completed",
            createdAt: meeting.createdAt
        )
        try await meetingRepository.update(updatedMeeting)

        do {
            try await embeddingPipeline.indexMeeting(meetingId: meetingId)
            logger.info("Meeting indexed for vector search")
        } catch {
            logger.warning("Skipping vector indexing: \(error.localizedDescription, privacy: .public)")
        }

        if UserDefaults.standard.bool(forKey: "calendarWritebackEnabled"),
           let calendarEventId = currentCalendarEventId {
            do {
                try await writebackService?.writeBack(
                    meetingId: meetingId,
                    calendarEventId: calendarEventId,
                    calendarId: nil,
                    existingDescription: nil
                )
                logger.info("Summary written back to calendar")
            } catch {
                logger.warning("Skipping summary writeback: \(error.localizedDescription, privacy: .public)")
            }
        }

        currentMeetingId = nil
        currentCalendarEventId = nil
        currentAudioConfiguration = AudioCaptureConfiguration()
        updateStatus(.completed)
        logger.info("Meeting stopped successfully")
    }

    public func pause() async {
        guard currentStatus == .active else {
            return
        }

        updateStatus(.paused)

        await microphoneCapture.stop()
        await systemAudioCapture.stop()
    }

    public func setTranscriptionLanguage(_ language: AppLanguage) async {
        await transcriptionPipeline.setLanguageHint(language.isoCode)
        logger.info("Transcription language changed to: \(language.displayName, privacy: .public)")
    }

    public func resume(audioConfiguration: AudioCaptureConfiguration? = nil) async throws {
        guard currentStatus == .paused else {
            throw MeetingSessionError.sessionNotPaused
        }

        guard let meetingId = currentMeetingId else {
            throw MeetingSessionError.noActiveSession
        }

        let configuration = audioConfiguration ?? currentAudioConfiguration
        currentAudioConfiguration = configuration
        let mixedStream = try await makeMixedAudioStream(using: configuration)
        let transcriptStream = transcriptionPipeline.start(mixedStream: mixedStream)

        transcriptionTask = Task {
            for await segment in transcriptStream {
                await handleTranscriptSegment(segment, meetingId: meetingId)
            }
        }

        updateStatus(.active)
    }

    private func makeMixedAudioStream(using configuration: AudioCaptureConfiguration) async throws -> AsyncStream<LabeledAudioChunk> {
        logger.info("Starting microphone capture...")
        await microphoneCapture.setPreferredInputDevice(uid: configuration.preferredInputDeviceUID)
        let micStream = try await microphoneCapture.start()
        logger.info("Microphone capture started")

        let systemStream: AsyncStream<AudioChunk>
        if configuration.systemAudioEnabled {
            logger.info("Starting system audio capture...")
            systemStream = systemAudioCapture.start()
            logger.info("System audio capture started")
        } else {
            logger.info("System audio capture disabled by configuration")
            systemStream = AsyncStream { continuation in
                continuation.finish()
            }
        }

        logger.info("Creating audio mixer...")
        let audioMixer = AudioMixer(
            microphoneStream: micStream,
            systemAudioStream: systemStream
        )
        let mixedStream = audioMixer.start()
        logger.info("Audio mixer started")
        return streamReportingAudioLevels(from: mixedStream)
    }

    private func streamReportingAudioLevels(from mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<LabeledAudioChunk> {
        AsyncStream { continuation in
            Task {
                for await chunk in mixedStream {
                    await reportAudioLevel(for: chunk)
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    private func reportAudioLevel(for chunk: LabeledAudioChunk) async {
        let source: AudioSource = chunk.speaker == "You" ? .microphone : .systemAudio
        let level = normalizedAudioLevel(samples: chunk.samples)
        eventContinuation?.yield(.audioLevel(source: source, level: level))
        await MeetingEventBroadcaster.shared.broadcast(.audioLevel(source: source, level: level))
    }

    private nonisolated func normalizedAudioLevel(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + ($1 * $1) }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        return min(1, rms * 8)
    }

    private func handleTranscriptSegment(_ segment: TranscriptSegment, meetingId: String) async {
        eventContinuation?.yield(.transcriptSegment(segment))
        await MeetingEventBroadcaster.shared.broadcast(.transcriptSegment(segment))

        let segmentRecord = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: segment.text,
            speaker: segment.speaker,
            startTime: segment.startTime,
            endTime: segment.endTime,
            createdAt: Date(),
            detectedLanguage: segment.detectedLanguage?.rawValue
        )

        do {
            try await meetingRepository.addTranscriptSegment(segmentRecord)
        } catch {
            eventContinuation?.yield(.error(MeetingEvent.ErrorWrapper(error)))
            await MeetingEventBroadcaster.shared.broadcast(.error(MeetingEvent.ErrorWrapper(error)))
        }
    }

    private func updateStatus(_ status: MeetingStatus) {
        currentStatus = status
        eventContinuation?.yield(.statusChange(status))
        Task { await MeetingEventBroadcaster.shared.broadcast(.statusChange(status)) }
    }
}

// MARK: - Errors

public enum MeetingSessionError: Error, LocalizedError, Sendable {
    case sessionAlreadyActive
    case noActiveSession
    case sessionNotPaused
    case meetingNotFound

    public var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "A meeting session is already active"
        case .noActiveSession:
            return "No active meeting session"
        case .sessionNotPaused:
            return "Meeting session is not paused"
        case .meetingNotFound:
            return "Meeting record not found"
        }
    }
}
