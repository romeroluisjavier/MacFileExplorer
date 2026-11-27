import AppKit
import Darwin
import Foundation

/// Grupo deduplicado y sanitizado de errores internos detectados en `INTERNAL_ERROR.log`.
public struct InternalErrorSummaryGroup: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let category: String
    public let sampleMessage: String
    public let count: Int
    public let firstSeen: String
    public let lastSeen: String
    public let sanitizedContext: String
    public let sampleStack: String

    public init(
        id: String,
        category: String,
        sampleMessage: String,
        count: Int,
        firstSeen: String,
        lastSeen: String,
        sanitizedContext: String,
        sampleStack: String
    ) {
        self.id = id
        self.category = category
        self.sampleMessage = sampleMessage
        self.count = count
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.sanitizedContext = sanitizedContext
        self.sampleStack = sampleStack
    }
}

/// Resultado de analizar `INTERNAL_ERROR.log` buscando errores nuevos no reportados o recientes.
public struct InternalErrorScanReport: Equatable, Sendable {
    public let groups: [InternalErrorSummaryGroup]
    public let totalOccurrences: Int
    public let logByteSize: UInt64
    public let scannedAt: Date

    public var isEmpty: Bool {
        groups.isEmpty
    }

    public var uniqueCount: Int {
        groups.count
    }

    /// Firma combinada determinística (FNV-1a) para deduplicar reportes en GitHub.
    public var combinedFingerprint: String {
        let joined = groups.map(\.id).sorted().joined(separator: "|")
        return InternalErrorLogger.deterministicFingerprint(joined)
    }

    public init(
        groups: [InternalErrorSummaryGroup],
        totalOccurrences: Int,
        logByteSize: UInt64,
        scannedAt: Date = Date()
    ) {
        self.groups = groups
        self.totalOccurrences = totalOccurrences
        self.logByteSize = logByteSize
        self.scannedAt = scannedAt
    }
}

/// Registrador interno silencioso de errores inesperados, cuelgues del hilo principal (hangs)
/// y excepciones/señales fatales en `~/Library/Application Support/MacFileExplorer/INTERNAL_ERROR.log`
/// (y enlace directo en `~/.macfileexplorer_INTERNAL_ERROR.log`).
///
/// Incluye rotación automática (2 MB), sanitización automática de privacidad (oculta usuario,
/// nombres de archivos personales, emails y tokens), agrupación por firma determinística y
/// cursor persistente para que el chequeo mensual solo informe errores nuevos.
public final class InternalErrorLogger: @unchecked Sendable {

    public static let shared = InternalErrorLogger()

    /// Tamaño máximo antes de rotar el archivo de log (2 MB, conservando la mitad más reciente).
    public static let maxLogBytes: UInt64 = 2 * 1024 * 1024
    private static let entrySeparator = "================================================================================"

    private enum DefaultsKeys {
        static let lastReportedOffset = "com.macfileexplorer.internalErrorLogger.lastReportedOffset"
        static let lastReportedFingerprints = "com.macfileexplorer.internalErrorLogger.lastReportedFingerprints"
        static let lastReportedAt = "com.macfileexplorer.internalErrorLogger.lastReportedAt"
    }

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
        queue.async {
            Self.rotateLogIfNeeded()
        }
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
        let stack = includeStackTrace ? Thread.callStackSymbols.prefix(20).joined(separator: "\n  ") : ""
        let sanitizedMessage = Self.sanitizeForPublicReport(message)
        let contextText = context.isEmpty
            ? ""
            : "\nContext: " + context
                .map { "\($0.key)=\(Self.sanitizeForPublicReport($0.value))" }
                .sorted()
                .joined(separator: ", ")

        let entry = """
        \(Self.entrySeparator)
        [INTERNAL_ERROR] [\(timestamp)] [\(category)]
        Message: \(sanitizedMessage)\(contextText)
        \(stack.isEmpty ? "" : "Stack:\n  \(stack)\n")
        """

