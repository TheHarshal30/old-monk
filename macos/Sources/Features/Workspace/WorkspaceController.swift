#if os(macOS)
import Cocoa
import SwiftUI
import Combine
import GhosttyKit

/// A workspace window: a persistent left sidebar (Agents / Terminals / Notes)
/// next to a main pane that renders the active session's terminal surface(s)
/// or a note editor.
///
/// This subclasses `BaseTerminalController` to inherit all of Ghostty's
/// surface plumbing (clipboard confirmation, fullscreen, splits, appearance,
/// close handling) for free. The base class's `surfaceTree` is treated as
/// "the active session's split tree"; switching sessions reassigns it.
///
/// Crucially, every session's surfaces stay instantiated in `runtimes` even
/// when not visible, so background agents/shells keep running and streaming.
class WorkspaceController: BaseTerminalController {
    /// All open workspace controllers. Computed from the live windows, exactly
    /// like `TerminalController.all`, so controller lifetime is managed by
    /// AppKit (the window retains its controller) rather than a static array.
    static var all: [WorkspaceController] {
        NSApplication.shared.windows.compactMap { $0.windowController as? WorkspaceController }
    }

    /// The observable sidebar/state model.
    let model: WorkspaceModel

    /// Persistence.
    let store: WorkspaceStore

    /// Live per-session state, keyed by session id. Surfaces here are retained
    /// regardless of visibility.
    private var runtimes: [UUID: SessionRuntime] = [:]

    /// Guards `surfaceTreeDidChange` so a programmatic session switch isn't
    /// mistaken for a user split edit.
    private var isSwitching = false

    /// Periodically refreshes session status from live surfaces.
    private var statusTimer: Timer?

    /// The active sheet window (new-agent picker), if any.
    private var sheetWindow: NSWindow?

    private weak var container: WorkspaceContainerView?

    // MARK: - Init

    init(_ ghostty: Ghostty.App, store: WorkspaceStore, model: WorkspaceModel) {
        self.store = store
        self.model = model

        // Pass an explicitly empty tree so the base class does NOT create a
        // stray default surface — sessions own all surfaces.
        super.init(ghostty, baseConfig: nil, surfaceTree: SplitTree<Ghostty.SurfaceView>())

        // Build live runtimes for every restored session.
        rebuildRuntimesFromModel()

        // BaseTerminalController calls `super.init(window: nil)` and we provide
        // no window nib, so AppKit never lazily calls `loadWindow()`. Create the
        // window ourselves and run the load-time setup explicitly.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Workspace"
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("GhosttyWorkspaceWindow")
        self.window = window
        windowDidLoad()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        statusTimer?.invalidate()
    }

    /// Create a live runtime (surface) for every session in the model that
    /// doesn't already have one. Called at init to restore persisted sessions.
    private func rebuildRuntimesFromModel() {
        for session in model.sessions where runtimes[session.id] == nil {
            guard let view = makeSurfaceView(for: session) else { continue }
            runtimes[session.id] = SessionRuntime(sessionID: session.id, tree: .init(view: view))
        }
    }

    // MARK: - Window

    private var didLoadWorkspace = false

    override func windowDidLoad() {
        super.windowDidLoad()
        guard !didLoadWorkspace, let window else { return }
        didLoadWorkspace = true
        window.delegate = self

        let sidebar = NSHostingView(rootView: SidebarView(
            model: model,
            onSelect: { [weak self] item in self?.activate(item) },
            onNewAgent: { [weak self] in self?.presentNewAgentPicker() },
            onNewTerminal: { [weak self] in _ = self?.newTerminalSession() },
            onNewNote: { [weak self] in self?.presentNewNotePrompt() },
            onRestart: { [weak self] id in self?.restartSession(id) },
            onCloseSession: { [weak self] id in self?.closeSession(id) },
            onDeleteNote: { [weak self] id in self?.model.removeNote(id: id) },
            onRenameSession: { [weak self] id, title in self?.model.renameSession(id: id, to: title) }
        ))

        let main = NSHostingView(rootView: WorkspaceMainView(
            ghostty: ghostty,
            controller: self,
            model: model,
            store: store
        ))

        let container = WorkspaceContainerView(sidebar: sidebar, main: main)
        self.container = container
        window.contentView = container

        // Restore the previously active item, else focus the first session.
        if let item = model.activeItem, isValid(item) {
            activate(item)
        } else if let first = model.sessions.first {
            activate(.session(first.id))
        }

        refreshStatuses()
        startStatusTimer()
    }

