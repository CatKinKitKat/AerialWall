import SwiftUI

struct RenameSheet: View {
    let target: WallpaperViewModel
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var name: String

    init(target: WallpaperViewModel, onCancel: @escaping () -> Void,
         onConfirm: @escaping (String) -> Void) {
        self.target = target
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self._name = State(initialValue: target.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Wallpaper")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { submit() }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
    }
}
