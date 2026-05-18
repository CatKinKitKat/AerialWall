import SwiftUI
import AerialWallKit

struct ImportSheet: View {
    let draft: ImportDraft
    let onCancel: () -> Void
    let onContinue: (ImportMetadata) -> Void

    @State private var name: String
    @State private var descText: String
    @FocusState private var focusedField: Field?

    private enum Field { case name, description }

    init(draft: ImportDraft, onCancel: @escaping () -> Void,
         onContinue: @escaping (ImportMetadata) -> Void) {
        self.draft = draft
        self.onCancel = onCancel
        self.onContinue = onContinue
        self._name = State(initialValue: draft.suggestedName)
        self._descText = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Wallpaper")
                .font(.title2).bold()

            HStack(alignment: .top, spacing: 16) {
                thumbnail
                    .frame(width: 200, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 8))   // V34

                VStack(alignment: .leading, spacing: 10) {
                    LabeledField(label: "Name") {
                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .description }
                    }
                    LabeledField(label: "Description") {
                        TextField("Optional", text: $descText, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .description)
                    }
                    Text("Category: \(Constants.AerialWallCategory.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Text("\(draft.sourceResolution) · \(draft.durationString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Exit", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            // Belt and suspenders: explicit focus once the sheet is on screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedField = .name
            }
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onContinue(ImportMetadata(
            name: trimmed,
            description: descText.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = NSImage(contentsOf: draft.previewThumbnailPath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .overlay {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            content
        }
    }
}
