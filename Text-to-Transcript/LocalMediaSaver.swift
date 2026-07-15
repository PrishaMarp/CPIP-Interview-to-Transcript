//
//  LocalMediaSaver.swift
//  Text-to-Transcript
//

import Foundation
import Photos
import UIKit

enum LocalMediaSaver {
    enum SaveError: LocalizedError {
        case photoLibraryDenied
        case downloadsUnavailable
        case sourceFileMissing
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .photoLibraryDenied:
                "Photo library access is required to save images."
            case .downloadsUnavailable:
                "Could not prepare the recording for export."
            case .sourceFileMissing:
                "The recording file could not be found. Try recording again."
            case .saveFailed:
                "Could not save the file."
            }
        }
    }

    static func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.photoLibraryDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.saveFailed)
                }
            }
        }
    }

    @discardableResult
    static func preparedAudioExportURL(from sourceURL: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SaveError.sourceFileMissing
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let filename = "Interview \(formatter.string(from: Date())).\(ext)"

        let exportsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let destination = exportsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

