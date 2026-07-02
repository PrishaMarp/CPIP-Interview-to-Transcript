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

    var icon: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .audio: "waveform"
        }
    }

    var subtitle: String {
        switch self {
        case .text: "Type notes or import a Google Doc"
        case .image: "Extract text from a photo"
        case .audio: "Transcribe a recording"
        }
    }
}

private enum TextEntryMode: String, CaseIterable, Identifiable {
    case type
    case importDocument

    var id: String { rawValue }

    var label: String {
        switch self {
        case .type: "Type"
        case .importDocument: "Google Doc"
        }
    }
}

struct InputView: View {
    @State private var selectedType: InputContentType = .text
    @State private var textEntryMode: TextEntryMode = .type
    @State private var textInput = ""
    @State private var importedDocumentName: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedUIImage: UIImage?
    @State private var imageFileName: String?
    @State private var audioURL: URL?
    @State private var showAudioImporter = false
    @State private var showDocumentImporter = false
    @State private var showTranscript = false
    @State private var generatedTranscript = ""
    @State private var generatedMediaType: TranscriptMediaType = .text
    @State private var isTranscribing = false
    @State private var showOCRError = false
    @State private var ocrErrorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        inputTypePicker

                        inputCard

                        if let hint = transcribeHint {
                            Label(hint, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }

                        transcribeButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showTranscript) {
                TranscriptView(transcript: generatedTranscript, mediaType: generatedMediaType)
            }
            .alert("Something went wrong", isPresented: $showOCRError) {
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
                    audioURL = urls.first.flatMap { persistImportedFile($0, defaultExtension: "m4a") }
                case .failure:
                    break
                }
            }
            .fileImporter(
                isPresented: $showDocumentImporter,
                allowedContentTypes: DocumentTextLoader.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importDocument(from: url)
                case .failure:
                    break
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Interview to Transcript")
                        .font(.title2.weight(.bold))
                    Text("Convert text, images, or audio")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private var inputTypePicker: some View {
        HStack(spacing: 10) {
            ForEach(InputContentType.allCases) { type in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedType = type
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: type.icon)
                            .font(.title3.weight(.semibold))
                        Text(type.label)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(selectedType == type ? .white : .primary)
                    .background {
                        if selectedType == type {
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            AppTheme.subtleFill
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selectedType.label)
                .font(.headline)
            Text(selectedType.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            switch selectedType {
            case .text:
                textInputArea
            case .image:
                imageInputArea
            case .audio:
                audioInputArea
            }
        }
        .appCard()
    }

    private var textInputArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            textEntryModePicker

            switch textEntryMode {
            case .type:
                typeTextArea
            case .importDocument:
                importDocumentArea
            }

            if !textInput.isEmpty {
                HStack {
                    Text("\(textInput.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        textInput = ""
                        importedDocumentName = nil
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    private var textEntryModePicker: some View {
        HStack(spacing: 10) {
            ForEach(TextEntryMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        textEntryMode = mode
                    }
                } label: {
                    Text(mode.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(textEntryMode == mode ? .white : .primary)
                        .background {
                            if textEntryMode == mode {
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accentSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                AppTheme.subtleFill
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var typeTextArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type or paste interview notes")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if textInput.isEmpty {
                    Text("Start typing here…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                }

                TextEditor(text: $textInput)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .onChange(of: textInput) { _, _ in
                        importedDocumentName = nil
                    }
            }
            .background(AppTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var importDocumentArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecondaryActionButton(title: "Import Google Doc", systemImage: "doc.richtext") {
                showDocumentImporter = true
            }

            googleDocsHelp

            if let importedDocumentName {
                Label(importedDocumentName, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if !textInput.isEmpty {
                Text("Preview")
                    .font(.subheadline.weight(.medium))

                Text(textInput)
                    .font(.body)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var googleDocsHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How to import from Google Docs", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Supported formats: .docx, .pdf, and .txt")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("From Google Docs: File → Download → Word (.docx), PDF (.pdf), or Plain text (.txt).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func importDocument(from url: URL) {
        do {
            let defaultExt = url.pathExtension.isEmpty ? "docx" : url.pathExtension
            let localURL = persistImportedFile(url, defaultExtension: defaultExt) ?? url
            textInput = try DocumentTextLoader.loadText(from: localURL)
            importedDocumentName = url.lastPathComponent
            textEntryMode = .importDocument
        } catch {
            ocrErrorMessage = error.localizedDescription
            showOCRError = true
        }
    }

    private var imageInputArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ActionRow(title: "Choose Photo", systemImage: "photo.on.rectangle")
            }

            if let selectedImage {
                selectedImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }

            if let imageFileName {
                Label(imageFileName, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadImage(from: newItem)
            }
        }
    }

    private var audioInputArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            SecondaryActionButton(title: "Choose Audio File", systemImage: "waveform") {
                showAudioImporter = true
            }

            if let audioURL {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected file")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(audioURL.lastPathComponent)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var transcribeButton: some View {
        Button {
            transcribe()
        } label: {
            HStack(spacing: 10) {
                if isTranscribing {
                    ProgressView()
                        .tint(.white)
                    Text("Transcribing…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Transcribe")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: canTranscribe))
        .disabled(!canTranscribe)
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

    private var transcribeHint: String? {
        switch selectedType {
        case .text:
            if textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return textEntryMode == .importDocument
                    ? "Import a .docx, .pdf, or .txt file to continue."
                    : "Type or paste text to continue."
            }
            return nil
        case .image:
            if selectedUIImage == nil {
                return "Choose a photo with clear, readable text."
            }
            return nil
        case .audio:
            if audioURL == nil {
                return "Choose an audio file to transcribe."
            }
            return nil
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

    private func persistImportedFile(_ url: URL, defaultExtension: String) -> URL? {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.isEmpty ? defaultExtension : url.pathExtension
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
        imageFileName = "Photo ready"
    }
}

#Preview {
    InputView()
}


