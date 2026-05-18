import SwiftUI
import AerialWallKit

struct ImportSheet: View {
    let draft: ImportDraft
    let onCancel: () -> Void
    let onContinue: (ImportMetadata) -> Void

    @State private var name: String
    @State private var descText: String
    @State private var categoryID: String
    @State private var options: [CategoryOption]

    init(draft: ImportDraft, onCancel: @escaping () -> Void,
         onContinue: @escaping (ImportMetadata) -> Void) {
        self.draft = draft
        self.onCancel = onCancel
        self.onContinue = onContinue

        let opts = CategoryCatalog.availableOptions()
        self._options = State(initialValue: opts)
        self._categoryID = State(initialValue: CategoryCatalog.defaultOption(in: opts)?.id ?? "")
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))    // V34: the one allowed tweak

                VStack(alignment: .leading, spacing: 10) {
                    LabeledField(label: "Name") {
                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField(label: "Description") {
                        TextField("Optional", text: $descText, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField(label: "Category") {
                        Picker("", selection: $categoryID) {
                            ForEach(options) { opt in
                                Text("\(opt.parentDisplayName) — \(opt.displayName)")
                                    .tag(opt.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            HStack(spacing: 12) {
                Text("\(draft.sourceResolution) · \(draft.durationString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Exit", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") {
                    guard let opt = options.first(where: { $0.id == categoryID }) else { return }
                    onContinue(ImportMetadata(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? draft.suggestedName
                            : name.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: descText.trimmingCharacters(in: .whitespacesAndNewlines),
                        categoryID: opt.parentID,
                        subcategoryID: opt.id
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || options.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
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
