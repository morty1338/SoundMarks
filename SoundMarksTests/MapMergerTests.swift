import Foundation
import Testing

@testable import SoundMarks

/// Merging shared maps: UUID, last-writer-wins, deletions via markers.
@Suite("MapMerger")
struct MapMergerTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func place(_ id: UUID = UUID(), note: String? = nil, minutes: Double = 0,
                       tombstone: Bool = false) -> PlaceDTO {
        PlaceDTO(id: id, latitude: 52.5, longitude: 13.4, placeName: nil, city: nil, country: nil,
                 createdAt: base, updatedAt: base.addingTimeInterval(minutes * 60),
                 eventYear: 2024, eventMonth: nil, eventDay: nil, note: note,
                 authorProfileId: nil, isTombstoned: tombstone, track: nil, media: [])
    }

    @Test("A friend's new place is added")
    func addsUnknown() {
        let incoming = place()
        let plan = MapMerger.plan(local: [place()], incoming: [incoming])
        #expect(plan.apply == [incoming])
    }

    @Test("The later edit wins")
    func newerWins() {
        let id = UUID()
        let plan = MapMerger.plan(local: [place(id, note: "old", minutes: 0)],
                                  incoming: [place(id, note: "new", minutes: 5)])
        #expect(plan.apply.first?.note == "new")
    }

    @Test("An outdated edit is ignored")
    func olderIgnored() {
        let id = UUID()
        let plan = MapMerger.plan(local: [place(id, note: "new", minutes: 10)],
                                  incoming: [place(id, note: "old", minutes: 5)])
        #expect(plan.apply.isEmpty)
        #expect(plan.ignored == 1)
    }

    @Test("A deletion later than an edit deletes the place")
    func newerTombstoneDeletes() {
        let id = UUID()
        let merged = MapMerger.merged(local: [place(id, minutes: 0)],
                                      incoming: [place(id, minutes: 3, tombstone: true)])
        #expect(merged.first?.isTombstoned == true)
    }

    @Test("An edit later than a deletion brings the place back")
    func editAfterDeleteRevives() {
        let id = UUID()
        let merged = MapMerger.merged(local: [place(id, minutes: 3, tombstone: true)],
                                      incoming: [place(id, note: "restored", minutes: 8)])
        #expect(merged.first?.isTombstoned == false)
        #expect(merged.first?.note == "restored")
    }

    @Test("An unknown marker is kept so the place does not come back to life")
    func unknownTombstoneKept() {
        let tombstone = place(minutes: 1, tombstone: true)
        #expect(MapMerger.plan(local: [], incoming: [tombstone]).apply == [tombstone])
    }

    @Test("With equal times the local version stays")
    func tieKeepsLocal() {
        let id = UUID()
        let plan = MapMerger.plan(local: [place(id, note: "mine", minutes: 1)],
                                  incoming: [place(id, note: "theirs", minutes: 1)])
        #expect(plan.apply.isEmpty)
    }

    @Test("After the exchange both sides converge to the same result")
    func convergence() {
        let shared = UUID()
        let a = [place(shared, note: "A", minutes: 2), place(note: "only A", minutes: 1)]
        let b = [place(shared, note: "B", minutes: 4), place(note: "only B", minutes: 1)]

        let onA = MapMerger.merged(local: a, incoming: b)
        let onB = MapMerger.merged(local: b, incoming: a)
        #expect(onA == onB)
        #expect(onA.count == 3)
        #expect(onA.first { $0.id == shared }?.note == "B")
    }

    @Test("Only changes since the last sync are sent")
    func changesSince() {
        let places = [place(minutes: 1), place(minutes: 10), place(minutes: 20, tombstone: true)]
        let changed = MapMerger.changes(in: places, since: base.addingTimeInterval(5 * 60))
        #expect(changed.count == 2)
        #expect(MapMerger.changes(in: places, since: nil).count == 3)
    }
}

/// ZIP writing for `.soundmap`: readable by our own reader, correct CRC.
@Suite("ZIPWriter")
struct ZIPWriterTests {
    @Test("CRC-32 matches the reference")
    func crcReference() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test("A written archive reads back")
    func roundTrip() throws {
        var writer = ZIPWriter()
        let manifest = Data("{\"formatVersion\":1}".utf8)
        let photo = Data((0..<5000).map { UInt8($0 % 251) })
        writer.add(manifest, at: "manifest.json")
        writer.add(photo, at: "photos/ÄÖÜ-foto-ß.jpg")

        let archive = try ZIPArchive(data: writer.build())
        #expect(archive.entries.map(\.path) == ["manifest.json", "photos/ÄÖÜ-foto-ß.jpg"])
        #expect(try archive.contents(of: archive.entries[0]) == manifest)
        #expect(try archive.contents(of: archive.entries[1]) == photo)
    }
}
