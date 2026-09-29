import Foundation

/// Map snapshot for sending to a friend — nearby via MultipeerConnectivity
/// or remotely as a `.soundmap` file. The format is the same.
struct SoundmapManifest: Codable, Sendable {
    static let currentFormat = 1

    var formatVersion = SoundmapManifest.currentFormat
    var createdAt: Date
    /// Sender. The import is accepted only if they're a friend and not blocked.
    var sender: ProfileDTO
    var map: MapDTO
    /// Places changed since the last sync, including deletion markers.
    var places: [PlaceDTO]
}

struct ProfileDTO: Codable, Hashable, Sendable {
    var id: UUID
    var nickname: String
    var uniqueCode: String
    var avatarColorHex: String?
    /// Path to the avatar inside the archive.
    var avatarFile: String?
    /// Turned off — my planet is deleted on the friend's side during sync.
    var planetVisible: Bool
}

struct MapDTO: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The sender's planet — becomes a friend's map for the recipient.
        case planet
        /// Shared map.
        case shared
    }

    var id: UUID
    var name: String
    var kind: Kind
    var ownerProfileId: UUID
    var participantIDs: [UUID]
    var updatedAt: Date
}

struct PlaceDTO: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var placeName: String?
    var city: String?
    var country: String?
    var createdAt: Date
    var updatedAt: Date
    var eventYear: Int
    var eventMonth: Int?
    var eventDay: Int?
    var note: String?
    var authorProfileId: UUID?
    var isTombstoned: Bool
    var track: TrackDTO?
    var media: [MediaDTO]
    /// The author's record skin. Older files don't have the field — then the default skin.
    var skinID: String? = nil
}

struct TrackDTO: Codable, Hashable, Sendable {
    var title: String
    var artist: String
    var album: String?
    var artworkURL: String?
    var previewURL: String?
    var spotifyURI: String?
    var source: String
}

struct MediaDTO: Codable, Hashable, Sendable {
    var id: UUID
    var kind: String
    var takenAt: Date?
    var order: Int
    /// Path to the compressed JPEG inside the archive. For a video — only the preview frame.
    var file: String?
}

extension JSONEncoder {
    static let soundmap: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let soundmap: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
