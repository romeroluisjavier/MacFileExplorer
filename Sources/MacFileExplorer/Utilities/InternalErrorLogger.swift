import AppKit
import Darwin
import Foundation

/// Registrador interno silencioso de errores inesperados, cuelgues del hilo principal (hangs)
/// y excepciones/señales fatales en `~/Library/Application Support/MacFileExplorer/INTERNAL_ERROR.log`
/// (y enlace directo en `~/.macfileexplorer_INTERNAL_ERROR.log`).
public final class InternalErrorLogger: @unchecked Sendable {

    public static let shared = InternalErrorLogger()

    private let queue = DispatchQueue(label: "com.macfileexplorer.internalErrorLogger", qos: .utility)
    private let watchdogQueue = DispatchQueue(label: "com.macfileexplorer.hangWatchdog", qos: .utility)
    private var isInstalled = false
    private var watchdogTimer: DispatchSourceTimer?
    private let lock = NSLock()
    private var lastMainThreadHeartbeat = Date()

    public static let logFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = appSupport.appendingPathComponent("MacFileExplorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("INTERNAL_ERROR.log", isDirectory: false)
    }()

    public static let hiddenHomeSymlinkURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".macfileexplorer_INTERNAL_ERROR.log")
    }()

    private init() {}

    /// Instala el watchdog de cuelgues, manejador de `NSException` y señales fatales.
    public func install() {
        lock.lock()
        guard !isInstalled else {
            lock.unlock()
            return
        }
        isInstalled = true
        lock.unlock()

        ensureLogFileAndSymlink()
        installUncaughtExceptionHandler()
        installSignalHandlers()
        startMainThreadHangWatchdog()
    }

    /// Registra un evento `INTERNAL_ERROR` con categoría, mensaje y stack trace actual.
    public func logError(
        category: String,
        message: String,
        context: [String: String] = [:],
        includeStackTrace: Bool = true
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let stack = includeStackTrace ? Thread.callStackSymbols.prefix(25).joined(separator: "\n  ") : ""
        let contextText = context.isEmpty
            ? ""
            : "\nContext: " + context.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")

        let entry = """
        ================================================================================
        [INTERNAL_ERROR] [\(timestamp)] [\(category)]
        Message: \(message)\(contextText)
        \(stack.isEmpty ? "" : "Stack:\n  \(stack)\n")
        """

        queue.async {
            Self.appendTextToLog(entry)
        }
    }

    private func ensureLogFileAndSymlink() {
        let fm = FileManager.default
        let path = Self.logFileURL.path(percentEncoded: false)
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        let linkPath = Self.hiddenHomeSymlinkURL.path(percentEncoded: false)
        if !fm.fileExists(atPath: linkPath) {
            try? fm.createSymbolicLink(atPath: linkPath, withDestinationPath: path)
        }
    }

    private static func appendTextToLog(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let path = logFileURL.path(percentEncoded: false)
        if let handle = FileHandle(forWritingAtPath: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    // MARK: - Watchdog de Cuelgues del Hilo Principal (> 3.0s sin responder, coalescido para Apple Silicon)

    private func startMainThreadHangWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let semaphore = DispatchSemaphore(value: 0)
            let checkStart = Date()
            DispatchQueue.main.async {
                self.lock.lock()
                self.lastMainThreadHeartbeat = Date()
                self.lock.unlock()
                semaphore.signal()
            }
            let waitResult = semaphore.wait(timeout: .now() + 3.0)
            if waitResult == .timedOut {
                let elapsed = Date().timeIntervalSince(checkStart)
                self.logError(
                    category: "MAIN_THREAD_HANG",
                    message: String(format: "El hilo principal tardó más de %.2fs en responder (posible cuelgue / freeze).", elapsed),
                    includeStackTrace: false
                )
            }
        }
        self.watchdogTimer = timer
        timer.resume()
    }

    // MARK: - Excepciones no capturadas y Señales Fatales

    private func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let stack = exception.callStackSymbols.joined(separator: "\n  ")
            let entry = """
            ================================================================================
            [INTERNAL_ERROR] [\(timestamp)] [UNCAUGHT_NSEXCEPTION]
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack:
              \(stack)

            """
            InternalErrorLogger.appendTextToLog(entry)
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP] {
            signal(sig) { receivedSignal in
                let path = InternalErrorLogger.logFileURL.path(percentEncoded: false)
                let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
                if fd >= 0 {
                    let header = "\n================================================================================\n[INTERNAL_ERROR] [FATAL_SIGNAL_\(receivedSignal)]\n"
                    _ = header.withCString { ptr in
                        write(fd, ptr, strlen(ptr))
                    }
                    var callstack = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
                    let frames = backtrace(&callstack, 64)
                    backtrace_symbols_fd(&callstack, frames, fd)
                    close(fd)
                }
                signal(receivedSignal, SIG_DFL)
                raise(receivedSignal)
            }
        }
    }
}
