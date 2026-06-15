//
//  TranscriptUploadService.swift
//  Text-to-Transcript
//

import Foundation

/// Mirrors the `media_type_enum` Postgres type.
enum TranscriptMediaType: String {
    case text
    case photo
    case audio
}

struct TranscriptUploadResponse: Decodable {
    let sessionId: UUID
    let mediaId: UUID

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case mediaId = "media_id"
    }
}

enum TranscriptUploadError: LocalizedError {
    case requestFailed(Error)
    case serverError(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let error):
            "Network request failed: \(error.localizedDescription)"
        case .serverError(let code):
            "Server returned an error (\(code))."
        case .decodingFailed(let error):
            "Could not read server response: \(error.localizedDescription)"
        }
    }
}

enum BackendConfig {
    /// The public URL of your FastAPI backend (Railway/Render).
    static let baseURL = URL(string: "https://YOUR-APP.up.railway.app")!

    /// Must match the API_KEY environment variable set on the backend.
    static let apiKey = "choose-a-long-random-string"
}

enum TranscriptUploadService {

    private struct NewTranscript: Encodable {
        let transcript_text: String
        let media_type: String
        let session_id: String?
    }

    /// Sends the transcript to the FastAPI backend, which creates a
    /// session (if needed) and a linked media row in Supabase.
    static func saveTranscript(
        _ text: String,
        mediaType: TranscriptMediaType,
        sessionId: UUID? = nil
    ) async throws -> TranscriptUploadResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("transcripts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let payload = NewTranscript(
            transcript_text: text,
            media_type: mediaType.rawValue,
            session_id: sessionId?.uuidString
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptUploadError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranscriptUploadError.serverError(code)
        }

        do {
            return try JSONDecoder().decode(TranscriptUploadResponse.self, from: data)
        } catch {
            throw TranscriptUploadError.decodingFailed(error)
        }
    }
}
