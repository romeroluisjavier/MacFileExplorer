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

    /// Calcula de forma asíncrona el tamaño total en bytes de una lista de URLs (archivos y carpetas).
    public static func calculateTotalBytes(of urls: [URL]) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var total: Int64 = 0
            for rawURL in urls {
                let url = rawURL.standardizedFileURL
                if let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey]),
                   vals.isDirectory == true && vals.isPackage != true {
                    if let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                        options: [.skipsPackageDescendants]
                    ) {
                        while let child = enumerator.nextObject() as? URL {
                            if let childVals = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                               childVals.isRegularFile == true,
                               let size = childVals.fileSize {
                                total += Int64(size)
                            }
                        }
                    }
                } else if let vals = try? url.resourceValues(forKeys: [.fileSizeKey]),
                          let size = vals.fileSize {
                    total += Int64(size)
                }
            }
            return total
        }.value
    }

    /// Encola una transferencia pesada, abre la ventana flotante unificada y comienza su ejecución.
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
        TransferQueueWindowController.shared.showWindow()
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
        guard !job.status.isTerminal else { return }
        job.status = .cancelled
        activeTasks[job.id]?.cancel()
        activeTasks.removeValue(forKey: job.id)
        completionHandlers.removeValue(forKey: job.id)
        startNextIfIdle()
    }

    public func clearFinished() {
        jobs.removeAll { $0.status.isTerminal }
    }

    private func startNextIfIdle() {
        let hasRunning = jobs.contains { $0.status == .running || $0.status == .paused }
        guard !hasRunning else { return }
        // Tomar el trabajo en cola más antiguo (al final del arreglo)
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
            do {
                let created = try await self.executeTransfer(
                    job: job,
                    kind: kind,
                    sources: sources,
                    destinationDirectory: destDir
                )
                if job.status == .cancelled || Task.isCancelled {
                    job.status = .cancelled
                } else {
                    job.resultingURLs = created
                    job.transferredBytes = max(job.transferredBytes, job.totalBytes)
                    job.status = .completed
                    if let handler = self.completionHandlers.removeValue(forKey: jobID) {
                        handler(created)
                    }
                }
            } catch {
                if job.status == .cancelled || Task.isCancelled {
                    job.status = .cancelled
                } else {
                    job.status = .failed(error.localizedDescription)
                }
                self.completionHandlers.removeValue(forKey: jobID)
            }
            self.activeTasks.removeValue(forKey: jobID)
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

            let vals = try? source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isFolder = (vals?.isDirectory == true) && (vals?.isPackage != true)

            if kind == .move, isSameVolume(source, destinationDirectory) {
                await MainActor.run {
                    job.currentFileName = source.lastPathComponent
                }
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.moveItem(at: source, to: destURL)
                }.value
                let size = await Self.calculateTotalBytes(of: [destURL])
                await MainActor.run {
                    job.transferredBytes += size
                }
                createdTopLevelURLs.append(destURL)
                continue
            }

            if isFolder {
                try await copyDirectoryChunked(
                    from: source,
                    to: destURL,
                    job: job
                )
                if kind == .move {
                    try? FileManager.default.removeItem(at: source)
                }
            } else {
                try await copyFileChunked(
                    from: source,
                    to: destURL,
                    job: job
                )
                if kind == .move {
                    try? FileManager.default.removeItem(at: source)
                }
            }
            createdTopLevelURLs.append(destURL)
        }
        return createdTopLevelURLs
    }

    private func copyDirectoryChunked(
        from sourceDir: URL,
        to destDir: URL,
        job: TransferJob
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        guard let enumerator = fm.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsPackageDescendants]
        ) else {
            return
        }

        let sourcePath = sourceDir.path(percentEncoded: false)
        while let child = enumerator.nextObject() as? URL {
            try await waitIfPausedOrCancelled(job: job)
            let childPath = child.path(percentEncoded: false)
            guard childPath.hasPrefix(sourcePath) else { continue }
            var relative = String(childPath.dropFirst(sourcePath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            let targetChild = destDir.appendingPathComponent(relative)

            let vals = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if vals?.isDirectory == true && vals?.isPackage != true {
                try fm.createDirectory(at: targetChild, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: targetChild.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await copyFileChunked(from: child, to: targetChild, job: job)
            }
        }
    }

    private func copyFileChunked(
        from sourceURL: URL,
        to destURL: URL,
        job: TransferJob
    ) async throws {
        await MainActor.run {
            job.currentFileName = sourceURL.lastPathComponent
        }

        let fm = FileManager.default
        let chunkSize = 4 * 1024 * 1024 // 4 MB por chunk para pausar/reanudar al instante

        let readHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? readHandle.close() }

        fm.createFile(atPath: destURL.path(percentEncoded: false), contents: nil)
        let writeHandle = try FileHandle(forWritingTo: destURL)
        var didComplete = false
        defer {
            try? writeHandle.close()
            if !didComplete {
                try? fm.removeItem(at: destURL)
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
            let chunkBytes = Int64(data.count)
            await MainActor.run {
                job.transferredBytes += chunkBytes
            }
        }
        didComplete = true
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
