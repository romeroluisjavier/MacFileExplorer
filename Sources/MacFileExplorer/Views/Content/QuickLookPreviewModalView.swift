import SwiftUI
import AppKit
import QuickLookUI

/// Envoltorio `NSViewRepresentable` sobre `QLPreviewView` nativo de macOS (`QuickLookUI`).
/// Permite previsualizar PDFs, imágenes, vídeos, audio, código fuente, documentos de texto y carpetas.
public struct NativeQLPreviewRepresentable: NSViewRepresentable {
    public let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        previewView.autostarts = true
        previewView.shouldCloseWithWindow = false
        previewView.previewItem = fileURL?.standardizedFileURL as NSURL?
        return previewView
    }

    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        let targetURL = fileURL?.standardizedFileURL as NSURL?
        let currentURL = nsView.previewItem as? NSURL
        if currentURL == targetURL {
            return
        }
        nsView.previewItem = targetURL
        if targetURL != nil {
            nsView.refreshPreviewItem()
        }
    }
}

/// Estado observable del panel flotante de Vista Rápida para reflejar si está maximizado.
@MainActor
@Observable
public final class QuickLookPanelState {
    public var isMaximized: Bool = false

    public init() {}
}

/// Ventana flotante nativa (`NSPanel`) para Quick Look con cambio de tamaño en bordes/esquinas,
/// arrastre libre desde la barra de título y maximizado/restauración mediante doble clic.
@MainActor
public final class QuickLookPreviewPanel: NSPanel {
    public var onRequestClose: (() -> Void)?
    public var onZoomStateChanged: ((Bool) -> Void)?

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        minSize = NSSize(width: 480, height: 340)
        isMovableByWindowBackground = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    override public func cancelOperation(_ sender: Any?) {
        onRequestClose?()
    }

    /// Alterna entre tamaño normal y maximizado al hacer doble clic en la barra de título o pulsar el botón correspondiente.
    public func toggleMaximize() {
        zoom(nil)
        onZoomStateChanged?(isZoomed)
    }

    /// Calcula el marco inicial predeterminado centrado sobre la ventana anfitriona y acotado a la pantalla visible.
    public static func defaultFrame(
        centeredOver hostFrame: NSRect,
        visibleScreenFrame: NSRect?
    ) -> NSRect {
        let defaultWidth: CGFloat = 860
        let defaultHeight: CGFloat = 600

        let bounds = visibleScreenFrame
        let targetWidth = min(defaultWidth, max(480, (bounds?.width ?? defaultWidth) - 40))
        let targetHeight = min(defaultHeight, max(340, (bounds?.height ?? defaultHeight) - 40))

        var originX = hostFrame.midX - (targetWidth / 2)
        var originY = hostFrame.midY - (targetHeight / 2)

        if let bounds {
            originX = min(max(originX, bounds.minX + 12), bounds.maxX - targetWidth - 12)
            originY = min(max(originY, bounds.minY + 12), bounds.maxY - targetHeight - 12)
        }

        return NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)
    }
}

/// Captura arrastres (mover ventana) y doble clic (maximizar/restaurar) únicamente sobre la barra superior del preview.
private struct QuickLookTitleBarDragZoomRepresentable: NSViewRepresentable {
    let onDoubleClickTitleBar: (() -> Void)?

    func makeNSView(context: Context) -> QuickLookTitleBarDragZoomNSView {
        let view = QuickLookTitleBarDragZoomNSView()
        view.onDoubleClickTitleBar = onDoubleClickTitleBar
        return view
    }

    func updateNSView(_ nsView: QuickLookTitleBarDragZoomNSView, context: Context) {
        nsView.onDoubleClickTitleBar = onDoubleClickTitleBar
    }
}

@MainActor
private final class QuickLookTitleBarDragZoomNSView: NSView {
    var onDoubleClickTitleBar: (() -> Void)?
    private var initialMouseDownEvent: NSEvent?

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            initialMouseDownEvent = nil
            onDoubleClickTitleBar?()
            return
        }
        initialMouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startEvent = initialMouseDownEvent, let window else {
            super.mouseDragged(with: event)
            return
        }
        let dx = abs(event.locationInWindow.x - startEvent.locationInWindow.x)
        let dy = abs(event.locationInWindow.y - startEvent.locationInWindow.y)
        if dx >= 2 || dy >= 2 {
            initialMouseDownEvent = nil
            window.performDrag(with: startEvent)
        }
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseDownEvent = nil
        super.mouseUp(with: event)
    }
}

