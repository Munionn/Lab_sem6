import Foundation

final class HistoryViewModel: ObservableObject {
    @Published var items: [CalculationHistoryItem] = []

    private let repository: HistoryRepository
    private let userId: String

    init(repository: HistoryRepository, userId: String) {
        self.repository = repository
        self.userId = userId
    }

    func load() {
        Task {
            if let loaded = try? await repository.loadHistory(for: userId) {
                await MainActor.run {
                    self.items = loaded.sorted { $0.timestamp > $1.timestamp }
                }
            }
        }
    }

    func clear() {
        Task {
            try? await repository.clear(for: userId)
            await MainActor.run {
                self.items = []
            }
        }
    }
}

