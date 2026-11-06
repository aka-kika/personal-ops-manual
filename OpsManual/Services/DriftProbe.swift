import Foundation

/// What Drift can ask the Mac. Every answer is read only. Tests swap in a fake.
protocol DriftProbing: Sendable {
    func app(_ subject: String) -> DriftFacts.App
    func notarization(path: String) -> DriftFacts.Notarization
    /// Server name to where it is wired ("user", "local: <project>"); nil when no config could be read.
    func mcpServers() -> [String: String]?
    func listeners(port: Int) -> DriftFacts.Port
    func launchd(label: String) -> DriftFacts.Launchd
    func cli(_ name: String) -> DriftFacts.CLI
}

enum DriftFacts {
    enum App: Equatable, Sendable { case installed(path: String, version: String?), missing(path: String) }
    enum Notarization: Equatable, Sendable { case notarized(String), signedNotNotarized(String), rejected(String), unknown(String) }
    enum Port: Equatable, Sendable { case listening([String]), nothing, unknown(String) }
    enum Launchd: Equatable, Sendable { case loaded(running: Bool), notLoaded, unknown(String) }
    enum CLI: Equatable, Sendable { case found(path: String, version: String?), notFound, unknown(String) }
}

/// The real Mac. Each check runs one fixed program with fixed arguments, with a timeout;
/// the page's words are passed as arguments, never through a shell.
struct DriftProbe: DriftProbing {
    var home: String = NSHomeDirectory()
    var timeout: TimeInterval = 6

    /// Folders a CLI is looked for in. An app started from the Dock has a short PATH,
    /// so the usual places are listed here instead of read from it.
    var cliFolders: [String] {
        ["\(home)/.local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
         "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.npm-global/bin", "\(home)/go/bin",
         "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    func appPath(_ subject: String) -> String {
        if subject.hasPrefix("~/") { return home + subject.dropFirst(1) }
        if subject.hasPrefix("/") { return subject }
        let name = subject.hasSuffix(".app") ? subject : subject + ".app"
        let system = "/Applications/\(name)"
        let user = "\(home)/Applications/\(name)"
        if !FileManager.default.fileExists(atPath: system), FileManager.default.fileExists(atPath: user) { return user }
        return system
    }

    func app(_ subject: String) -> DriftFacts.App {
        let path = appPath(subject)
        guard FileManager.default.fileExists(atPath: path) else { return .missing(path: path) }
        let plist = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        return .installed(path: path, version: plist?["CFBundleShortVersionString"] as? String)
    }

    func notarization(path: String) -> DriftFacts.Notarization {
        guard let out = ProcessRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "-vv", path], timeout: timeout) else {
            return .unknown("spctl did not answer")
        }
        let text = out.stdout + out.stderr
        let source = text.components(separatedBy: "\n")
            .first { $0.hasPrefix("source=") }.map { String($0.dropFirst(7)) } ?? ""
        if out.status != 0 { return .rejected(source.isEmpty ? "rejected" : source) }
        if source.contains("Notarized") || source.contains("App Store") || source == "Apple System" {
            return .notarized(source)
        }
        return .signedNotNotarized(source.isEmpty ? "accepted" : source)
    }

    func mcpServers() -> [String: String]? {
        let url = URL(fileURLWithPath: home + "/.claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        if let projects = json["projects"] as? [String: Any] {
            for (path, value) in projects.sorted(by: { $0.key < $1.key }) {
                guard let servers = (value as? [String: Any])?["mcpServers"] as? [String: Any] else { continue }
                for name in servers.keys where out[name] == nil {
                    out[name] = "local: \((path as NSString).lastPathComponent)"
                }
            }
        }
        // User scope wins over a project's own copy: it reaches every session.
        for name in ((json["mcpServers"] as? [String: Any]) ?? [:]).keys { out[name] = "user" }
        return out
    }

    func listeners(port: Int) -> DriftFacts.Port {
        guard let out = ProcessRunner.run("/usr/sbin/lsof", ["-nP", "+c", "0", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fc"], timeout: timeout) else {
            return .unknown("lsof did not answer")
        }
        let names = out.stdout.components(separatedBy: "\n").filter { $0.hasPrefix("c") }.map { String($0.dropFirst()) }
        if names.isEmpty { return out.status <= 1 ? .nothing : .unknown("lsof failed") }
        var unique: [String] = []
        for n in names where !unique.contains(n) { unique.append(n) }
        return .listening(unique)
    }

    func launchd(label: String) -> DriftFacts.Launchd {
        guard let out = ProcessRunner.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"], timeout: timeout) else {
            return .unknown("launchctl did not answer")
        }
        guard out.status == 0 else { return .notLoaded }
        let running = out.stdout.components(separatedBy: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces) == "state = running"
        }
        return .loaded(running: running)
    }

    func cli(_ name: String) -> DriftFacts.CLI {
        guard DriftCheck.isPlainName(name) else { return .unknown("not a plain name") }
        guard let path = cliFolders.map({ "\($0)/\(name)" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .notFound
        }
        guard let out = ProcessRunner.run(path, ["--version"], timeout: timeout) else {
            return .unknown("\(name) --version did not answer")
        }
        return .found(path: path, version: Self.firstVersion(in: out.stdout + "\n" + out.stderr))
    }

    /// The first thing that looks like a version: "gh version 2.103.3 (2026-10-26)" is 2.103.3.
    static func firstVersion(in text: String) -> String? {
        let pattern = #"\d+(\.\d+)+([-+][0-9A-Za-z.]+)?"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

/// Runs one program with a timeout and collects its output. No shell.
enum ProcessRunner {
    struct Output: Sendable { var status: Int32; var stdout: String; var stderr: String }

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var out = Data()
        var err = Data()
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let reads = DispatchGroup()
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            box.lock.lock(); box.out = data; box.lock.unlock()
            reads.leave()
        }
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            box.lock.lock(); box.err = data; box.lock.unlock()
            reads.leave()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        // A child that outlives the program can hold the pipe open; don't wait on it for long.
        _ = reads.wait(timeout: .now() + 1)
        box.lock.lock(); defer { box.lock.unlock() }
        return Output(status: process.terminationStatus,
                      stdout: String(decoding: box.out, as: UTF8.self),
                      stderr: String(decoding: box.err, as: UTF8.self))
    }
}
