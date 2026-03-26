import SwiftUI

@main
struct CalcProApp: App {
    @StateObject private var themeService = ThemeService()
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        FirebaseManager.configureIfAvailable()
        NotificationService.shared.registerForRemoteNotificationsIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(themeService)
                .environmentObject(authViewModel)
                .preferredColorScheme(themeService.currentTheme.preferredColorScheme)
        }
    }
}

