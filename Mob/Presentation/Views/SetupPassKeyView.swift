import SwiftUI

struct SetupPassKeyView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var pin: String = ""
    @State private var confirmation: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Up PIN")
                .font(.title)

            SecureField("Enter PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            SecureField("Confirm PIN", text: $confirmation)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }

            Button("Save PIN") {
                authViewModel.setupPassKey(pin: pin, confirmation: confirmation)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

