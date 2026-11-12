import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Reglas de Operación Drag & Drop Estilo Finder

/// Centraliza la detección de URLs arrastradas, validación de destinos (evitando bucles en subcarpetas)
/// y decisión Mover vs Copiar idéntica a macOS Finder.
@MainActor
public enum DragDropOperationHelper {

    public static func isOptionKeyPressed() -> Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    public static func isCommandKeyPressed() -> Bool {
        NSEvent.modifierFlags.contains(.command)
    }

    /// Lee de forma síncrona las URLs de archivos locales presentes en el pasteboard de arrastre del sistema.
    public static func readDragPasteboardFileURLs() -> [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return []
        }
        return urls.map(\.standardizedFileURL)
    }

    /// Extrae todas las URLs de archivo válidas desde `DropInfo` (tanto internas de `MacFileExplorer` como de Finder u otras apps).
    public static func extractFileURLs(from info: DropInfo) async -> [URL] {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            return readDragPasteboardFileURLs()
        }

        var extracted: [URL] = []
        extracted.reserveCapacity(providers.count)
        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                extracted.append(url)
            }
        }

        if !extracted.isEmpty {
            return extracted
        }
        return readDragPasteboardFileURLs()
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.isFileURL else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url.standardizedFileURL)
            }
        }
    }

    /// Determina si soltar `sources` en `destinationDir` debe **copiar** (`true`) o **mover** (`false`):
    /// - Con tecla `⌥` (`Option`) presionada -> siempre Copiar.
    /// - En el mismo volumen sin `⌥` -> Mover.
    /// - Entre volúmenes distintos -> Copiar salvo que se mantenga `⌘` (`Command`).
    public static func shouldCopy(
        sources: [URL],
        destinationDir: URL,
        forceOptionCopy: Bool = isOptionKeyPressed(),
        forceCommandMove: Bool = isCommandKeyPressed()
    ) -> Bool {
        if forceOptionCopy {
            return true
        }
        let destVolume = try? destinationDir.standardizedFileURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let allSameVolume = !sources.isEmpty && sources.allSatisfy { source in
            guard let destVolume,
                  let srcVolume = try? source.standardizedFileURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
                return true
            }
            return srcVolume.isEqual(destVolume)
        }
        if allSameVolume {
            return false
        }
        return !forceCommandMove
    }

    /// Valida que todas las rutas origen puedan soltarse sobre `destinationDir` (sin soltar carpetas dentro de sí mismas
    /// ni mover a la misma carpeta donde ya residen).
    public static func canDrop(_ sources: [URL], into destinationDir: URL, copyRequested: Bool) -> Bool {
        guard !sources.isEmpty else { return false }
        let dest = destinationDir.standardizedFileURL
        var isDestDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dest.path(percentEncoded: false), isDirectory: &isDestDir),
              isDestDir.boolValue else {
            return false
        }

        let destPath = dest.path(percentEncoded: false)
        for source in sources {
            let src = source.standardizedFileURL
            guard src.isFileURL else { return false }

            if src == dest {
                return false
            }

            let srcPath = src.path(percentEncoded: false)
            let srcPrefix = srcPath.hasSuffix("/") ? srcPath : srcPath + "/"
            if destPath.hasPrefix(srcPrefix) {
                return false
            }

            if !copyRequested && src.deletingLastPathComponent().standardizedFileURL == dest {
                return false
            }
        }
        return true
    }

    public static func isPoint(_ point: CGPoint, insideAny frames: [FileItem.ID: CGRect]) -> Bool {
        frames.values.contains { $0.contains(point) }
    }

    private static var recentInternalDrops: [(urls: Set<URL>, recordedAt: Date)] = []

    /// Registra que un drop fue manejado internamente por `MacFileExplorer` para que la fuente de arrastre no repita la operación.
    public static func recordInternalDrop(urls: [URL]) {
        let cutoff = Date().addingTimeInterval(-5.0)
        recentInternalDrops.removeAll { $0.recordedAt < cutoff }
        recentInternalDrops.append((Set(urls.map(\.standardizedFileURL)), Date()))
    }

    /// Consume y devuelve `true` si las URLs arrastradas ya fueron procesadas por un destino interno de `MacFileExplorer`.
    public static func consumeInternalDropMatch(for urls: [URL]) -> Bool {
        let cutoff = Date().addingTimeInterval(-5.0)
        recentInternalDrops.removeAll { $0.recordedAt < cutoff }
        let targetSet = Set(urls.map(\.standardizedFileURL))
        guard let idx = recentInternalDrops.firstIndex(where: { !$0.urls.isDisjoint(with: targetSet) }) else {
            return false
        }
        recentInternalDrops.remove(at: idx)
        return true
    }
}

