import Foundation

public enum MeetingStatus: String, Sendable, Codable {
    case idle
    case starting
    case active
    case paused
    case stopping
    case completed
}

public enum MeetingEvent: Sendable {
    case transcriptSegment(TranscriptSegment)
    case suggestion(String)
    case statusChange(MeetingStatus)
    case audioLevel(source: AudioSource, level: Float)
    case playbackProgress(currentTime: TimeInterval, duration: TimeInterval)
    case automation(AutomationEvent)
    case error(Error)
}

extension MeetingEvent {
    public struct ErrorWrapper: Error, Sendable {
        public let underlyingError: String

        public init(_ error: Error) {
            self.underlyingError = "\(error)"
        }
    }
}

// MARK: - MeetingEventBroadcaster

public actor MeetingEventBroadcaster {
    public static let shared = MeetingEventBroadcaster()

    private var subscribers: [UUID: AsyncStream<MeetingEvent>.Continuation] = [:]

    public init() {}

    public func broadcast(_ event: MeetingEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    public func subscribe() -> AsyncStream<MeetingEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: MeetingEvent.self)
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id: id) }
        }
        return stream
    }

    public func unsubscribe(id: UUID) {
        subscribers[id]?.finish()
        subscribers.removeValue(forKey: id)
    }
}
