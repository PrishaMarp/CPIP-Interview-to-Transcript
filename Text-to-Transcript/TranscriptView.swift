//
//  TranscriptView.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 6/3/26.
//

import SwiftUI

struct TranscriptView: View {
    let transcript: String

    var body: some View {
        ScrollView {
            Text(transcript)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TranscriptView(transcript: "Sample transcript text.")
    }
}