// MARK: - Destino Reutilizable de Drag & Drop sobre Carpetas / Paneles

@MainActor
public struct ExplorerFolderDropDelegate: DropDelegate {
    public let destinationURL: URL
    public let viewModel: ExplorerViewModel
    public let onTargetChanged: (Bool) -> Void

    public init(
        destinationURL: URL,
        viewModel: ExplorerViewModel,
        onTargetChanged: @escaping (Bool) -> Void
    ) {
        self.destinationURL = destinationURL
        self.viewModel = viewModel
        self.onTargetChanged = onTargetChanged
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    public func dropEntered(info: DropInfo) {
        let proposal = evaluateProposal(for: info)
        onTargetChanged(proposal.operation == .move || proposal.operation == .copy)
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        let proposal = evaluateProposal(for: info)
        onTargetChanged(proposal.operation == .move || proposal.operation == .copy)
        return proposal
    }

    public func dropExited(info: DropInfo) {
        onTargetChanged(false)
    }

    public func performDrop(info: DropInfo) -> Bool {
        onTargetChanged(false)
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }

        let targetDir = destinationURL
        let explicitCopy = DragDropOperationHelper.isOptionKeyPressed()
        let explicitMove = DragDropOperationHelper.isCommandKeyPressed()
        let vm = viewModel

        let syncURLs = DragDropOperationHelper.readDragPasteboardFileURLs()
        if !syncURLs.isEmpty {
            let copy = DragDropOperationHelper.shouldCopy(
                sources: syncURLs,
                destinationDir: targetDir,
                forceOptionCopy: explicitCopy,
                forceCommandMove: explicitMove
            )
            guard DragDropOperationHelper.canDrop(syncURLs, into: targetDir, copyRequested: copy) else {
                return false
            }
            DragDropOperationHelper.recordInternalDrop(urls: syncURLs)
            Task { @MainActor in
                await vm.handleDrop(
                    urls: syncURLs,
                    into: targetDir,
                    explicitCopy: explicitCopy,
                    explicitMove: explicitMove
                )
            }
            return true
        }

        Task { @MainActor in
            let urls = await DragDropOperationHelper.extractFileURLs(from: info)
            guard !urls.isEmpty else { return }
            DragDropOperationHelper.recordInternalDrop(urls: urls)
            await vm.handleDrop(
                urls: urls,
                into: targetDir,
                explicitCopy: explicitCopy,
                explicitMove: explicitMove
            )
        }
        return true
    }

    private func evaluateProposal(for info: DropInfo) -> DropProposal {
        guard info.hasItemsConforming(to: [.fileURL]) else {
            return DropProposal(operation: .forbidden)
        }
        let pasteboardURLs = DragDropOperationHelper.readDragPasteboardFileURLs()
        if !pasteboardURLs.isEmpty {
            let copy = DragDropOperationHelper.shouldCopy(sources: pasteboardURLs, destinationDir: destinationURL)
            guard DragDropOperationHelper.canDrop(pasteboardURLs, into: destinationURL, copyRequested: copy) else {
                return DropProposal(operation: .forbidden)
            }
            return DropProposal(operation: copy ? .copy : .move)
        }
        let copy = DragDropOperationHelper.isOptionKeyPressed()
        return DropProposal(operation: copy ? .copy : .move)
    }
}

public extension View {
    /// Habilita un destino de arrastre de archivos estilo Finder sobre carpetas del contenido o del panel lateral.
    @ViewBuilder
    func explorerFolderDropTarget(
        enabled: Bool,
        destinationURL: URL,
        viewModel: ExplorerViewModel,
        isTargeted: Binding<Bool>
    ) -> some View {
        if enabled {
            self.onDrop(
                of: [.fileURL],
                delegate: ExplorerFolderDropDelegate(
                    destinationURL: destinationURL,
                    viewModel: viewModel,
                    onTargetChanged: { targeted in
                        isTargeted.wrappedValue = targeted
                    }
                )
            )
        } else {
            self
        }
    }

    /// Habilita un destino de arrastre en la sección "Acceso rápido" para fijar carpetas como favoritas.
    func quickAccessFavoriteDropTarget(
        isTargeted: Binding<Bool>,
        onDropFolders: @escaping @MainActor ([URL]) -> Void
    ) -> some View {
        self.onDrop(
            of: [.fileURL],
            delegate: QuickAccessPinDropDelegate(
                onTargetChanged: { targeted in
                    isTargeted.wrappedValue = targeted
                },
                onDropFolders: onDropFolders
            )
        )
    }
}

@MainActor
public struct QuickAccessPinDropDelegate: DropDelegate {
    public let onTargetChanged: (Bool) -> Void
    public let onDropFolders: @MainActor ([URL]) -> Void

