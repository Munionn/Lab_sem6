import Foundation

protocol ThemeRepository {
    func loadTheme(for userId: String) async throws -> Theme
    func saveTheme(_ theme: Theme, for userId: String) async throws
}

