import Foundation

final class FirebaseHistoryRepository: HistoryRepository {
    func loadHistory(for userId: String) async throws -> [CalculationHistoryItem] {
        // Placeholder implementation: returns empty list.
        // Replace with Firestore reads.
        return []
    }

    func append(item: CalculationHistoryItem, for userId: String) async throws {
        // Placeholder implementation: no-op.
        // Replace with Firestore writes.
    }

    func clear(for userId: String) async throws {
        // Placeholder implementation: no-op.
        // Replace with Firestore deletes.
    }
}

