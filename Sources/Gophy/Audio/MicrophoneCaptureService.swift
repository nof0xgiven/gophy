import AVFoundation
import CoreAudio
import AudioToolbox
import Foundation
import os.log

private let audioLogger = Logger(subsystem: "com.gophy.app", category: "MicrophoneCapture")

/// Protocol for audio capture to enable testability
protocol AudioCaptureProtocol: Actor {
    func start() async throws -> AsyncStream<AudioChunk>
    func stop() async
    func setInputDevice(deviceID: String) async throws
}

/// Public protocol for microphone capture to enable DI in MeetingSessionController
public protocol MicrophoneCaptureProtocol: Sendable {
    func start() async throws -> AsyncStream<AudioChunk>
    func stop() async
    func setPreferredInputDevice(uid: String?) async
}

/// Microphone capture service using AVAudioEngine
public actor MicrophoneCaptureService: AudioCaptureProtocol, MicrophoneCaptureProtocol {
    private let audioEngine = AVAudioEngine()
    private let audioDeviceManager: AudioDeviceManager
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var audioConverter: AVAudioConverter?
    private var buffer: [Float] = []
    private let targetSampleRate: Double = 16000.0
    private let chunkSize = 16000 // 1 second at 16kHz
    private var preferredInputDeviceUID: String?
    private var activeRouting: MicrophoneCaptureRouting?
    private var deviceListenerTask: Task<Void, Never>?

    public init() {
        self.audioDeviceManager = AudioDeviceManager()
    }

    init(audioDeviceManager: AudioDeviceManager) {
        self.audioDeviceManager = audioDeviceManager
    }

    /// Start capturing audio from the microphone
    public func start() async throws -> AsyncStream<AudioChunk> {
        audioLogger.info("Starting microphone capture...")

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        setContinuation(continuation)

        do {
            try await ensureMicrophonePermission()
            try await configureInputRouting()
            try await setupAudioEngine()
            try await startEngine()
            startDeviceListener()
            audioLogger.info("Microphone capture started successfully")
            return stream
        } catch {
            audioLogger.error("Failed to start microphone capture: \(error.localizedDescription, privacy: .public)")
            cleanupAfterFailedStart()
            throw error
        }
    }

    private func setContinuation(_ continuation: AsyncStream<AudioChunk>.Continuation) {
        self.continuation = continuation
    }

    /// Stop capturing audio
    public func stop() async {
        deviceListenerTask?.cancel()
        deviceListenerTask = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
        buffer.removeAll()
        audioConverter = nil
        activeRouting = nil
    }

    public func setPreferredInputDevice(uid: String?) async {
        preferredInputDeviceUID = uid
    }

    private func ensureMicrophonePermission() async throws {
        #if os(macOS)
        audioLogger.info("Requesting microphone permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        audioLogger.info("Microphone permission granted: \(granted, privacy: .public)")
        guard granted else {
            audioLogger.error("Microphone permission denied")
            throw AudioCaptureError.permissionDenied
        }
        #endif
    }

    /// Set input device by device ID
    func setInputDevice(deviceID: String) async throws {
        #if os(macOS)
        guard let audioDeviceID = UInt32(deviceID) else {
            throw AudioCaptureError.deviceNotFound
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioCaptureError.deviceNotFound
        }
        var mutableDeviceID = audioDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioCaptureError.deviceSelectionFailed(status)
        }
        #endif
    }

    private func configureInputRouting() async throws {
        let devices = try audioDeviceManager.listInputDevices()
        let defaultDevice = try audioDeviceManager.defaultInputDevice()
        let routing = MicrophoneCaptureRouting.resolve(
            preferredInputDeviceUID: preferredInputDeviceUID,
            availableDevices: devices,
            defaultDevice: defaultDevice
        )
        activeRouting = routing
        try await setInputDevice(deviceID: String(routing.activeDevice.id))
    }

    private func startDeviceListener() {
        deviceListenerTask?.cancel()
        deviceListenerTask = Task { [weak self] in
            guard let self else { return }
            for await devices in audioDeviceManager.deviceChangeStream {
                await self.handleAvailableDevicesChanged(devices)
            }
        }
    }

    private func handleAvailableDevicesChanged(_ devices: [AudioDevice]) async {
        guard let activeRouting else { return }

        let defaultDevice = try? audioDeviceManager.defaultInputDevice()
        guard let rerouted = activeRouting.reroutingAfterDeviceChange(
            availableDevices: devices,
            defaultDevice: defaultDevice ?? nil
        ) else {
            return
        }

        do {
            try await setInputDevice(deviceID: String(rerouted.activeDevice.id))
            self.activeRouting = rerouted
            audioLogger.info("Fell back microphone input to \(rerouted.activeDevice.name, privacy: .public)")
        } catch {
            audioLogger.error("Failed to reroute microphone input: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private Methods

    private func setupAudioEngine() async throws {
        audioLogger.info("Setting up audio engine...")

        let inputNode = audioEngine.inputNode
        let nodeFormat = inputNode.outputFormat(forBus: 0)
        guard let captureFormat = MicrophoneCaptureFormatSelection.resolve(
            activeDevice: activeRouting?.activeDevice,
            nodeSampleRate: nodeFormat.sampleRate,
            nodeChannelCount: nodeFormat.channelCount
        ), let inputFormat = captureFormat.makeAVAudioFormat() else {
            throw AudioCaptureError.formatCreationFailed
        }
        audioLogger.info("Input format: \(inputFormat.sampleRate, privacy: .public) Hz, \(inputFormat.channelCount, privacy: .public) channels")

        // Create target format: 16kHz, mono, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        // Create converter if formats differ
        // The tap extracts channel 0, so input to converter is always mono
        if inputFormat.sampleRate != targetFormat.sampleRate ||
           inputFormat.channelCount != targetFormat.channelCount {
            guard let monoInputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw AudioCaptureError.formatCreationFailed
            }
            guard let converter = AVAudioConverter(from: monoInputFormat, to: targetFormat) else {
                throw AudioCaptureError.converterCreationFailed
            }
            audioConverter = converter
        }

        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Copy buffer data to make it safe for actor isolation
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let bufferSampleRate = buffer.format.sampleRate
            let bufferChannelCount = buffer.format.channelCount
            let sampleTime = time.sampleTime
            let isSampleTimeValid = time.isSampleTimeValid

            Task {
                await self.processAudioSamples(
                    samples: samples,
                    sampleRate: bufferSampleRate,
                    channelCount: bufferChannelCount,
                    sampleTime: sampleTime,
                    isSampleTimeValid: isSampleTimeValid
                )
            }
        }
    }

    private func startEngine() async throws {
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func cleanupAfterFailedStart() {
        deviceListenerTask?.cancel()
        deviceListenerTask = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
        buffer.removeAll()
        audioConverter = nil
        activeRouting = nil
    }

    private func processAudioSamples(
        samples: [Float],
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        sampleTime: AVAudioFramePosition,
        isSampleTimeValid: Bool
    ) {
        guard let continuation = continuation else { return }

        var processedSamples: [Float]

        if let converter = audioConverter {
            // Use AVAudioConverter for proper anti-aliased resampling
            let frameCount = AVAudioFrameCount(samples.count)
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.inputFormat,
                frameCapacity: frameCount
            ) else { return }
            inputBuffer.frameLength = frameCount

            // Copy samples into input buffer
            if let channelData = inputBuffer.floatChannelData {
                samples.withUnsafeBufferPointer { src in
                    guard let base = src.baseAddress else { return }
                    channelData[0].update(from: base, count: samples.count)
                }
            }

            // Calculate output frame count based on sample rate ratio
            let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            var inputConsumed = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard status != .error, error == nil else {
                audioLogger.error("AVAudioConverter failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                return
            }

            let count = Int(outputBuffer.frameLength)
            if let outData = outputBuffer.floatChannelData {
                processedSamples = Array(UnsafeBufferPointer(start: outData[0], count: count))
            } else {
                return
            }
        } else {
            // Formats already match, pass through directly
            processedSamples = samples
        }

        // Add to buffer
        self.buffer.append(contentsOf: processedSamples)

        // Emit chunks when buffer reaches target size
        while self.buffer.count >= chunkSize {
            let chunkSamples = Array(self.buffer.prefix(chunkSize))
            self.buffer.removeFirst(chunkSize)

            let timestamp = isSampleTimeValid
                ? Double(sampleTime) / sampleRate
                : ProcessInfo.processInfo.systemUptime

            let chunk = AudioChunk(
                samples: chunkSamples,
                timestamp: timestamp,
                source: .microphone
            )

            audioLogger.info("Emitting audio chunk: \(chunkSamples.count, privacy: .public) samples")
            continuation.yield(chunk)
        }
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case deviceNotFound
    case deviceSelectionFailed(OSStatus)
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .deviceNotFound:
            return "Audio device not found"
        case .deviceSelectionFailed(let status):
            return "Failed to select microphone device (OSStatus: \(status))"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        }
    }
}

struct MicrophoneCaptureFormatSelection: Equatable {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount

    static func resolve(
        activeDevice: AudioDevice?,
        nodeSampleRate: Double,
        nodeChannelCount: AVAudioChannelCount
    ) -> MicrophoneCaptureFormatSelection? {
        if let activeDevice,
           activeDevice.sampleRate > 0,
           activeDevice.inputChannelCount > 0 {
            return MicrophoneCaptureFormatSelection(
                sampleRate: activeDevice.sampleRate,
                channelCount: AVAudioChannelCount(activeDevice.inputChannelCount)
            )
        }

        guard nodeSampleRate > 0, nodeChannelCount > 0 else {
            return nil
        }

        return MicrophoneCaptureFormatSelection(
            sampleRate: nodeSampleRate,
            channelCount: nodeChannelCount
        )
    }

    func makeAVAudioFormat() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )
    }
}
