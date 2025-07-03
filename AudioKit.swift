import Foundation
import AVFoundation
import ScreenCaptureKit
// import CoreMedia
import CRecorder // This should match your module.modulemap

public struct RecorderConfiguration {
    public var fileName: String
    public var sampleRate: UInt32
    public var channelCount: UInt8
    public var bitsPerSample: UInt8
    public var ringDuration: UInt16

    public init(fileName: String,
                sampleRate: UInt32 = 48_000,
                channelCount: UInt8 = 1,
                bitsPerSample: UInt8 = 32,
                ringDuration: UInt16 = 60) {
        self.fileName = fileName
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerSample = bitsPerSample
        self.ringDuration = ringDuration
    }
}

public enum RecordingError: Error {
    case initializationFailed
    case noDisplayFound
    case failedToStartStream(OSStatus)
    case saveFailed
}

final class Recorder {
    private let ptr: UnsafeMutablePointer<AudioRecorder>
    init(config: RecorderConfiguration) throws {
        let cName = strdup(config.fileName)
        defer { free(cName) }
        guard let cName else { throw RecordingError.initializationFailed }
        guard let p = Initialization(cName,
                                     config.sampleRate,
                                     config.channelCount,
                                     config.bitsPerSample,
                                     config.ringDuration) else {
            throw RecordingError.initializationFailed
        }
        ptr = p
    }

    deinit { Stop(ptr) }

    func append(_ buf: UnsafeRawPointer, _ length: Int) {
        Record(ptr, UnsafeMutableRawPointer(mutating: buf), Int(length))
    }

    func save(to url: URL, seconds: UInt16) throws {
        let path = url.path.cString(using: .utf8)!
        let status = Save(ptr, path, seconds)
        guard status == 0 else { throw RecordingError.saveFailed }
    }
}

fileprivate extension CMSampleBuffer {
    struct AudioData { let pointer: UnsafeRawPointer; let length: Int }

    var audioData: AudioData? {
        guard let block = CMSampleBufferGetDataBuffer(self) else { return nil }
        var length = 0
        var dataPtr: UnsafeMutablePointer<Int8>? = nil
        let err = CMBlockBufferGetDataPointer(block,
                                              atOffset: 0,
                                              lengthAtOffsetOut: nil,
                                              totalLengthOut: &length,
                                              dataPointerOut: &dataPtr)
        guard err == kCMBlockBufferNoErr, let base = dataPtr else { return nil }
        return AudioData(pointer: UnsafeRawPointer(base), length: length)
    }
}

fileprivate final class OutputHandler: NSObject, SCStreamOutput {
    weak var owner: AudioCaptureService?
    init(owner: AudioCaptureService) { self.owner = owner }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, 
            let owner = owner,
            let audio = sb.audioData else { return }
        Task { await owner.append(buffer: audio.pointer, length: audio.length) }
    }
}

public actor AudioCaptureService {
    public enum State { case idle, recording }
    public private(set) var state: State = .idle

    private var recorder: Recorder?
    private var stream: SCStream?
    private var handler: OutputHandler?
    private var currentConfig: RecorderConfiguration?

    public func start_recording(with config: RecorderConfiguration) async throws {
        guard state == .idle else { return }
        currentConfig = config
        recorder = try Recorder(config: config)
        stream = try await makeStream(for: config)
        try await stream?.startCapture()
        state = .recording
    }

    @discardableResult
    public func save_recording(seconds: UInt16? = nil) async throws -> URL {
        guard state == .recording, let recorder = recorder else {
            throw RecordingError.saveFailed
        }

        let secs = seconds ?? currentConfig?.ringDuration ?? 60
        let url  = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent((currentConfig?.fileName ?? "audio") + ".wav")

        try await Task(priority: .userInitiated) {
            try recorder.save(to: url, seconds: secs)
        }.value
        return url
    }


    public func stop_recording() async throws {
        guard state == .recording else { return }
        try await stream?.stopCapture()
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s grace
        stream = nil
        handler = nil
        recorder = nil
        currentConfig = nil
        state = .idle
    }

    fileprivate func append(buffer: UnsafeRawPointer, length: Int) {
        recorder?.append(buffer, length)
    }

    private func makeStream(for config: RecorderConfiguration) async throws -> SCStream {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw RecordingError.noDisplayFound }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scConfig = SCStreamConfiguration()
        scConfig.capturesAudio = true
        scConfig.sampleRate = Int(config.sampleRate)
        scConfig.channelCount = Int(config.channelCount)
        let s = SCStream(filter: filter, configuration: scConfig, delegate: nil)
        let h = OutputHandler(owner: self)
        try s.addStreamOutput(h, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        handler = h
        return s
    }
}