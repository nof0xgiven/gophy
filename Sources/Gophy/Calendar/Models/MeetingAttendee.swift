import Foundation

struct MeetingAttendee: Sendable, Equatable, Identifiable, Hashable {
    let email: String
    let displayName: String?
    let responseStatus: String?
    let isSelf: Bool

    var id: String { email }
}
