//
//  InputView.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 6/3/26.
//

import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum InputContentType: String, CaseIterable, Identifiable {
    case text
    case image
    case audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .audio: "Audio"
        }
    }
}

struct InputView: View {
    @State private var selectedType: InputContentType = .text
    @State private var textInput = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var imageFileName: String?
    @State private var audioURL: URL?
    @State private var showAudioImporter = false
    @State private var showTranscript = false
    @State private var generatedTranscript = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Input type", selection: $selectedType) {
                        ForEach(InputContentType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                switch selectedType {
                case .text:
                    textSection
                case .image:
                    imageSection
                case .audio:
                    audioSection
                }
                Section {
                    Button("Transcribe") {
                        transcribe()
                    }
                    .disabled(!canTranscribe)
                } footer: {
                    transcribeFooter
                }
            }
            .navigationTitle("Add Input")
            .navigationDestination(isPresented: $showTranscript) {
                TranscriptView(transcript: generatedTranscript)
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    audioURL = urls.first
                case .failure:
                    break
                }
            }
        }
    }

    private var canTranscribe: Bool {
        guard selectedType == .text else { return false }
        return TranscriptGenerator.transcript(fromText: textInput) != nil
    }

    @ViewBuilder
    private var transcribeFooter: some View {
        switch selectedType {
        case .text:
            if textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Enter text above to transcribe.")
            }
        case .image, .audio:
            Text("Image and audio transcription coming soon.")
        }
    }

    private func transcribe() {
        guard let transcript = TranscriptGenerator.transcript(fromText: textInput) else {
            return
        }
        generatedTranscript = transcript
        showTranscript = true
    }

    private var textSection: some View {
        Section {
            TextEditor(text: $textInput)
                .frame(minHeight: 160)
        } header: {
            Text("Text")
        } footer: {
            if !textInput.isEmpty {
                Text("\(textInput.count) characters")
            }
        }
    }

    private var imageSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }

            if let selectedImage {
                selectedImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let imageFileName {
                Text(imageFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Image")
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadImage(from: newItem)
            }
        }
    }

    private var audioSection: some View {
        Section {
            Button {
                showAudioImporter = true
            } label: {
                Label("Choose Audio File", systemImage: "waveform")
            }

            if let audioURL {
                LabeledContent("File", value: audioURL.lastPathComponent)
            }
        } header: {
            Text("Audio file")
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else {
            selectedImage = nil
            imageFileName = nil
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }

        selectedImage = Image(uiImage: uiImage)
        imageFileName = "Selected image"
    }
}

#Preview {
    InputView()
}

