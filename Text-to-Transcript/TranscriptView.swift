//
//  TranscriptView.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 6/3/26.
//

import SwiftUI

struct TranscriptView: View {
    let transcript: String
    let mediaType: TranscriptMediaType

    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var body: some View {
        ScrollView {
            Text(transcript)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
    }

    @ViewBuilder
    private var saveBar: some View {
        VStack(spacing: 8) {
            switch saveState {
            case .idle:
                Button {
                    save()
                } label: {
                    Label("Save to database", systemImage: "icloud.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            case .saving:
                ProgressView("Saving...")

            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .failed(let message):
                VStack(spacing: 4) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Retry") { save() }
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func save() {
        saveState = .saving
        Task {
            do {
                _ = try await TranscriptUploadService.saveTranscript(transcript, mediaType: mediaType)
                saveState = .saved
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TranscriptView(transcript: "Sample transcript text.", mediaType: .text)
    }
}
