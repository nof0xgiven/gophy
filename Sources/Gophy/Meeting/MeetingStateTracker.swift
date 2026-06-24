import Foundation
import SwiftUI

@MainActor
@Observable
public final class MeetingStateTracker {
    public static let shared = MeetingStateTracker()

    public var status: MeetingStatus = .idle
    public var currentMeetingTitle: String = ""
    public var currentMeetingId: String?
    public var duration: TimeInterval = 0
    public var lastTranscriptText: String = ""
    public var lastTranscriptSpeaker: String = ""

    private var subscriberTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var meetingStartTime: Date?

    private init() {}

    public func startTracking() {
        guard subscriberTask == nil else { return }

        subscriberTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await MeetingEventBroadcaster.shared.subscribe()
            for await event in stream {
                self.handleEvent(event)
            }
        }
    }

    public func stopTracking() {
        subscriberTask?.cancel()
        subscriberTask = nil
        stopDurationTimer()
    }

    public func setMeetingTitle(_ title: String) {
        currentMeetingTitle = title
    }

    public func setMeetingId(_ id: String?) {
        currentMeetingId = id
    }

    private func handleEvent(_ event: MeetingEvent) {
        switch event {
        case .transcriptSegment(let segment):
            lastTranscriptText = segment.text
            lastTranscriptSpeaker = segment.speaker

        case .statusChange(let newStatus):
            status = newStatus
            switch newStatus {
            case .active:
                if meetingStartTime == nil {
                    meetingStartTime = Date()
                }
                startDurationTimer()
                if UserDefaults.standard.object(forKey: "autoShowOverlay") as? Bool ?? true {
                    CompactOverlayWindowController.shared.showOverlay()
                }
            case .completed, .idle:
                stopDurationTimer()
                meetingStartTime = nil
                duration = 0
            case .paused:
                stopDurationTimer()
            default:
                break
            }

        case .suggestion, .audioLevel, .playbackProgress, .automation, .error:
            break
        }
    }

    private func startDurationTimer() {
        guard durationTimer == nil else { return }
        if let start = meetingStartTime {
            duration = Date().timeIntervalSince(start)
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.meetingStartTime else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    public var formattedDuration: String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
