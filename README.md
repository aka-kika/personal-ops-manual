<p align="center"><img src="docs/icon.png" width="128" alt="Personal Ops Manual icon"></p>

# Personal Ops Manual

<p align="center">
<img alt="macOS 26 or newer" src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white">
<img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
<img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-0A84FF">
<img alt="Notarized" src="https://img.shields.io/badge/Developer%20ID-notarized-2DA44E">
<img alt="MCP server" src="https://img.shields.io/badge/MCP-7%20tools-6E56CF">
<img alt="Markdown files" src="https://img.shields.io/badge/data-Markdown%20%2B%20YAML-555555">
<img alt="Version" src="https://img.shields.io/badge/release-2.1.1-blue">
<img alt="MIT license" src="https://img.shields.io/badge/license-MIT-green">
</p>

<p align="center"><a href="https://ops-manual.akakika.com/">ops-manual.akakika.com</a> · <a href="https://github.com/aka-kika/personal-ops-manual/releases/latest">latest release</a></p>

A native macOS app and an MCP server over one folder of Markdown pages that
describe your setup: machines, services, launch agents, agents, MCP servers,
domains, backups, recovery steps. The folder is the truth; the app and the
server are two windows onto it. One operator writes, every other agent reads
and reports.

![Personal Ops Manual, three columns: categories on the left, the Agents list in the middle, an agent page open in the reader with its config paths, hooks and the MCP servers it is wired into](docs/screenshots/01-agents-claude-code.png)

- macOS 26 or newer. Swift 6, SwiftUI, XcodeGen, swift-markdown.
- Three columns: categories, pages, reader. Wiki links between pages,
  "Linked from", agent glyphs, a New and Edit sheet, search, settings.
- `mcp/server.mjs`: seven tools for any MCP client, read-only on pages
  (`list_categories`, `list_documents`, `search_documents`, `get_document`,
  `get_stale`) plus an inbox (`report_change` appends a line, `list_reports`
  reads it) so readers can tell the operator what changed. Node 18 or newer.

## One page per thing

Every machine, service, agent or domain gets exactly one page, and every page
looks the same: one line that says what it is, a few short sections, links to
the pages that belong with it, and a last line that says when someone last
checked the facts and how.

![An agent page in the reader: config paths, wired MCP servers, a Related row of page links, and the Verified line](docs/screenshots/02-reader-cursor.png)

Pages point at each other with `[[links]]`. Open a page and the app also
shows you which other pages point back at it, so nothing is ever a dead end.
At the bottom, a small Frontmatter section shows the page's properties: its
category, tags, dates and id.

![A server page with its Related links, the Linked from list of pages pointing here, and the Frontmatter disclosure showing the page properties as rows](docs/screenshots/03-linked-from-frontmatter.png)

## The manual describes itself

The manual has a page about itself: where the files live, how to connect an
agent, and who is allowed to change things. Anyone who opens the folder for
the first time can read the rules right there.

![The How this manual works page: where the files live, the app and MCP paths, and the rule that only one agent edits pages](docs/screenshots/04-how-this-manual-works.png)

Anything you have shipped gets a page too, under Releases: what it is, where
the website and the code are, the latest version, and how to install it. One
place to look instead of five browser tabs.

![The Releases category: one page per public tool, with website, source, latest release, the install line and the notarization note](docs/screenshots/05-releases-sift.png)

## Install

Download the zip from Releases, unzip, drop the app into `/Applications`.
Or build it: `./build.sh --install` (ad hoc signed, for the machine you
build on).

Everything else, from the MCP install lines to the skills, is in the app's
Settings and in `docs/FIRST-SETUP.md`.

## Docs

- `docs/FIRST-SETUP.md` — standing the manual up on a new machine
- `docs/PHILOSOPHY.md` — why only one agent writes
- `docs/HANDOFF.md` — the code, how to build, known gaps
- `docs/AGENT-ICONS.md` — the glyphs and where they came from
- `skill/` — the reader skill for every agent and the operator skill for one
- `CONTRIBUTING.md` — how to build, test, and send a change; `LICENSE` is MIT

## Release

`./release.sh` builds with Developer ID, notarizes, staples, and zips;
`--install` replaces the installed app, `--publish` creates the GitHub
release. It reads the signing identity from a git-ignored `release.env`; the
script header says what goes in it.

## Contributing

Issues and pull requests are welcome; `CONTRIBUTING.md` has the build steps
and the house style.

## License

MIT. See `LICENSE`.
