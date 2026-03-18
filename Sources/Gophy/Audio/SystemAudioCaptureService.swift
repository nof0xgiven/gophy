import Foundation
import CoreAudio
import AVFoundation

/// Protocol for system audio capture to enable testing
public protocol SystemAudioCaptureProtocol: Sendable {
    /// Start capturing system audio
    /// - Returns: AsyncStream of AudioChunk instances (16kHz mono float32)
    nonisolated func start() -> AsyncStream<AudioChunk>

    /// Stop capturing system audio and clean up resources
    func stop() async
}

/// System audio capture service using CoreAudio ProcessTap (macOS 14.4+)
///
/// Captures system audio output without Screen Recording permission using the
/// ProcessTap API introduced in macOS 14.4. Creates an aggregate audio device
/// with a tap on system audio, converts to 16kHz mono float32, and emits via
/// AsyncStream.
///
/// Reference: AudioCap (github.com/insidegui/AudioCap)
@available(macOS 14.4, *)
public actor SystemAudioCaptureService: SystemAudioCaptureProtocol {
    
    private var tapID: AudioDeviceID?
    private var aggregateDeviceID: AudioDeviceID?
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var startTime: TimeInterval = 0
    private var audioConverter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var routeState: SystemAudioRouteState?
    private var routeListenerRegistered = false

    private let targetSampleRate: Double = 16000
    private let targetChannelCount: UInt32 = 1
    
    public init() {}

    nonisolated public func start() -> AsyncStream<AudioChunk> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                await self.setupCapture(continuation: continuation)
            }
        }
    }
    
    public func stop() async {
        guard isRunning else { return }

        isRunning = false
        unregisterDefaultOutputListener()
        routeState = routeState?.stopping()

        // Remove IO proc
        if let ioProcID = ioProcID, let aggregateDeviceID = aggregateDeviceID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        
        // Destroy aggregate device
        if let aggregateDeviceID = aggregateDeviceID {
            destroyAggregateDevice(aggregateDeviceID)
            self.aggregateDeviceID = nil
        }
        
        // Destroy process tap
        if let tapID = tapID {
            destroyProcessTap(tapID)
            self.tapID = nil
        }
        
        audioConverter = nil
        sourceFormat = nil
        continuation?.finish()
        continuation = nil
    }
    
    // MARK: - Private Setup
    
    private func setupCapture(continuation: AsyncStream<AudioChunk>.Continuation) async {
        self.continuation = continuation
        self.isRunning = true
        self.startTime = CACurrentMediaTime()

        do {
            try rebuildCaptureGraphForCurrentDefaultOutput(initialStart: true)
        } catch {
            continuation.finish()
            isRunning = false
        }
    }

    private func rebuildCaptureGraphForCurrentDefaultOutput(initialStart: Bool) throws {
        let outputDeviceUID = try currentDefaultSystemOutputUID()
        routeState = if let existingRouteState = routeState {
            existingRouteState.rebuilding(for: outputDeviceUID)
        } else {
            SystemAudioRouteState.make(defaultOutputDeviceUID: outputDeviceUID)
        }

        if !initialStart {
            tearDownCaptureGraph()
        }

        let tap = try createProcessTap()
        self.tapID = tap

        let aggregateDevice = try createAggregateDevice(with: tap, outputDeviceUID: outputDeviceUID)
        self.aggregateDeviceID = aggregateDevice

        var nominalSampleRate: Float64 = 48000.0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(aggregateDevice, &srAddress, 0, nil, &srSize, &nominalSampleRate)

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nominalSampleRate,
            channels: 2,
            interleaved: true
        ) else {
            throw SystemAudioCaptureError.formatCreationFailed
        }
        self.sourceFormat = inputFormat

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw SystemAudioCaptureError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SystemAudioCaptureError.converterCreationFailed
        }
        self.audioConverter = converter

        try setupIOProc(for: aggregateDevice)
        try startDevice(aggregateDevice)
        registerDefaultOutputListenerIfNeeded()
    }

    private func tearDownCaptureGraph() {
        if let ioProcID = ioProcID, let aggregateDeviceID = aggregateDeviceID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if let aggregateDeviceID = aggregateDeviceID {
            destroyAggregateDevice(aggregateDeviceID)
            self.aggregateDeviceID = nil
        }

        if let tapID = tapID {
            destroyProcessTap(tapID)
            self.tapID = nil
        }
    }

    private func currentDefaultSystemOutputUID() throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            throw SystemAudioCaptureError.defaultOutputLookupFailed(status)
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidDataSize = UInt32(MemoryLayout<CFString>.size)
        var uidRef: Unmanaged<CFString>?
        let uidStatus = withUnsafeMutablePointer(to: &uidRef) { ptr in
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidDataSize, ptr)
        }

        guard uidStatus == noErr, let uid = uidRef?.takeUnretainedValue() as String? else {
            throw SystemAudioCaptureError.defaultOutputLookupFailed(uidStatus)
        }

        return uid
    }

    private func registerDefaultOutputListenerIfNeeded() {
        guard !routeListenerRegistered else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultSystemOutputListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )

        guard status == noErr else { return }
        routeListenerRegistered = true
        routeState = routeState?.withListenerRegistration()
    }

    private func unregisterDefaultOutputListener() {
        guard routeListenerRegistered else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultSystemOutputListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
        routeListenerRegistered = false
    }

    func handleDefaultOutputDeviceChanged() async {
        guard isRunning else { return }

        do {
            try rebuildCaptureGraphForCurrentDefaultOutput(initialStart: false)
        } catch {
            await stop()
        }
    }

    // MARK: - ProcessTap Creation
    
    private func createProcessTap() throws -> AudioDeviceID {
        var tapDescription = CATapDescription()
        
        // Configure tap for system audio output
        // UUID for system-wide tap (null UUID means all processes)
        tapDescription.uuid = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        
        // Tap format: stereo 48kHz float32 (we'll convert to 16kHz mono later)
        tapDescription.tapMode = kCATapModeListenOnly
        tapDescription.stereoMixdown = true
        
        var tapID: AudioDeviceID = 0
        var tapIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyCreateProcessTap),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = withUnsafeMutablePointer(to: &tapDescription) { tapDescPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<CATapDescription>.size),
                tapDescPtr,
                &tapIDSize,
                &tapID
            )
        }
        
        guard status == noErr else {
            throw SystemAudioCaptureError.tapCreationFailed(status)
        }
        
        return tapID
    }
    
    // MARK: - Aggregate Device Creation
    
    private func createAggregateDevice(with tapID: AudioDeviceID, outputDeviceUID: String) throws -> AudioDeviceID {
        let aggregateDeviceUID = routeState?.aggregateDeviceUID ?? SystemAudioRouteState.make(defaultOutputDeviceUID: outputDeviceUID).aggregateDeviceUID
        let aggregateDeviceDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Gophy System Audio Tap",
            kAudioAggregateDeviceUIDKey: aggregateDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapID,
                kAudioSubTapDriftCompensationKey: true
            ]],
            kAudioAggregateDeviceIsPrivateKey: 1
        ]
        
        var aggregateDeviceID: AudioDeviceID = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioPlugInCreateAggregateDevice),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var outDataSize: UInt32 = 0
        let status = withUnsafePointer(to: aggregateDeviceDict as CFDictionary) { dictPtr in
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &outDataSize
            )
            
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<CFDictionary>.size),
                dictPtr,
                &outDataSize,
                &aggregateDeviceID
            )
        }
        
        guard status == noErr else {
            throw SystemAudioCaptureError.aggregateDeviceCreationFailed(status)
        }
        
        return aggregateDeviceID
    }
    
    // MARK: - IO Proc Setup
    
    private func setupIOProc(for deviceID: AudioDeviceID) throws {
        var ioProcID: AudioDeviceIOProcID?

        let status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            deviceID,
            nil
        ) { [weak self] (
            inNow: UnsafePointer<AudioTimeStamp>,
            inInputData: UnsafePointer<AudioBufferList>,
            inInputTime: UnsafePointer<AudioTimeStamp>,
            outOutputData: UnsafeMutablePointer<AudioBufferList>,
            inOutputTime: UnsafePointer<AudioTimeStamp>
        ) in
            guard let self = self else { return }

            // Copy buffer data immediately before Task boundary
            let bufferCount = Int(inInputData.pointee.mNumberBuffers)
            guard bufferCount > 0 else { return }

            let buffer = inInputData.pointee.mBuffers
            guard let data = buffer.mData else { return }

            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            let samplesArray = Array(UnsafeBufferPointer<Float>(start: samples, count: sampleCount))
            let channelCount = Int(buffer.mNumberChannels)
            let captureTime = CACurrentMediaTime()

            // Now process with copied data in async context
            Task {
                await self.processAudioSamples(samplesArray, channelCount: channelCount, captureTime: captureTime)
            }
        }

        guard status == noErr, let procID = ioProcID else {
            throw SystemAudioCaptureError.ioProcCreationFailed(status)
        }

        self.ioProcID = procID
    }

    private func processAudioSamples(_ samplesArray: [Float], channelCount: Int, captureTime: TimeInterval) async {
        guard let converter = audioConverter else { return }

        // Build an AVAudioPCMBuffer from the raw interleaved samples
        let frameCount = AVAudioFrameCount(samplesArray.count / channelCount)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.inputFormat,
            frameCapacity: frameCount
        ) else { return }
        inputBuffer.frameLength = frameCount

        // Copy interleaved samples into the buffer
        if let bufferData = inputBuffer.floatChannelData {
            samplesArray.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                bufferData[0].update(from: base, count: samplesArray.count)
            }
        }

        // Calculate output frame count
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

        guard status != .error, error == nil,
              let outData = outputBuffer.floatChannelData else { return }

        let count = Int(outputBuffer.frameLength)
        let convertedSamples = Array(UnsafeBufferPointer(start: outData[0], count: count))

        // Create chunk and emit
        let timestamp = captureTime - startTime
        let chunk = AudioChunk(
            samples: convertedSamples,
            timestamp: timestamp,
            source: .systemAudio
        )

        continuation?.yield(chunk)
    }

    // MARK: - Device Control

    private func startDevice(_ deviceID: AudioDeviceID) throws {
        guard let ioProcID = ioProcID else {
            throw SystemAudioCaptureError.noProcID
        }

        let status = AudioDeviceStart(deviceID, ioProcID)
        guard status == noErr else {
            throw SystemAudioCaptureError.deviceStartFailed(status)
        }
    }
    
    // MARK: - Cleanup
    
    private func destroyProcessTap(_ tapID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDestroyProcessTap),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var tapIDCopy = tapID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            size,
            &tapIDCopy
        )
    }
    
    private func destroyAggregateDevice(_ deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioPlugInDestroyAggregateDevice),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceIDCopy = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            size,
            &deviceIDCopy
        )
    }
}

