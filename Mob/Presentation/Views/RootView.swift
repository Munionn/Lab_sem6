import SwiftUI

struct RootView: View {
    @EnvironmentObject var themeService: ThemeService
    @EnvironmentObject var authViewModel: AuthViewModel

    private let userId = "local-user"
    private let historyRepository = FirebaseHistoryRepository()
    private let themeRepository = FirebaseThemeRepository()

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .needsSetup:
                SetupPassKeyView()
            case .locked:
                UnlockView()
            case .unlocked:
                mainContent
            }
        }
    }

    private var mainContent: some View {
        let calculatorVM = CalculatorViewModel(historyRepository: historyRepository, userId: userId)
        let themeVM = ThemeViewModel(repository: themeRepository, userId: userId, themeService: themeService)
        let historyVM = HistoryViewModel(repository: historyRepository, userId: userId)

        return NavigationStack {
            CalculatorView(viewModel: calculatorVM)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        NavigationLink(destination: HistoryView(viewModel: historyVM)) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        NavigationLink(destination: SettingsView(viewModel: themeVM)) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
    }
}

