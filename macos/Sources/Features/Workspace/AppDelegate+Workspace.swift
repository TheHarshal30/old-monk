#if os(macOS)
import AppKit

/// Workspace integration for the app delegate. Kept in its own file so the
/// feature is additive and easy to review/remove. The workspace is opt-in:
/// classic Ghostty behavior is the default.
@MainActor
extension AppDelegate {
    /// UserDefaults key controlling whether launching opens a workspace window
    /// instead of a classic terminal window. Defaults to `false`.
    static let workspaceDefaultWindowKey = "WorkspaceDefaultWindow"

    /// Whether the workspace should be the default window on launch (opt-in).
    static var workspaceIsDefaultWindow: Bool {
        UserDefaults.standard.bool(forKey: workspaceDefaultWindowKey)
    }

    /// Open (or focus) the workspace window. There is a single workspace
    /// instance ("default") for now; opening again focuses the existing one.
    @objc func newWorkspaceWindow(_ sender: Any?) {
        if let existing = WorkspaceController.all.first {
            existing.showWindow(self)
            existing.window?.makeKeyAndOrderFront(self)
            return
        }

        guard let store = WorkspaceStore(name: "default") else {
            AppDelegate.logger.error("could not create workspace store")
            return
        }

        let templates = store.loadAgentTemplates()
        let workspace = store.load()
        let model = WorkspaceModel(
            workspace: workspace,
            agentTemplates: templates,
            store: store)

        // Once shown, the window retains its controller (matching
        // TerminalController), so we don't need to hold a strong reference here.
        let controller = WorkspaceController(ghostty, store: store, model: model)
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    /// Insert the "New Workspace Window" (and "Toggle Sidebar") items into the
    /// File menu programmatically, so we don't have to edit MainMenu.xib.
    func installWorkspaceMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }

        // Find the File menu. Prefer the submenu that contains the "New Window"
        // item (matched by selector); otherwise fall back to the conventional
        // second top-level menu.
        let fileMenu: NSMenu
        let insertIndex: Int
        if let (menu, idx) = fileMenuAndNewWindowIndex() {
            fileMenu = menu
            insertIndex = idx + 1
        } else if mainMenu.items.count > 1, let sub = mainMenu.items[1].submenu {
            fileMenu = sub
            insertIndex = 0
        } else {
            return
        }

        // Avoid double-install.
        let selector = #selector(newWorkspaceWindow(_:))
        guard !fileMenu.items.contains(where: { $0.action == selector }) else { return }

        let item = NSMenuItem(
            title: "New Workspace Window",
            action: selector,
            keyEquivalent: "n")
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        fileMenu.insertItem(item, at: min(insertIndex, fileMenu.items.count))

        // Toggle Sidebar is targeted at the first responder so it reaches the
        // key workspace window's controller.
        let toggle = NSMenuItem(
            title: "Toggle Workspace Sidebar",
            action: #selector(WorkspaceController.toggleWorkspaceSidebar(_:)),
            keyEquivalent: "b")
        toggle.keyEquivalentModifierMask = [.command, .option]
        toggle.target = nil
        fileMenu.insertItem(toggle, at: min(insertIndex + 1, fileMenu.items.count))
    }

    /// Locate the File menu and the index of its "New Window" item by matching
    /// the action selector (avoids reliance on localized titles or private
    /// outlets).
    private func fileMenuAndNewWindowIndex() -> (NSMenu, Int)? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        for top in mainMenu.items {
            guard let sub = top.submenu else { continue }
            if let idx = sub.items.firstIndex(where: { $0.action == #selector(newWindow(_:)) }) {
                return (sub, idx)
            }
        }
        return nil
    }
}
#endif
