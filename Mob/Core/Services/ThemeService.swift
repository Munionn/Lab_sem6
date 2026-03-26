import SwiftUI

final class ThemeService: ObservableObject {
    @Published var currentTheme: Theme = .default

    func apply(theme: Theme) {
        currentTheme = theme
    }
}