    override func windowWillClose(_ notification: Notification) {
        // Persist final state before teardown.
        model.saveNow()
        statusTimer?.invalidate()
        statusTimer = nil
        super.windowWillClose(notification)
    }

    // MARK: - Session creation

    @discardableResult
    func newTerminalSession(cwd: String? = nil, title: String = "Terminal") -> Session? {
        let session = Session.terminal(cwd: cwd ?? defaultCwd(), title: title)
        return launch(session)
    }

    @discardableResult
    func newAgentSession(template: AgentTemplate, cwd: String? = nil, title: String? = nil) -> Session? {
        let session = Session.from(template: template, cwd: cwd ?? defaultCwd(), title: title)
        return launch(session)
    }

    /// Create the surface for a new session, register it, add it to the model,
    /// and make it active.
    @discardableResult
    private func launch(_ session: Session) -> Session? {
        guard let view = makeSurfaceView(for: session) else { return nil }
        runtimes[session.id] = SessionRuntime(sessionID: session.id, tree: .init(view: view))
        model.addSession(session)
        activate(.session(session.id))
        return session
    }

    /// Kill the current process for a session and start it fresh. Keeps the
    /// session's identity, title, and position.
    func restartSession(_ id: UUID) {
        guard let session = model.session(id: id),
              let view = makeSurfaceView(for: session) else { return }

        // Replacing the runtime drops the old surfaces; they deinit and their
        // PTYs are torn down.
        let runtime = SessionRuntime(sessionID: id, tree: .init(view: view))
        runtimes[id] = runtime
        model.updateStatus(id: id, .starting)

        if case .session(let active)? = model.activeItem, active == id {
            isSwitching = true
            surfaceTree = runtime.tree
            focusedSurface = view
            isSwitching = false
            DispatchQueue.main.async { Ghostty.moveFocus(to: view, from: nil) }
        }
    }

    /// Close a session entirely (all its splits) and remove it from the sidebar.
    func closeSession(_ id: UUID, confirm: Bool = true, alreadyEmptyTree: Bool = false) {
        // Confirm if a child process is still alive.
        if confirm, !alreadyEmptyTree,
           let rt = runtimes[id],
           rt.surfaces.contains(where: { $0.needsConfirmQuit }) {
            confirmClose(
                messageText: "Close Session?",
                informativeText: "This session still has a running process. Closing it will kill the process."
            ) { [weak self] in
                self?.closeSession(id, confirm: false)
            }
            return
        }

        let wasActive: Bool = {
            if case .session(let active)? = model.activeItem { return active == id }
            return false
        }()

        // Drop live surfaces (deinit closes the PTYs), then remove from model.
        runtimes[id] = nil
        model.removeSession(id: id)

        if wasActive {
            isSwitching = true
            if let next = model.activeItem {
                isSwitching = false
                activate(next)
            } else {
                surfaceTree = .init()
                focusedSurface = nil
                isSwitching = false
            }
        }
    }

    // MARK: - Activation / switching

