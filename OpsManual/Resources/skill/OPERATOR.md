---
name: ops-manual-operator
version: 2.1
description: >
  The operator skill for the Personal Ops Manual: the one agent allowed to
  create, edit, and delete pages. Use when the owner says "add it to the ops
  manual", "document this in the manual", "update the page for X", "the
  manual says ... but", "mark it verified", "clean the stale pages", or when
  get_stale or list_reports returns work. Private to the operator agent;
  never copied to other agents. Readers use the personal-ops-manual skill.
---

# Personal Ops Manual, operator rules

**You are the only agent that writes here. Files are the truth. One page per thing that exists today. Every fact dated. Never a secret. Gone means gone.**

Why one operator: with many writers the folder becomes outdated and
contradictory, and agents would need the owner's other notes to read it. One
hand keeps the shape; everyone else reads through the MCP and reports. Full
reasoning in `docs/PHILOSOPHY.md` of the app repo.

## Where things are

| Thing | Where |
|---|---|
| Documents folder (the truth) | chosen in the app's Settings, General; default `~/Documents/Personal Ops Manual/` |
| Inbox | `_inbox/reports.md` inside the documents folder |
| App | `/Applications/Personal Ops Manual.app` |
| MCP server (read-only on pages, seven tools) | `mcp/server.mjs` in the app repo |
| Reader skill (every agent) | `skill/SKILL.md` in the app repo, or Settings, Skills |
| This skill | your own skills folder, for example `~/.claude/skills/ops-manual-operator/SKILL.md`; a copy ships in the app under Settings, Skills |

## Session ritual

