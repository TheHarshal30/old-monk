import Foundation
import os

/// Filesystem-backed persistence for a single named workspace.
///
/// Layout:
/// ```
/// ~/Library/Application Support/com.mitchellh.ghostty/workspaces/<name>/
///   workspace.json   ← sessions, notes index, active item, collapse state
///   agents.json      ← user-defined agent templates (optional)
///   notes/           ← <slug>.md files
/// ```
///
/// Writes are atomic (temp file + rename). The notes directory is the source
/// of truth for note bodies; `workspace.json` only indexes them.
final class WorkspaceStore {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "workspace-store"
    )

    let name: String
    let rootURL: URL
    private let notesURL: URL
    private let workspaceFileURL: URL
    private let agentsFileURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Create a store for the given workspace name (defaults to "default").
    /// Returns nil only if the Application Support directory can't be resolved.
    init?(name: String = "default") {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty"
        self.name = name
        self.rootURL = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        self.notesURL = rootURL.appendingPathComponent("notes", isDirectory: true)
        self.workspaceFileURL = rootURL.appendingPathComponent("workspace.json")
        self.agentsFileURL = rootURL.appendingPathComponent("agents.json")
    }

    // MARK: - Directory setup

    private func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: notesURL, withIntermediateDirectories: true)
    }

    // MARK: - Workspace document

    /// Load the workspace document. Returns an empty workspace if none exists
    /// yet or if the file is unreadable (logged).
    func load() -> Workspace {
        guard FileManager.default.fileExists(atPath: workspaceFileURL.path) else {
            return Workspace()
        }
        do {
            let data = try Data(contentsOf: workspaceFileURL)
            return try decoder.decode(Workspace.self, from: data)
        } catch {
            Self.logger.error("failed to load workspace.json: \(error.localizedDescription)")
            return Workspace()
        }
    }

    func save(_ workspace: Workspace) throws {
        try ensureDirectories()
        let data = try encoder.encode(workspace)
        try atomicWrite(data, to: workspaceFileURL)
    }

    // MARK: - Agent templates

    /// Load user agent templates merged over the built-ins.
    func loadAgentTemplates() -> [AgentTemplate] {
        guard FileManager.default.fileExists(atPath: agentsFileURL.path) else {
            return AgentTemplate.builtins
        }
        do {
            let data = try Data(contentsOf: agentsFileURL)
            let user = try decoder.decode([AgentTemplate].self, from: data)
            return AgentTemplate.merged(userTemplates: user)
        } catch {
            Self.logger.error("failed to load agents.json: \(error.localizedDescription)")
            return AgentTemplate.builtins
        }
    }

    // MARK: - Notes

    func readNote(filename: String) -> String {
        let url = notesURL.appendingPathComponent(filename)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func writeNote(filename: String, body: String) throws {
        try ensureDirectories()
        let url = notesURL.appendingPathComponent(filename)
        try atomicWrite(Data(body.utf8), to: url)
    }

    func deleteNote(filename: String) throws {
        let url = notesURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }
}
