import Foundation
import SwiftUI

@MainActor
@Observable
public final class CompactOverlayViewModel {
    var status: MeetingStatus = .idle
    var meetingTitle: String = ""
    var duration: TimeInterval = 0
    var recentSegments: [TranscriptSegmentRecord] = []
    var latestSuggestion: String = ""

    private var subscriberTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var maxSegments = 3

    func start() {
        guard subscriberTask == nil else { return }

        refreshFromTracker()
        startRefreshTimer()

        subscriberTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await MeetingEventBroadcaster.shared.subscribe()
            for await event in stream {
                self.handleEvent(event)
            }
        }
    }

    func stop() {
        subscriberTask?.cancel()
        subscriberTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    var isActive: Bool {
        status == .active || status == .paused
    }

    var formattedDuration: String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var statusText: String {
        switch status {
        case .idle, .completed: return "Idle"
        case .starting: return "Starting..."
        case .active: return "Recording"
        case .paused: return "Paused"
        case .stopping: return "Stopping..."
        }
    }

    var statusColor: Color {
        switch status {
        case .idle, .completed: return .gray
        case .starting, .stopping: return .yellow
        case .active: return .red
        case .paused: return .orange
        }
    }

    private func handleEvent(_ event: MeetingEvent) {
        switch event {
        case .transcriptSegment(let segment):
            let record = TranscriptSegmentRecord(
                id: UUID().uuidString,
                meetingId: "",
                text: segment.text,
                speaker: segment.speaker,
                startTime: segment.startTime,
                endTime: segment.endTime,
                createdAt: Date()
            )
            recentSegments.append(record)
            if recentSegments.count > maxSegments {
                recentSegments.removeFirst(recentSegments.count - maxSegments)
            }

        case .suggestion(let text):
            latestSuggestion = text

        case .statusChange(let newStatus):
            refreshFromTracker(statusOverride: newStatus)
            if newStatus == .idle || newStatus == .completed {
                recentSegments.removeAll()
                latestSuggestion = ""
            }

        case .automation, .playbackProgress, .error:
            break
        }
    }

    private func refreshFromTracker(statusOverride: MeetingStatus? = nil) {
        let tracker = MeetingStateTracker.shared
        status = statusOverride ?? tracker.status
        duration = tracker.duration
        meetingTitle = tracker.currentMeetingTitle
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromTracker()
            }
        }
    }
}
