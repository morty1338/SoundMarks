import Foundation

/// Writing a ZIP without compression. A `.soundmap` holds JPEGs (already compressed) and a small JSON,
/// so "store" is enough; the archive opens with any unpacker.
struct ZIPWriter {
    private var entries: [(name: String, data: Data)] = []

    mutating func add(_ data: Data, at path: String) {
        entries.append((path, data))
    }

    func build() -> Data {
        var output = Data()
        var directory = Data()

        for entry in entries {
            let offset = output.count
            let name = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)

            output.appendLE(UInt32(0x0403_4B50))
            output.appendLE(UInt16(20))       // version needed to extract
            output.appendLE(UInt16(0x0800))   // UTF-8 names
            output.appendLE(UInt16(0))        // no compression
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0x21))     // 1980-01-01
            output.appendLE(crc)
            output.appendLE(size)
            output.appendLE(size)
            output.appendLE(UInt16(name.count))
            output.appendLE(UInt16(0))
            output.append(name)
            output.append(entry.data)

            directory.appendLE(UInt32(0x0201_4B50))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(0x0800))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0x21))
            directory.appendLE(crc)
            directory.appendLE(size)
            directory.appendLE(size)
            directory.appendLE(UInt16(name.count))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt32(0))
            directory.appendLE(UInt32(offset))
            directory.append(name)
        }

        let directoryOffset = output.count
        output.append(directory)
        output.appendLE(UInt32(0x0605_4B50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(directory.count))
        output.appendLE(UInt32(directoryOffset))
        output.appendLE(UInt16(0))
        return output
    }
}

/// CRC-32 (IEEE 802.3), as ZIP requires.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func appendLE(_ value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
}
