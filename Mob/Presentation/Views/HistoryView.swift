import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.expression)
                        .font(.subheadline)
                    Text("= \(item.result)")
                        .font(.headline)
                    Text(item.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("History")
        .toolbar {
            Button("Clear") {
                viewModel.clear()
            }
        }
        .onAppear {
            viewModel.load()
        }
    }
}

