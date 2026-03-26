import Foundation

struct CalculationHistoryItem: Identifiable, Codable {
    let id: String
    let expression: String
    let result: String
    let timestamp: Date
}

