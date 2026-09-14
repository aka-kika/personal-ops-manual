---
name: personal-ops-manual
version: 2.0
description: >
  Use when the owner asks about their own technical setup: machines, network
  nodes, which service runs on which port, launch agents and scheduled jobs,
  domains, backups, deployment routines, recovery steps, API endpoints, or
  recurring maintenance. Triggers: "ops manual", "my setup", "what runs on
  port", "where is X running", "which machine", "how do I recover", "document
  this in the manual". Tool-shaped: anything that calls list_documents,
  get_document, search_documents, list_categories, get_stale, report_change,
  or list_reports on the personal-ops-manual MCP server. Also use when you
  changed something in the setup and need to tell the operator.
---

# Personal Ops Manual, house rules for readers

**Read through the MCP · only the operator writes · changed something? report it · never a secret.**

The Personal Ops Manual is the owner's reference for their own
infrastructure: a native macOS app over a folder of plain Markdown files with
YAML frontmatter. The files are the truth. The app watches the folder, so a
change on disk shows up without touching the app.

## Where things are

| Thing | Where |
|---|---|
| Documents folder (the truth) | chosen in the app's Settings, General; default `~/Documents/Personal Ops Manual/` |
| App | `/Applications/Personal Ops Manual.app` |
| MCP server | `mcp/server.mjs` in the app repo |
| Inbox for reports | `_inbox/reports.md` inside the documents folder |

The folder is standalone: every page carries the facts it needs and never
points at a private note for more. Agents without access to the owner's other
notes get the whole picture from here.

## Reading

Every agent may read. The MCP server `personal-ops-manual` exposes seven tools
and nothing else:

| Tool | Use it for |
|---|---|
| `list_categories` | The shape of the manual: category names with counts. Start here. |
| `list_documents` | Pages with id, title, category, tags, summary, timestamps. Filter by `category`, page with `limit` and `offset`; the reply carries `total`. |
| `search_documents` | Ranked search: title hits first, then tag, summary, body. Each hit has `matchedIn`, `updatedAt`, and a snippet. |
| `get_document` | One page in full by id, including the body and custom properties. |
| `get_stale` | The re-verification queue: oldest Verified date first, or pages with open `- [ ]` checkboxes. |
| `report_change` | Tell the operator something changed or a page is stale. Appends one line to the inbox; never touches a page. |
| `list_reports` | The inbox: open reports (default), handled, or all. |

If the server is not wired into your client, read the files directly from the
documents folder. Same content, same rules.

When a page links to `[[Another page]]`, `search_documents` on that title to
get its id.

## Reporting a change

You do not edit pages. When you change something in the setup during your
work (a new MCP server, a moved config, a port, a launch agent, a domain), or
you notice a page that no longer matches the machine, file a report before
you finish:

```
report_change(agent: "<your name>", page: "<page title or id, or none>",
              what: "<one sentence>", evidence: "<command, path, or what you saw>")
```

It appends one dated line to `_inbox/reports.md`. The operator reads the
inbox at the start of every session, applies what is true to the pages, and
ticks the line. If the same fact matters right now, also tell the owner in
the chat. Do not report things you only guessed.

The manual holds only what exists today, running or parked. It is not a
history record: a cancelled service, a removed server, a replaced tool has no
page and no mention; the owner's other notes keep the story. If you find a
page for a thing that no longer exists, report it as gone so the operator
removes it; do not ask the manual what used to be.

## Writing

There are no page write tools on purpose. One operator edits the files
directly, following its own operator skill. Everyone else reports what is
stale or missing and lets the operator change it.

## House style of the pages (so you can read them well)

- One page per thing: a machine, a service, a domain, a routine.
- One sentence first, then short `##` sections, bullets over prose, commands
  in fenced blocks, tables for things with two or more attributes.
- Open questions as `- [ ]` under `## To confirm`.
- A rule, then `## Related` with `[[links]]`; a rule, then one quote line:
  `> **Verified** YYYY-MM-DD by <how>`. That date is what `get_stale` reads.
- Never a secret on a page; the page names where the secret lives.
