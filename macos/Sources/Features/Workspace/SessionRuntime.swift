#if os(macOS)
import AppKit

/// Holds the live, in-memory state for one session: its split tree of
/// `Ghostty.SurfaceView`s (usually a single leaf). Runtimes are kept alive for
/// every session in the workspace — even ones not currently visible — so their
/// PTYs keep running and streaming output in the background. Switching sessions
/// only changes which runtime's tree the main pane renders.
@MainActor
final class SessionRuntime {
    let sessionID: UUID

    /// The split tree for this session. Mutated when the user splits within
    /// the session. Persisted back from `WorkspaceController` on change.
    var tree: SplitTree<Ghostty.SurfaceView>

    init(sessionID: UUID, tree: SplitTree<Ghostty.SurfaceView>) {
        self.sessionID = sessionID
        self.tree = tree
    }

    /// The primary (leftmost) surface, used for status and focus.
    var primarySurface: Ghostty.SurfaceView? {
        tree.root?.leftmostLeaf()
    }

    /// All surfaces in the session (the leaves of the tree).
    var surfaces: [Ghostty.SurfaceView] {
        Array(tree)
    }
}
#endif
