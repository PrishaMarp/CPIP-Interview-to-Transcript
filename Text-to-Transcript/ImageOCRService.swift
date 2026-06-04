//
//  ImageOCRService.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 6/3/26.
//

import UIKit
import Vision

enum ImageOCRService {
    enum OCRFailure: LocalizedError {
        case invalidImage
        case noTextFound
        case recognitionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                "The selected image could not be processed."
            case .noTextFound:
                "No text was detected in the image."
            case .recognitionFailed(let error):
                "Text recognition failed: \(error.localizedDescription)"
            }
        }
    }

    static func transcript(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRFailure.invalidImage
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRFailure.recognitionFailed(error))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else {
                    continuation.resume(throwing: OCRFailure.noTextFound)
                    return
                }

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )

            Task.detached(priority: .userInitiated) {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRFailure.recognitionFailed(error))
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

