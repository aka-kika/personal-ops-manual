import Foundation
import os

/// Watches one directory and its files with a DispatchSource and calls back on the main actor after a quiet period.
final class FolderWatcher: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.kikalab.opsmanual", category: "FolderWatcher")

    private struct FileWatch {
        let ino: ino_t
        let source: DispatchSourceFileSystemObject
    }

    private struct State {
        var stopped = false
        var pending: Task<Void, Never>?
        var fileWatches: [String: FileWatch] = [:]
    }

    private let url: URL
    private let fd: Int32
    private let source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.kikalab.opsmanual.folderwatcher", qos: .utility)
    /// False when `open()` failed: the folder is not being watched and the app
    /// will not notice external edits until something calls `load()` again.
    let isActive: Bool
    /// Mutated from the DispatchSource's event-handler queue (schedule()) and read/cancelled
    /// from stop() (called from the main actor and from deinit) — must go through the lock.
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let debounce: Duration
    private let onChange: @MainActor () -> Void

    init(url: URL, debounce: Duration = .milliseconds(300), onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            source = nil
            isActive = false
            Self.log.warning("Cannot watch \(url.path, privacy: .public): open() failed with errno \(errno). External changes will not reload.")
            return
        }
        isActive = true
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue)
        source = src
        src.setEventHandler { [weak self] in
            self?.syncFileWatches()
            self?.schedule()
        }
        src.setCancelHandler { [fd] in close(fd) }
        syncFileWatches()
        src.resume()
    }

    private func syncFileWatches() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        var found: [String: ino_t] = [:]
        for name in names {
            let fileURL = url.appendingPathComponent(name)
            var st = stat()
            if lstat(fileURL.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
                found[name] = st.st_ino
            }
        }
        let currentSt = found

        let (isStopped, toCancel, toOpen) = state.withLock { s -> (Bool, [DispatchSourceFileSystemObject], [(name: String, ino: ino_t)]) in
            if s.stopped { return (true, [], []) }
            var cancel: [DispatchSourceFileSystemObject] = []
            for (name, watch) in s.fileWatches where currentSt[name] != watch.ino {
                cancel.append(watch.source)
                s.fileWatches.removeValue(forKey: name)
            }
            let open = currentSt.filter { s.fileWatches[$0.key] == nil }.map { (name: $0.key, ino: $0.value) }
            return (false, cancel, open)
        }

        for src in toCancel { src.cancel() }
        guard !isStopped else { return }

        for item in toOpen {
            let filePath = url.appendingPathComponent(item.name).path
            let fileFD = open(filePath, O_EVTONLY)
            guard fileFD >= 0 else { continue }
            let fileSrc = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileFD,
                eventMask: [.write, .extend, .attrib, .rename, .delete, .link],
                queue: queue)
            fileSrc.setEventHandler { [weak self] in
                guard let self else { return }
                let flags = fileSrc.data
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.syncFileWatches()
                }
                self.schedule()
            }
            fileSrc.setCancelHandler { close(fileFD) }
            let added = state.withLock { s -> Bool in
                if s.stopped || s.fileWatches[item.name] != nil { return false }
                s.fileWatches[item.name] = FileWatch(ino: item.ino, source: fileSrc)
                return true
            }
            fileSrc.resume()
            if !added {
                fileSrc.cancel()
            }
        }
    }

    private func schedule() {
        let delay = debounce
        let callback = onChange
        let newTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await callback()
        }
        state.withLock { s in
            s.pending?.cancel()
            if s.stopped {
                newTask.cancel()
            } else {
                s.pending = newTask
            }
        }
    }

    /// Idempotent: safe to call more than once (stop() then deinit's own stop() call).
    func stop() {
        let sourcesToCancel = state.withLock { s -> [DispatchSourceFileSystemObject] in
            s.stopped = true
            s.pending?.cancel()
            s.pending = nil
            let watches = Array(s.fileWatches.values.map(\.source))
            s.fileWatches.removeAll()
            return watches
        }
        for src in sourcesToCancel { src.cancel() }
        source?.cancel()
    }

    deinit { stop() }
}
