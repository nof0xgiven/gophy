import Foundation

struct MicrophoneCaptureRouting: Sendable, Equatable {
    let preferredInputDeviceUID: String?
    let activeDevice: AudioDevice
    let usingFallback: Bool

    static func resolve(
        preferredInputDeviceUID: String?,
        availableDevices: [AudioDevice],
        defaultDevice: AudioDevice?
    ) -> MicrophoneCaptureRouting {
        if let preferredInputDeviceUID,
           let preferredDevice = availableDevices.first(where: { $0.uid == preferredInputDeviceUID }) {
            return MicrophoneCaptureRouting(
                preferredInputDeviceUID: preferredInputDeviceUID,
                activeDevice: preferredDevice,
                usingFallback: false
            )
        }

        if let defaultDevice {
            return MicrophoneCaptureRouting(
                preferredInputDeviceUID: preferredInputDeviceUID,
                activeDevice: defaultDevice,
                usingFallback: preferredInputDeviceUID != nil && preferredInputDeviceUID != defaultDevice.uid
            )
        }

        guard let firstAvailableDevice = availableDevices.first else {
            fatalError("Microphone routing requires at least one available input device or a default device")
        }

        return MicrophoneCaptureRouting(
            preferredInputDeviceUID: preferredInputDeviceUID,
            activeDevice: firstAvailableDevice,
            usingFallback: preferredInputDeviceUID != nil && preferredInputDeviceUID != firstAvailableDevice.uid
        )
    }

    func reroutingAfterDeviceChange(
        availableDevices: [AudioDevice],
        defaultDevice: AudioDevice?
    ) -> MicrophoneCaptureRouting? {
        guard !availableDevices.contains(activeDevice) else {
            return nil
        }

        return Self.resolve(
            preferredInputDeviceUID: preferredInputDeviceUID,
            availableDevices: availableDevices,
            defaultDevice: defaultDevice
        )
    }
}