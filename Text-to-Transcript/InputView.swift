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
    @State private var selectedUIImage: UIImage?
    @State private var imageFileName: String?
    @State private var audioURL: URL?
    @State private var showAudioImporter = false
    @State private var showTranscript = false
    @State private var generatedTranscript = ""
    @State private var generatedMediaType: TranscriptMediaType = .text
    @State private var isTranscribing = false
    @State private var showOCRError = false
    @State private var ocrErrorMessage = ""

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
                    Button {
                        transcribe()
                    } label: {
                        if isTranscribing {
                            HStack {
                                ProgressView()
                                Text("Transcribing…")
                            }
                        } else {
                            Text("Transcribe")
                        }
                    }
                    .disabled(!canTranscribe)
                } footer: {
                    transcribeFooter
                }
            }
            .navigationTitle("Add Input")
            .navigationDestination(isPresented: $showTranscript) {
                TranscriptView(transcript: generatedTranscript, mediaType: generatedMediaType)
            }
            .alert("Transcription failed", isPresented: $showOCRError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ocrErrorMessage)
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    audioURL = urls.first.flatMap { persistImportedAudio($0) }
                case .failure:
                    break
                }
            }
        }
    }

    private var canTranscribe: Bool {
        if isTranscribing { return false }
        switch selectedType {
        case .text:
            return TranscriptGenerator.transcript(fromText: textInput) != nil
        case .image:
            return selectedUIImage != nil
        case .audio:
            return audioURL != nil
        }
    }

    @ViewBuilder
    private var transcribeFooter: some View {
        switch selectedType {
        case .text:
            if textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Enter text above to transcribe.")
            }
        case .image:
            if selectedUIImage == nil {
                Text("Choose a photo with text to transcribe.")
            }
        case .audio:
            if audioURL == nil {
                Text("Choose an audio file to transcribe.")
            }
        }
    }

    private func transcribe() {
        switch selectedType {
        case .text:
            guard let transcript = TranscriptGenerator.transcript(fromText: textInput) else {
                return
            }
            generatedTranscript = transcript
            generatedMediaType = .text
            showTranscript = true

        case .image:
            guard let selectedUIImage else { return }
            isTranscribing = true
            Task {
                do {
                    let transcript = try await ImageOCRService.transcript(from: selectedUIImage)
                    await MainActor.run {
                        generatedTranscript = transcript
                        generatedMediaType = .photo
                        isTranscribing = false
                        showTranscript = true
                    }
                } catch {
                    await MainActor.run {
                        isTranscribing = false
                        ocrErrorMessage = error.localizedDescription
                        showOCRError = true
                    }
                }
            }

        case .audio:
            guard let audioURL else { return }
            isTranscribing = true
            Task {
                do {
                    let transcript = try await AudioTranscriptionService.transcript(from: audioURL)
                    await MainActor.run {
                        generatedTranscript = transcript
                        generatedMediaType = .audio
                        isTranscribing = false
                        showTranscript = true
                    }
                } catch {
                    await MainActor.run {
                        isTranscribing = false
                        ocrErrorMessage = error.localizedDescription
                        showOCRError = true
                    }
                }
            }
        }
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

    private func persistImportedAudio(_ url: URL) -> URL? {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else {
            selectedImage = nil
            selectedUIImage = nil
            imageFileName = nil
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }

        selectedImage = Image(uiImage: uiImage)
        selectedUIImage = uiImage
        imageFileName = "Selected image"
    }
}

#Preview {
    InputView()
}
