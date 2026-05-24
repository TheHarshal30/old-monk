#if os(macOS)
import AppKit

/// The window content view for a workspace: a fixed-width sidebar on the left,
/// a hairline divider, and the main pane filling the rest.
///
/// The sidebar width is intentionally constant (per design: it does NOT resize
/// based on content). It can be collapsed entirely (width 0) for a distraction-
/// free view.
final class WorkspaceContainerView: NSView {
    /// The fixed sidebar width in points.
    static let sidebarWidth: CGFloat = 220

    private let sidebarView: NSView
    private let dividerView: NSView
    private let mainView: NSView

    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var dividerWidthConstraint: NSLayoutConstraint!

    private(set) var isSidebarVisible: Bool = true

    init(sidebar: NSView, main: NSView) {
        self.sidebarView = sidebar
        self.dividerView = NSView()
        self.mainView = main
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        for v in [sidebarView, dividerView, mainView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor

        sidebarWidthConstraint = sidebarView.widthAnchor.constraint(
            equalToConstant: Self.sidebarWidth)
        dividerWidthConstraint = dividerView.widthAnchor.constraint(equalToConstant: 1)

        NSLayoutConstraint.activate([
            // Sidebar pinned left, fixed width.
            sidebarView.topAnchor.constraint(equalTo: topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebarWidthConstraint,

            // Divider.
            dividerView.topAnchor.constraint(equalTo: topAnchor),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            dividerWidthConstraint,

            // Main pane fills the rest.
            mainView.topAnchor.constraint(equalTo: topAnchor),
            mainView.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainView.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            mainView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    /// Show or hide the sidebar. When hidden, the main pane expands to fill the
    /// full window width.
    func setSidebarVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != isSidebarVisible else { return }
        isSidebarVisible = visible

        let sidebarTarget: CGFloat = visible ? Self.sidebarWidth : 0
        let dividerTarget: CGFloat = visible ? 1 : 0

        let apply = {
            self.sidebarWidthConstraint.constant = sidebarTarget
            self.dividerWidthConstraint.constant = dividerTarget
            self.layoutSubtreeIfNeeded()
        }

        sidebarView.isHidden = !visible
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
    }

    func toggleSidebar() {
        setSidebarVisible(!isSidebarVisible)
    }
}
#endif
