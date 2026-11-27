import AppKit
import Foundation
import Observation

public enum TransferOperationKind: String, Sendable {
    case copy
    case move

    @MainActor
    public func localizedVerb(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .copy: return loc.text(es: "Copiando", en: "Copying")
        case .move: return loc.text(es: "Moviendo", en: "Moving")
        }
    }
}

public enum TransferJobStatus: Equatable, Sendable {
    case queued
    case running
    case paused
    case completed
    case cancelled
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed: return true
        default: return false
        }
    }
}

@MainActor
@Observable
public final class TransferJob: Identifiable {
    public let id = UUID()
    public let kind: TransferOperationKind
    public let sourceURLs: [URL]
    public let destinationDirectory: URL
    public let totalBytes: Int64
    public var transferredBytes: Int64 = 0
    public var currentFileName: String = ""
    public var status: TransferJobStatus = .queued
    public var resultingURLs: [URL] = []

    public var progress: Double {
        guard totalBytes > 0 else { return status == .completed ? 1.0 : 0.0 }
        return min(max(Double(transferredBytes) / Double(totalBytes), 0.0), 1.0)
    }

    public var title: String {
        let loc = LocalizationManager.shared
        let count = sourceURLs.count
        if count == 1, let first = sourceURLs.first {
            return "\(kind.localizedVerb(using: loc)): \(first.lastPathComponent)"
        }
        return loc.text(
            es: "\(kind.localizedVerb(using: loc)) \(count) elementos",
            en: "\(kind.localizedVerb(using: loc)) \(count) items"
        )
    }

    public init(
        kind: TransferOperationKind,
        sourceURLs: [URL],
        destinationDirectory: URL,
        totalBytes: Int64
    ) {
        self.kind = kind
        self.sourceURLs = sourceURLs
        self.destinationDirectory = destinationDirectory
        self.totalBytes = totalBytes
    }
}

/// Gestor unificado de cola de transferencias (> 1 GB) con soporte de Pausar, Reanudar y Cancelar.
@MainActor
@Observable
public final class TransferQueueManager {
    public static let shared = TransferQueueManager()

    /// Umbral de 1 GB (1_000_000_000 bytes) a partir del cual se usa la cola pausable.
    public static let queueThresholdBytes: Int64 = 1_000_000_000

    public private(set) var jobs: [TransferJob] = []
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var completionHandlers: [UUID: @MainActor ([URL]) -> Void] = [:]

    private init() {}

