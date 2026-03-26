import Foundation

final class ThemeViewModel: ObservableObject {
    @Published var theme: Theme = .default

    private let repository: ThemeRepository
    private let userId: String
    private let themeService: ThemeService

    init(repository: ThemeRepository, userId: String, themeService: ThemeService) {
        self.repository = repository
        self.userId = userId
        self.themeService = themeService
        self.theme = themeService.currentTheme
    }

    func load() {
        Task {
            if let loaded = try? await repository.loadTheme(for: userId) {
                await MainActor.run {
                    self.theme = loaded
                    self.themeService.apply(theme: loaded)
                }
            }
        }
    }

    func save() {
        let themeToSave = theme
        Task {
            try? await repository.saveTheme(themeToSave, for: userId)
            await MainActor.run {
                self.themeService.apply(theme: themeToSave)
            }
        }
    }
}

