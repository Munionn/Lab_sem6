import Foundation

final class CalculatorViewModel: ObservableObject {
    @Published var displayText: String = "0"
    @Published var errorText: String?

    private var state: CalculatorState = .initial
    private let engine = CalculatorEngine()
    private let historyRepository: HistoryRepository
    private let userId: String

    init(historyRepository: HistoryRepository, userId: String) {
        self.historyRepository = historyRepository
        self.userId = userId
    }

    func pressDigit(_ value: Int) {
        HapticsService.shared.tap()
        apply(input: .digit(value))
    }

    func pressDecimal() {
        HapticsService.shared.tap()
        apply(input: .decimalPoint)
    }

    func pressOperation(_ op: CalculatorOperation) {
        HapticsService.shared.tap()
        apply(input: .operation(op))
    }

    func pressEquals() {
        HapticsService.shared.tap()
        let previous = state
        apply(input: .equals)
        Task {
            await saveHistoryItemIfNeeded(previousState: previous, newState: state)
        }
    }

    func pressClear() {
        HapticsService.shared.tap()
        apply(input: .clear)
    }

    func deleteLastDigit() {
        guard !state.isEnteringNewNumber, !state.currentInput.isEmpty else { return }
        state.currentInput.removeLast()
        if state.currentInput.isEmpty {
            state.currentInput = "0"
            state.isEnteringNewNumber = true
        }
        syncFromState()
    }

    private func apply(input: CalculatorInput) {
        state = engine.handleInput(state: state, input: input)
        syncFromState()
    }

    private func syncFromState() {
        displayText = state.currentInput
        errorText = state.errorMessage
    }

    private func saveHistoryItemIfNeeded(previousState: CalculatorState, newState: CalculatorState) async {
        guard previousState.pendingOperation != nil,
              previousState.previousValue != nil,
              previousState.errorMessage == nil else { return }

        let expression = "\(previousState.previousValue ?? 0) \(symbol(for: previousState.pendingOperation)) \(Double(previousState.currentInput) ?? 0)"
        let item = CalculationHistoryItem(
            id: UUID().uuidString,
            expression: expression,
            result: newState.currentInput,
            timestamp: Date()
        )

        try? await historyRepository.append(item: item, for: userId)
    }

    private func symbol(for operation: CalculatorOperation?) -> String {
        guard let operation else { return "" }
        switch operation {
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        }
    }
}

