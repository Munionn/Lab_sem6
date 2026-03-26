import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ThemeViewModel

    var body: some View {
        Form {
            Section("Colors") {
                ColorPicker("Primary", selection: Binding(
                    get: { viewModel.theme.primaryColor },
                    set: { viewModel.theme.primaryColor = $0 }
                ))
                ColorPicker("Secondary", selection: Binding(
                    get: { viewModel.theme.secondaryColor },
                    set: { viewModel.theme.secondaryColor = $0 }
                ))
                ColorPicker("Background", selection: Binding(
                    get: { viewModel.theme.backgroundColor },
                    set: { viewModel.theme.backgroundColor = $0 }
                ))
            }

            Section {
                Button("Save Theme") {
                    viewModel.save()
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            viewModel.load()
        }
    }
}

