import Foundation

/// A reference to a markdown note stored on disk in the workspace `notes/`
/// directory. The note body itself is not held here; it is read/written
/// lazily via `WorkspaceStore`. This keeps the index light and the source of
/// truth on the filesystem (developer-trustable, portable).
struct NoteRef: Codable, Identifiable, Equatable {
    let id: UUID

    /// Display title (the filename without extension, humanized).
    var title: String

    /// The on-disk filename within the notes directory, e.g. `"auth.md"`.
    /// Unique within the directory.
    var filename: String

    /// Last modification time, used for sidebar ordering.
    var modifiedAt: Date

    init(id: UUID = UUID(), title: String, filename: String, modifiedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.filename = filename
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, filename, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.filename = try c.decode(String.self, forKey: .filename)
        self.modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}

extension NoteRef {
    /// Produce a filesystem-safe `.md` filename from a desired title, ensuring
    /// uniqueness against `existing` filenames.
    static func uniqueFilename(for title: String, existing: Set<String>) -> String {
        let base = slug(title)
        var candidate = "\(base).md"
        var n = 2
        while existing.contains(candidate.lowercased()) {
            candidate = "\(base)-\(n).md"
            n += 1
        }
        return candidate
    }

    /// Lowercase, hyphen-separated slug suitable for a filename.
    static func slug(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let lowered = title.lowercased()
        var out = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "note" : trimmed
    }
}
