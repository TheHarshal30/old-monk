import Foundation

/// The kind of a workspace session. Both kinds are PTY-backed and use the
/// exact same rendering and lifecycle machinery; the only difference is what
/// command is launched.
enum SessionType: String, Codable {
    /// A predefined CLI agent tool (Claude Code, Codex CLI, ...).
    case agent

    /// A plain shell.
    case terminal
}

/// The runtime status of a session. This is intentionally NOT persisted as
/// truth: a session that was "running" when the app last quit is `exited`
/// until its process is relaunched on restore.
enum SessionStatus: String, Codable {
    /// Surface created, the child process has not yet been confirmed running.
    case starting

    /// The PTY child process is alive.
    case running

    /// The child process exited. Restartable.
    case exited

    /// The session failed to launch.
    case failed
}

/// A single workspace session. Mirrors the unified session model from the
/// project spec: agents and terminals share this one type.
///
/// `status` is runtime-only and is excluded from `Codable` (see `CodingKeys`).
struct Session: Identifiable, Equatable {
    let id: UUID
    var title: String
    var type: SessionType

    /// Absolute working directory. Defaults to the user's home directory.
    var cwd: String

    /// The command to launch. `nil` means "use the default shell" (a plain
    /// terminal). Agents set this to e.g. `"claude"`.
    var command: String?

    /// Arguments passed to `command`, e.g. `["code"]` for `claude code`.
    var args: [String]

    /// The id of the `AgentTemplate` this session was created from, if any.
    /// `nil` for plain terminals.
    var agentTemplateID: String?

    /// Notes attached to this session (Phase 3).
    var noteRefs: [UUID]

    /// Runtime status. Not persisted; recomputed from the live surface.
    var status: SessionStatus = .starting

    init(
        id: UUID = UUID(),
        title: String,
        type: SessionType,
        cwd: String,
        command: String? = nil,
        args: [String] = [],
        agentTemplateID: String? = nil,
        noteRefs: [UUID] = [],
        status: SessionStatus = .starting
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.cwd = cwd
        self.command = command
        self.args = args
        self.agentTemplateID = agentTemplateID
        self.noteRefs = noteRefs
        self.status = status
    }

    /// The full command line that should be handed to libghostty as the
    /// surface `command`. libghostty parses this like a shell would, so we
    /// join the executable and its arguments with spaces. Arguments that
    /// contain spaces are quoted.
    var resolvedCommand: String? {
        guard let command, !command.isEmpty else { return nil }
        guard !args.isEmpty else { return command }
        let quoted = args.map { arg -> String in
            arg.contains(" ") ? "\"\(arg)\"" : arg
        }
        return ([command] + quoted).joined(separator: " ")
    }

    /// Build a session from an agent template.
    static func from(
        template: AgentTemplate,
        cwd: String,
        title: String? = nil
    ) -> Session {
        Session(
            title: title ?? template.name,
            type: .agent,
            cwd: cwd,
            command: template.command,
            args: template.args,
            agentTemplateID: template.id
        )
    }

    /// Build a plain terminal session.
    static func terminal(cwd: String, title: String = "Terminal") -> Session {
        Session(title: title, type: .terminal, cwd: cwd)
    }
}

// MARK: - Codable

extension Session: Codable {
    /// Note: `status` is deliberately omitted so it is never read from or
    /// written to disk.
    private enum CodingKeys: String, CodingKey {
        case id, title, type, cwd, command, args, agentTemplateID, noteRefs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.type = try c.decode(SessionType.self, forKey: .type)
        self.cwd = try c.decode(String.self, forKey: .cwd)
        self.command = try c.decodeIfPresent(String.self, forKey: .command)
        self.args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        self.agentTemplateID = try c.decodeIfPresent(String.self, forKey: .agentTemplateID)
        self.noteRefs = try c.decodeIfPresent([UUID].self, forKey: .noteRefs) ?? []
        // Restored sessions are not running until relaunched.
        self.status = .exited
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(type, forKey: .type)
        try c.encode(cwd, forKey: .cwd)
        try c.encodeIfPresent(command, forKey: .command)
        try c.encode(args, forKey: .args)
        try c.encodeIfPresent(agentTemplateID, forKey: .agentTemplateID)
        try c.encode(noteRefs, forKey: .noteRefs)
    }
}