        queue.async {
            Self.rotateLogIfNeeded()
            Self.appendTextToLog(entry)
        }
    }

    /// Registra un error Swift no fatal evitando registrar cancelaciones normales del usuario o falta de internet.
    public func logNonFatalError(
        category: String,
        error: Error,
        context: [String: String] = [:],
        includeStackTrace: Bool = false
    ) {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return
        }
        if nsError.domain == NSURLErrorDomain && (
            nsError.code == NSURLErrorCancelled ||
            nsError.code == NSURLErrorNotConnectedToInternet ||
            nsError.code == NSURLErrorNetworkConnectionLost
        ) {
            return
        }
        var enrichedContext = context
        enrichedContext["domain"] = nsError.domain
        enrichedContext["code"] = String(nsError.code)
        logError(
            category: category,
            message: nsError.localizedDescription,
            context: enrichedContext,
            includeStackTrace: includeStackTrace
        )
    }

    // MARK: - Escaneo, Deduplicación, Sanitización y Cursor de Reportes

    /// Analiza solo los errores **nuevos** agregados desde el último reporte/descarte mensual.
    public func scanUnreportedErrors(maxGroups: Int = 10) -> InternalErrorScanReport {
        queue.sync {
            let defaults = UserDefaults.standard
            let currentSize = Self.currentLogByteSize()
            var startOffset = UInt64(max(0, defaults.integer(forKey: DefaultsKeys.lastReportedOffset)))
            // Si el archivo rotó o fue limpiado, reiniciar el cursor desde 0.
            if currentSize < startOffset {
                startOffset = 0
                defaults.set(0, forKey: DefaultsKeys.lastReportedOffset)
            }
            let rawText = Self.readLogText(fromByteOffset: startOffset)
            let previouslyReported = Set(defaults.stringArray(forKey: DefaultsKeys.lastReportedFingerprints) ?? [])
            let parsed = Self.parseAndGroupEntries(from: rawText, maxGroups: maxGroups)
            let filtered = parsed.groups.filter { !previouslyReported.contains($0.id) || startOffset > 0 }
            let total = filtered.reduce(0) { $0 + $1.count }
            return InternalErrorScanReport(
                groups: filtered,
                totalOccurrences: total,
                logByteSize: currentSize,
                scannedAt: Date()
            )
        }
    }

    /// Analiza los errores más recientes del log completo (ideal para adjuntar en reportes manuales desde «Acerca de»).
    public func scanRecentErrors(maxBytes: UInt64 = 256 * 1024, maxGroups: Int = 8) -> InternalErrorScanReport {
        queue.sync {
            let currentSize = Self.currentLogByteSize()
            let startOffset: UInt64 = currentSize > maxBytes ? (currentSize - maxBytes) : 0
            let rawText = Self.readLogText(fromByteOffset: startOffset)
            let parsed = Self.parseAndGroupEntries(from: rawText, maxGroups: maxGroups)
            return InternalErrorScanReport(
                groups: parsed.groups,
                totalOccurrences: parsed.totalOccurrences,
                logByteSize: currentSize,
                scannedAt: Date()
            )
        }
    }

    /// Marca los errores actuales del log como ya reportados/revisados para no repetirlos el mes siguiente.
    public func markCurrentErrorsAsReported(fingerprints: [String] = []) {
        queue.sync {
            let defaults = UserDefaults.standard
            let size = Self.currentLogByteSize()
            defaults.set(Int(min(size, UInt64(Int.max))), forKey: DefaultsKeys.lastReportedOffset)
            defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKeys.lastReportedAt)
            if !fingerprints.isEmpty {
                var merged = Set(defaults.stringArray(forKey: DefaultsKeys.lastReportedFingerprints) ?? [])
                merged.formUnion(fingerprints)
                defaults.set(Array(merged.prefix(200)), forKey: DefaultsKeys.lastReportedFingerprints)
            }
        }
    }

    /// Limpia por completo `INTERNAL_ERROR.log` y reinicia el cursor de errores reportados.
    public func clearLog() {
        queue.sync {
            try? Data().write(to: Self.logFileURL, options: .atomic)
            let defaults = UserDefaults.standard
            defaults.set(0, forKey: DefaultsKeys.lastReportedOffset)
            defaults.removeObject(forKey: DefaultsKeys.lastReportedFingerprints)
        }
    }

    /// Elimina información personal identificable (usuario de macOS, rutas privadas, emails y tokens)
    /// antes de incluir cualquier fragmento de log en un Issue público de GitHub.
    public static func sanitizeForPublicReport(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var text = raw

        // 1. Ocultar carpeta personal y nombre de usuario actual.
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if !homePath.isEmpty {
            text = text.replacingOccurrences(of: homePath, with: "~")
        }
        let userName = NSUserName()
        if userName.count >= 3 {
            text = text.replacingOccurrences(of: "/Users/\(userName)", with: "~")
        }

        // 2. Ocultar cualquier otro /Users/<nombre> genérico.
        text = replacingRegex(in: text, pattern: #"/Users/[^/\s:,;"')\]>]+"#, with: "~")

        // 3. Redactar nombres de archivos personales dentro de carpetas sensibles conservando solo la extensión.
        let sensitiveDirs = ["Desktop", "Documents", "Downloads", "Movies", "Pictures", "Music", "Escritorio", "Documentos", "Descargas"]
        for dir in sensitiveDirs {
            text = redactFilesUnderFolder(dir, in: text)
        }

        // 4. Redactar correos electrónicos.
        text = replacingRegex(in: text, pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "<redacted-email>")

        // 5. Redactar tokens Bearer / OAuth / parámetros sensibles.
        text = replacingRegex(in: text, pattern: #"(?i)(Bearer\s+)[A-Za-z0-9._\-~+/=]+"#, with: "$1<redacted>")
        text = replacingRegex(in: text, pattern: #"(?i)((?:access_token|refresh_token|api_key|token|secret|password)\s*[=:]\s*)[^\s&,;\"']+"#, with: "$1<redacted>")

        return text
    }

    /// Hash determinístico FNV-1a (64-bit, estable entre ejecuciones) para deduplicar errores.
    public static func deterministicFingerprint(_ input: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func redactFilesUnderFolder(_ folder: String, in text: String) -> String {
        let pattern = #"~/"# + NSRegularExpression.escapedPattern(for: folder) + #"/[^\s:,;"')\]>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var mutable = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: mutable) else { continue }
            let matchedPath = String(mutable[range])
            let ext = URL(fileURLWithPath: matchedPath).pathExtension
            let replacement = ext.isEmpty ? "~/\(folder)/<redacted>" : "~/\(folder)/<redacted.\(ext)>"
            mutable.replaceSubrange(range, with: replacement)
        }
        return mutable
    }

    private static func replacingRegex(in text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private struct ParsedBlock {
        let timestamp: String
        let category: String
        let message: String
        let context: String
        let stack: String
    }

    private static func parseAndGroupEntries(
        from rawText: String,
        maxGroups: Int
    ) -> (groups: [InternalErrorSummaryGroup], totalOccurrences: Int) {
        let chunks = rawText.components(separatedBy: entrySeparator)
        var blocks: [ParsedBlock] = []

        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("[INTERNAL_ERROR]") else { continue }
            let lines = trimmed.components(separatedBy: .newlines)
            guard let headerLine = lines.first(where: { $0.contains("[INTERNAL_ERROR]") }) else { continue }

            // Extraer tokens entre corchetes: [INTERNAL_ERROR] [timestamp] [category] o [INTERNAL_ERROR] [FATAL_SIGNAL_X]
            let bracketTokens = extractBracketTokens(from: headerLine)
            let timestamp: String
            let category: String
            if bracketTokens.count >= 3 {
                timestamp = bracketTokens[1]
                category = bracketTokens[2]
            } else if bracketTokens.count == 2 {
                timestamp = "unknown"
                category = bracketTokens[1]
            } else {
                timestamp = "unknown"
                category = "UNKNOWN"
            }

            var message = ""
            var context = ""
            var stackLines: [String] = []
            var inStack = false

            for line in lines where line != headerLine {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("Message:") {
                    message = String(l.dropFirst("Message:".count)).trimmingCharacters(in: .whitespaces)
                } else if l.hasPrefix("Name:") && message.isEmpty {
                    message = l
                } else if l.hasPrefix("Reason:") {
                    message = message.isEmpty ? l : "\(message) — \(l)"
                } else if l.hasPrefix("Context:") {
                    context = String(l.dropFirst("Context:".count)).trimmingCharacters(in: .whitespaces)
                } else if l.hasPrefix("Stack:") {
                    inStack = true
                } else if inStack && !l.isEmpty {
                    stackLines.append(l)
                } else if category.hasPrefix("FATAL_SIGNAL") && !l.isEmpty {
                    stackLines.append(l)
                }
            }

            let sanitizedMsg = sanitizeForPublicReport(message.isEmpty ? category : message)
            let sanitizedCtx = sanitizeForPublicReport(context)
            let sanitizedStack = sanitizeForPublicReport(stackLines.prefix(6).joined(separator: "\n"))
            blocks.append(ParsedBlock(
                timestamp: timestamp,
                category: category,
                message: sanitizedMsg,
                context: sanitizedCtx,
                stack: sanitizedStack
            ))
        }

        // Agrupar por firma estable (categoría + mensaje normalizado sin números variables).
        struct GroupBucket {
            let id: String
            let category: String
            let sampleMessage: String
            var count: Int
            var firstSeen: String
            var lastSeen: String
            var context: String
            var stack: String
        }

        var buckets: [String: GroupBucket] = [:]
        for block in blocks {
            let normalizedMsg = replacingRegex(in: block.message, pattern: #"\d+(?:\.\d+)?"#, with: "#")
            let fp = deterministicFingerprint("\(block.category)::\(normalizedMsg.prefix(140))")
            if var existing = buckets[fp] {
                existing.count += 1
                existing.lastSeen = block.timestamp
                if existing.stack.isEmpty && !block.stack.isEmpty {
                    existing.stack = block.stack
                }
                buckets[fp] = existing
            } else {
                buckets[fp] = GroupBucket(
                    id: fp,
                    category: block.category,
                    sampleMessage: String(block.message.prefix(220)),
                    count: 1,
                    firstSeen: block.timestamp,
                    lastSeen: block.timestamp,
                    context: String(block.context.prefix(180)),
                    stack: block.stack
                )
            }
        }

        let sorted = buckets.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.lastSeen > rhs.lastSeen
            }
            .prefix(maxGroups)
            .map {
                InternalErrorSummaryGroup(
                    id: $0.id,
                    category: $0.category,
                    sampleMessage: $0.sampleMessage,
                    count: $0.count,
                    firstSeen: $0.firstSeen,
                    lastSeen: $0.lastSeen,
                    sanitizedContext: $0.context,
                    sampleStack: $0.stack
                )
            }

        return (Array(sorted), blocks.count)
    }

    private static func extractBracketTokens(from line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]"#) else { return [] }
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    private static func currentLogByteSize() -> UInt64 {
        let path = logFileURL.path(percentEncoded: false)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else {
            return 0
        }
        return size
    }

    private static func readLogText(fromByteOffset offset: UInt64) -> String {
        let path = logFileURL.path(percentEncoded: false)
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    private static func rotateLogIfNeeded() {
        let size = currentLogByteSize()
        guard size > maxLogBytes else { return }
        let keepFrom = size - (maxLogBytes / 2)
        let tail = readLogText(fromByteOffset: keepFrom)
        let trimmedTail: String
        if let sepRange = tail.range(of: entrySeparator) {
            trimmedTail = String(tail[sepRange.lowerBound...])
        } else {
            trimmedTail = tail
        }
        if let data = trimmedTail.data(using: .utf8) {
            try? data.write(to: logFileURL, options: .atomic)
            UserDefaults.standard.set(0, forKey: DefaultsKeys.lastReportedOffset)
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
            let checkStartUptime = ProcessInfo.processInfo.systemUptime
            let checkStartWall = Date()
            DispatchQueue.main.async {
                self.lock.lock()
                self.lastMainThreadHeartbeat = Date()
                self.lock.unlock()
                semaphore.signal()
            }
            let waitResult = semaphore.wait(timeout: .now() + 3.0)
            if waitResult == .timedOut {
                let awakeElapsed = ProcessInfo.processInfo.systemUptime - checkStartUptime
                let wallElapsed = Date().timeIntervalSince(checkStartWall)
                // Ignorar falsos positivos producidos por suspensión/reactivación del sistema (sleep/wake).
                guard awakeElapsed >= 2.8, abs(wallElapsed - awakeElapsed) < 2.0 else {
                    return
                }
                self.logError(
                    category: "MAIN_THREAD_HANG",
                    message: String(format: "El hilo principal tardó más de %.2fs en responder (posible cuelgue / freeze).", awakeElapsed),
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
            \(InternalErrorLogger.entrySeparator)
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
                    let header = "\n\(InternalErrorLogger.entrySeparator)\n[INTERNAL_ERROR] [FATAL_SIGNAL_\(receivedSignal)]\n"
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
