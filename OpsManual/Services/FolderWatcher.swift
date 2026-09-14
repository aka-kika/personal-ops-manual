import Foundation
import os

/// Watches one directory with a DispatchSource and calls back on the main actor after a quiet period.
final class FolderWatcher: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.kikalab.opsmanual", category: "FolderWatcher")

    private let fd: Int32
    private let source: DispatchSourceFileSystemObject?
    /// False when `open()` failed: the folder is not being watched and the app
    /// will not notice external edits until something calls `load()` again.
    let isActive: Bool
    /// Mutated from the DispatchSource's event-handler queue (schedule()) and read/cancelled
    /// from stop() (called from the main actor and from deinit) — must go through the lock.
    private let pending = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
    private let debounce: Duration
    private let onChange: @MainActor () -> Void

    init(url: URL, debounce: Duration = .milliseconds(300), onChange: @escaping @MainActor () -> Void) {
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
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .global(qos: .utility))
        source = src
        src.setEventHandler { [weak self] in self?.schedule() }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
    }

    private func schedule() {
        let delay = debounce
        let callback = onChange
        let newTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await callback()
        }
        pending.withLock { $0?.cancel(); $0 = newTask }
    }

    /// Idempotent: safe to call more than once (stop() then deinit's own stop() call).
    func stop() {
        pending.withLock { $0?.cancel(); $0 = nil }
        source?.cancel()
    }

    deinit { stop() }
}