/// Puente invisible alojado en `MainExplorerView` que administra el ciclo de vida del `QuickLookPreviewPanel`
/// de cada pestaña (mostrar, ocultar al cambiar de pestaña, mover, redimensionar y maximizar con doble clic).
public struct QuickLookPanelHostBridge: NSViewRepresentable {
    @Bindable var viewModel: ExplorerViewModel

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> QuickLookAnchorNSView {
        let view = QuickLookAnchorNSView()
        let coordinator = context.coordinator
        view.onHostWindowChange = { [weak coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.sync(viewModel: viewModel, in: view)
        }
        return view
    }

    public func updateNSView(_ nsView: QuickLookAnchorNSView, context: Context) {
        _ = viewModel.isQuickLookPresented
        _ = viewModel.quickLookItem?.id
        let coordinator = context.coordinator
        nsView.onHostWindowChange = { [weak coordinator, weak nsView] in
            guard let coordinator, let nsView else { return }
            coordinator.sync(viewModel: viewModel, in: nsView)
        }
        coordinator.sync(viewModel: viewModel, in: nsView)
    }

    public static func dismantleNSView(_ nsView: QuickLookAnchorNSView, coordinator: Coordinator) {
        nsView.onHostWindowChange = nil
        coordinator.teardown()
    }

    @MainActor
    public final class Coordinator: NSObject, NSWindowDelegate {
        private var panel: QuickLookPreviewPanel?
        private let panelState = QuickLookPanelState()
        private weak var viewModel: ExplorerViewModel?
        private weak var lastHostWindow: NSWindow?
        private var isApplyingSync = false

        func sync(viewModel: ExplorerViewModel, in anchorView: NSView) {
            self.viewModel = viewModel
            let hostWindow = anchorView.window
            lastHostWindow = hostWindow

            guard viewModel.isQuickLookPresented, viewModel.quickLookItem != nil else {
                hidePanelAndRestoreFocusIfNeeded()
                return
            }

            guard let hostWindow else { return }
            let isHostTabSelected = hostWindow.tabGroup == nil || hostWindow.tabGroup?.selectedWindow === hostWindow
            guard isHostTabSelected && hostWindow.isVisible else {
                // La pestaña no está activa en pantalla: ocultar temporalmente sin perder `isQuickLookPresented`.
                if let panel, panel.isVisible {
                    panel.orderOut(nil)
                }
                return
            }

            let previewPanel = ensurePanel(for: viewModel, hostWindow: hostWindow)

            isApplyingSync = true
            defer { isApplyingSync = false }

            if previewPanel.parent !== hostWindow {
                previewPanel.parent?.removeChildWindow(previewPanel)
                hostWindow.addChildWindow(previewPanel, ordered: .above)
            }

            if !previewPanel.isVisible {
                previewPanel.makeKeyAndOrderFront(nil)
            }
            panelState.isMaximized = previewPanel.isZoomed
        }

        private func ensurePanel(
            for viewModel: ExplorerViewModel,
            hostWindow: NSWindow
        ) -> QuickLookPreviewPanel {
            if let existing = panel {
                return existing
            }

            let visibleFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame
            let initialFrame = PersistenceService.shared.loadQuickLookWindowFrame()
                ?? QuickLookPreviewPanel.defaultFrame(
                    centeredOver: hostWindow.frame,
                    visibleScreenFrame: visibleFrame
                )

            let newPanel = QuickLookPreviewPanel(contentRect: initialFrame)
            newPanel.delegate = self
            newPanel.onRequestClose = { [weak self] in
                self?.viewModel?.closeQuickLook()
            }
            newPanel.onZoomStateChanged = { [weak self] isZoomed in
                self?.panelState.isMaximized = isZoomed
            }

            let contentView = QuickLookPreviewModalView(
                viewModel: viewModel,
                panelState: panelState,
                onToggleMaximize: { [weak newPanel] in
                    newPanel?.toggleMaximize()
                }
            )
            let hostingController = NSHostingController(rootView: contentView)
            hostingController.sizingOptions = []
            newPanel.contentViewController = hostingController
            newPanel.setFrame(initialFrame, display: true)

            self.panel = newPanel
            return newPanel
        }

        private func hidePanelAndRestoreFocusIfNeeded() {
            guard let panel else { return }
            let wasKey = panel.isKeyWindow
            panel.parent?.removeChildWindow(panel)
            if panel.isVisible {
                panel.orderOut(nil)
            }
            if wasKey {
                lastHostWindow?.makeKeyAndOrderFront(nil)
            }
        }

        func teardown() {
            guard let panel else { return }
            panel.delegate = nil
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.close()
            self.panel = nil
        }

        public func windowShouldClose(_ sender: NSWindow) -> Bool {
            viewModel?.closeQuickLook()
            return false
        }

        public func windowDidMove(_ notification: Notification) {
            persistCurrentFrameIfCustom()
        }

        public func windowDidResize(_ notification: Notification) {
            persistCurrentFrameIfCustom()
        }

        private func persistCurrentFrameIfCustom() {
            guard let panel else { return }
            panelState.isMaximized = panel.isZoomed
            guard !isApplyingSync, panel.isVisible, !panel.isZoomed else { return }
            PersistenceService.shared.saveQuickLookWindowFrame(panel.frame)
        }
    }
}

@MainActor
public final class QuickLookAnchorNSView: NSView {
    var onHostWindowChange: (() -> Void)?

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let oldWindow = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: oldWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: oldWindow)
        }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleHostWindowEvent(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleHostWindowEvent(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        DispatchQueue.main.async { [weak self] in
            self?.onHostWindowChange?()
        }
    }

    @objc private func handleHostWindowEvent(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification {
            onHostWindowChange?()
            return
        }
        onHostWindowChange?()
    }
}

