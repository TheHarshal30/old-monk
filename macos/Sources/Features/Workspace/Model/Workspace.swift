import Foundation

/// The three sidebar sections.
enum WorkspaceSection: String, Codable, CaseIterable {
    case agents
    case terminals
    case notes

    var title: String {
        switch self {
        case .agents: return "Agents"
        case .terminals: return "Terminals"
        case .notes: return "Notes"
        }
    }
}

/// The currently selected item in the sidebar / main pane.
enum WorkspaceItem: Equatable, Codable {
    case session(UUID)
    case note(UUID)

    private enum Kind: String, Codable { case session, note }
    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let id = try c.decode(UUID.self, forKey: .id)
        switch kind {
        case .session: self = .session(id)
        case .note: self = .note(id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session(let id):
            try c.encode(Kind.session, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .note(let id):
            try c.encode(Kind.note, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }
}

/// The persisted, on-disk shape of a workspace. This is the `workspace.json`
/// document. Pure data — no live surfaces. The live state (running PTYs) is
/// owned by `WorkspaceController` via `SessionRuntime`.
struct Workspace: Codable {
    /// Schema version for forward migration.
    var version: Int = 1

    /// All sessions, in their canonical (persisted) order.
    var sessions: [Session]

    /// All notes (index only; bodies live on disk).
    var notes: [NoteRef]

    /// The selected item when the workspace was last saved.
    var activeItem: WorkspaceItem?

    /// Collapsed state per section.
    var sectionCollapsed: [WorkspaceSection: Bool]

    init(
        version: Int = 1,
        sessions: [Session] = [],
        notes: [NoteRef] = [],
        activeItem: WorkspaceItem? = nil,
        sectionCollapsed: [WorkspaceSection: Bool] = [:]
    ) {
        self.version = version
        self.sessions = sessions
        self.notes = notes
        self.activeItem = activeItem
        self.sectionCollapsed = sectionCollapsed
    }

    private enum CodingKeys: String, CodingKey {
        case version, sessions, notes, activeItem, sectionCollapsed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        self.notes = try c.decodeIfPresent([NoteRef].self, forKey: .notes) ?? []
        self.activeItem = try c.decodeIfPresent(WorkspaceItem.self, forKey: .activeItem)
        // [WorkspaceSection: Bool] encodes via string keys.
        if let raw = try c.decodeIfPresent([String: Bool].self, forKey: .sectionCollapsed) {
            var map: [WorkspaceSection: Bool] = [:]
            for (k, v) in raw {
                if let section = WorkspaceSection(rawValue: k) { map[section] = v }
            }
            self.sectionCollapsed = map
        } else {
            self.sectionCollapsed = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(activeItem, forKey: .activeItem)
        let raw = Dictionary(uniqueKeysWithValues: sectionCollapsed.map { ($0.key.rawValue, $0.value) })
        try c.encode(raw, forKey: .sectionCollapsed)
    }
}
