import Foundation

/// What the GitHub view can ask. Read only; tests swap in a fake.
protocol GitHubProbing: Sendable {
    /// The signed-in account's own repos, plus any `extra` ("owner/name") a page names.
    func repos(extra: [String]) -> Result<(login: String, repos: [RemoteRepo]), GitHubProbeError>
    func local(path: String) -> LocalRepo
}

enum GitHubProbeError: Error, Equatable, Sendable {
    case ghMissing, notSignedIn, failed(String)

    var message: String {
        switch self {
        case .ghMissing: "gh is not installed"
        case .notSignedIn: "gh is not signed in"
        case .failed(let why): why
        }
    }
}

/// GitHub through the `gh` login that already exists (no token in the app), and local
/// git for the working copy. Fixed programs, fixed arguments, no shell.
struct GitHubProbe: GitHubProbing {
    var home: String = NSHomeDirectory()
    var timeout: TimeInterval = 30

    private var drift: DriftProbe { DriftProbe(home: home) }

    private func tool(_ name: String) -> String? {
        drift.cliFolders.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let pageSize = 25

    static let repoFields = """
    nameWithOwner name visibility isArchived url
    latestRelease { tagName }
    refs(refPrefix: "refs/tags/", last: 1, orderBy: {field: TAG_COMMIT_DATE, direction: ASC}) { nodes { name } }
    pullRequests(states: OPEN) { totalCount }
    defaultBranchRef { target { ... on Commit {
      statusCheckRollup { state }
      checkSuites(last: 1) { nodes { updatedAt workflowRun { workflow { name } } } }
    } } }
    """

    func repos(extra: [String]) -> Result<(login: String, repos: [RemoteRepo]), GitHubProbeError> {
        guard let gh = tool("gh") else { return .failure(.ghMissing) }
        var login = ""
        var repos: [RemoteRepo] = []
        var cursor: String?
        // 25 repos a request: about 3 seconds each. 100 at once took about 10 s and
        // often hit GitHub's time limit (HTTP 502, 2026-11-06).
        for _ in 0..<40 {   // 1000 repos at most
            let after = cursor.map { ", after: \"\($0)\"" } ?? ""
            let query = "query { viewer { login repositories(first: \(Self.pageSize), ownerAffiliations: OWNER\(after)) { pageInfo { hasNextPage endCursor } nodes { \(Self.repoFields) } } } }"
            switch graphql(gh, query) {
            case .failure(let e): return .failure(e)
            case .success(let data):
                guard let page = Self.parseViewer(data) else { return .failure(.failed("GitHub's answer could not be read")) }
                login = page.login
                repos += page.repos
                cursor = page.next
            }
            if cursor == nil { break }
        }
        let known = Set(repos.map(\.key))
        let missing = extra.filter { !known.contains($0.lowercased()) && Self.isRepoName($0) }
        if !missing.isEmpty {
            let parts = missing.enumerated().map { i, full -> String in
                let bits = full.split(separator: "/")
                return "r\(i): repository(owner: \"\(bits[0])\", name: \"\(bits[1])\") { \(Self.repoFields) }"
            }
            if case .success(let data) = graphql(gh, "query { \(parts.joined(separator: " ")) }") {
                repos += Self.parseAliases(data)
            }
        }
        return .success((login, repos))
    }

    /// One retry when GitHub answers with a server error (502/503/504): those pass.
    private func graphql(_ gh: String, _ query: String) -> Result<Data, GitHubProbeError> {
        let first = graphqlOnce(gh, query)
        if case .failure(.failed(let why)) = first, why.contains("HTTP 5") {
            Thread.sleep(forTimeInterval: 2)
            return graphqlOnce(gh, query)
        }
        return first
    }

    private func graphqlOnce(_ gh: String, _ query: String) -> Result<Data, GitHubProbeError> {
        guard let out = ProcessRunner.run(gh, ["api", "graphql", "-f", "query=\(query)"], timeout: timeout) else {
            return .failure(.failed("gh did not answer"))
        }
        if out.status != 0 {
            let text = (out.stderr + out.stdout).lowercased()
            if text.contains("auth login") || text.contains("not logged") || text.contains("authentication") { return .failure(.notSignedIn) }
            if out.stdout.contains("\"data\"") { return .success(Data(out.stdout.utf8)) }   // partial: a named repo is gone
            return .failure(.failed(out.stderr.split(separator: "\n").first.map(String.init) ?? "gh failed"))
        }
        return .success(Data(out.stdout.utf8))
    }

    func local(path: String) -> LocalRepo {
        let expanded = path.hasPrefix("~/") ? home + path.dropFirst(1) : path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else { return .missing(path) }
        guard let git = tool("git"),
              let out = ProcessRunner.run(git, ["-C", expanded, "status", "--porcelain=v1", "--branch", "--untracked-files=no"], timeout: 10),
              out.status == 0 else {
            var notRepo = LocalRepo.missing(path)
            notRepo.exists = true
            return notRepo
        }
        return LocalRepo.parse(porcelain: out.stdout, path: path)
    }

    /// "owner/name" with only the characters GitHub allows.
    static func isRepoName(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
    }

    // MARK: Parsing (pure, tested)

    static func parseViewer(_ data: Data) -> (login: String, repos: [RemoteRepo], next: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let viewer = (root["data"] as? [String: Any])?["viewer"] as? [String: Any],
              let list = viewer["repositories"] as? [String: Any] else { return nil }
        let nodes = list["nodes"] as? [[String: Any]] ?? []
        let info = list["pageInfo"] as? [String: Any]
        let next = (info?["hasNextPage"] as? Bool == true) ? info?["endCursor"] as? String : nil
        return (viewer["login"] as? String ?? "", nodes.compactMap(repo), next)
    }

    static func parseAliases(_ data: Data) -> [RemoteRepo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataNode = root["data"] as? [String: Any] else { return [] }
        return dataNode.keys.sorted().compactMap { dataNode[$0] as? [String: Any] }.compactMap(repo)
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    static func repo(_ node: [String: Any]) -> RemoteRepo? {
        guard let full = node["nameWithOwner"] as? String, let name = node["name"] as? String else { return nil }
        let visibility = RemoteRepo.Visibility(rawValue: (node["visibility"] as? String ?? "").lowercased()) ?? .private
        let release = (node["latestRelease"] as? [String: Any])?["tagName"] as? String
        let tag = ((node["refs"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last?["name"] as? String
        let prs = (node["pullRequests"] as? [String: Any])?["totalCount"] as? Int ?? 0
        let target = (node["defaultBranchRef"] as? [String: Any])?["target"] as? [String: Any]
        let state = ((target?["statusCheckRollup"] as? [String: Any])?["state"] as? String)?.uppercased()
        let ci: RemoteRepo.CI = switch state {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: .none
        }
        let suite = ((target?["checkSuites"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last
        let workflow = ((suite?["workflowRun"] as? [String: Any])?["workflow"] as? [String: Any])?["name"] as? String
        let at = (suite?["updatedAt"] as? String).flatMap { iso.date(from: $0) }
        return RemoteRepo(nameWithOwner: full, name: name, visibility: visibility, isArchived: node["isArchived"] as? Bool ?? false,
                          url: node["url"] as? String ?? "https://github.com/\(full)", latestTag: release ?? tag,
                          openPRs: prs, ci: ci, ciName: workflow, ciAt: ci == .none ? nil : at)
    }
}
