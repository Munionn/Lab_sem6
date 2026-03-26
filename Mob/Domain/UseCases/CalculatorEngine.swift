import Foundation

struct CalculatorEngine {
    func handleInput(state: CalculatorState, input: CalculatorInput) -> CalculatorState {
        switch input {
        case .digit(let value):
            return handleDigit(state: state, value: value)
        case .decimalPoint:
            return handleDecimalPoint(state: state)
        case .operation(let op):
            return handleOperation(state: state, operation: op)
        case .equals:
            return handleEquals(state: state)
        case .clear:
            return .initial
        }
    }

    private func handleDigit(state: CalculatorState, value: Int) -> CalculatorState {
        var newState = state
        newState.errorMessage = nil

        if newState.isEnteringNewNumber {
            newState.currentInput = "\(value)"
            newState.isEnteringNewNumber = false
        } else {
            if newState.currentInput == "0" {
                newState.currentInput = "\(value)"
            } else {
                newState.currentInput.append("\(value)")
            }
        }
        return newState
    }

    private func handleDecimalPoint(state: CalculatorState) -> CalculatorState {
        var newState = state
        newState.errorMessage = nil

        if newState.isEnteringNewNumber {
            newState.currentInput = "0."
            newState.isEnteringNewNumber = false
        } else if !newState.currentInput.contains(".") {
            newState.currentInput.append(".")
        }
        return newState
    }

    private func handleOperation(state: CalculatorState, operation: CalculatorOperation) -> CalculatorState {
        var newState = state
        newState.errorMessage = nil

        let currentValue = Double(newState.currentInput) ?? 0

        if let pending = newState.pendingOperation, let previous = newState.previousValue, !newState.isEnteringNewNumber {
            if let result = performOperation(lhs: previous, rhs: currentValue, operation: pending, state: &newState) {
                newState.previousValue = result
                newState.currentInput = format(result)
            } else {
                // error already set
                return newState
            }
        } else {
            newState.previousValue = currentValue
        }

        newState.pendingOperation = operation
        newState.isEnteringNewNumber = true
        return newState
    }

    private func handleEquals(state: CalculatorState) -> CalculatorState {
        var newState = state
        newState.errorMessage = nil

        guard let pending = newState.pendingOperation, let previous = newState.previousValue else {
            return newState
        }

        let currentValue = Double(newState.currentInput) ?? 0
        if let result = performOperation(lhs: previous, rhs: currentValue, operation: pending, state: &newState) {
            newState.currentInput = format(result)
            newState.previousValue = nil
            newState.pendingOperation = nil
            newState.isEnteringNewNumber = true
        }

        return newState
    }

    private func performOperation(lhs: Double, rhs: Double, operation: CalculatorOperation, state: inout CalculatorState) -> Double? {
        switch operation {
        case .add:
            return lhs + rhs
        case .subtract:
            return lhs - rhs
        case .multiply:
            return lhs * rhs
        case .divide:
            if rhs == 0 {
                state.errorMessage = "Cannot divide by zero"
                return nil
            }
            return lhs / rhs
        }
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        } else {
            return String(value)
        }
    }
}