// MARK: - CATapDescription

/// CoreAudio Tap Description structure (macOS 14.4+)
struct CATapDescription {
    var uuid: UUID = UUID()
    var tapMode: UInt32 = 0
    var stereoMixdown: Bool = false
    var reserved: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
}

// MARK: - Constants

let kCATapModeListenOnly: UInt32 = 0

let kAudioHardwarePropertyCreateProcessTap: UInt32 = 0x70746170  // 'ptap'
let kAudioHardwarePropertyDestroyProcessTap: UInt32 = 0x70746170 // 'ptap'
let kAudioAggregateDeviceTapListKey = "tap-list"
let kAudioSubTapUIDKey = "subtap-uid"
let kAudioSubTapDriftCompensationKey = "drift-compensation"
let kAudioSubDeviceUIDKey = "uid"

// MARK: - Errors

public enum SystemAudioCaptureError: Error, Sendable {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case defaultOutputLookupFailed(OSStatus)
    case noProcID
    case unsupportedMacOSVersion
    case formatCreationFailed
    case converterCreationFailed
}

private func defaultSystemOutputListenerProc(
    _: AudioObjectID,
    _: UInt32,
    _: UnsafePointer<AudioObjectPropertyAddress>,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else {
        return noErr
    }

    let service = Unmanaged<SystemAudioCaptureService>.fromOpaque(clientData).takeUnretainedValue()
    Task {
        await service.handleDefaultOutputDeviceChanged()
    }
    return noErr
}
