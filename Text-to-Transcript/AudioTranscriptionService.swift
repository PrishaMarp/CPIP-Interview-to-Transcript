//
//  AudioTranscriptionService.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 6/3/26.
//

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

    static func transcript(from url: URL) async throws -> String {
        try await ensureAuthorization()

        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            throw TranscriptionFailure.recognizerUnavailable
        }

        let localURL = try copyToTemporaryFile(from: url)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let request = SFSpeechURLRecognitionRequest(url: localURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasFinished = false

            recognizer.recognitionTask(with: request) { result, error in
                guard !hasFinished else { return }

                if let error {
                    hasFinished = true
                    continuation.resume(throwing: TranscriptionFailure.recognitionFailed(error))
                    return
                }

                guard let result else { return }

                if result.isFinal {
                    hasFinished = true
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        continuation.resume(throwing: TranscriptionFailure.noSpeechDetected)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }

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

