import CryptoKit
import Foundation

/// Local artwork cache: memory (`NSCache`) + disk. Returns `Data`
/// so the value can freely cross actor boundaries. Decoded thumbnails live
/// in `ImagePipeline`.
actor ArtworkCache {
    static let shared = ArtworkCache()

    private let session: URLSession
    private let directory: URL
    /// Compressed artwork bytes; the system purges the cache itself under memory pressure.
    private let memory: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.countLimit = 300
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(session: URLSession = .metadata) {
        self.session = session
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        directory = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Artwork data. `nil` if loading failed — artwork isn't critical.
    func data(for url: URL) async -> Data? {
        if let cached = memory.object(forKey: url as NSURL) { return cached as Data }

        let file = fileURL(for: url)
        if let onDisk = try? Data(contentsOf: file) {
            store(onDisk, for: url)
            return onDisk
        }

        if let existing = inFlight[url] { return await existing.value }

        let task = Task<Data?, Never> { [session] in
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            return data
        }
        inFlight[url] = task

        let data = await task.value
        inFlight[url] = nil

        if let data {
            store(data, for: url)
            try? data.write(to: file, options: .atomic)
        }
        return data
    }

    /// Artwork if it is already in memory — for drawing a pin synchronously without flicker.
    func cachedData(for url: URL) -> Data? { memory.object(forKey: url as NSURL) as Data? }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func store(_ data: Data, for url: URL) {
        memory.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
    }

    private func fileURL(for url: URL) -> URL {
        // File name from a hash of the address — the iTunes path contains slashes. The hash is stable:
        // Swift's `hashValue` changes on every launch, and previously the disk never found yesterday's artwork.
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).img")
    }
}
