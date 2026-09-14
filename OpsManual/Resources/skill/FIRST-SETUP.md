# First setup

How to stand up the Personal Ops Manual on a machine and fill it, whether you
do it yourself or hand the job to an agent. Read `PHILOSOPHY.md` first: one
operator writes, everyone else reads and reports.

## 1. Install the app

Download the zip from Releases and drop the app into `/Applications`, or
build it:

```bash
git clone https://github.com/aka-kika/personal-ops-manual.git
cd personal-ops-manual
brew install xcodegen   # once
./build.sh --install    # Release build, ad hoc signed, into /Applications
```

macOS 26 or newer; Xcode 27 to build. Open the app once. In Settings, General,
point it at the folder that will hold the pages (default
`~/Documents/Personal Ops Manual`). An empty folder is fine; the app creates
it. If you keep notes in Obsidian or similar, a folder inside that vault works
well: the pages are plain Markdown.

## 2. Install the MCP server for every reader

```bash
cd mcp && node --version && npm install   # node 18 or newer
```

Then add the server to each agent (the exact snippets are in Settings, MCP):

```bash
claude mcp add --scope user personal-ops-manual -- node /path/to/personal-ops-manual/mcp/server.mjs
```

Same command and path go into Claude Desktop, Cursor, Goose, and any other
MCP client. The server finds the folder through the app's setting, or
`OPS_MANUAL_DIR`, or the default path. Check with a `list_categories` call
from one agent.

## 3. Install the skills

- Every reader gets the reader skill (Settings, Skills, Save SKILL.md) in its
  skills folder. It tells the agent how to read the manual and how to file a
  report when it changes something.
- Only the operator gets the operator skill (Settings, Skills, Save
  OPERATOR.md), for example at `~/.claude/skills/ops-manual-operator/SKILL.md`
  for Claude Code. Never give it to the other agents.

## 4. Gather the setup into pages

The operator does this, on your request. Work from the machine, not from
memory: every fact comes from a command or a file, and the Verified line says
which. One page per thing. Categories are fixed unless you add one.

| Category | Sources to read | One page per |
|---|---|---|
| Manual | this repo's docs | how the manual works (one page) |
| Machines | `hostname`, `sw_vers`, `sysctl hw`, `df`, `tailscale status --json` | Mac, server, phone, tablet |
| Services | `lsof -iTCP -sTCP:LISTEN`, `launchctl list`, app configs | service with a port |
| Self-hosted | your hosting dashboards, Docker, the notes you already have | hosted service |
| Automations | `~/Library/LaunchAgents/*.plist`, cron, `brew services list` | launchd job, cron job |
| Agents | each agent's config folder, `claude mcp list`, skills folders | agent (with `icon:`) |
| MCP (mine) | servers you built | server you built |
| MCP (third-party) | agent configs | server from someone else |
| Skills | your skill folders | the collection, the sync |
| Domains | registrar, DNS, hosting | domain |
| Backups | Time Machine, offsite scripts, config snapshots | backup route |
| Deployments | hosting, package registries, GitHub releases | deployment target |
| Recovery | what has broken before | failure scenario |
| APIs | self-hosted APIs, push services, automation platforms | endpoint or API family |
| Maintenance | recurring chores | routine (weekly, monthly) |
| Releases | `gh release list`, PyPI, npm, Homebrew | public tool |
| Hooks | agent hook folders | hook script |

Rules while gathering:

- **Never a secret.** Tokens, keys, passwords, bearer strings stay out. Write
  where the secret lives (Keychain item, `.env` path, a separate secrets
  note). If a script has a token inline, say so on the page and tell the
  owner.
- **Unknowns are checkboxes** under `## To confirm`. The owner answers them
  later; `get_stale` with `mode: unchecked` collects them.
- **Link pages** with `[[Title]]` in a `## Related` section: agent to its MCP
  servers, service to its job and host, domain to its deployment.
- **Finish every page** with the rule and `> **Verified** YYYY-MM-DD by <how>`.
- Use the app's New Document (or Load Markdown File on a draft) for the first
  pages so the frontmatter and file names are right; after that, edit files
  directly following the operator skill.

## 5. Hand over

- Commit the repo changes (the pages live in the folder, not the repo).
- Tell the owner the open checkboxes as a short list.
- From then on, readers file changes with `report_change` and the operator
  empties `_inbox/reports.md` every session. The sidebar shows the open count
  as Inbox.
