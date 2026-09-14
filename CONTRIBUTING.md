# Contributing

Thanks for looking. This is a small personal tool with one maintainer, so
replies come when they come.

## Build and test

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project OpsManual.xcodeproj -scheme OpsManual -destination 'platform=macOS' test
./build.sh --install     # ad hoc build into /Applications
```

The MCP server lives in `mcp/`: `npm install` there once, then
`node mcp/server.mjs` speaks MCP over stdio.

## Issues and pull requests

- Issues are welcome: what you expected, what happened, macOS version, app
  version from Settings, About.
- Pull requests: one change per request, tests passing, a sentence on why.
  Match what is already there: plain English, no emojis, sentence case.
- The file format is a contract. Pages must stay byte-identical across
  writers, so changes to `FrontmatterCodec` or the server's parser need a
  round-trip test and a clear reason.
- One operator writes pages; readers report. Changes that give readers
  write access to pages will not be merged. `docs/PHILOSOPHY.md` says why.

## License

MIT. By contributing you agree your work is released under the same
license.
