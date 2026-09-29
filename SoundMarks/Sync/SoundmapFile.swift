import Foundation
import UniformTypeIdentifiers

/// The `.soundmap` exchange file: a ZIP with `manifest.json` and compressed photo JPEGs.
enum SoundmapFile {
    static let fileExtension = "soundmap"
    static let type = UTType(exportedAs: "com.bibadev.musicmap.soundmap", conformingTo: .data)
    static let manifestPath = "manifest.json"

    enum Failure: LocalizedError {
        case unreadable
        case newerFormat

        var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "error.soundmap.unreadable", defaultValue: "Couldn't read the map file.")
            case .newerFormat:
                String(localized: "error.soundmap.newerFormat",
                       defaultValue: "This file was made by a newer version of the app — please update the app.")
            }
        }
    }

    static func write(manifest: SoundmapManifest, files: [String: Data]) throws -> Data {
        var writer = ZIPWriter()
        writer.add(try JSONEncoder.soundmap.encode(manifest), at: manifestPath)
        for (path, data) in files.sorted(by: { $0.key < $1.key }) {
            writer.add(data, at: path)
        }
        return writer.build()
    }

    static func read(_ data: Data) throws -> (manifest: SoundmapManifest, files: [String: Data]) {
        let archive: ZIPArchive
        do {
            archive = try ZIPArchive(data: data)
        } catch {
            throw Failure.unreadable
        }

        var files: [String: Data] = [:]
        var manifestData: Data?
        for entry in archive.entries where !entry.isDirectory {
            let contents = try archive.contents(of: entry)
            if entry.path == manifestPath {
                manifestData = contents
            } else {
                files[entry.path] = contents
            }
        }

        guard let manifestData,
              let manifest = try? JSONDecoder.soundmap.decode(SoundmapManifest.self, from: manifestData)
        else { throw Failure.unreadable }
        guard manifest.formatVersion <= SoundmapManifest.currentFormat else { throw Failure.newerFormat }
        return (manifest, files)
    }
}
