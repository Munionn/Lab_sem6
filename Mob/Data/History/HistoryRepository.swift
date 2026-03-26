import Foundation

protocol HistoryRepository {
    func loadHistory(for userId: String) async throws -> [CalculationHistoryItem]
    func append(item: CalculationHistoryItem, for userId: String) async throws
    func clear(for userId: String) async throws
}

