import Compression
import Foundation
import Testing

@testable import SoundMarks

/// ZIP reading is written by hand, so it's checked against archives built right here.
@Suite("ZIPArchive")
struct ZIPArchiveTests {
    @Test("An uncompressed entry is read")
    func storedEntry() throws {
        let payload = Data("hello, this is JSON".utf8)
        let zip = ZIPBuilder().adding(name: "a.json", contents: payload, compressed: false).build()

        let archive = try ZIPArchive(data: zip)
        #expect(archive.entries.map(\.path) == ["a.json"])
        #expect(try archive.contents(of: #require(archive.entries.first)) == payload)
    }

    @Test("A compressed entry is decompressed")
    func deflatedEntry() throws {
        // Long repetitive text is guaranteed to compress.
        let payload = Data(String(repeating: "Streaming_History_Audio ", count: 500).utf8)
        let zip = ZIPBuilder().adding(name: "b.json", contents: payload, compressed: true).build()

        let archive = try ZIPArchive(data: zip)
        let entry = try #require(archive.entries.first)
        #expect(entry.compressionMethod == 8)
        #expect(entry.compressedSize < entry.uncompressedSize)
        #expect(try archive.contents(of: entry) == payload)
    }

    @Test("Several entries are read separately")
    func multipleEntries() throws {
        let first = Data(String(repeating: "one", count: 200).utf8)
        let second = Data("two".utf8)
        let zip = ZIPBuilder()
            .adding(name: "dir/first.json", contents: first, compressed: true)
            .adding(name: "dir/second.json", contents: second, compressed: false)
            .build()

        let archive = try ZIPArchive(data: zip)
        #expect(archive.entries.map(\.path) == ["dir/first.json", "dir/second.json"])
        #expect(try archive.contents(of: archive.entries[0]) == first)
        #expect(try archive.contents(of: archive.entries[1]) == second)
    }

    @Test("An empty entry doesn't break reading")
    func emptyEntry() throws {
        let zip = ZIPBuilder().adding(name: "empty.json", contents: Data(), compressed: false).build()
        let archive = try ZIPArchive(data: zip)
        #expect(try archive.contents(of: #require(archive.entries.first)).isEmpty)
    }

    @Test("A non-ZIP is rejected with a clear error")
    func rejectsNonZIP() {
        #expect(throws: ZIPArchive.Failure.self) {
            _ = try ZIPArchive(data: Data(repeating: 0, count: 100))
        }
    }

    @Test("ZIP errors have a human-readable description")
    func failuresAreReadable() {
        let failures: [ZIPArchive.Failure] = [
            .notAZIP, .unsupportedZIP64, .unsupportedCompression(99), .corrupted("x"),
        ]
        for failure in failures {
            #expect(failure.errorDescription?.isEmpty == false)
        }
    }
}

/// Minimal ZIP builder for tests: local headers, central directory, EOCD.
struct ZIPBuilder {
    private struct Item {
        let name: String
        let stored: Data
        let originalSize: Int
        let method: UInt16
    }

    private var items: [Item] = []

    func adding(name: String, contents: Data, compressed: Bool) -> ZIPBuilder {
        var copy = self
        if compressed, let deflated = Self.deflate(contents), deflated.count < contents.count {
            copy.items.append(Item(name: name, stored: deflated,
                                   originalSize: contents.count, method: 8))
        } else {
            copy.items.append(Item(name: name, stored: contents,
                                   originalSize: contents.count, method: 0))
        }
        return copy
    }

    func build() -> Data {
        var output = Data()
        var directory = Data()
        var offsets: [Int] = []

        for item in items {
            offsets.append(output.count)
            let name = Data(item.name.utf8)

            output.append(uint32: 0x0403_4B50)
            output.append(uint16: 20)
            output.append(uint16: 0)
            output.append(uint16: item.method)
            output.append(uint16: 0)
            output.append(uint16: 0)
            output.append(uint32: 0) // CRC32 isn't checked by the reader
            output.append(uint32: UInt32(item.stored.count))
            output.append(uint32: UInt32(item.originalSize))
            output.append(uint16: UInt16(name.count))
            output.append(uint16: 0)
            output.append(name)
            output.append(item.stored)
        }

        for (index, item) in items.enumerated() {
            let name = Data(item.name.utf8)
            directory.append(uint32: 0x0201_4B50)
            directory.append(uint16: 20)
            directory.append(uint16: 20)
            directory.append(uint16: 0)
            directory.append(uint16: item.method)
            directory.append(uint16: 0)
            directory.append(uint16: 0)
            directory.append(uint32: 0)
            directory.append(uint32: UInt32(item.stored.count))
            directory.append(uint32: UInt32(item.originalSize))
            directory.append(uint16: UInt16(name.count))
            directory.append(uint16: 0)
            directory.append(uint16: 0)
            directory.append(uint16: 0)
            directory.append(uint16: 0)
            directory.append(uint32: 0)
            directory.append(uint32: UInt32(offsets[index]))
            directory.append(name)
        }

        let directoryOffset = output.count
        output.append(directory)

        output.append(uint32: 0x0605_4B50)
        output.append(uint16: 0)
        output.append(uint16: 0)
        output.append(uint16: UInt16(items.count))
        output.append(uint16: UInt16(items.count))
        output.append(uint32: UInt32(directory.count))
        output.append(uint32: UInt32(directoryOffset))
        output.append(uint16: 0)

        return output
    }

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 64
        var destination = Data(count: capacity)

        let written = destination.withUnsafeMutableBytes { output -> Int in
            guard let outputBase = output.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { input -> Int in
                guard let inputBase = input.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(outputBase, capacity,
                                                 inputBase, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return destination.prefix(written)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8(value >> 8 & 0xFF),
            UInt8(value >> 16 & 0xFF),
            UInt8(value >> 24 & 0xFF),
        ])
    }
}
