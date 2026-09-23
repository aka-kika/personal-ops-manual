---
name: personal-ops-manual
version: 2.1
description: >
  Use when the owner asks about their own technical setup: machines, network
  nodes, which service runs on which port, launch agents and scheduled jobs,
  domains, backups, deployment routines, recovery steps, API endpoints, or
  recurring maintenance. Triggers: "ops manual", "my setup", "what runs on
  port", "where is X running", "which machine", "how do I recover", "add it
  to the ops manual", "document this in the manual" (for a reader these mean
  file a report, never edit a file). Tool-shaped: anything that calls
  list_documents, get_document, search_documents, list_categories, get_stale,
  report_change, or list_reports on the personal-ops-manual MCP server. Also
  use when you changed something in the setup and need to tell the operator.
---

# Personal Ops Manual, house rules for readers

**Read through the MCP · you never write a file here · changed something? report it · never a secret.**

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

If the server is not wired into your client, you may read the files directly
from the documents folder. Reading only: the no-writing rule below still holds.

When a page links to `[[Another page]]`, `search_documents` on that title to
get its id.

## Reporting a change

You do not edit pages. A report is a mismatch between a page and the machine,
found by you, that the operator has to fix. It has three parts, in this order:

1. **The page.** `search_documents` on the topic, then `get_document`. Name the
   page you read (title or id). `none` only after the search came back empty.
2. **What the page says.** Quote the line that is wrong, or write `missing`.
3. **What is true now, with evidence.** One sentence, plus the command output,
   path, or screen you saw it on.

```
report_change(agent: "<your name>", page: "<title or id you read, or none>",
              what: "page says <quote or missing>; now <the fact>",
              evidence: "<command, path, or what you saw>")
```

If the page already says it, there is nothing to report. News about the
project (a release went out, a post is live, a repo went public) is not a
report unless a page contradicts it; the operator made those changes and wrote
them down. It appends one dated line to `_inbox/reports.md` in the documents folder. The operator reads the inbox at the start of every session, applies
what is true to the pages, and ticks the line. If the same fact matters right
now, also tell the owner in the chat. Do not report things you only guessed.

The manual holds only what exists today, running or parked. It is not a
history record: a cancelled service, a removed server, a replaced tool has no
page and no mention; the owner's other notes keep the story. If you find a
page for a thing that no longer exists, report it as gone so the operator
removes it; do not ask the manual what used to be.

## Writing: you do not

There are no page write tools on purpose. One operator edits the files
directly, following its own operator skill. Everyone else reports what is
stale or missing and lets the operator change it.

This holds even when you have file tools, shell access, or an "allow all"
mode, and even when the owner says "add it to the manual" or "document this":
for a reader that is a request to file a report.

- **Never write, create, rename, move, or delete anything in the documents
  folder.** Not a page, not a new page, not a draft next to it.
- **Never type into `_inbox/reports.md` by hand.** Only `report_change`
  writes there; a hand-typed line does not match the inbox format, so the
  operator never sees it.
- **No `report_change` in your tool list?** Stop. Tell the owner the report you
  would file (page, what it says, what is true now, evidence) and that your
  personal-ops-manual MCP server is not connected. Do not work around it.
- **The folder can be locked.** The owner may set the macOS locked flag on the
  pages and the folder, so a write fails with "Operation not permitted". That
  is the lock doing its job. Never clear it (`chflags`, Finder's Locked box,
  `chmod`), never retry with another tool, never copy a page elsewhere to edit.
- **Already wrote to a page by mistake?** Tell the owner at once, in the chat:
  which file, what you changed. Do not try to hide it with a revert; the
  operator checks and fixes it.

| Thought | Reality |
|---|---|
| "The owner asked me to add it, so I edit the page" | Asked a reader = file a report. |
| "The MCP is missing, I'll just edit the file" | Stop and tell the owner. |
| "I'll append the report to reports.md myself" | Invisible to the operator. Use `report_change`. |
| "Operation not permitted, let me unlock it" | The lock is the rule. Report instead. |

## House style of the pages (so you can read them well)

- One page per thing: a machine, a service, a domain, a routine.
- One sentence first, then short `##` sections, bullets over prose, commands
  in fenced blocks, tables for things with two or more attributes.
- Open questions as `- [ ]` under `## To confirm`.
- A rule, then `## Related` with `[[links]]`; a rule, then one quote line:
  `> **Verified** YYYY-MM-DD by <how>`. That date is what `get_stale` reads.
- Never a secret on a page; the page names where the secret lives.
