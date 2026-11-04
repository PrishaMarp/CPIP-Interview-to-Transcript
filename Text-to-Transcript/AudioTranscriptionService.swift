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

    /// Words an interview is likely to use. Passed as hints so names of medicines and programs are less likely to be misheard.
    private static let pathwayTerms = [
        "buprenorphine", "Suboxone", "methadone", "naltrexone", "naloxone", "Narcan",
        "fentanyl", "opioid", "MOUD", "MAT",
        "detox", "inpatient", "outpatient", "peer recovery",
        "probation", "parole",
    ]

    /// Apple's older file recognizer is only reliable for about a minute, so the fallback splits longer audio.
    private static let legacyChunkSeconds: Double = 50
    private static let recognitionTimeoutSeconds: UInt64 = 120

    static func transcript(from url: URL) async throws -> String {
        try await ensureAuthorization()

        let copiedURL = try copyToTemporaryFile(from: url)
        defer { try? FileManager.default.removeItem(at: copiedURL) }

        let preparedURL = await normalizeAudioForRecognition(from: copiedURL)
        defer {
            if preparedURL != copiedURL {
                try? FileManager.default.removeItem(at: preparedURL)
            }
        }

        if let longForm = try? await transcribeLongForm(from: preparedURL), !longForm.isEmpty {
            return longForm
        }

        return try await transcribeInChunks(from: preparedURL)
    }

    // MARK: - Long-form transcription (iOS 26)

    /// Transcribes the whole file with SpeechTranscriber and prefixes each section with its start time.
    private static func transcribeLongForm(from url: URL) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionFailure.recognizerUnavailable
        }
        guard let locale = await matchingLocale() else {
            throw TranscriptionFailure.recognizerUnavailable
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModelInstalled(for: transcriber, locale: locale)

        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let context = AnalysisContext()
        context.contextualStrings = [.general: pathwayTerms]
        try? await analyzer.setContext(context)

        let collectTask = Task { try await collectFinalSegments(from: transcriber) }
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collectTask.cancel()
            throw error
        }

        let transcript = try await collectTask.value
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionFailure.noSpeechDetected
        }
        return trimmed
    }

    private static func collectFinalSegments(from transcriber: SpeechTranscriber) async throws -> String {
        var lines: [String] = []
        for try await result in transcriber.results {
            guard result.isFinal else { continue }
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            lines.append("\(timestamp(for: result.range.start)) \(text)")
        }
        return lines.joined(separator: "\n\n")
    }

    private static func matchingLocale() async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else { return nil }

        var candidates: [Locale] = []
        if let preferred = Locale.preferredLanguages.first {
            candidates.append(Locale(identifier: preferred))
        }
        candidates.append(Locale.current)
        candidates.append(Locale(identifier: "en-US"))

        for candidate in candidates {
            if let exact = supported.first(where: { $0.identifier(.bcp47) == candidate.identifier(.bcp47) }) {
                return exact
            }
            if let sameLanguage = supported.first(where: { $0.language.languageCode == candidate.language.languageCode }) {
                return sameLanguage
            }
        }
        return supported.first
    }

    private static func ensureModelInstalled(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            throw TranscriptionFailure.recognizerUnavailable
        case .supported, .downloading:
            try await reserveLocaleIfNeeded(locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
    }

    private static func reserveLocaleIfNeeded(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        let wanted = locale.identifier(.bcp47)
        if reserved.contains(where: { $0.identifier(.bcp47) == wanted }) {
            return
        }
        if reserved.count >= AssetInventory.maximumReservedLocales {
            for extra in reserved where extra.identifier(.bcp47) != wanted {
                await AssetInventory.release(reservedLocale: extra)
                break
            }
        }
        _ = try await AssetInventory.reserve(locale: locale)
    }

    private static func timestamp(for time: CMTime) -> String {
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0 else { return "[0:00]" }
        let total = Int(seconds.rounded(.down))
        return String(format: "[%d:%02d]", total / 60, total % 60)
    }

    // MARK: - Legacy recognizer, split so a long recording is not cut off

    private static func transcribeInChunks(from url: URL) async throws -> String {
        guard let recognizer = makeRecognizer() else {
            throw TranscriptionFailure.recognizerUnavailable
        }

        let chunks = await chunkAudio(at: url)
        defer {
            for chunk in chunks where chunk != url {
                try? FileManager.default.removeItem(at: chunk)
            }
        }

        var parts: [String] = []
        var lastError: Error?
        for chunk in chunks {
            let request = SFSpeechURLRecognitionRequest(url: chunk)
            configure(request)
            do {
                let text = try await runRecognition(recognizer: recognizer, request: request)
                if !text.isEmpty {
                    parts.append(text)
                }
            } catch {
                lastError = error
            }
        }

        let transcript = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if transcript.isEmpty {
            if let lastError {
                throw lastError
            }
            throw TranscriptionFailure.noSpeechDetected
        }
        return transcript
    }

    private static func chunkAudio(at url: URL) async -> [URL] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return [url] }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > legacyChunkSeconds + 5 else { return [url] }

        var chunks: [URL] = []
        var start = 0.0
        while start < seconds - 0.25 {
            let length = min(legacyChunkSeconds, seconds - start)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                break
            }
            exportSession.outputURL = destination
            exportSession.outputFileType = .m4a
            exportSession.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: length, preferredTimescale: 600)
            )
            do {
                try await exportSession.export(to: destination, as: .m4a)
                chunks.append(destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                break
            }
            start += length
        }
        return chunks.isEmpty ? [url] : chunks
    }

    private static func configure(_ request: SFSpeechURLRecognitionRequest) {
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = false
        request.contextualStrings = pathwayTerms
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

        do {
            try await exportSession.export(to: destination, as: .m4a)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return url
        }
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
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
