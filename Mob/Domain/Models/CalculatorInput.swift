import Foundation

enum CalculatorInput {
    case digit(Int)
    case decimalPoint
    case operation(CalculatorOperation)
    case equals
    case clear
}

