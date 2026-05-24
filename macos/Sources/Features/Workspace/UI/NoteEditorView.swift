#if os(macOS)
import SwiftUI

/// A deliberately lightweight markdown note editor. Plain monospaced text with
/// debounced autosave to disk. Not a Notion/Obsidian replacement — a scratchpad.
struct NoteEditorView: View {
    let noteRef: NoteRef
    let store: WorkspaceStore
    @ObservedObject var model: WorkspaceModel

    @State private var text: String = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(noteRef.filename)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            text = store.readNote(filename: noteRef.filename)
            loaded = true
        }
        .onChange(of: text) { _ in
            guard loaded else { return }
            scheduleSave()
        }
        .onDisappear { flushSave() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let body = text
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            try? store.writeNote(filename: noteRef.filename, body: body)
            model.noteWasModified(id: noteRef.id)
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard loaded else { return }
        try? store.writeNote(filename: noteRef.filename, body: text)
        model.noteWasModified(id: noteRef.id)
    }
}
#endif
