import SwiftUI

struct LogView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Logs", systemImage: "terminal")
        } description: {
            Text("Structured log viewer lands with T14 (error handling sweep).")
        }
        .navigationTitle("Logs")
    }
}
