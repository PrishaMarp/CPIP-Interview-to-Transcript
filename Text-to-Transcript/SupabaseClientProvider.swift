//
//  SupabaseClientProvider.swift
//  Text-to-Transcript
//

import Foundation
import Supabase

enum SupabaseClientProvider {
    static let client = SupabaseClient(
        supabaseURL: BackendSecrets.supabaseURL,
        supabaseKey: BackendSecrets.supabaseAnonKey
    )

    /// Ensures there is an authenticated session (anonymous is fine for RLS scoping).
    static func ensureAuthenticated() async throws {
        do {
            _ = try await client.auth.session
        } catch {
            try await client.auth.signInAnonymously()
        }
    }

    static func currentUserID() async throws -> UUID {
        try await ensureAuthenticated()
        return try await client.auth.session.user.id
    }
}
