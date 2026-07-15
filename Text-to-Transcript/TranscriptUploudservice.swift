//
//  TranscriptUploadService.swift
//  Text-to-Transcript
//

import Foundation
import Supabase

/// Matches the `media.media_type` values used by the existing schema.
enum TranscriptMediaType: String, Encodable {
    case text
    case photo
    case audio
}

struct TranscriptUploadResponse {
    let sessionId: UUID
    let mediaId: UUID
}

enum TranscriptUploadError: LocalizedError {
    case notAuthenticated
    case insertFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Could not sign in to save this transcript."
        case .insertFailed(let error):
            "Could not save transcript: \(error.localizedDescription)"
        }
    }
}

enum TranscriptUploadService {

    private struct NewSession: Encodable {
        let status: String
    }

    private struct SessionRow: Decodable {
        let id: UUID
    }

    private struct NewMedia: Encodable {
        let session_id: UUID
        let media_type: String
        let transcript_text: String
        let processing_status: String
    }

    private struct MediaRow: Decodable {
        let id: UUID
        let session_id: UUID
    }

    /// Creates a `sessions` row, then inserts the transcript into `media`.
    /// Railway is no longer involved — a Supabase webhook can call `/extract` after the media insert.
    @discardableResult
    static func saveTranscript(
        _ text: String,
        mediaType: TranscriptMediaType,
        sessionId: UUID? = nil
    ) async throws -> TranscriptUploadResponse {
        do {
            try await SupabaseClientProvider.ensureAuthenticated()
        } catch {
            throw TranscriptUploadError.notAuthenticated
        }

        let client = SupabaseClientProvider.client

        do {
            let resolvedSessionID: UUID
            if let sessionId {
                resolvedSessionID = sessionId
            } else {
                let session: SessionRow = try await client
                    .from("sessions")
                    .insert(NewSession(status: "pending"))
                    .select("id")
                    .single()
                    .execute()
                    .value
                resolvedSessionID = session.id
            }

            let media: MediaRow = try await client
                .from("media")
                .insert(
                    NewMedia(
                        session_id: resolvedSessionID,
                        media_type: mediaType.rawValue,
                        transcript_text: text,
                        processing_status: "pending"
                    )
                )
                .select("id, session_id")
                .single()
                .execute()
                .value

            return TranscriptUploadResponse(
                sessionId: media.session_id,
                mediaId: media.id
            )
        } catch {
            throw TranscriptUploadError.insertFailed(error)
        }
    }
}
