#if os(macOS)
import SwiftUI

/// The main (right) pane of a workspace window. Renders the active session's
/// terminal surfaces via Ghostty's existing `TerminalView`, or a note editor
/// when a note is selected. Driven by `model.activeItem`.
struct WorkspaceMainView: View {
    @ObservedObject var ghostty: Ghostty.App
    @ObservedObject var controller: WorkspaceController
    @ObservedObject var model: WorkspaceModel
    let store: WorkspaceStore

    var body: some View {
        Group {
            switch model.activeItem {
            case .note(let id):
                if let ref = model.note(id: id) {
                    NoteEditorView(noteRef: ref, store: store, model: model)
                        .id(id)
                } else {
                    WorkspaceEmptyView(title: "Note not found", systemImage: "doc")
                }

            case .session(let id):
                if controller.hasRuntime(id) {
                    // Reuse Ghostty's terminal view verbatim. The controller is
                    // the TerminalViewModel (surfaceTree) and the delegate.
                    TerminalView(ghostty: ghostty, viewModel: controller, delegate: controller)
                } else {
                    // Session was stopped by the user; offer to restart it.
                    StoppedSessionView(
                        title: model.session(id: id)?.title ?? "Session",
                        onRestart: { controller.restartSession(id) })
                }

            case nil:
                WorkspaceEmptyView(
                    title: "No session selected",
                    systemImage: "terminal",
                    detail: "Create a terminal or launch an agent from the sidebar.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown in the main pane when the active session has been stopped. Calm and
/// minimal, with a single Restart affordance.
struct StoppedSessionView: View {
    let title: String
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "stop.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("\(title) is stopped")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Restart", action: onRestart)
                .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A calm, minimal empty state for the main pane.
struct WorkspaceEmptyView: View {
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.0))
    }
}
#endif