    public init(
        onTargetChanged: @escaping (Bool) -> Void,
        onDropFolders: @escaping @MainActor ([URL]) -> Void
    ) {
        self.onTargetChanged = onTargetChanged
        self.onDropFolders = onDropFolders
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    public func dropEntered(info: DropInfo) {
        onTargetChanged(evaluateProposal(for: info).operation == .copy)
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        let proposal = evaluateProposal(for: info)
        onTargetChanged(proposal.operation == .copy)
        return proposal
    }

    public func dropExited(info: DropInfo) {
        onTargetChanged(false)
    }

    public func performDrop(info: DropInfo) -> Bool {
        onTargetChanged(false)
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }

        let syncURLs = DragDropOperationHelper.readDragPasteboardFileURLs()
        if !syncURLs.isEmpty {
            let folders = Self.filterDirectoryURLs(syncURLs)
            guard !folders.isEmpty else { return false }
            DragDropOperationHelper.recordInternalDrop(urls: syncURLs)
            onDropFolders(folders)
            return true
        }

        let handler = onDropFolders
        Task { @MainActor in
            let urls = await DragDropOperationHelper.extractFileURLs(from: info)
            let folders = Self.filterDirectoryURLs(urls)
            guard !folders.isEmpty else { return }
            DragDropOperationHelper.recordInternalDrop(urls: urls)
            handler(folders)
        }
        return true
    }

    private func evaluateProposal(for info: DropInfo) -> DropProposal {
        guard info.hasItemsConforming(to: [.fileURL]) else {
            return DropProposal(operation: .forbidden)
        }
        let pasteboardURLs = DragDropOperationHelper.readDragPasteboardFileURLs()
        if !pasteboardURLs.isEmpty {
            return DropProposal(operation: Self.filterDirectoryURLs(pasteboardURLs).isEmpty ? .forbidden : .copy)
        }
        return DropProposal(operation: .copy)
    }

    private static func filterDirectoryURLs(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        return urls.compactMap { rawURL in
            let standardized = rawURL.standardizedFileURL
            guard standardized.isFileURL else { return nil }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path(percentEncoded: false), isDirectory: &isDir),
                  isDir.boolValue else {
                return nil
            }
            return standardized
        }
    }
}

// MARK: - Origen Nativo AppKit de Arrastre Multi-Archivo (`NSDraggingSession`)

/// Vista auxiliar transparente inserta en el lienzo de archivos para iniciar sesiones nativas
/// `NSDraggingSession` con múltiples archivos, iconos reales y soporte completo Mover/Copiar hacia Finder y otras apps.
public struct NativeFileDragCanvas: NSViewRepresentable {
    public let viewModel: ExplorerViewModel
    public let itemFrames: [FileItem.ID: CGRect]

    public init(viewModel: ExplorerViewModel, itemFrames: [FileItem.ID: CGRect]) {
        self.viewModel = viewModel
        self.itemFrames = itemFrames
    }

    public func makeNSView(context: Context) -> DragCanvasNSView {
        let view = DragCanvasNSView()
        view.viewModel = viewModel
        view.itemFrames = itemFrames
        return view
    }

    public func updateNSView(_ nsView: DragCanvasNSView, context: Context) {
        nsView.viewModel = viewModel
        nsView.itemFrames = itemFrames
    }

    public static func dismantleNSView(_ nsView: DragCanvasNSView, coordinator: ()) {
        nsView.uninstallMonitor()
    }
}

@MainActor
public final class DragCanvasNSView: NSView, NSDraggingSource {
    weak var viewModel: ExplorerViewModel?
    var itemFrames: [FileItem.ID: CGRect] = [:]

    private struct PendingDrag {
        let item: FileItem
        let startWindowPoint: NSPoint
        let mouseDownEvent: NSEvent
    }

    private var mouseMonitor: Any?
    private var pendingDrag: PendingDrag?
    private var isDraggingSessionActive: Bool = false
    private var activeDraggedURLs: [URL] = []

