//
//  TranscriptGenerator.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 6/3/26.
//

import Foundation

enum TranscriptGenerator {
    /// Plain text input is kept as-is for the transcript.
    static func transcript(fromText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

