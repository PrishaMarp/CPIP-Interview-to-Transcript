//
//  AudioRecorder.swift
//  Text-to-Transcript
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingURL: URL?
    @Published private(set) var elapsedSeconds = 0

    private var recorder: AVAudioRecorder?
    private var elapsedTask: Task<Void, Never>?

    private static var recordingsDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("Recordings", isDirectory: true)
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case failedToStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Microphone access is required to record audio."
            case .failedToStart:
                "Could not start recording."
            }
        }
    }

    func start() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw RecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        try FileManager.default.createDirectory(
            at: Self.recordingsDirectory,
            withIntermediateDirectories: true
        )

        let url = Self.recordingsDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)

        guard recorder?.prepareToRecord() == true,
              recorder?.record() == true else {
            throw RecorderError.failedToStart
        }

        recordingURL = url
        isRecording = true
        elapsedSeconds = 0
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isRecording else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        elapsedTask?.cancel()
        elapsedTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func recordingFileURL() -> URL? {
        guard let recordingURL,
              FileManager.default.fileExists(atPath: recordingURL.path) else {
            return nil
        }
        return recordingURL
    }

    func reset() {
        stop()
        recordingURL = nil
        elapsedSeconds = 0
    }

    var formattedElapsed: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

