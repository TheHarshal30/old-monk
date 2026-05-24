import Foundation

/// A configurable definition of a CLI agent tool. Agent sessions are launched
/// from these templates. Deliberately provider-agnostic: adding a new agent is
/// just another entry, either built-in or in the user's `agents.json`.
///
/// Example JSON (from the project spec):
/// ```json
/// { "id": "claude-code", "name": "Claude Code", "command": "claude", "args": ["code"] }
/// ```
struct AgentTemplate: Codable, Identifiable, Equatable {
    /// Stable identifier, e.g. `"claude-code"`. Referenced by `Session.agentTemplateID`.
    let id: String

    /// Display name shown in the sidebar, e.g. `"Claude Code"`.
    var name: String

    /// The executable to launch, e.g. `"claude"`.
    var command: String

    /// Arguments, e.g. `["code"]`.
    var args: [String]

    /// Optional SF Symbol used as the row icon. Falls back to a generic glyph.
    var icon: String?

    init(id: String, name: String, command: String, args: [String] = [], icon: String? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, command, args, icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.command = try c.decode(String.self, forKey: .command)
        self.args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
    }
}

extension AgentTemplate {
    /// Built-in agent templates shipped with the app. User templates in
    /// `agents.json` are merged over these (by `id`).
    static let builtins: [AgentTemplate] = [
        AgentTemplate(id: "claude-code", name: "Claude Code", command: "claude", args: ["code"], icon: "sparkle"),
        AgentTemplate(id: "codex-cli", name: "Codex CLI", command: "codex", args: [], icon: "chevron.left.forwardslash.chevron.right"),
        AgentTemplate(id: "gemini-cli", name: "Gemini CLI", command: "gemini", args: [], icon: "diamond"),
    ]

    /// Merge user-defined templates over the built-ins. User templates with an
    /// id matching a built-in override it; new ids are appended.
    static func merged(userTemplates: [AgentTemplate]) -> [AgentTemplate] {
        var byID: [String: AgentTemplate] = [:]
        var order: [String] = []
        for t in builtins {
            byID[t.id] = t
            order.append(t.id)
        }
        for t in userTemplates {
            if byID[t.id] == nil { order.append(t.id) }
            byID[t.id] = t
        }
        return order.compactMap { byID[$0] }
    }
}
