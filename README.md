# old-monk

An AI-native terminal **workspace** — a persistent left sidebar that turns the
terminal into a session navigator for AI coding agents, shells, and notes.

It is built on top of [Ghostty](https://github.com/ghostty-org/ghostty) (MIT),
reusing Ghostty's terminal rendering, PTY handling, and surface/split system
unchanged. The workspace layer adds orchestration, persistence, and a
session-centric UI on top — it does not modify the terminal engine.

## What it adds

A fixed left sidebar with three sections:

- **Agents** — PTY-backed sessions that launch CLI coding agents (Claude Code,
  Codex CLI, Gemini CLI, … configurable).
- **Terminals** — plain shell sessions.
- **Notes** — lightweight, local-first markdown scratchpads.

Core ideas:

- **Unified session model** — agents and terminals are the *same* thing; they
  differ only by the command they launch.
- **Sessions stay alive when hidden** — switching sessions never kills them;
  background agents keep running and streaming.
- **Persistent workspace** — open sessions, ordering, the active item, working
  directories, and notes are saved and restored across restarts. Continuity is
  the point.
- **Keyboard-first, minimal chrome** — operational and dense, not a dashboard.

## Status

Early. The workspace is **opt-in** (the app behaves like normal Ghostty by
default). Window creation, session restore, hidden-session continuity, and
persistence are working; UX is still being validated through real use.

## Building (macOS)

Requires Zig 0.15.x and Xcode 26 (with the macOS SDK and Metal toolchain).

```sh
zig build -Demit-macos-app
open zig-out/Ghostty.app
```

To open a workspace window: **File ▸ New Workspace Window** (⌘⇧N), or enable it
as the default window:

```sh
defaults write com.mitchellh.ghostty WorkspaceDefaultWindow -bool true
```

## License

This project builds on Ghostty and retains its license. See [LICENSE](LICENSE).
