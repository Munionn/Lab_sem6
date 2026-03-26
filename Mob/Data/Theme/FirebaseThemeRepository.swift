import Foundation

final class FirebaseThemeRepository: ThemeRepository {
    func loadTheme(for userId: String) async throws -> Theme {
        // Placeholder implementation: return default theme.
        // Replace with Firestore / Realtime Database reads.
        return .default
    }

    func saveTheme(_ theme: Theme, for userId: String) async throws {
        // Placeholder implementation: no-op.
        // Replace with Firestore / Realtime Database writes.
    }
}