    /// Make a sidebar item active. For sessions this swaps the rendered surface
    /// tree; for notes the main pane shows the editor (driven by
    /// `model.activeItem`).
    func activate(_ item: WorkspaceItem) {
        guard isValid(item) else { return }
        model.activeItem = item

        switch item {
        case .session(let id):
            guard let rt = runtimes[id] else { return }
            let old = focusedSurface
            isSwitching = true
            surfaceTree = rt.tree
            let target = rt.primarySurface
            focusedSurface = target
            isSwitching = false
            if let target {
                DispatchQueue.main.async { Ghostty.moveFocus(to: target, from: old) }
            }

        case .note:
            // The main view observes `model.activeItem` and renders the editor.
            // We leave the surface tree intact (just not displayed).
            break
        }

        model.scheduleSave()
    }

    /// Toggle sidebar visibility (⌘B).
    @objc func toggleWorkspaceSidebar(_ sender: Any?) {
        container?.toggleSidebar()
    }

    // MARK: - Surface tree sync

    override func surfaceTreeDidChange(
        from: SplitTree<Ghostty.SurfaceView>,
        to: SplitTree<Ghostty.SurfaceView>
    ) {
        super.surfaceTreeDidChange(from: from, to: to)

        // Ignore programmatic switches; only react to genuine user edits
        // (splitting, closing a split) of the active session's tree.
        guard !isSwitching else { return }
        guard case .session(let id)? = model.activeItem, let rt = runtimes[id] else { return }

        rt.tree = to

        // If the active session's last surface was closed, close the session.
        if to.isEmpty {
            closeSession(id, confirm: false, alreadyEmptyTree: true)
        }
    }

    // MARK: - Status

    private func startStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor explicitly
            // to satisfy concurrency checking across deployment targets.
            Task { @MainActor in self?.refreshStatuses() }
        }
    }

    private func refreshStatuses() {
        for session in model.sessions {
            model.updateStatus(id: session.id, computeStatus(sessionID: session.id))
        }
    }

    private func computeStatus(sessionID: UUID) -> SessionStatus {
        guard let rt = runtimes[sessionID], let surface = rt.primarySurface else {
            return .exited
        }
        if surface.processExited { return .exited }
        if surface.surfaceModel != nil { return .running }
        return .starting
    }

    // MARK: - New-item UI

    private func presentNewAgentPicker() {
        guard let window, sheetWindow == nil else { return }
        let hosting = NSHostingController(rootView: NewSessionSheet(
            templates: model.agentTemplates,
            defaultCwd: defaultCwd(),
            onCreate: { [weak self] template, cwd, title in
                self?.dismissSheet()
                _ = self?.newAgentSession(template: template, cwd: cwd, title: title)
            },
            onCancel: { [weak self] in self?.dismissSheet() }
        ))
        let sheet = NSWindow(contentViewController: hosting)
        sheet.styleMask = [.titled]
        self.sheetWindow = sheet
        window.beginSheet(sheet)
    }

    private func dismissSheet() {
        guard let sheetWindow else { return }
        window?.endSheet(sheetWindow)
        self.sheetWindow = nil
    }

    private func presentNewNotePrompt() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "New Note"
        alert.informativeText = "Name this note. A markdown file will be created in the workspace."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g. auth"
        alert.accessoryView = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let self else { return }
            if let ref = self.model.addNote(title: title) {
                self.activate(.note(ref.id))
            }
        }
    }

    // MARK: - Helpers

    private func makeSurfaceView(for session: Session) -> Ghostty.SurfaceView? {
        guard let app = ghostty.app else { return nil }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = session.cwd.isEmpty ? nil : session.cwd
        config.command = session.resolvedCommand
        return Ghostty.SurfaceView(app, baseConfig: config)
    }

    private func defaultCwd() -> String {
        if case .session(let id)? = model.activeItem, let s = model.session(id: id), !s.cwd.isEmpty {
            return s.cwd
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func isValid(_ item: WorkspaceItem) -> Bool {
        switch item {
        case .session(let id): return runtimes[id] != nil
        case .note(let id): return model.note(id: id) != nil
        }
    }
}
#endif
