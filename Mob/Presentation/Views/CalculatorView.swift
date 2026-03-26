import SwiftUI

struct CalculatorView: View {
    @ObservedObject var viewModel: CalculatorViewModel
    @EnvironmentObject var themeService: ThemeService

    private let buttonSpacing: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: buttonSpacing) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(viewModel.displayText)
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(themeService.currentTheme.primaryColor)

                    if let error = viewModel.errorText {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding()

                let buttonHeight = (geometry.size.height - 140) / 5

                VStack(spacing: buttonSpacing) {
                    HStack(spacing: buttonSpacing) {
                        calcButton(title: "C", background: .gray.opacity(0.3)) {
                            viewModel.pressClear()
                        }
                        .frame(height: buttonHeight)

                        calcButton(title: "÷", background: .orange) {
                            viewModel.pressOperation(.divide)
                        }
                        .frame(height: buttonHeight)
                    }

                    HStack(spacing: buttonSpacing) {
                        numberButton("7", height: buttonHeight)
                        numberButton("8", height: buttonHeight)
                        numberButton("9", height: buttonHeight)
                        opButton("×", op: .multiply, height: buttonHeight)
                    }

                    HStack(spacing: buttonSpacing) {
                        numberButton("4", height: buttonHeight)
                        numberButton("5", height: buttonHeight)
                        numberButton("6", height: buttonHeight)
                        opButton("−", op: .subtract, height: buttonHeight)
                    }

                    HStack(spacing: buttonSpacing) {
                        numberButton("1", height: buttonHeight)
                        numberButton("2", height: buttonHeight)
                        numberButton("3", height: buttonHeight)
                        opButton("+", op: .add, height: buttonHeight)
                    }

                    HStack(spacing: buttonSpacing) {
                        calcButton(title: "0") {
                            viewModel.pressDigit(0)
                        }
                        .frame(height: buttonHeight)

                        calcButton(title: ".") {
                            viewModel.pressDecimal()
                        }
                        .frame(height: buttonHeight)

                        calcButton(title: "=") {
                            viewModel.pressEquals()
                        }
                        .frame(height: buttonHeight)
                    }
                }
                .padding(.horizontal)
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                viewModel.deleteLastDigit()
                            }
                        }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themeService.currentTheme.backgroundColor.ignoresSafeArea())
        }
    }

    private func numberButton(_ title: String, height: CGFloat) -> some View {
        calcButton(title: title) {
            if let value = Int(title) {
                viewModel.pressDigit(value)
            }
        }
        .frame(height: height)
    }

    private func opButton(_ title: String, op: CalculatorOperation, height: CGFloat) -> some View {
        calcButton(title: title, background: .orange) {
            viewModel.pressOperation(op)
        }
        .frame(height: height)
    }

    private func calcButton(title: String, background: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.white)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

