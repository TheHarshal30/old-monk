#if os(macOS)
import SwiftUI

/// A compact, Raycast-style picker for launching a new agent session. Lists the
/// available agent templates and lets the user set the working directory and an
/// optional title.
struct NewSessionSheet: View {
    let templates: [AgentTemplate]
    let defaultCwd: String
    let onCreate: (AgentTemplate, String, String?) -> Void
    let onCancel: () -> Void

    @State private var selectedID: String?
    @State private var cwd: String
    @State private var title: String = ""

    init(
        templates: [AgentTemplate],
        defaultCwd: String,
        onCreate: @escaping (AgentTemplate, String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.templates = templates
        self.defaultCwd = defaultCwd
        self.onCreate = onCreate
        self.onCancel = onCancel
        _cwd = State(initialValue: defaultCwd)
        _selectedID = State(initialValue: templates.first?.id)
    }

    private var selectedTemplate: AgentTemplate? {
        templates.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Launch Agent")
                .font(.system(size: 13, weight: .semibold))

            // Template list
            VStack(spacing: 1) {
                ForEach(templates) { t in
                    templateRow(t)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor)))

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Title (optional)")
                TextField(selectedTemplate?.name ?? "Agent", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                fieldLabel("Working Directory")
                HStack(spacing: 6) {
                    TextField("~", text: $cwd)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Button("Choose…") { chooseDirectory() }
                        .controlSize(.small)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Launch") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedTemplate == nil)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    @ViewBuilder
    private func templateRow(_ t: AgentTemplate) -> some View {
        let isSelected = t.id == selectedID
        HStack(spacing: 8) {
            Image(systemName: t.icon ?? "sparkle")
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(t.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(([t.command] + t.args).joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { selectedID = t.id }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func create() {
        guard let t = selectedTemplate else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(t, cwd, trimmedTitle.isEmpty ? nil : trimmedTitle)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: cwd)
        if panel.runModal() == .OK, let url = panel.url {
            cwd = url.path
        }
    }
}
#endif
