import SwiftUI

struct UnlockView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var pin: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Unlock")
                .font(.title)

            SecureField("Enter PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }

            Button("Unlock with PIN") {
                authViewModel.unlockWithPIN(pin)
            }
            .buttonStyle(.borderedProminent)

            Button("Use Face ID / Touch ID") {
                authViewModel.unlockWithBiometrics()
            }

            Button("Forgot PIN?") {
                authViewModel.resetPassKeyWithBiometrics()
            }
            .foregroundColor(.red)
        }
        .padding()
    }
}

