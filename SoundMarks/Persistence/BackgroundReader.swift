import CoreData
import Foundation

/// Reading from the store off the main thread: its own background context, results are `Sendable` values.
final class BackgroundReader: @unchecked Sendable {
    // The context is touched only inside `perform` — on its own queue.
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func read<Value: Sendable>(_ body: @escaping @Sendable (NSManagedObjectContext) throws -> Value) async throws -> Value {
        let context = context
        return try await context.perform { try body(context) }
    }
}
