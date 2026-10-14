#!/usr/bin/env node
/* global console */
// mcp/server.mjs — Standalone stdio MCP server for Personal Ops Manual (native app)
// READ-ONLY on pages by design: agents can list, read, and search
// the same .md files the app uses, but never write them through this server. Edits
// happen in the app or directly on the files, by the one operator.
// The single exception (2026-09-14): report_change appends one line to
// _inbox/reports.md so readers can tell the operator what drifted. It can never
// touch a page.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import os from "node:os";
import { execFileSync } from "node:child_process";

// ── Documents path ───────────────────────────────────────────────────────
// The native app (com.kikalab.opsmanual) stores the folder in its defaults;
// OPS_MANUAL_DIR overrides it; otherwise the manual's canonical folder.

const DEFAULT_DOCS_DIR = path.join(os.homedir(), "Documents", "Personal Ops Manual");

function getDocsDir() {
  if (process.env.OPS_MANUAL_DIR) return process.env.OPS_MANUAL_DIR;
  try {
    const out = execFileSync("defaults", ["read", "com.kikalab.opsmanual", "documentsPath"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (out) return out;
  } catch {
    // key not set: fall through
  }
  return DEFAULT_DOCS_DIR;
}

if (process.argv.includes("--print-docs-dir")) {
  console.log(getDocsDir());
  process.exit(0);
}

// ── Frontmatter serialize / parse (mirrors document-store.ts) ────────────

const KNOWN_KEYS = new Set(["title", "category", "tags", "createdAt", "updatedAt", "id", "summary"]);

function unquote(val) {
  if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
    return val.slice(1, -1).replace(/\\"/g, '"');
  }
  return val;
}

// Same rules as FrontmatterCodec.parse in the app: CRLF read as LF, the first
// value of a repeated key wins, list tags stay whole (a comma inside one is
// kept), inline tags are unquoted.
function parseFrontmatter(raw) {
  const text = raw.replace(/\r\n/g, "\n");
  const match = text.match(/^---\n([\s\S]*?)\n---(?:\n([\s\S]*))?$/);
  if (!match) return { meta: {}, fields: [], tags: [], body: text };
  const fields = [];
  let tags = [];
  let collectingTags = false;

  for (const line of match[1].split("\n")) {
    const listMatch = line.match(/^[ \t]+- (.*)$/);
    if (listMatch && collectingTags) {
      tags.push(unquote(listMatch[1].trim()));
      continue;
    }
    collectingTags = false;
    const idx = line.indexOf(":");
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    const val = line.slice(idx + 1).trim();
    if (key === "tags") {
      if (val === "" || val === "[]") {
        collectingTags = true;
        continue;
      }
      const inner = val.replace(/^\[/, "").replace(/\]$/, "");
      tags = inner.split(",").map((t) => unquote(t.trim())).filter(Boolean);
      continue;
    }
    fields.push({ key, value: unquote(val) });
  }

  const meta = {};
  for (const { key, value } of fields) if (!(key in meta)) meta[key] = value;
  return { meta, fields, tags, body: (match[2] ?? "").trimStart() };
}

function extractProperties(fields) {
  return fields.filter(({ key }) => !KNOWN_KEYS.has(key)).map(({ key, value }) => ({ key, value }));
}

// Fenced code blocks hold examples (page templates), not the page's own
// Verified line or open checkboxes.
function withoutFences(body) {
  const out = [];
  let fence = null;
  for (const line of body.split("\n")) {
    const m = line.match(/^\s{0,3}(`{3,}|~{3,})/);
    if (fence) {
      if (m && m[1][0] === fence[0] && m[1].length >= fence.length) fence = null;
      continue;
    }
    if (m) { fence = m[1]; continue; }
    out.push(line);
  }
  return out.join("\n");
}

function stripMarkdown(text) {
  return text
    .replace(/```[\s\S]*?```/g, "")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/__([^_]+)__/g, "$1")
    .replace(/_([^_]+)_/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
    .replace(/^[\s]*[-*+]\s+/gm, "")
    .replace(/^[\s]*\d+\.\s+/gm, "")
    .replace(/^>\s+/gm, "")
    .replace(/^---+$/gm, "")
    .replace(/\|/g, " ")
    .replace(/\n{2,}/g, "\n")
    .replace(/\s{2,}/g, " ")
    .trim();
}

// ── File I/O ─────────────────────────────────────────────────────────────

function readAllFiles() {
  const dir = getDocsDir();
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  const mdFiles = entries.filter((f) => f.endsWith(".md"));
  const docs = [];
  for (const file of mdFiles) {
    try {
      const filePath = path.join(dir, file);
      const raw = fs.readFileSync(filePath, "utf-8");
      const { meta, fields, tags, body } = parseFrontmatter(raw);
      if (!meta.id) continue;
      // A missing date falls back to the file's own date, never to "now":
      // "now" would hide the page from get_stale and pin it to the top.
      const fileDate = () => fs.statSync(filePath).mtime.toISOString();
      docs.push({
        id: meta.id,
        title: meta.title || "Untitled",
        category: meta.category || "Uncategorized",
        tags,
        createdAt: meta.createdAt || fileDate(),
        updatedAt: meta.updatedAt || fileDate(),
        summary: meta.summary || "",
        properties: extractProperties(fields),
        body,
      });
    } catch {
      // Skip unreadable files
    }
  }
  return docs;
}

function findDocById(id) {
  return readAllFiles().find((d) => d.id === id) ?? null;
}

// ── Tool helpers ────────────────────────────────────────────────────────

function summarize(doc) {
  return {
    id: doc.id,
    title: doc.title,
    category: doc.category,
    tags: doc.tags,
    summary: doc.summary,
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

// ── Server ──────────────────────────────────────────────────────────────

const server = new McpServer({ name: "personal-ops-manual", version: "2.2.0" });

const VERIFIED_RE = /^>\s*\*\*Verified\*\*\s*(\d{4}-\d{2}-\d{2})/m;
const UNCHECKED_RE = /^\s*[-*+]\s+\[ \]\s+(.+)$/gm;

function verifiedDate(doc) {
  const m = VERIFIED_RE.exec(withoutFences(doc.body));
  return m ? m[1] : null;
}

function uncheckedItems(doc) {
  const items = [];
  for (const m of withoutFences(doc.body).matchAll(UNCHECKED_RE)) items.push(m[1].trim());
  return items;
}

function text(payload) {
  return { content: [{ type: "text", text: JSON.stringify(payload, null, 2) }] };
}

// list_documents — summaries, filterable by category, paged
server.registerTool(
  "list_documents",
  {
    title: "List documents",
    description:
      "List documents in the Personal Ops Manual: id, title, category, tags, summary, timestamps. Sorted by category then title. Filter with `category`; page with `limit` (default 200) and `offset`. The response carries `total` so you know when you have everything.",
    inputSchema: {
      category: z.string().optional().describe("Exact category name, as returned by list_categories"),
      limit: z.number().int().min(1).max(500).optional().describe("Max documents to return (default 200)"),
      offset: z.number().int().min(0).optional().describe("Skip this many documents first (default 0)"),
    },
  },
  async ({ category, limit, offset }) => {
    let docs = readAllFiles();
    if (category) docs = docs.filter((d) => d.category === category);
    docs.sort((a, b) => a.category.localeCompare(b.category) || a.title.localeCompare(b.title));
    const start = offset ?? 0;
    const page = docs.slice(start, start + (limit ?? 200)).map(summarize);
    return text({ count: page.length, total: docs.length, offset: start, documents: page });
  },
);

// get_document — return full document by id
server.registerTool(
  "get_document",
  {
    title: "Get document",
    description: "Get a single document by its id, including the full Markdown body, summary, tags, and custom properties.",
    inputSchema: { id: z.string().describe("Document id") },
  },
  async ({ id }) => {
    const doc = findDocById(id);
    if (!doc) return text({ error: "Document not found" });
    return text(doc);
  },
);

// search_documents — ranked substring search: title, then tags, then summary or category, then body
server.registerTool(
  "search_documents",
  {
    title: "Search documents",
    description:
      "Search titles, tags, summaries, categories, and bodies. Hits are ranked: title matches first, then tag, then summary or category, then body; ties by title. Each hit carries `matchedIn`, `updatedAt`, and a snippet around the first body match. `limit` defaults to 50.",
    inputSchema: {
      query: z.string().describe("Search query (case-insensitive substring)"),
      limit: z.number().int().min(1).max(200).optional().describe("Max hits (default 50)"),
    },
  },
  async ({ query, limit }) => {
    const q = query.toLowerCase().trim();
    if (!q) return text({ count: 0, results: [] });
    const results = [];
    for (const doc of readAllFiles()) {
      let rank = null;
      let matchedIn = null;
      if (doc.title.toLowerCase().includes(q)) { rank = 0; matchedIn = "title"; }
      else if (doc.tags.some((t) => t.toLowerCase().includes(q))) { rank = 1; matchedIn = "tags"; }
      else if (doc.summary.toLowerCase().includes(q)) { rank = 2; matchedIn = "summary"; }
      else if (doc.category.toLowerCase().includes(q)) { rank = 2; matchedIn = "category"; }
      else if (doc.body.toLowerCase().includes(q)) { rank = 3; matchedIn = "body"; }
      if (rank === null) continue;
      const bodyIdx = doc.body.toLowerCase().indexOf(q);
      let snippet;
      if (bodyIdx !== -1) {
        const start = Math.max(0, bodyIdx - 40);
        const end = Math.min(doc.body.length, bodyIdx + q.length + 60);
        snippet = (start > 0 ? "…" : "") + doc.body.slice(start, end).trim() + (end < doc.body.length ? "…" : "");
      } else {
        snippet = doc.summary || doc.body.slice(0, 100).trim();
      }
      results.push({ rank, id: doc.id, title: doc.title, category: doc.category, matchedIn, updatedAt: doc.updatedAt, snippet: stripMarkdown(snippet) });
    }
    results.sort((a, b) => a.rank - b.rank || a.title.localeCompare(b.title));
    const capped = results.slice(0, limit ?? 50).map(({ rank, ...hit }) => hit);
    return text({ count: capped.length, total: results.length, results: capped });
  },
);

// list_categories — return all categories with document counts
server.registerTool(
  "list_categories",
  {
    title: "List categories",
    description: "List all document categories with the number of documents in each.",
    inputSchema: {},
  },
  async () => {
    const counts = {};
    for (const doc of readAllFiles()) {
      const cat = doc.category || "Uncategorized";
      counts[cat] = (counts[cat] || 0) + 1;
    }
    const categories = Object.entries(counts)
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => a.name.localeCompare(b.name));
    return text({ count: categories.length, categories });
  },
);

// get_stale — the re-verification queue: oldest pages, or pages with open checkboxes
server.registerTool(
  "get_stale",
  {
    title: "Get stale pages",
    description:
      "Pages that need a look. mode `oldest` (default) sorts by the Verified date on the page (falling back to updatedAt), oldest first. mode `unchecked` returns pages with open `- [ ]` checkboxes and lists them. Read-only; report findings to Kika or the operator, who edit the files.",
    inputSchema: {
      mode: z.enum(["oldest", "unchecked"]).optional().describe("oldest (default) or unchecked"),
      category: z.string().optional().describe("Restrict to one category"),
      limit: z.number().int().min(1).max(200).optional().describe("Max pages (default 20)"),
    },
  },
  async ({ mode, category, limit }) => {
    let docs = readAllFiles();
    if (category) docs = docs.filter((d) => d.category === category);
    const rows = docs.map((d) => ({
      id: d.id,
      title: d.title,
      category: d.category,
      updatedAt: d.updatedAt,
      verified: verifiedDate(d),
      openItems: uncheckedItems(d),
    }));
    let picked;
    if (mode === "unchecked") {
      picked = rows.filter((r) => r.openItems.length > 0).sort((a, b) => b.openItems.length - a.openItems.length || a.title.localeCompare(b.title));
    } else {
      const key = (r) => r.verified ?? r.updatedAt.slice(0, 10);
      picked = rows.sort((a, b) => key(a).localeCompare(key(b)) || a.title.localeCompare(b.title));
    }
    const page = picked.slice(0, limit ?? 20);
    return text({ mode: mode ?? "oldest", count: page.length, total: picked.length, pages: page });
  },
);

// ── Inbox: readers report, the operator applies ──────────────────────────

const INBOX_DIR = "_inbox";
const INBOX_FILE = "reports.md";
const INBOX_HEADER = `# Reports for the operator

One line per report, appended by agents through the personal-ops-manual MCP
(report_change). Open reports start with \`- [ ]\`; the operator applies what is
true to the pages, then ticks the box (\`- [x]\`). Nothing here is a page; the
manual's pages are edited only by the operator.

`;

function inboxPath() {
  return path.join(getDocsDir(), INBOX_DIR, INBOX_FILE);
}

function oneLine(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function readInbox() {
  try { return fs.readFileSync(inboxPath(), "utf-8"); } catch (error) { if (error.code === "ENOENT") return ""; throw error; }
}

function parseReports() {
  const out = [];
  const re = /^- \[( |x)\] (\S+ \S+ UTC) · (.+?) · page: (.+?) · (.+?)(?: · evidence: (.*))?$/;
  for (const line of readInbox().split("\n")) {
    const m = re.exec(line);
    if (!m) continue;
    out.push({ handled: m[1] === "x", reportedAt: m[2], agent: m[3], page: m[4], what: m[5], evidence: m[6] ?? "", line });
  }
  return out;
}

// Checkbox lines that report_change did not write (typed by hand): they do not
// parse, so without this they would be invisible to the operator.
function malformedReports() {
  const re = /^- \[( |x)\] (\S+ \S+ UTC) · (.+?) · page: (.+?) · (.+?)(?: · evidence: (.*))?$/;
  return readInbox().split("\n").filter((line) => /^- \[[ xX]\]/.test(line) && !re.test(line));
}

server.registerTool(
  "report_change",
  {
    title: "Report a change to the operator",
    description:
      "For readers. Report a mismatch between a page and the machine so the operator can fix the page. Read the page first (search_documents, then get_document). Appends one dated line to _inbox/reports.md in the documents folder; it never edits a page. This is the only way to report: never edit pages or type into the inbox file yourself. If the page already says it, do not report; news about the project is not a report unless a page contradicts it.",
    inputSchema: {
      agent: z.string().min(1).describe("Your name, e.g. goose, cursor, aka"),
      page: z.string().min(1).describe("Title or id of the page you read; 'none' only after search_documents found nothing"),
      what: z.string().min(1).describe("'page says <quoted line or missing>; now <the fact>', one sentence"),
      evidence: z.string().optional().describe("Command output, file path, or where you saw it"),
    },
  },
  async ({ agent, page, what, evidence }) => {
    const file = inboxPath();
    const stamp = new Date().toISOString().replace("T", " ").slice(0, 16) + " UTC";
    let line = `- [ ] ${stamp} · ${oneLine(agent)} · page: ${oneLine(page)} · ${oneLine(what)}`;
    if (evidence && oneLine(evidence)) line += ` · evidence: ${oneLine(evidence)}`;
    try {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      if (!fs.existsSync(file)) fs.writeFileSync(file, INBOX_HEADER, "utf-8");
      fs.appendFileSync(file, line + "\n", "utf-8");
    } catch (error) {
      if (error.code !== "EPERM" && error.code !== "EACCES") throw error;
      return text({
        ok: false,
        error: `The ${INBOX_DIR}/ folder is missing or locked, so the report was not filed. Tell Kika the inbox needs the operator: ops-lock lock (re)opens it. Your report was: ${line}`,
      });
    }
    return text({ ok: true, file, line, open: parseReports().filter((r) => !r.handled).length });
  },
);

server.registerTool(
  "list_reports",
  {
    title: "List reports in the inbox",
    description:
      "For the operator (and anyone curious): the reports readers filed with report_change. status `open` (default) returns unticked lines, `handled` the ticked ones, `all` both. The operator applies open reports to the pages and ticks them in _inbox/reports.md. Hand-typed lines that do not parse come back under `malformed`.",
    inputSchema: {
      status: z.enum(["open", "handled", "all"]).optional().describe("open (default), handled, or all"),
      limit: z.number().int().min(1).max(500).optional().describe("Max reports (default 50)"),
    },
  },
  async ({ status, limit }) => {
    const wanted = status ?? "open";
    const all = parseReports();
    const picked = all.filter((r) => wanted === "all" || (wanted === "handled") === r.handled);
    const page = picked.slice(-(limit ?? 50)).reverse();
    const malformed = malformedReports();
    const result = { status: wanted, count: page.length, total: picked.length, file: inboxPath(), reports: page };
    if (malformed.length) {
      result.malformed = malformed;
      result.note = "These lines were typed into the inbox by hand, not filed with report_change. Check each one like a report, then delete it.";
    }
    return text(result);
  },
);

await server.connect(new StdioServerTransport());
