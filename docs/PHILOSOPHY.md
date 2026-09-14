# Why one operator

The Personal Ops Manual is the single place that describes how a setup
actually works: the machines, the services, the agents, the domains, the
backups, the recovery steps. Any number of agents read it through the MCP
server. Exactly one agent, the operator, is allowed to create, edit and delete
pages. Everything else is a reader.

## The problem it solves

The information usually already exists, spread across a notes app, agent
configs, plists and someone's head. That is not enough, for three reasons
that compound:

1. **A notes folder is only reachable by agents that have the notes.** Giving
   an agent a whole vault so it can read one folder gives it everything else:
   personal notes, keys, drafts, contracts. The manual has to be readable
   without that.
2. **Shared write access rots the content.** When every agent can edit, every
   agent edits in its own style, at its own moment, with its own idea of what
   is true. Pages drift apart, duplicate each other, contradict each other,
   and nobody owns the fix. Within weeks the folder is what the notes were:
   outdated, messy, broken.
3. **A source of truth needs a shape.** One page per thing, the same sections
   on every page, a Verified line with a date and a source, links between
   pages instead of prose that repeats itself. A shape survives only if one
   hand keeps it.

## The rule

- **The folder is the source of truth.** Plain Markdown files with
  frontmatter in one folder. The app is a window onto that folder; the MCP
  server is another. Neither owns the data.
- **Readers read, and report.** The server exposes list, search, get, a
  re-verification queue, and an inbox. When a reader changes something in the
  setup, it files a one-line report; that append is the only write the server
  allows and it never touches a page. No agent needs the rest of your notes to
  use it, so secrets stay unreachable.
- **One operator writes.** The person, by hand or through the app, and the
  one agent designated as operator. The operator carries the operator skill,
  which encodes the page shape, the frontmatter contract, the naming rule and
  the Verified discipline, and starts every session by emptying the inbox. A
  change made by anyone else is a bug.
- **The manual is today.** A thing that exists has a page, running or
  parked. A thing that was cancelled, removed or replaced has no page and no
  mention; its story lives in a changelog or a session log outside the
  manual. A reader at two in the morning cannot tell a "retired" page from a
  live one, so retired pages do not exist.
- **Consistency over convenience.** A page is one thing, in one place, in the
  agreed shape. If information does not fit the shape, the shape is discussed
  first, then the information is added.

## What this buys

- Agents get accurate, current operational facts without touching your notes.
- You get one place to look, and one place to fix.
- The folder stays legible to any notes app, to `grep`, and to any future
  tool, because it is only files.
- The data outlives the app. The app can be replaced without a migration,
  because the files never change shape.

## What it costs

- The operator is a bottleneck by design. Other agents that learn something
  new about the setup report it and wait, instead of writing it themselves.
  That delay is the price of a manual that stays true.

In the author's words, from the day the rule was made: "if all agents can edit
it is the same thing as having the folder just in the notes app; eventually it
is outdated, messy, broken, and agents need access to the vault to reach the
folder. Here it is all organized, consistent, and agents do not need vault
access to reach this info, so personal keys and files are not reachable at
all."
