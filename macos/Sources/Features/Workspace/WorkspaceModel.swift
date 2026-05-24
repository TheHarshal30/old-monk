import Foundation
import Combine

/// The observable source of truth for a workspace's sidebar state. The UI
/// (`SidebarView`) observes this; `WorkspaceController` owns the live surfaces
/// separately. Any mutation here schedules a debounced save to disk.
@MainActor
final class WorkspaceModel: ObservableObject {
    /// Sessions in canonical order (agents and terminals interleaved; the
    /// sidebar filters by `type` per section).
    @Published private(set) var sessions: [Session]

    /// Note index in display order (most-recently-modified first).
    @Published private(set) var notes: [NoteRef]

    /// The selected sidebar item.
    @Published var activeItem: WorkspaceItem?

    /// Collapsed state per section.
    @Published var sectionCollapsed: [WorkspaceSection: Bool]

    /// Available agent templates (built-ins merged with user `agents.json`).
    let agentTemplates: [AgentTemplate]

    private let store: WorkspaceStore
    private var saveTask: Task<Void, Never>?

    init(workspace: Workspace, agentTemplates: [AgentTemplate], store: WorkspaceStore) {
        self.sessions = workspace.sessions
        self.notes = workspace.notes
        self.activeItem = workspace.activeItem
        self.sectionCollapsed = workspace.sectionCollapsed
        self.agentTemplates = agentTemplates
        self.store = store
    }

    // MARK: - Derived

    func sessions(in section: WorkspaceSection) -> [Session] {
        switch section {
        case .agents: return sessions.filter { $0.type == .agent }
        case .terminals: return sessions.filter { $0.type == .terminal }
        case .notes: return []
        }
    }

    func session(id: UUID) -> Session? {
        sessions.first { $0.id == id }
    }

    func note(id: UUID) -> NoteRef? {
        notes.first { $0.id == id }
    }

    func template(id: String?) -> AgentTemplate? {
        guard let id else { return nil }
        return agentTemplates.first { $0.id == id }
    }

    func isCollapsed(_ section: WorkspaceSection) -> Bool {
        sectionCollapsed[section] ?? false
    }

    // MARK: - Session mutations

    func addSession(_ session: Session) {
        sessions.append(session)
        scheduleSave()
    }

    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if case .session(let active) = activeItem, active == id {
            activeItem = nextActiveItem(afterRemoving: id)
        }
        scheduleSave()
    }

    func renameSession(id: UUID, to title: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].title = title
        scheduleSave()
    }

    func updateStatus(id: UUID, _ status: SessionStatus) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard sessions[i].status != status else { return }
        sessions[i].status = status
        // Status is not persisted, so no save needed.
    }

    func updateCwd(id: UUID, _ cwd: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard sessions[i].cwd != cwd else { return }
        sessions[i].cwd = cwd
        scheduleSave()
    }

    /// Reorder a session within the overall list. Indices are into the full
    /// `sessions` array.
    func moveSession(from source: Int, to destination: Int) {
        guard sessions.indices.contains(source) else { return }
        let item = sessions.remove(at: source)
        let dest = min(max(destination, 0), sessions.count)
        sessions.insert(item, at: dest)
        scheduleSave()
    }

    // MARK: - Note mutations

    /// Create a new empty note on disk and add it to the index.
    @discardableResult
    func addNote(title: String) -> NoteRef? {
        let existing = Set(notes.map { $0.filename.lowercased() })
        let filename = NoteRef.uniqueFilename(for: title, existing: existing)
        let ref = NoteRef(title: title, filename: filename)
        do {
            try store.writeNote(filename: filename, body: "# \(title)\n\n")
        } catch {
            return nil
        }
        notes.insert(ref, at: 0)
        scheduleSave()
        return ref
    }

    func renameNote(id: UUID, to title: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].title = title
        notes[i].modifiedAt = Date()
        scheduleSave()
    }

    func removeNote(id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let ref = notes[i]
        try? store.deleteNote(filename: ref.filename)
        notes.remove(at: i)
        if case .note(let active) = activeItem, active == id {
            activeItem = nextActiveItem(afterRemoving: nil)
        }
        scheduleSave()
    }

    func noteWasModified(id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].modifiedAt = Date()
        scheduleSave()
    }

    // MARK: - Selection

    /// Pick a reasonable item to focus after the active one is removed:
    /// prefer the first remaining session, else the first note, else nil.
    private func nextActiveItem(afterRemoving id: UUID?) -> WorkspaceItem? {
        if let first = sessions.first(where: { $0.id != id }) {
            return .session(first.id)
        }
        if let firstNote = notes.first {
            return .note(firstNote.id)
        }
        return nil
    }

    // MARK: - Persistence

    func snapshot() -> Workspace {
        Workspace(
            sessions: sessions,
            notes: notes,
            activeItem: activeItem,
            sectionCollapsed: sectionCollapsed
        )
    }

    /// Debounced save. Coalesces rapid mutations into a single write, staying
    /// on the main actor where this model is isolated.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            try? self.store.save(self.snapshot())
        }
    }

    /// Force an immediate synchronous save (used on quit / window close).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        try? store.save(snapshot())
    }
}
