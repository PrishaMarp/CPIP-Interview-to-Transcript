//
//  DocumentTextLoader.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 7/1/26.
//

import Foundation
import PDFKit
import UniformTypeIdentifiers

enum DocumentTextLoader {
    enum LoadFailure: LocalizedError {
        case unreadable
        case empty
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "Could not read the selected document."
            case .empty:
                "The document did not contain any text."
            case .unsupported:
                "Only .docx, .pdf, and .txt files are supported."
            }
        }
    }

    static var supportedTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .utf8PlainText]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let txt = UTType(filenameExtension: "txt") { types.append(txt) }
        return types
    }

    static func loadText(from url: URL) throws -> String {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.lowercased()
        let text: String?

        switch ext {
        case "docx":
            text = try? DocxTextExtractor.extractText(from: url)
        case "pdf":
            text = textFromPDF(url)
        case "txt", "text":
            text = try? String(contentsOf: url, encoding: .utf8)
        default:
            if let type = UTType(filenameExtension: ext), type.conforms(to: .pdf) {
                text = textFromPDF(url)
            } else {
                throw LoadFailure.unsupported
            }
        }

        guard let text else { throw LoadFailure.unreadable }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LoadFailure.empty }
        return trimmed
    }

    private static func textFromPDF(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let joined = pages.joined(separator: "\n\n")
        return joined.isEmpty ? nil : joined
    }
}
