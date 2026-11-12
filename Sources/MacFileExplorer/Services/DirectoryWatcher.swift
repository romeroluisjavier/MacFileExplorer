import Foundation
import CoreServices

/// Monitor de cambios en tiempo real para una carpeta usando `FSEventStream` (`CoreServices`)
/// y `DispatchSourceFileSystemObject` (`O_EVTONLY`) sobre el hilo principal.
@MainActor
public final class DirectoryWatcher {
    private nonisolated(unsafe) var source: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var eventStream: FSEventStreamRef?
    private let fsEventBox: FSEventCallbackBox?

    public init?(
        url: URL,
        enableFSEvents: Bool = false,
        onChange: @escaping @MainActor () -> Void
    ) {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let watchedPath = Self.normalizedPath(resolvedURL.path(percentEncoded: false))

        let fd = open(watchedPath, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend, .link, .attrib, .revoke],
                queue: .main
            )
            src.setEventHandler {
                MainActor.assumeIsolated {
                    onChange()
                }
            }
            src.setCancelHandler {
                close(fd)
            }
            src.resume()
            self.source = src
        }

        if enableFSEvents {
            let box = FSEventCallbackBox(
                watchedRootPath: watchedPath,
                ignoredPrefixes: [
                    DirectoryIndexCacheService.hiddenCacheFileName,
                    ThumbnailDiskCoordinator.hiddenCacheFileName
                ],
                onChange: onChange
            )
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(box).toOpaque(),
                retain: nil,
                release: { pointer in
                    guard let pointer else { return }
                    Unmanaged<FSEventCallbackBox>.fromOpaque(pointer).release()
                },
                copyDescription: nil
            )

            let pathsToWatch = [watchedPath] as CFArray
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
            if let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                directoryWatcherFSEventCallback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.05,
                flags
            ) {
                FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
                if FSEventStreamStart(stream) {
                    self.eventStream = stream
                    self.fsEventBox = box
                } else {
                    FSEventStreamInvalidate(stream)
                    FSEventStreamRelease(stream)
                    self.fsEventBox = nil
                }
            } else {
                Unmanaged.passUnretained(box).release()
                self.fsEventBox = nil
            }
        } else {
            self.fsEventBox = nil
        }

        if self.source == nil && self.eventStream == nil {
            return nil
        }
    }

    public func invalidate() {
        fsEventBox?.isInvalidated = true
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        source?.cancel()
        source = nil
    }

    deinit {
        fsEventBox?.isInvalidated = true
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        source?.cancel()
    }

    private nonisolated static func normalizedPath(_ rawPath: String) -> String {
        if rawPath.count > 1 && rawPath.hasSuffix("/") {
            return String(rawPath.dropLast())
        }
        return rawPath
    }
}

private final class FSEventCallbackBox: @unchecked Sendable {
    let watchedRootPath: String
    let ignoredPrefixes: [String]
    var isInvalidated: Bool = false
    let onChange: @MainActor () -> Void

    init(
        watchedRootPath: String,
        ignoredPrefixes: [String],
        onChange: @escaping @MainActor () -> Void
    ) {
        self.watchedRootPath = watchedRootPath
        self.ignoredPrefixes = ignoredPrefixes
        self.onChange = onChange
    }

    func shouldTriggerChange(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) -> Bool {
        guard !isInvalidated, numEvents > 0 else { return false }

        let paths = UnsafeRawPointer(eventPaths).assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let structuralMask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagRootChanged |
            kFSEventStreamEventFlagMount |
            kFSEventStreamEventFlagUnmount
        )

        for index in 0..<numEvents {
            let flags = eventFlags[index]
            if (flags & structuralMask) != 0 {
                return true
            }

            let rawPath = String(cString: paths[index])
            let cleanPath = (rawPath.count > 1 && rawPath.hasSuffix("/"))
                ? String(rawPath.dropLast())
                : rawPath

            if cleanPath == watchedRootPath {
                return true
            }

            if watchedRootPath == "/" {
                let relative = cleanPath.dropFirst()
                if !relative.contains("/") && !isIgnoredChildName(relative) {
                    return true
                }
            } else if cleanPath.hasPrefix(watchedRootPath + "/") {
                let relative = cleanPath.dropFirst(watchedRootPath.count + 1)
                if !relative.contains("/") && !isIgnoredChildName(relative) {
                    return true
                }
            }
        }

        return false
    }

    private func isIgnoredChildName(_ name: Substring) -> Bool {
        ignoredPrefixes.contains { prefix in
            name.hasPrefix(prefix)
        }
    }
}

private func directoryWatcherFSEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let box = Unmanaged<FSEventCallbackBox>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    guard box.shouldTriggerChange(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags) else {
        return
    }
    MainActor.assumeIsolated {
        guard !box.isInvalidated else { return }
        box.onChange()
    }
}
