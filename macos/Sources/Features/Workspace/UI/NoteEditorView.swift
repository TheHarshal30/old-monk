#if os(macOS)
import SwiftUI

/// A deliberately lightweight markdown note editor with an Edit/Preview toggle.
/// Plain monospaced editing with debounced autosave; preview is a minimal block
/// renderer. Not a Notion/Obsidian replacement — a scratchpad.
struct NoteEditorView: View {
    let noteRef: NoteRef
    let store: WorkspaceStore
    @ObservedObject var model: WorkspaceModel

    private enum Mode: Hashable { case edit, preview }

    @State private var text: String = ""
    @State private var loaded = false
    @State private var mode: Mode = .edit
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(noteRef.filename)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $mode) {
                    Text("Edit").tag(Mode.edit)
                    Text("Preview").tag(Mode.preview)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            switch mode {
            case .edit:
                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(.horizontal, 6)
            case .preview:
                MarkdownPreview(text: text)
                    .background(Color(nsColor: .textBackgroundColor))
            }
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

/// Minimal markdown preview: headings, bullet lists, fenced code blocks, and
/// paragraphs with inline formatting (bold/italic/code/links). Intentionally
/// small — enough to read a note, not a full markdown engine.
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                let blocks = Self.parse(text)
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(inline(content))
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, level <= 2 ? 4 : 0)
        case .bullet(let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(content))
            }
            .font(.system(size: 13))
        case .code(let content):
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .paragraph(let content):
            Text(inline(content)).font(.system(size: 13))
        case .blank:
            EmptyView()
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 18
        case 3: return 15
        default: return 13
        }
    }

    /// Parse inline markdown into an AttributedString, falling back to plain.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    // MARK: - Block parsing

    enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case code(text: String)
        case paragraph(text: String)
        case blank
    }

    static func parse(_ s: String) -> [Block] {
        var blocks: [Block] = []
        var inCode = false
        var codeBuf: [String] = []

        for rawLine in s.components(separatedBy: "\n") {
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    blocks.append(.code(text: codeBuf.joined(separator: "\n")))
                    codeBuf.removeAll()
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuf.append(rawLine)
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                blocks.append(.blank)
                continue
            }
            if let h = heading(line) {
                blocks.append(.heading(level: h.level, text: h.text))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                blocks.append(.bullet(text: String(line.dropFirst(2))))
                continue
            }
            blocks.append(.paragraph(text: line))
        }
        if inCode { blocks.append(.code(text: codeBuf.joined(separator: "\n"))) }
        return blocks
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        return (level, String(line[line.index(after: idx)...]))
    }
}
#endif