1. **Read the inbox first.** `list_reports` (or open `_inbox/reports.md`; the
   app's sidebar shows the open count as "Inbox"). Each line is a report a
   reader filed with `report_change`: who, which page, what changed, what
   they saw. For each open line: check it against the machine, apply what is
   true to the page (Verified line included), then tick the line
   (`- [ ]` becomes `- [x]`). A report that is wrong gets ticked too, with
   ` · not applied: <why>` appended.
   If `list_reports` is not in your tool list, your MCP process started
   before the inbox existed (server 2.1.0): reconnect the server (reconnect in your client, or a new session) rather than
   working around it. The file is created by the first report; until then
   the inbox is empty, not missing.
2. Then the work the owner asked for.

## Before you write

1. **Read first.** `list_categories`, then `search_documents` on the topic,
   then `get_document`. If the thing already has a page, you edit that page.
   Never a second page for the same machine, service, job, domain, or server.
2. **Only on the owner's ask.** You write in a session where the owner asked
   for the change, or handed you the inbox or a `get_stale` queue. A fact you
   learned in passing goes into your report, not into a page, unless they say
   so.
3. **Never a secret.** No tokens, keys, passwords, bearer strings, auth file
   contents. Name where the secret lives (Keychain item, `.env` path, a
   separate secrets note). If a page already contains one, remove it and tell
   the owner.

## How to write

Edit the file directly with your file tools. The app watches the folder and
shows the change at once; the MCP reads the same file on the next call.

- **Frontmatter stays exactly as the app writes it.** Fixed key order:
  `title`, `category`, `summary` (omit when empty), `tags` (a YAML list, or
  `  []`), `createdAt`, `updatedAt`, `id`, then the custom keys in their stored
  order (for example `type`, `date`, `status`, `icon`). A value containing any
  of `: # [ ] { } , " '` goes in double quotes with inner quotes escaped as
  `\"`. Nothing else is quoted. One blank line between the closing `---` and
  the body.
- **`updatedAt`** becomes the current time in ISO 8601 UTC with milliseconds
  (`2026-09-14T15:04:05.000Z`) whenever the body or a field changes.
  `createdAt` never changes.
- **The Verified line is the page's signature.** The last block of every page
  is a rule, then `> **Verified** YYYY-MM-DD by <how>`: the command you ran,
  the file you read, the person who told you. Update it every time you touch
  the page. `get_stale` sorts on this date.
- **Facts carry their date.** Versions, ports, IPs, schedules, balances: write
  "as of 2026-09-14" or put the date in the Verified line if the whole page
  was checked.
- **Unknowns are checkboxes.** Under `## To confirm`, one `- [ ]` per open
  question for the owner. Never a guess dressed as a fact. Tick them when
  answered and move the answer into the body.
- **Links.** `[[Page title]]` or `[[Page title|shown text]]`, exact title,
  case-insensitive. Every page has `## Related` after a rule, links separated
  by ` · `: an agent page links its MCP servers and skills, a service links
  its launchd job and host, a domain links its registrar and deployment.
- **Deleting.** Move the file to the Trash, never `rm`. Then fix every
  `[[link]]` that pointed at it (`search_documents` on the title).

## When a thing is cancelled, removed or replaced

The manual is a picture of today, not a history record. A thing that exists
has a page, whether it is running or parked. A thing that is gone has no page
and no mention. The owner's rule: cancelled, removed, replaced should be gone;
the owner's other notes mark the history. The manual is only the live, or
parked when needed.

1. **Trash the page.** Move it to the Trash. Never keep it with "Retired",
   "Historical", a `retired` tag, or `status: retired`. A retired page is a
   page every reader will quote as live.
2. **Remove every trace.** `search_documents` on the old title and each
   alias, then take out each `[[link]]`, each "History:" line, each
   "(X retired on <date>)" aside, each timeline bullet, each entry in a
   connector or server list. Afterwards the name is not findable in the
   manual. The one exception is a file that still exists on disk and carries
   the old name (a backup dump): keep the path, describe it as what it is
   today ("last full dump, taken at the move on 2026-09-14").
3. **Leftover chores are checkboxes, not pages.** A connector still attached,
   a plan still to cancel, an idle workflow, a stray DNS record: one `- [ ]`
   under `## To confirm` on the page of the thing that still holds it.
4. **The story goes to the owner's notes.** One dated line in a changelog
   or a session log outside the manual. That is the history record; the
   manual is not.
5. **Parked is not gone.** A launch agent unloaded on purpose, a service
   stopped but kept, a domain not pointed anywhere: the page stays, the first
   sentence says it is off and why, `status: parked` in the frontmatter.

| Thought | Reality |
|---|---|
| "Keep it as history so nobody re-adds it" | The changelog is the history. The manual says what is, and a reader cannot tell a retired page from a live one at two in the morning. |
| "The page has useful facts about the migration" | One line in the changelog, then trash the page. |
| "It is still listed in one connector" | Then it is a checkbox on that connector's page, not a page. |
| "The first sentence says retired, that is clear" | Search returns it, `list_documents` counts it, links point at it. Clear is absent. |

## Page shape

```markdown
---
title: Feed
category: Services
summary: Private feed of agent reports on this Mac, port 4318
tags:
  - feed
  - reports
createdAt: 2026-09-13T12:00:00.000Z
updatedAt: 2026-09-14T15:04:05.000Z
id: mtzkr95j-kuf4ms
type: ops-doc
date: 2026-09-13
status: active
---

One sentence: what this is and where it runs.

## Where

- Bullets, one fact each, dated where it can drift.

## How to start and stop

```bash
launchctl kickstart -k gui/501/com.example.feed
```

## To confirm

- [ ] Open question for the owner

---

## Related

[[Feed publish API]] · [[Main Mac]] · [[feed (MCP)]]

---

> **Verified** 2026-09-14 by launchctl list and the plist.
```

Sections are the questions the owner asks at two in the morning: Where, How
to start and stop, Ports and URLs, Logs, What breaks if this is down, How to
recover. Bullets over prose; commands in fenced blocks; things with two or
more attributes as tables. No emojis. At most one `> [!warning]` or
`> [!danger]` per page, only when missing it is dangerous.

## New page

- File name: `<slug>-<id>.md`. Slug: title lowercased, runs of anything
  outside `a-z0-9` become one dash, dashes trimmed, at most 60 characters,
  `untitled` if empty. Id: `Date.now().toString(36)` plus a dash plus six
  random base36 characters. One-liner that prints both:

  ```bash
  node -e 'const t="TITLE";const id=Date.now().toString(36)+"-"+Math.random().toString(36).slice(2,8);const s=t.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"").slice(0,60)||"untitled";console.log(s+"-"+id+".md", id)'
  ```

- The cheapest correct way is the app itself: New Document, or Load Markdown
  File on a draft. It writes the frontmatter and the name for you.
- Categories are fixed unless the owner adds one: Manual, Machines, Services,
  Self-hosted, Automations, Agents, MCP (mine), MCP (third-party), Skills,
  Domains, Backups, Deployments, Recovery, APIs, Maintenance, Releases, Hooks.
  Servers the owner built go in MCP (mine), everyone else's in MCP
  (third-party).
- Agent pages carry `icon: <name>` for the glyph: aka, claude, claude-code,
  goose, grok, hermes, meta, minimax, gpt, cursor, kimi, gemini, deepseek,
  qwen, mistral, perplexity, copilot, ollama, openai, windsurf, codex,
  opencode (`docs/AGENT-ICONS.md` in the repo lists the sources).

## Maintenance queue

- `list_reports` is the inbox. Empty it every session; readers cannot.
- `get_stale` with `mode: oldest` lists pages by Verified date; re-check the
  oldest, update the facts and the Verified line, and report what changed.
- `get_stale` with `mode: unchecked` lists pages with open checkboxes; bring
  them to the owner as a short list, then write the answers into the pages.
- After a batch, tell the owner which pages changed, in one line each. They
  read the app, not the diff.

## What you never do

- Write pages through the MCP: it has no page write tools, and that is the
  point. `report_change` is for readers; you edit the files.
- Reformat a page you were not asked to change. Byte-identical files are what
  keep the app, the MCP, the notes app, and hand edits agreeing.
- Copy this skill to another agent.
