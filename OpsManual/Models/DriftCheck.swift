import Foundation

/// One fact a page states in a checkable way: a line under `checks:` in its frontmatter.
///
///     app "Personal Ops Manual" 2.2.5 notarized
///     mcp personal-ops-manual
///     port 4319 node
///     launchd com.akakika.socials [running]
///     cli gh 2.103.3
///
/// The line is only ever split into words. No part of it reaches a shell: each kind
/// runs one fixed program with fixed arguments (see `DriftProbe`).
struct DriftCheck: Hashable, Sendable, Codable {
    enum Kind: String, CaseIterable, Sendable, Codable {
        case app, mcp, port, launchd, cli
        /// Not a checks: line: a page's claims about its GitHub repo (latest release,
        /// repo, path), checked by the GitHub refresh and shown in Drift.
        case repo

        /// The claim's name in the Drift views.
        var claimTitle: String {
            switch self {
            case .app: "App version"
            case .mcp: "MCP server"
            case .port: "Port"
            case .launchd: "Launch job"
            case .cli: "CLI version"
            case .repo: "GitHub"
            }
        }

        /// The group on the overview's "what drags it down" card.
        var groupTitle: String {
            switch self {
            case .app, .cli: "App and CLI versions"
            case .mcp: "MCP servers"
            case .port: "Ports"
            case .launchd: "Launch jobs"
            case .repo: "GitHub repos"
            }
        }

        var symbol: String {
            switch self {
            case .app, .cli: "app.dashed"
            case .mcp: "server.rack"
            case .port: "network"
            case .launchd: "bolt"
            case .repo: "arrow.triangle.branch"
            }
        }
    }

    /// The line exactly as the page has it.
    var line: String
    var kind: Kind
    /// The app name or path, server name, port number, label or CLI name.
    var subject: String
    /// The version for `app` and `cli`, the process for `port`; nil when the page states none.
    var expected: String?
    /// `app ... notarized`.
    var wantsNotarized = false
    /// `launchd ... running`.
    var wantsRunning = false

    enum ParseError: Error, Equatable {
        case empty, unknownKind(String), missingSubject, badPort(String), badName(String), unclosedQuote
    }

    static func parse(_ line: String) -> Result<DriftCheck, ParseError> {
        let words: [String]
        switch split(line) {
        case .success(let w): words = w
        case .failure(let e): return .failure(e)
        }
        guard let first = words.first else { return .failure(.empty) }
        guard let kind = Kind(rawValue: first.lowercased()), kind != .repo else { return .failure(.unknownKind(first)) }
        guard words.count >= 2, !words[1].isEmpty else { return .failure(.missingSubject) }
        var check = DriftCheck(line: line.trimmingCharacters(in: .whitespaces), kind: kind, subject: words[1])
        var rest = Array(words.dropFirst(2))
        switch kind {
        case .app:
            if let i = rest.firstIndex(where: { $0.lowercased() == "notarized" }) {
                check.wantsNotarized = true
                rest.remove(at: i)
            }
            check.expected = rest.first
        case .launchd:
            check.wantsRunning = rest.contains { $0.lowercased() == "running" }
        case .port:
            guard let number = Int(check.subject), (1...65535).contains(number) else {
                return .failure(.badPort(check.subject))
            }
            check.expected = rest.first
        case .cli:
            guard isPlainName(check.subject) else { return .failure(.badName(check.subject)) }
            check.expected = rest.first
        case .mcp, .repo:
            break
        }
        return .success(check)
    }

    /// A CLI is looked up by name on known folders, never a path or anything a shell could read.
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && !name.hasPrefix("-") && !name.hasPrefix(".")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._+-".contains($0)) }
    }

    /// Words separated by spaces; a "double quoted" part is one word.
    static func split(_ line: String) -> Result<[String], ParseError> {
        var words: [String] = []
        var current = ""
        var inQuotes = false
        var hasWord = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                hasWord = true
            } else if ch.isWhitespace, !inQuotes {
                if hasWord { words.append(current); current = ""; hasWord = false }
            } else {
                current.append(ch)
                hasWord = true
            }
        }
        if inQuotes { return .failure(.unclosedQuote) }
        if hasWord { words.append(current) }
        return .success(words)
    }
}

extension DriftCheck.ParseError {
    var message: String {
        switch self {
        case .empty: "The line is empty."
        case .unknownKind(let word): "\"\(word)\" is not a kind of check (app, mcp, port, launchd, cli)."
        case .missingSubject: "The line names no app, server, port, job or CLI."
        case .badPort(let text): "\"\(text)\" is not a port number."
        case .badName(let text): "\"\(text)\" is not a plain CLI name."
        case .unclosedQuote: "A quote is not closed."
        }
    }
}
