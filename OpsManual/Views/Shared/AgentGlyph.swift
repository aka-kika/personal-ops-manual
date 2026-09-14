import SwiftUI

/// Maps the `icon:` frontmatter value to a bundled glyph. Unknown names fall back to a chip symbol.
struct AgentGlyph: View {
    let name: String
    var size: CGFloat = 16

    static let known: Set<String> = ["aka", "claude", "claude-code", "goose", "grok", "hermes", "meta", "minimax", "gpt", "cursor", "kimi", "gemini", "deepseek", "qwen", "mistral", "perplexity", "copilot", "ollama", "openai", "windsurf", "codex", "opencode"]

    var body: some View {
        if Self.known.contains(name) {
            Image("agent-\(name)")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "cpu")
                .font(.system(size: size - 3, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}
