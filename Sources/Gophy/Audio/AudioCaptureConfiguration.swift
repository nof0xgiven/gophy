import Foundation

public struct AudioCaptureConfiguration: Sendable, Equatable {
    public let preferredInputDeviceUID: String?
    public let systemAudioEnabled: Bool

    public init(
        preferredInputDeviceUID: String? = nil,
        systemAudioEnabled: Bool = true
    ) {
        self.preferredInputDeviceUID = preferredInputDeviceUID
        self.systemAudioEnabled = systemAudioEnabled
    }
}