/// Contenido de la ventana flotante de Vista Rápida (Quick Look) al presionar la Barra Espaciadora (`Space`),
/// emulando el Quick Look del Finder de macOS con barra de título arrastrable, redimensionable y maximizable.
public struct QuickLookPreviewModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Bindable var panelState: QuickLookPanelState
    var onToggleMaximize: (() -> Void)?

    public init(
        viewModel: ExplorerViewModel,
        panelState: QuickLookPanelState = QuickLookPanelState(),
        onToggleMaximize: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.panelState = panelState
        self.onToggleMaximize = onToggleMaximize
    }

    public var body: some View {
        let activeItem = viewModel.quickLookItem
        let activeURL = viewModel.isQuickLookPresented ? activeItem?.url : nil

        VStack(spacing: 0) {
            if let item = activeItem {
                quickLookHeaderBar(for: item)
                Divider()

                ZStack {
                    if item.isNavigableFolder {
                        Color(nsColor: .windowBackgroundColor)
                        ItemPropertiesContentView(
                            item: item,
                            horizontalPadding: 32,
                            verticalPadding: 22
                        )
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(item.id)
                    } else if let activeURL, RichCodePreviewSupport.supportsRichPreview(for: activeURL) {
                        RichCodePreviewView(fileURL: activeURL)
                            .id(item.id)
                    } else {
                        Color(nsColor: .underPageBackgroundColor)
                        NativeQLPreviewRepresentable(fileURL: activeURL)
                            .id(item.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NativeQLPreviewRepresentable(fileURL: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Barra Superior estilo Finder Quick Look (Arrastrable y Maximizable con Doble Clic)

    private func quickLookHeaderBar(for item: FileItem) -> some View {
        let loc = LocalizationManager.shared
        return HStack(spacing: 10) {
            // 1. Botón de cerrar (✕) y flechas de elemento anterior/siguiente (‹ ›)
            Button {
                viewModel.closeQuickLook()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Cerrar Vista Rápida (Espacio / Esc)", en: "Close Quick Look (Space / Esc)"))

            HStack(spacing: 2) {
                Button {
                    viewModel.selectAdjacentItem(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.canSelectPreviousItem)
                .help(loc.text(es: "Elemento anterior (↑ / ←)", en: "Previous item (↑ / ←)"))

                Button {
                    viewModel.selectAdjacentItem(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.canSelectNextItem)
                .help(loc.text(es: "Elemento siguiente (↓ / →)", en: "Next item (↓ / →)"))
            }

            Divider()
                .frame(height: 16)
                .allowsHitTesting(false)

            // 2. Icono y Nombre del archivo previsualizado (atraviesan clics para permitir mover/maximizar)
            HStack(spacing: 7) {
                Image(nsImage: FileIconProvider.shared.icon(for: item, size: 18))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)

                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !item.formattedSize.isEmpty {
                    Text("(\(item.formattedSize))")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .allowsHitTesting(false)

            Spacer(minLength: 12)

            // 3. Acción principal contextual arriba a la derecha: "Abrir carpeta" o "Open in Preview"
            if item.isNavigableFolder {
                Button {
                    let target = item
                    viewModel.closeQuickLook()
                    viewModel.openItem(target)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11.5, weight: .medium))
                        Text(loc.text(es: "Abrir carpeta", en: "Open Folder"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .help(loc.text(
                    es: "Entrar en esta carpeta",
                    en: "Open this folder"
                ))
            } else {
                Button {
                    viewModel.openInNativePreviewApp(item)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text("Open in Preview")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .help(loc.text(
                    es: "Abrir este archivo en la aplicación nativa 'Preview' (Vista Previa) de macOS",
                    en: "Open this file in macOS native 'Preview' application"
                ))
            }

            // Botón de compartir nativo
            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .help(loc.text(es: "Compartir archivo", en: "Share file"))

            // Botón para maximizar / restaurar (complementa el doble clic en la barra de título)
            Button {
                onToggleMaximize?()
            } label: {
                Image(systemName: panelState.isMaximized
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .help(loc.text(
                es: panelState.isMaximized
                    ? "Restaurar tamaño (doble clic en la barra de título)"
                    : "Maximizar ventana (doble clic en la barra de título)",
                en: panelState.isMaximized
                    ? "Restore size (double-click title bar)"
                    : "Maximize window (double-click title bar)"
            ))
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background {
            Rectangle()
                .fill(.bar)
            QuickLookTitleBarDragZoomRepresentable(onDoubleClickTitleBar: onToggleMaximize)
        }
    }
}
