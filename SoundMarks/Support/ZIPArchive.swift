import Compression
import Foundation

/// Minimal ZIP reading: the central directory plus decompression
/// of the "store" and "deflate" methods via the system `Compression`.
///
/// Our own implementation instead of a dependency — the Spotify export archive is a plain ZIP
/// with JSON inside, and a full library isn't needed for it.
struct ZIPArchive {
    struct Entry {
        let path: String
        let compressedSize: Int
        let uncompressedSize: Int
        let compressionMethod: UInt16
        let localHeaderOffset: Int

        var isDirectory: Bool { path.hasSuffix("/") }
    }

    enum Failure: LocalizedError {
        case notAZIP
        case unsupportedZIP64
        case unsupportedCompression(UInt16)
        case corrupted(String)

        var errorDescription: String? {
            switch self {
            case .notAZIP:
                String(localized: "error.zip.notAZIP", defaultValue: "That isn’t a ZIP archive.")
            case .unsupportedZIP64:
                String(localized: "error.zip.zip64", defaultValue: "The archive is too large (ZIP64) — unpack it yourself and hand over the JSON files.")
            case .unsupportedCompression:
                String(localized: "error.zip.compression", defaultValue: "The archive uses an unknown compression method.")
            case .corrupted:
                String(localized: "error.zip.corrupted", defaultValue: "The archive is damaged.")
            }
        }
    }

    private let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        self.data = data
        entries = try Self.readCentralDirectory(in: data)
    }

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Decompressed contents of an entry.
    func contents(of entry: Entry) throws -> Data {
        // The name and "extra" in the local header may differ from the directory,
        // so the lengths are read from there.
        let header = entry.localHeaderOffset
        guard data.count >= header + 30,
              read32(at: header) == 0x0403_4B50
        else { throw Failure.corrupted("local header") }

        let nameLength = Int(read16(at: header + 26))
        let extraLength = Int(read16(at: header + 28))
        let start = header + 30 + nameLength + extraLength
        let end = start + entry.compressedSize

        guard end <= data.count else { throw Failure.corrupted("payload out of bounds") }
        let payload = data.subdata(in: start..<end)

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return try inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw Failure.unsupportedCompression(entry.compressionMethod)
        }
    }

    // MARK: - Central directory

    private static func readCentralDirectory(in data: Data) throws -> [Entry] {
        guard data.count > 22 else { throw Failure.notAZIP }

        // End of Central Directory is searched from the end: it may be followed by a comment of up to 64 KB.
        let searchLimit = min(data.count, 22 + 0xFFFF)
        var eocd: Int?
        for offset in stride(from: data.count - 22, through: data.count - searchLimit, by: -1) {
            if read32(in: data, at: offset) == 0x0605_4B50 {
                eocd = offset
                break
            }
        }
        guard let eocd else { throw Failure.notAZIP }

        let entryCount = Int(read16(in: data, at: eocd + 10))
        let directoryOffset = Int(read32(in: data, at: eocd + 16))
        guard directoryOffset != 0xFFFF_FFFF, entryCount != 0xFFFF else { throw Failure.unsupportedZIP64 }
        guard directoryOffset < data.count else { throw Failure.corrupted("central directory offset") }

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        var cursor = directoryOffset

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, read32(in: data, at: cursor) == 0x0201_4B50 else {
                throw Failure.corrupted("central directory entry")
            }

            let method = read16(in: data, at: cursor + 10)
            let compressed = Int(read32(in: data, at: cursor + 20))
            let uncompressed = Int(read32(in: data, at: cursor + 24))
            let nameLength = Int(read16(in: data, at: cursor + 28))
            let extraLength = Int(read16(in: data, at: cursor + 30))
            let commentLength = Int(read16(in: data, at: cursor + 32))
            let localOffset = Int(read32(in: data, at: cursor + 42))

            guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else {
                throw Failure.unsupportedZIP64
            }

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { throw Failure.corrupted("entry name") }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLength)), as: UTF8.self)

            entries.append(Entry(path: name,
                                 compressedSize: compressed,
                                 uncompressedSize: uncompressed,
                                 compressionMethod: method,
                                 localHeaderOffset: localOffset))

            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    // MARK: - Decompression

    private func inflate(_ payload: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }

        var output = Data(count: expectedSize)
        let written: Int = try output.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                throw Failure.corrupted("destination buffer")
            }
            return payload.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB in the Apple implementation is "raw" DEFLATE, as in ZIP.
                return compression_decode_buffer(destinationBase, expectedSize,
                                                 sourceBase, payload.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }

        guard written == expectedSize else { throw Failure.corrupted("inflate size mismatch") }
        return output
    }

    // MARK: - Reading numbers

    private func read16(at offset: Int) -> UInt16 { Self.read16(in: data, at: offset) }
    private func read32(at offset: Int) -> UInt32 { Self.read32(in: data, at: offset) }

    private static func read16(in data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func read32(in data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base])
            | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16
            | UInt32(data[base + 3]) << 24
    }
}
