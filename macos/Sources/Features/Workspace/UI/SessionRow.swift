#if os(macOS)
import SwiftUI

/// A compact sidebar row for a session (agent or terminal). Single line, ~22pt
/// tall, with a leading status dot. No cards or shadows — list density.
struct SessionRow: View {
    let session: Session
    let isActive: Bool
    let icon: String
    let onSelect: () -> Void
    let onRestart: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var draftTitle = ""

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: session.status)

            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 14)

            if isEditing {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(session.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.primary.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename") { beginRename() }
            Button("Restart") { onRestart() }
            Divider()
            Button("Close", role: .destructive) { onClose() }
        }
        .help(session.cwd)
    }

    private func beginRename() {
        draftTitle = session.title
        isEditing = true
    }

    private func commitRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onRename(trimmed) }
        isEditing = false
    }
}

/// Small status indicator dot. Operational, not decorative.
struct StatusDot: View {
    let status: SessionStatus

    private var color: Color {
        switch status {
        case .running: return .green
        case .starting: return .yellow
        case .exited: return Color.secondary.opacity(0.5)
        case .failed: return .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(status == .starting ? 0.7 : 1.0)
    }
}
#endif