    public override var isFlipped: Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        // Transparente a clics, hovers, menú contextual y botones de casilla de SwiftUI
        return nil
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitorIfNeeded()
        } else {
            uninstallMonitor()
        }
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            uninstallMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private struct MainThreadEventBox: @unchecked Sendable {
        let event: NSEvent
    }

    private func installMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard Thread.isMainThread else { return event }
            let box = MainThreadEventBox(event: event)
            let shouldConsume = MainActor.assumeIsolated {
                self?.processMouseEvent(box.event) ?? false
            }
            return shouldConsume ? nil : event
        }
    }

    func uninstallMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        pendingDrag = nil
    }

    private func processMouseEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            pendingDrag = nil
            guard !isDraggingSessionActive,
                  event.clickCount == 1,
                  let hostWindow = window,
                  event.window === hostWindow,
                  hostWindow.tabGroup?.selectedWindow == nil || hostWindow.tabGroup?.selectedWindow === hostWindow,
                  !isHiddenOrHasHiddenAncestor,
                  let viewModel,
                  viewModel.renamingItemID == nil else {
                return false
            }

            let locationInWindow = event.locationInWindow
            if let hit = hostWindow.contentView?.hitTest(locationInWindow),
               hit is NSScroller || hit is NSTextView {
                return false
            }

            let localPoint = convert(locationInWindow, from: nil)
            guard bounds.contains(localPoint), visibleRect.contains(localPoint) else {
                return false
            }

            if !viewModel.isEditingAddressBar {
                KeyboardShortcuts.resignTextFocus(in: hostWindow)
            }

            guard let matched = itemFrames.first(where: { $0.value.contains(localPoint) }),
                  let item = viewModel.displayedItems.first(where: { $0.id == matched.key }) else {
                return false
            }

            pendingDrag = PendingDrag(
                item: item,
                startWindowPoint: locationInWindow,
                mouseDownEvent: event
            )
            return false

        case .leftMouseDragged:
            guard let pending = pendingDrag,
                  !isDraggingSessionActive,
                  let hostWindow = window,
                  event.window === hostWindow,
                  let viewModel else {
                return false
            }

            let locationInWindow = event.locationInWindow
            let dx = locationInWindow.x - pending.startWindowPoint.x
            let dy = locationInWindow.y - pending.startWindowPoint.y
            guard hypot(dx, dy) >= 5.0 else {
                return false
            }

            pendingDrag = nil
            startDraggingSession(for: pending.item, triggerEvent: event, viewModel: viewModel)
            return true

        case .leftMouseUp:
            pendingDrag = nil
            return false

        default:
            return false
        }
    }

    private func startDraggingSession(for anchorItem: FileItem, triggerEvent: NSEvent, viewModel: ExplorerViewModel) {
        let itemsToDrag = viewModel.itemsForDrag(startingWith: anchorItem)
        guard !itemsToDrag.isEmpty else { return }

        let anchorPoint = convert(triggerEvent.locationInWindow, from: nil)
        let iconDimension: CGFloat = 40
        var draggingItems: [NSDraggingItem] = []
        draggingItems.reserveCapacity(itemsToDrag.count)

        for (index, item) in itemsToDrag.enumerated() {
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let offset = CGFloat(min(index, 4)) * 3.0
            let frame = NSRect(
                x: anchorPoint.x - iconDimension / 2.0 + offset,
                y: anchorPoint.y - iconDimension / 2.0 + offset,
                width: iconDimension,
                height: iconDimension
            )
            if index < 6 {
                let preview = dragPreviewImage(for: item, size: iconDimension)
                draggingItem.setDraggingFrame(frame, contents: preview)
            } else {
                draggingItem.setDraggingFrame(frame, contents: nil)
            }
            draggingItems.append(draggingItem)
        }

        activeDraggedURLs = itemsToDrag.map(\.url)
        isDraggingSessionActive = true

        let session = beginDraggingSession(with: draggingItems, event: triggerEvent, source: self)
        session.draggingFormation = itemsToDrag.count > 1 ? .pile : .none
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func dragPreviewImage(for item: FileItem, size: CGFloat) -> NSImage {
        if let thumb = ThumbnailCacheService.shared.memoryCachedThumbnail(for: item) {
            let preview = Image(nsImage: thumb)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: size, maxHeight: size)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(width: size, height: size)
            let renderer = ImageRenderer(content: preview)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
            if let nsImg = renderer.nsImage {
                nsImg.size = NSSize(width: size, height: size)
                return nsImg
            }
        }
        return FileIconProvider.shared.icon(for: item, size: size)
    }

    // MARK: - `NSDraggingSource`

    public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return [.move, .copy]
        case .outsideApplication:
            // Incluir `.move` y `.copy` sin `.every` permite a Finder mover archivos en el mismo volumen
            // (o copiar manteniendo `⌥`) y a otras apps (Mail, Slack, Chrome, VS Code) recibir el archivo.
            return [.move, .copy, .generic, .link, .delete]
        @unknown default:
            return [.move, .copy]
        }
    }

    public func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }

    public func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let finishedURLs = activeDraggedURLs
        activeDraggedURLs = []
        isDraggingSessionActive = false
        viewModel?.handleCompletedOutgoingDrag(urls: finishedURLs, operation: operation)
    }
}
