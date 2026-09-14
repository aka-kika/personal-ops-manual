# Handoff

Personal Ops Manual, native SwiftUI. What the code is, how to build it, what
is still rough.

## What this is

A three-column Markdown reader and editor over one folder of frontmatter
files. The folder is the source of truth; the app and the MCP server are two
windows onto it. One operator edits, everyone else reads and reports
(`PHILOSOPHY.md`).

## Layout

- `project.yml` — XcodeGen. Targets `OpsManual` (app, product name "Personal
  Ops Manual", bundle id `com.kikalab.opsmanual`) and `OpsManualTests`.
- `OpsManual/App` — `OpsManualApp` (scenes, appearance, commands), `AppState`
  (selection, sheets), `Commands`.
- `OpsManual/Models` — `OpsDocument`, `DocDraft`, `AppSettings` (defaults
  keys, default folder).
- `OpsManual/Services` — `FrontmatterCodec` (fixed key order and quoting so
  files stay byte-identical across writers; see its header for the two quirks
  kept on purpose), `DocumentStore` (`@MainActor @Observable`, atomic writes,
  on-disk file name tracking, Finder Trash, search, backlinks, inbox count),
  `FolderWatcher`, `MarkdownText`, `WikiLinks`.
- `OpsManual/Theme` — `WindowChrome` and `TitlebarClickRouting` (merged
  title bar with the traffic lights in the sidebar row, adapted from an
  earlier app of the author's), `OpsTheme` tokens (canvas `#2A2A2D`, sidebar
  `#2E3036`).
- `OpsManual/Views` — Sidebar, List, Reader (swift-markdown AST rendered by
  hand, measured table rows), Editor sheet, Search palette, Settings (tabs:
  General, MCP, Skills, About), shared `ColumnHeader` (38 pt chrome row +
  32 pt title row).
- `OpsManual/Resources` — asset catalog (app icon, agent glyphs, brand marks),
  bundled `skill/SKILL.md`, `skill/OPERATOR.md`, `skill/FIRST-SETUP.md` and
  `mcp-install.txt` handed out from Settings.
- `mcp/server.mjs` — the stdio MCP server, read-only on pages: seven tools
  (`list_categories`, `list_documents` with category/limit/offset,
  `search_documents` ranked with updatedAt, `get_document`, `get_stale`,
  `report_change` which appends one line to `_inbox/reports.md`,
  `list_reports`). Folder path from `defaults read com.kikalab.opsmanual
  documentsPath`, else `OPS_MANUAL_DIR`, else `~/Documents/Personal Ops
  Manual`. `npm install` inside `mcp/` once; Node 18 or newer.
- `skill/SKILL.md` — the reader skill for every agent; `skill/OPERATOR.md` —
  the operator skill for one. Both are bundled and offered in Settings.
- `docs/` — first setup, philosophy, agent icons, this file.

## Build and install

```bash
./build.sh            # Release build, ad hoc signed, under build/
./build.sh --install  # also moves the old /Applications bundle to the Trash and installs
```

Tests: `xcodegen generate && xcodebuild -project OpsManual.xcodeproj -scheme
OpsManual -destination 'platform=macOS' test`. The codec round-trip test over a
real folder runs only when `OPS_MANUAL_TEST_DIR` points at one.

`./release.sh` is the public path: Developer ID Application signature,
hardened runtime, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` (Apple rejects the
injected `get-task-allow` entitlement), notarized through a notarytool
Keychain profile, stapled, zipped to `build/release/`; `--install` replaces
the installed app, `--publish` creates the GitHub release. Identity and
profile come from a git-ignored `release.env`. Both install paths unregister
the build copy from LaunchServices and restart the Dock, otherwise macOS can
keep showing an older icon from a stray build product.

## Known gaps

- "Linked from" is a vertical list; an inline wrapping row would be tighter.
- Header buttons in the merged title bar are not reachable by assistive
  technology (the click router shadows them).
- No keyboard navigation in the list; `opsmanual://` links are only handled
  inside the reader.
- The two frontmatter parsers (Swift and Node) are hand-rolled and must not
  drift; multiline YAML is outside the contract.
