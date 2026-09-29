import Foundation

/// Lazy service holder.
///
/// Heavy system objects — `CLLocationManager`, a `URLSession` with a disk
/// cache, PhotoKit, the notification center — are created on first use,
/// not at app launch: otherwise all of that runs before the first frame.
@MainActor
final class LazyService<Value> {
    private let make: @MainActor () -> Value
    private var cached: Value?

    init(_ make: @escaping @MainActor () -> Value) {
        self.make = make
    }

    var value: Value {
        if let cached { return cached }
        let created = make()
        cached = created
        return created
    }

    /// Whether the service was already created — so it isn't woken up just to check state.
    var isCreated: Bool { cached != nil }
}
