#if os(macOS)
import SwiftUI

/// A compact sidebar row for a note. Matches `SessionRow` density.
struct NoteRow: View {
    let note: NoteRef
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Spacer to align with the session rows' status dot column.
            Color.clear.frame(width: 7, height: 7)

            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 14)

            Text(note.title)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

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
            Button("Delete", role: .destructive) { onDelete() }
        }
        .help(note.filename)
    }
}
#endif
