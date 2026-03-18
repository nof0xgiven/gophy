import Foundation

final class MeetingStarterBridge: MeetingStarterProtocol, @unchecked Sendable {
    private let navigationCoordinator: NavigationCoordinator

    @MainActor
    init(navigationCoordinator: NavigationCoordinator) {
        self.navigationCoordinator = navigationCoordinator
    }

    func startMeeting(title: String, calendarEventId: String?) async throws {
        await MainActor.run {
            navigationCoordinator.requestAutoStart(title: title, calendarEventId: calendarEventId)
        }
    }

    var isRecording: Bool {
        get async {
            UserDefaults.standard.bool(forKey: "isCurrentlyRecording")
        }
    }
}
