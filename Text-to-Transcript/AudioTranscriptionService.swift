//
//  AudioTranscriptionService.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 6/3/26.
//

import AVFoundation
import Foundation
import Speech

enum AudioTranscriptionService {
    enum TranscriptionFailure: LocalizedError {
        case authorizationDenied
        case authorizationRestricted
        case recognizerUnavailable
        case noSpeechDetected
        case recognitionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                "Speech recognition permission was denied. Enable it in Settings."
            case .authorizationRestricted:
                "Speech recognition is restricted on this device."
            case .recognizerUnavailable:
                "Speech recognition is not available for the current language."
            case .noSpeechDetected:
                "No speech was detected in the audio file."
            case .recognitionFailed(let error):
                "Speech recognition failed: \(error.localizedDescription)"
            }
        }
    }

    /// Maximum time to wait for recognition before using the best partial result.
    private static let recognitionTimeoutSeconds: UInt64 = 300

    static func transcript(from url: URL) async throws -> String {
        try await ensureAuthorization()

        guard let recognizer = makeRecognizer() else {
            throw TranscriptionFailure.recognizerUnavailable
        }

        let copiedURL = try copyToTemporaryFile(from: url)
        defer { try? FileManager.default.removeItem(at: copiedURL) }

        let preparedURL = await normalizeAudioForRecognition(from: copiedURL)
        defer {
            if preparedURL != copiedURL {
                try? FileManager.default.removeItem(at: preparedURL)
            }
        }

        let request = SFSpeechURLRecognitionRequest(url: preparedURL)
        configure(request)

        return try await runRecognition(recognizer: recognizer, request: request)
    }

    // MARK: - Recognition

    private static func configure(_ request: SFSpeechURLRecognitionRequest) {
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Server-based recognition is more accurate than on-device (Apple documentation).
        request.requiresOnDeviceRecognition = false
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
    }

    private static func runRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var hasFinished = false
            var latestTranscript = ""
            var recognitionTask: SFSpeechRecognitionTask?

            func finish(with text: String) {
                guard !hasFinished else { return }
                hasFinished = true
                recognitionTask?.cancel()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continuation.resume(throwing: TranscriptionFailure.noSpeechDetected)
                } else {
                    continuation.resume(returning: trimmed)
                }
            }

            func fail(_ error: Error) {
                guard !hasFinished else { return }
                hasFinished = true
                recognitionTask?.cancel()
                continuation.resume(throwing: TranscriptionFailure.recognitionFailed(error))
            }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    // If we already have partial text, prefer that over failing outright.
                    if !latestTranscript.isEmpty {
                        finish(with: latestTranscript)
                    } else {
                        fail(error)
                    }
                    return
                }

                guard let result else { return }

                latestTranscript = result.bestTranscription.formattedString

                if result.isFinal {
                    finish(with: latestTranscript)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: recognitionTimeoutSeconds * 1_000_000_000)
                guard !hasFinished else { return }
                if latestTranscript.isEmpty {
                    fail(
                        NSError(
                            domain: "AudioTranscriptionService",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Recognition timed out."]
                        )
                    )
                } else {
                    finish(with: latestTranscript)
                }
            }
        }
    }

    private static func makeRecognizer() -> SFSpeechRecognizer? {
        var locales: [Locale] = []
        if let preferred = Locale.preferredLanguages.first {
            locales.append(Locale(identifier: preferred))
        }
        locales.append(Locale.current)
        locales.append(Locale(identifier: "en-US"))

        var seen = Set<String>()
        for locale in locales {
            let id = locale.identifier
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                return recognizer
            }
        }

        if let fallback = SFSpeechRecognizer(), fallback.isAvailable {
            return fallback
        }
        return nil
    }

    // MARK: - Audio preparation

    /// Re-encode to AAC in an .m4a container so Speech gets a consistent format.
    private static func normalizeAudioForRecognition(from url: URL) async -> URL {
        let asset = AVURLAsset(url: url)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            return url
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            return url
        }

        return destination
    }

    // MARK: - Authorization & file access

    private static func ensureAuthorization() async throws {
        let status = await requestAuthorization()
        switch status {
        case .authorized:
            return
        case .denied:
            throw TranscriptionFailure.authorizationDenied
        case .restricted:
            throw TranscriptionFailure.authorizationRestricted
        case .notDetermined:
            throw TranscriptionFailure.authorizationDenied
        @unknown default:
            throw TranscriptionFailure.authorizationDenied
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func copyToTemporaryFile(from url: URL) throws -> URL {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}

