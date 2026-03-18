import Foundation

struct SystemAudioRouteState: Sendable, Equatable {
    let outputDeviceUID: String
    let aggregateDeviceUID: String
    let isListeningForRouteChanges: Bool

    static func make(defaultOutputDeviceUID: String) -> SystemAudioRouteState {
        SystemAudioRouteState(
            outputDeviceUID: defaultOutputDeviceUID,
            aggregateDeviceUID: aggregateUID(for: defaultOutputDeviceUID),
            isListeningForRouteChanges: false
        )
    }

    func rebuilding(for newOutputDeviceUID: String) -> SystemAudioRouteState {
        SystemAudioRouteState(
            outputDeviceUID: newOutputDeviceUID,
            aggregateDeviceUID: Self.aggregateUID(for: newOutputDeviceUID),
            isListeningForRouteChanges: isListeningForRouteChanges
        )
    }

    func withListenerRegistration() -> SystemAudioRouteState {
        SystemAudioRouteState(
            outputDeviceUID: outputDeviceUID,
            aggregateDeviceUID: aggregateDeviceUID,
            isListeningForRouteChanges: true
        )
    }

    func stopping() -> SystemAudioRouteState {
        SystemAudioRouteState(
            outputDeviceUID: outputDeviceUID,
            aggregateDeviceUID: aggregateDeviceUID,
            isListeningForRouteChanges: false
        )
    }

    private static func aggregateUID(for outputDeviceUID: String) -> String {
        "com.gophy.system-audio-tap.\(outputDeviceUID).\(UUID().uuidString)"
    }
}