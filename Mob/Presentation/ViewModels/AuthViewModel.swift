import Foundation
import CryptoKit

enum AuthState {
    case needsSetup
    case locked
    case unlocked
}

final class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .locked
    @Published var errorMessage: String?

    private let keychain = KeychainService.shared

    init() {
        Task { await determineInitialState() }
    }

    @MainActor
    private func determineInitialState() async {
        if (try? keychain.loadPassKeyHash()) == nil {
            authState = .needsSetup
        } else {
            authState = .locked
        }
    }

    func setupPassKey(pin: String, confirmation: String) {
        guard pin == confirmation, !pin.isEmpty else {
            errorMessage = "PINs do not match"
            return
        }

        let hash = hashPIN(pin)
        do {
            try keychain.savePassKeyHash(hash)
            errorMessage = nil
            authState = .unlocked
        } catch {
            errorMessage = "Failed to save PIN"
        }
    }

    func unlockWithPIN(_ pin: String) {
        guard let stored = try? keychain.loadPassKeyHash() else {
            authState = .needsSetup
            return
        }

        let hash = hashPIN(pin)
        if hash == stored {
            errorMessage = nil
            authState = .unlocked
        } else {
            errorMessage = "Incorrect PIN"
        }
    }

    func unlockWithBiometrics() {
        Task {
            let success = await BiometricAuthService.shared.authenticate(reason: "Unlock calculator")
            await MainActor.run {
                if success {
                    self.errorMessage = nil
                    self.authState = .unlocked
                } else {
                    self.errorMessage = "Biometric authentication failed"
                }
            }
        }
    }

    func resetPassKeyWithBiometrics() {
        Task {
            let success = await BiometricAuthService.shared.authenticate(reason: "Reset pass key")
            if success {
                try? keychain.deletePassKey()
                await MainActor.run {
                    self.authState = .needsSetup
                    self.errorMessage = nil
                }
            }
        }
    }

    private func hashPIN(_ pin: String) -> Data {
        let data = Data(pin.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
    }
}