    /// Calcula de forma asíncrona el tamaño total en bytes de una lista de URLs (archivos, carpetas y paquetes).
    public static func calculateTotalBytes(of urls: [URL]) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var total: Int64 = 0
            for rawURL in urls {
                let url = rawURL.standardizedFileURL
                let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if vals?.isSymbolicLink == true {
                    if let size = vals?.fileSize {
                        total += Int64(size)
                    }
                    continue
                }
                if vals?.isDirectory == true {
                    if let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
                        options: []
                    ) {
                        while let child = enumerator.nextObject() as? URL {
                            if let childVals = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                               childVals.isSymbolicLink != true,
                               childVals.isRegularFile == true,
                               let size = childVals.fileSize {
                                total += Int64(size)
                            }
                        }
                    }
                } else if let size = vals?.fileSize {
                    total += Int64(size)
                }
            }
            return total
        }.value
    }

    public var primaryActiveJob: TransferJob? {
        jobs.first(where: { $0.status == .running || $0.status == .paused }) ?? jobs.first
    }

    /// Encola una transferencia pesada y comienza su ejecución mostrándola en la barra de progreso inferior.
    @discardableResult
    public func enqueue(
        kind: TransferOperationKind,
        sourceURLs: [URL],
        destinationDirectory: URL,
        totalBytes: Int64,
        onComplete: (@MainActor ([URL]) -> Void)? = nil
    ) -> TransferJob {
        let job = TransferJob(
            kind: kind,
            sourceURLs: sourceURLs,
            destinationDirectory: destinationDirectory,
            totalBytes: totalBytes
        )
        jobs.insert(job, at: 0)
        if let onComplete {
            completionHandlers[job.id] = onComplete
        }
        startNextIfIdle()
        return job
    }

    public func pause(_ job: TransferJob) {
        guard job.status == .running else { return }
        job.status = .paused
    }

    public func resume(_ job: TransferJob) {
        guard job.status == .paused else { return }
        job.status = .running
    }

    public func cancel(_ job: TransferJob) {
        guard !job.status.isTerminal else {
            jobs.removeAll { $0.id == job.id }
            return
        }
        job.status = .cancelled
        activeTasks[job.id]?.cancel()
        activeTasks.removeValue(forKey: job.id)
        completionHandlers.removeValue(forKey: job.id)
        jobs.removeAll { $0.id == job.id }
        startNextIfIdle()
    }

    public func clearFinished() {
        jobs.removeAll { $0.status.isTerminal }
    }

    private func startNextIfIdle() {
        let hasRunning = jobs.contains { $0.status == .running || $0.status == .paused }
        guard !hasRunning else { return }
        guard let nextJob = jobs.last(where: { $0.status == .queued }) else { return }
        run(job: nextJob)
    }

    private func run(job: TransferJob) {
        job.status = .running
        let jobID = job.id
        let kind = job.kind
        let sources = job.sourceURLs
        let destDir = job.destinationDirectory

        let task = Task { [weak self] in
            guard let self else { return }
            var shouldKeepVisible = false
            do {
                let created = try await self.executeTransfer(
                    job: job,
                    kind: kind,
                    sources: sources,
                    destinationDirectory: destDir
                )
                if job.status != .cancelled && !Task.isCancelled {
                    job.resultingURLs = created
                    job.transferredBytes = max(job.transferredBytes, job.totalBytes)
                    job.status = .completed
                    if let handler = self.completionHandlers.removeValue(forKey: jobID) {
                        handler(created)
                    }
                }
            } catch is CancellationError {
                self.completionHandlers.removeValue(forKey: jobID)
                if job.status != .cancelled {
                    job.status = .cancelled
                }
            } catch {
                self.completionHandlers.removeValue(forKey: jobID)
                if job.status != .cancelled && !Task.isCancelled {
                    job.status = .failed(error.localizedDescription)
                    shouldKeepVisible = true
                }
            }
            self.activeTasks.removeValue(forKey: jobID)
            if !shouldKeepVisible {
                self.jobs.removeAll { $0.id == jobID }
            }
            self.startNextIfIdle()
        }
        activeTasks[jobID] = task
    }

    private func executeTransfer(
        job: TransferJob,
        kind: TransferOperationKind,
        sources: [URL],
        destinationDirectory: URL
    ) async throws -> [URL] {
        var createdTopLevelURLs: [URL] = []

        for rawSource in sources {
            try await waitIfPausedOrCancelled(job: job)
            let source = rawSource.standardizedFileURL
            let destURL = uniqueDestinationURL(
                in: destinationDirectory,
                originalName: source.lastPathComponent
            )

            let vals = try? source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
            let isSymlink = vals?.isSymbolicLink == true
            let isPackage = vals?.isPackage == true
            let isFolder = (vals?.isDirectory == true) && !isPackage && !isSymlink

            if kind == .move, isSameVolume(source, destinationDirectory) {
                job.currentFileName = source.lastPathComponent
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.moveItem(at: source, to: destURL)
                }.value
                let size = await Self.calculateTotalBytes(of: [destURL])
                job.transferredBytes += size
                createdTopLevelURLs.append(destURL)
                continue
            }

            if isSymlink || isPackage {
                try await copyItemDirectly(from: source, to: destURL, job: job)
            } else if isFolder {
                try await copyDirectoryChunked(
                    from: source,
                    to: destURL,
                    job: job
                )
            } else {
                try await copyFileChunked(
                    from: source,
                    to: destURL,
                    job: job
                )
            }

            if kind == .move {
                try? await Task.detached(priority: .userInitiated) {
                    try FileManager.default.removeItem(at: source)
                }.value
            }
            createdTopLevelURLs.append(destURL)
        }
        return createdTopLevelURLs
    }

    private func copyItemDirectly(
        from sourceURL: URL,
        to destURL: URL,
        job: TransferJob
    ) async throws {
        try await waitIfPausedOrCancelled(job: job)
        job.currentFileName = sourceURL.lastPathComponent
        let copiedBytes: Int64 = try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: sourceURL, to: destURL)
            let vals = try? destURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if vals?.isSymbolicLink == true {
                return Int64(vals?.fileSize ?? 0)
            }
            if vals?.isDirectory == true {
                var total: Int64 = 0
                if let enumerator = fm.enumerator(
                    at: destURL,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
                    options: []
                ) {
                    while let child = enumerator.nextObject() as? URL {
                        if let cVals = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                           cVals.isSymbolicLink != true,
                           cVals.isRegularFile == true,
                           let sz = cVals.fileSize {
                            total += Int64(sz)
                        }
                    }
                }
                return total
            }
            return Int64(vals?.fileSize ?? 0)
        }.value
        job.transferredBytes += copiedBytes
    }

    private struct DirectoryEntry: Sendable {
        let sourceURL: URL
        let relativePath: String
        let isDirectory: Bool
        let isPackage: Bool
        let isSymbolicLink: Bool
    }

    private func copyDirectoryChunked(
        from sourceDir: URL,
        to destDir: URL,
        job: TransferJob
    ) async throws {
        let entries: [DirectoryEntry] = try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            guard let enumerator = fm.enumerator(
                at: sourceDir,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            ) else {
                return []
            }

            let sourcePath = sourceDir.path(percentEncoded: false)
            var collected: [DirectoryEntry] = []
            while let child = enumerator.nextObject() as? URL {
                let childPath = child.path(percentEncoded: false)
                guard childPath.hasPrefix(sourcePath) else { continue }
                var relative = String(childPath.dropFirst(sourcePath.count))
                if relative.hasPrefix("/") { relative.removeFirst() }
                guard !relative.isEmpty else { continue }

                let vals = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
                collected.append(
                    DirectoryEntry(
                        sourceURL: child,
                        relativePath: relative,
                        isDirectory: vals?.isDirectory == true,
                        isPackage: vals?.isPackage == true,
                        isSymbolicLink: vals?.isSymbolicLink == true
                    )
                )
            }
            return collected
        }.value

        for entry in entries {
            try await waitIfPausedOrCancelled(job: job)
            let targetChild = destDir.appendingPathComponent(entry.relativePath)

            if entry.isSymbolicLink || entry.isPackage {
                try await copyItemDirectly(from: entry.sourceURL, to: targetChild, job: job)
            } else if entry.isDirectory {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: targetChild, withIntermediateDirectories: true)
                }.value
            } else {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: targetChild.deletingLastPathComponent(), withIntermediateDirectories: true)
                }.value
                try await copyFileChunked(from: entry.sourceURL, to: targetChild, job: job)
            }
        }

        await Task.detached(priority: .userInitiated) {
            Self.preserveAttributes(from: sourceDir, to: destDir)
        }.value
    }

    private func copyFileChunked(
        from sourceURL: URL,
        to destURL: URL,
        job: TransferJob
    ) async throws {
        let vals = try? sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isPackageKey, .isDirectoryKey])
        if vals?.isSymbolicLink == true || vals?.isPackage == true || vals?.isDirectory == true {
            try await copyItemDirectly(from: sourceURL, to: destURL, job: job)
            return
        }

        job.currentFileName = sourceURL.lastPathComponent

        let chunkSize = 4 * 1024 * 1024 // 4 MB por chunk para pausar/reanudar al instante

        let (readHandle, writeHandle): (FileHandle, FileHandle) = try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let rHandle = try FileHandle(forReadingFrom: sourceURL)
            let destPath = destURL.path(percentEncoded: false)
            if !fm.createFile(atPath: destPath, contents: nil) {
                try? rHandle.close()
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destPath])
            }
            do {
                let wHandle = try FileHandle(forWritingTo: destURL)
                return (rHandle, wHandle)
            } catch {
                try? rHandle.close()
                try? fm.removeItem(at: destURL)
                throw error
            }
        }.value

        var didComplete = false
        defer {
            try? readHandle.close()
            try? writeHandle.close()
            if !didComplete {
                try? FileManager.default.removeItem(at: destURL)
            }
        }

        while true {
            try await waitIfPausedOrCancelled(job: job)
            let data = try await Task.detached(priority: .userInitiated) {
                try readHandle.read(upToCount: chunkSize)
            }.value
            guard let data, !data.isEmpty else {
                break
            }
            try await Task.detached(priority: .userInitiated) {
                try writeHandle.write(contentsOf: data)
            }.value
            job.transferredBytes += Int64(data.count)
        }
        didComplete = true

        try? writeHandle.close()
        await Task.detached(priority: .userInitiated) {
            Self.preserveAttributes(from: sourceURL, to: destURL)
        }.value
    }

    private nonisolated static func preserveAttributes(from sourceURL: URL, to destURL: URL) {
        let fm = FileManager.default
        let srcPath = sourceURL.path(percentEncoded: false)
        let dstPath = destURL.path(percentEncoded: false)
        guard let srcAttrs = try? fm.attributesOfItem(atPath: srcPath) else { return }
        var preserved: [FileAttributeKey: Any] = [:]
        if let perms = srcAttrs[.posixPermissions] {
            preserved[.posixPermissions] = perms
        }
        if let creation = srcAttrs[.creationDate] {
            preserved[.creationDate] = creation
        }
        if let modification = srcAttrs[.modificationDate] {
            preserved[.modificationDate] = modification
        }
        if !preserved.isEmpty {
            try? fm.setAttributes(preserved, ofItemAtPath: dstPath)
        }
    }

    private func waitIfPausedOrCancelled(job: TransferJob) async throws {
        while true {
            if Task.isCancelled || job.status == .cancelled {
                throw CancellationError()
            }
            if job.status != .paused {
                return
            }
            try await Task.sleep(for: .milliseconds(120))
        }
    }

    private func isSameVolume(_ lhs: URL, _ rhs: URL) -> Bool {
        let v1 = try? lhs.standardizedFileURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let v2 = try? rhs.standardizedFileURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let v1, let v2 else { return false }
        return v1.isEqual(v2)
    }

    private func uniqueDestinationURL(in directory: URL, originalName: String) -> URL {
        let fm = FileManager.default
        let candidate = directory.appendingPathComponent(originalName)
        if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }
        let stem = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            let next = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: next.path(percentEncoded: false)) {
                return next
            }
            counter += 1
        }
    }
}
