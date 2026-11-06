import Foundation

/// What GitHub says about one repo, from the `gh` login already on this Mac.
struct RemoteRepo: Hashable, Sendable, Codable {
    enum Visibility: String, Sendable, Codable { case `public`, `private`, `internal` }
    enum CI: String, Sendable, Codable { case success, failure, pending, none }

    var nameWithOwner: String
    var name: String
    var visibility: Visibility
    var isArchived: Bool
    var url: String
    var latestTag: String?
    var openPRs: Int
    var ci: CI
    var ciName: String?
    var ciAt: Date?

    var key: String { nameWithOwner.lowercased() }
}

/// The working copy on this Mac, from local git only (no network).
struct LocalRepo: Hashable, Sendable, Codable {
    var path: String
    var exists: Bool
    var isRepo: Bool
    var branch: String?
    var upstream: String?
    var ahead: Int
    var behind: Int
    /// Changed files git already tracks (modified, deleted, staged); new untracked files are not counted.
    var changedFiles: [String]

    var uncommitted: Int { changedFiles.count }
    var hasUnsavedWork: Bool { uncommitted > 0 || ahead > 0 }

    static func missing(_ path: String) -> LocalRepo {
        LocalRepo(path: path, exists: false, isRepo: false, branch: nil, upstream: nil, ahead: 0, behind: 0, changedFiles: [])
    }

    /// `git status --porcelain=v1 --branch --untracked-files=no`.
    static func parse(porcelain: String, path: String) -> LocalRepo {
        var repo = LocalRepo(path: path, exists: true, isRepo: true, branch: nil, upstream: nil, ahead: 0, behind: 0, changedFiles: [])
        for line in porcelain.components(separatedBy: "\n") where !line.isEmpty {
            if line.hasPrefix("## ") {
                parseBranch(String(line.dropFirst(3)), into: &repo)
            } else if line.count > 3, !line.hasPrefix("??"), !line.hasPrefix("!!") {
                var file = String(line.dropFirst(3))
                if let arrow = file.range(of: " -> ") { file = String(file[arrow.upperBound...]) }
                repo.changedFiles.append(file.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            }
        }
        return repo
    }

    /// "main...origin/main [ahead 1, behind 2]", "main", "No commits yet on main", "HEAD (no branch)".
    private static func parseBranch(_ text: String, into repo: inout LocalRepo) {
        if text.hasPrefix("No commits yet on ") { repo.branch = String(text.dropFirst(18)); return }
        if text.hasPrefix("HEAD (no branch)") { repo.branch = "detached"; return }
        var head = text
        var counts = ""
        if let open = text.firstIndex(of: "[") {
            head = String(text[..<open]).trimmingCharacters(in: .whitespaces)
            counts = String(text[text.index(after: open)...]).replacingOccurrences(of: "]", with: "")
        }
        if let dots = head.range(of: "...") {
            repo.branch = String(head[..<dots.lowerBound])
            repo.upstream = String(head[dots.upperBound...])
        } else {
            repo.branch = head
        }
        for part in counts.components(separatedBy: ",") {
            let words = part.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard words.count == 2, let n = Int(words[1]) else { continue }
            if words[0] == "ahead" { repo.ahead = n }
            if words[0] == "behind" { repo.behind = n }
        }
    }
}

/// The last refresh: GitHub facts for the repos that manual pages name, and each page's working copy.
struct GitHubSnapshot: Sendable, Codable {
    var remote: [String: RemoteRepo] = [:]
    /// By page id.
    var local: [String: LocalRepo] = [:]
    var login: String?
    var refreshedAt: Date?
    /// Why GitHub could not be read ("gh is not signed in"); local git still shows.
    var remoteError: String?
}
