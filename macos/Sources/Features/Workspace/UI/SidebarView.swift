#if os(macOS)
import SwiftUI

/// The persistent left sidebar: three collapsible sections (Agents, Terminals,
/// Notes) acting as the workspace's session navigator. Dense, keyboard-first,
/// minimal chrome.
struct SidebarView: View {
    @ObservedObject var model: WorkspaceModel

    let onSelect: (WorkspaceItem) -> Void
    let onNewAgent: () -> Void
    let onNewTerminal: () -> Void
    let onNewNote: () -> Void
    let onRestart: (UUID) -> Void
    let onStop: (UUID) -> Void
    let onCloseSession: (UUID) -> Void
    let onDeleteNote: (UUID) -> Void
    let onRenameSession: (UUID, String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                section(.agents)
                section(.terminals)
                section(.notes)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(_ section: WorkspaceSection) -> some View {
        let collapsed = model.isCollapsed(section)

        SectionHeader(
            title: section.title,
            collapsed: collapsed,
            onToggle: { toggleCollapse(section) },
            onAdd: { add(for: section) }
        )
        .padding(.top, section == .agents ? 0 : 8)

        if !collapsed {
            switch section {
            case .agents, .terminals:
                let sessions = model.sessions(in: section)
                if sessions.isEmpty {
                    EmptyHint(text: section == .agents ? "No agents" : "No terminals")
                } else {
                    ForEach(sessions) { s in
                        SessionRow(
                            session: s,
                            isActive: model.activeItem == .session(s.id),
                            icon: icon(for: s),
                            onSelect: { onSelect(.session(s.id)) },
                            onRestart: { onRestart(s.id) },
                            onStop: { onStop(s.id) },
                            onClose: { onCloseSession(s.id) },
                            onRename: { onRenameSession(s.id, $0) }
                        )
                    }
                }

            case .notes:
                if model.notes.isEmpty {
                    EmptyHint(text: "No notes")
                } else {
                    ForEach(model.notes) { n in
                        NoteRow(
                            note: n,
                            isActive: model.activeItem == .note(n.id),
                            onSelect: { onSelect(.note(n.id)) },
                            onDelete: { onDeleteNote(n.id) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func toggleCollapse(_ section: WorkspaceSection) {
        model.sectionCollapsed[section] = !model.isCollapsed(section)
        model.scheduleSave()
    }

    private func add(for section: WorkspaceSection) {
        switch section {
        case .agents: onNewAgent()
        case .terminals: onNewTerminal()
        case .notes: onNewNote()
        }
    }

    private func icon(for session: Session) -> String {
        switch session.type {
        case .terminal:
            return "terminal"
        case .agent:
            return model.template(id: session.agentTemplateID)?.icon ?? "sparkle"
        }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    let collapsed: Bool
    let onToggle: () -> Void
    let onAdd: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Add")
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .frame(height: 20, alignment: .leading)
    }
}
#endif
