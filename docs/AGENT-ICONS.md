# Agent icons

Glyphs the app shows next to agent pages, chosen with `icon: <name>` in a
page's frontmatter. They live in `OpsManual/Resources/Assets.xcassets/agents/`
as `agent-<name>` image sets; `AgentGlyph.known` lists the names. Trademarks
belong to their owners; the glyphs identify pages and imply no endorsement.

| icon | Source |
|---|---|
| aka | the author's own agent app, owner-supplied |
| claude | claude.ai favicon (2026-09-09) |
| claude-code | thesvg.org, claude-code/color.svg (MIT) |
| gpt | chatgpt.com favicon (2026-09-09) |
| grok | grok.com favicon (2026-09-09) |
| meta | meta.ai favicon |
| goose | goose project favicon (2026-09-09) |
| minimax | agent.minimax.io favicon (2026-09-12) |
| hermes | hermes-agent.nousresearch.com icon |
| cursor | thesvg.org, cursor/dark.svg and light.svg (themed pair) |
| kimi | thesvg.org, kimi/color.svg and a light variant (themed pair) |
| gemini, deepseek, qwen, mistral, perplexity, copilot | @lobehub/icons-static-svg (MIT), colour variants, 2026-09-14 |
| ollama, openai, windsurf, codex, opencode | @lobehub/icons-static-svg (MIT), monochrome; themed pairs with `#1D1D1F` on light and `#F5F5F7` on dark, 2026-09-14 |

To add one: drop an SVG or PNG into a new `agent-<name>.imageset` with a
`Contents.json` like its neighbours, add the name to `AgentGlyph.known`, and
list it here.
