//
//  DocxTextExtractor.swift
//  Text-to-Transcript
//
//  Created by Prisha Marpu on 7/1/26.
//


import Foundation
import zlib

enum DocxTextExtractor {
    enum ExtractFailure: Error {
        case invalidArchive
        case missingDocumentXML
        case decompressionFailed
    }

    static func extractText(from url: URL) throws -> String {
        let zipData = try Data(contentsOf: url)
        guard let xmlData = extractEntry(named: "word/document.xml", from: zipData) else {
            throw ExtractFailure.missingDocumentXML
        }
        guard let xml = String(data: xmlData, encoding: .utf8) else {
            throw ExtractFailure.invalidArchive
        }
        return plainText(from: xml)
    }

    private static func plainText(from xml: String) -> String {
        var text = xml
        text = text.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<w:tab/>", with: "\t")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func extractEntry(named entryName: String, from zipData: Data) -> Data? {
        var offset = 0
        while offset + 30 <= zipData.count {
            guard zipData[offset] == 0x50, zipData[offset + 1] == 0x4b,
                  zipData[offset + 2] == 0x03, zipData[offset + 3] == 0x04 else {
                break
            }

            let compressionMethod = zipData.readUInt16(at: offset + 8)
            let compressedSize = Int(zipData.readUInt32(at: offset + 18))
            let fileNameLength = Int(zipData.readUInt16(at: offset + 26))
            let extraFieldLength = Int(zipData.readUInt16(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= zipData.count else { break }

            let name = String(data: zipData[nameStart..<nameEnd], encoding: .utf8) ?? ""
            let dataStart = nameEnd + extraFieldLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= zipData.count else { break }

            if name == entryName {
                let compressed = zipData[dataStart..<dataEnd]
                switch compressionMethod {
                case 0:
                    return Data(compressed)
                case 8:
                    return decompressDeflate(Data(compressed))
                default:
                    return nil
                }
            }

            offset = dataEnd
        }
        return nil
    }

    private static func decompressDeflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16_384

        let inflateStatus: Int32 = data.withUnsafeBytes { inputBuffer in
            guard let inputPointer = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer(mutating: inputPointer)
            stream.avail_in = uInt(data.count)

            var status: Int32 = Z_OK
            while status == Z_OK {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                let produced: Int = chunk.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_SYNC_FLUSH)
                    return chunkSize - Int(stream.avail_out)
                }
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
                if status == Z_STREAM_END { break }
                if status != Z_OK { break }
            }
            return status
        }

        guard inflateStatus == Z_STREAM_END || inflateStatus == Z_OK, !output.isEmpty else {
            return nil
        }
        return output
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
