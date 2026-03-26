import Foundation

struct CalculatorState {
    var currentInput: String = "0"
    var previousValue: Double?
    var pendingOperation: CalculatorOperation?
    var isEnteringNewNumber: Bool = true
    var errorMessage: String?

    static let initial = CalculatorState()
}

