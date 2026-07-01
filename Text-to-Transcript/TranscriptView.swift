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
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mediaTypeBadge

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Transcript")
                                .font(.headline)
                            Spacer()
                            Text("\(transcript.count) chars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(transcript)
                            .font(.body)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .appCard()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
    }

    private var mediaTypeBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: mediaTypeIcon)
                .font(.caption.weight(.semibold))
            Text(mediaTypeLabel)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.accent.opacity(0.12))
        .clipShape(Capsule())
    }

    private var mediaTypeIcon: String {
        switch mediaType {
        case .text: "text.alignleft"
        case .photo: "photo"
        case .audio: "waveform"
        }
    }

    private var mediaTypeLabel: String {
        switch mediaType {
        case .text: "From Text"
        case .photo: "From Image"
        case .audio: "From Audio"
        }
    }

    @ViewBuilder
    private var saveBar: some View {
        VStack(spacing: 10) {
            switch saveState {
            case .idle:
                Button {
                    save()
                } label: {
                    Label("Save to Database", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: true))

            case .saving:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Saving…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

            case .saved:
                Label("Saved successfully", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)

            case .failed(let message):
                VStack(spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)

                    Button("Try Again") { save() }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: true))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
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
        TranscriptView(
            transcript: "This is a sample transcript with multiple lines of text to preview the layout.",
            mediaType: .text
        )
    }
}

