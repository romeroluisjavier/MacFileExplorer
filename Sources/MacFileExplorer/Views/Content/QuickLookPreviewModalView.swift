import SwiftUI
import AppKit
import QuickLookUI

/// Contenedor `NSView` que inicializa `QLPreviewView` con un frame inicial no nulo y refresca
/// el elemento tras adjuntarse a la ventana para evitar el bug de hoja en blanco de QuickLookUI en macOS.
@MainActor
public final class QLPreviewContainerNSView: NSView {
    public let previewView: QLPreviewView
    private var pendingURL: URL?
    private var lastReloadToken: Int = 0

    override public init(frame frameRect: NSRect) {
        let initialRect = frameRect.isEmpty ? NSRect(x: 0, y: 0, width: 880, height: 560) : frameRect
        self.previewView = QLPreviewView(frame: initialRect, style: .normal) ?? QLPreviewView(frame: initialRect)
        super.init(frame: initialRect)
        previewView.autostarts = true
        previewView.shouldCloseWithWindow = false
        previewView.autoresizingMask = [.width, .height]
        previewView.frame = bounds
        addSubview(previewView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setPreviewURL(_ url: URL?, reloadToken: Int = 0) {
        let normalized = url?.standardizedFileURL
        let currentURL = previewView.previewItem as? URL
        let tokenChanged = (reloadToken != lastReloadToken)
        if !tokenChanged && currentURL == normalized && pendingURL == normalized {
            return
        }
        lastReloadToken = reloadToken
        pendingURL = normalized
        if tokenChanged {
            previewView.previewItem = nil
        }
        previewView.previewItem = normalized as NSURL?
        if normalized != nil, window != nil {
            previewView.refreshPreviewItem()
        }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let url = pendingURL else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.pendingURL == url else { return }
            self.previewView.previewItem = url as NSURL
            self.previewView.refreshPreviewItem()
        }
    }
}

/// Envoltorio `NSViewRepresentable` sobre `QLPreviewView` nativo de macOS (`QuickLookUI`).
/// Permite previsualizar PDFs, imágenes, vídeos, audio, código fuente, documentos de texto y carpetas.
public struct NativeQLPreviewRepresentable: NSViewRepresentable {
    public let fileURL: URL?
    public let reloadToken: Int

    public init(fileURL: URL?, reloadToken: Int = 0) {
        self.fileURL = fileURL
        self.reloadToken = reloadToken
    }

    public func makeNSView(context: Context) -> QLPreviewContainerNSView {
        let container = QLPreviewContainerNSView(frame: NSRect(x: 0, y: 0, width: 880, height: 560))
        container.setPreviewURL(fileURL, reloadToken: reloadToken)
        return container
    }

    public func updateNSView(_ nsView: QLPreviewContainerNSView, context: Context) {
        nsView.setPreviewURL(fileURL, reloadToken: reloadToken)
    }
}

/// Estado observable del panel flotante de Vista Rápida para reflejar si está maximizado.
@MainActor
@Observable
public final class QuickLookPanelState {
    public var isMaximized: Bool = false

    public init() {}
}

/// Ventana flotante independiente (`NSPanel`) para Quick Look con movimiento libre fuera de la ventana
/// principal y entre monitores, redimensionado en bordes/esquinas y maximizado mediante doble clic.
@MainActor
public final class QuickLookPreviewPanel: NSPanel {
    /// Ventana principal de `MacFileExplorer` que abrió esta Vista Rápida (vínculo lógico sin anclaje `addChildWindow`
    /// para permitir mover libremente la vista previa fuera del explorador o hacia otro monitor sin frenos).
    public weak var ownerHostWindow: NSWindow?
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
        isMovable = true
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
        let defaultWidth: CGFloat = 960
        let defaultHeight: CGFloat = 650

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

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClickTitleBar?()
            return
        }
        // Invocar `performDrag(with:)` directamente en `mouseDown` entrega el arrastre nativo al WindowServer
        // de macOS desde el primer píxel, evitando frenos al sacar la ventana de MacFileExplorer o cruzar monitores.
        window?.performDrag(with: event)
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
        view.onHostWindowChange = { [weak coordinator, weak view] hostWillClose in
            guard let coordinator, let view else { return }
            if hostWillClose {
                coordinator.handleHostWindowWillClose()
            } else {
                coordinator.sync(viewModel: viewModel, in: view)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: QuickLookAnchorNSView, context: Context) {
        _ = viewModel.isQuickLookPresented
        _ = viewModel.quickLookItem?.id
        let coordinator = context.coordinator
        nsView.onHostWindowChange = { [weak coordinator, weak nsView] hostWillClose in
            guard let coordinator, let nsView else { return }
            if hostWillClose {
                coordinator.handleHostWindowWillClose()
            } else {
                coordinator.sync(viewModel: viewModel, in: nsView)
            }
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
        private var pendingSaveFrameWorkItem: DispatchWorkItem?

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
                    flushPendingFrameSave()
                    panel.orderOut(nil)
                }
                return
            }

            let previewPanel = ensurePanel(for: viewModel, hostWindow: hostWindow)

            isApplyingSync = true
            defer { isApplyingSync = false }

            // Mantener únicamente vínculo lógico (sin `addChildWindow`) para movimiento 100% libre fuera de MacFileExplorer y entre monitores
            previewPanel.ownerHostWindow = hostWindow
            if previewPanel.parent != nil {
                previewPanel.parent?.removeChildWindow(previewPanel)
            }

            if !previewPanel.isVisible {
                previewPanel.makeKeyAndOrderFront(nil)
            }
            if panelState.isMaximized != previewPanel.isZoomed {
                panelState.isMaximized = previewPanel.isZoomed
            }
        }

        func handleHostWindowWillClose() {
            hidePanelAndRestoreFocusIfNeeded(restoreHostFocus: false)
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
            newPanel.ownerHostWindow = hostWindow
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

        private func hidePanelAndRestoreFocusIfNeeded(restoreHostFocus: Bool = true) {
            guard let panel else { return }
            flushPendingFrameSave()
            let wasKey = panel.isKeyWindow
            panel.parent?.removeChildWindow(panel)
            if panel.isVisible {
                panel.orderOut(nil)
            }
            if restoreHostFocus && wasKey {
                lastHostWindow?.makeKeyAndOrderFront(nil)
            }
        }

        func teardown() {
            pendingSaveFrameWorkItem?.cancel()
            pendingSaveFrameWorkItem = nil
            guard let panel else { return }
            flushPendingFrameSave()
            panel.delegate = nil
            panel.ownerHostWindow = nil
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
            schedulePersistCurrentFrameIfCustom()
        }

        public func windowDidResize(_ notification: Notification) {
            schedulePersistCurrentFrameIfCustom()
        }

        private func schedulePersistCurrentFrameIfCustom() {
            guard let panel else { return }
            let zoomed = panel.isZoomed
            if panelState.isMaximized != zoomed {
                panelState.isMaximized = zoomed
            }
            guard !isApplyingSync, panel.isVisible, !zoomed else { return }
            pendingSaveFrameWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.flushPendingFrameSave()
                }
            }
            pendingSaveFrameWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        private func flushPendingFrameSave() {
            pendingSaveFrameWorkItem?.cancel()
            pendingSaveFrameWorkItem = nil
            guard let panel, !isApplyingSync, panel.isVisible, !panel.isZoomed else { return }
            PersistenceService.shared.saveQuickLookWindowFrame(panel.frame)
        }
    }
}

@MainActor
public final class QuickLookAnchorNSView: NSView {
    var onHostWindowChange: ((_ hostWillClose: Bool) -> Void)?

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let oldWindow = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: oldWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: oldWindow)
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
                name: NSWindow.didResignKeyNotification,
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
            self?.onHostWindowChange?(false)
        }
    }

    @objc private func handleHostWindowEvent(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification {
            onHostWindowChange?(true)
            return
        }
        onHostWindowChange?(false)
    }
}

/// Contenido de la ventana flotante de Vista Rápida (Quick Look) al presionar la Barra Espaciadora (`Space`),
/// emulando el Quick Look del Finder de macOS con barra de título arrastrable, redimensionable y maximizable.
public struct QuickLookPreviewModalView: View {
    private enum QuickLookMediaSheet: Identifiable {
        case imageConvert(URL)
        case videoConvert(URL)
        case videoTrim(URL)

        var id: String {
            switch self {
            case .imageConvert(let url): return "ql-imageConvert-\(url.absoluteString)"
            case .videoConvert(let url): return "ql-videoConvert-\(url.absoluteString)"
            case .videoTrim(let url): return "ql-videoTrim-\(url.absoluteString)"
            }
        }
    }

    private struct QuickActionFeedbackBanner: Equatable {
        let message: String
        let isError: Bool
    }

    @Bindable var viewModel: ExplorerViewModel
    @Bindable var panelState: QuickLookPanelState
    @Bindable private var googleManager: GoogleAccountsManager = .shared
    @Bindable private var drivePrefs: GoogleDriveUploadPreferences = .shared
    @Bindable private var officePrefs: OfficePreferences = .shared
    var onToggleMaximize: (() -> Void)?

    @ViewState private var activeQuickActionSheet: QuickLookMediaSheet? = nil
    @ViewState private var mediaPreviewReloadToken: Int = 0
    @ViewState private var isRunningQuickAction: Bool = false
    @ViewState private var quickActionStatusText: String = ""
    @ViewState private var quickActionFeedback: QuickActionFeedbackBanner? = nil
    @ViewState private var showCopiedBadge: Bool = false
    @ViewState private var copyFeedbackResetTask: Task<Void, Never>? = nil
    @ViewState private var actionFeedbackResetTask: Task<Void, Never>? = nil

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
        let isImage = activeURL.map { !(activeItem?.isNavigableFolder ?? true) && QuickActionsService.isImageURL($0) } ?? false
        let isVideo = activeURL.map { !(activeItem?.isNavigableFolder ?? true) && QuickActionsService.isVideoURL($0) } ?? false
        let shouldSuspendBackgroundVideo = isVideo && activeQuickActionSheet != nil

        VStack(spacing: 0) {
            if let item = activeItem {
                quickLookHeaderBar(for: item)
                Divider()

                if isImage || isVideo {
                    mediaQuickActionsBar(for: item, isImage: isImage, isVideo: isVideo)
                    Divider()
                }

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
                    } else if let activeURL,
                              let officeKind = OfficePreviewSupport.documentKind(for: activeURL),
                              officePrefs.isPreviewEnabled(for: officeKind) {
                        switch officeKind {
                        case .csv:
                            CSVSpreadsheetPreviewView(fileURL: activeURL)
                                .id(item.id)
                        case .word:
                            OfficeWordPreviewView(fileURL: activeURL)
                                .id(item.id)
                        case .excel:
                            OfficeExcelPreviewView(fileURL: activeURL)
                                .id(item.id)
                        case .powerpoint:
                            OfficePowerPointPreviewView(fileURL: activeURL)
                                .id(item.id)
                        }
                    } else if let activeURL, RichCodePreviewSupport.supportsRichPreview(for: activeURL) {
                        RichCodePreviewView(fileURL: activeURL)
                            .id(item.id)
                    } else if let activeURL, QuickActionsService.isPDFURL(activeURL) {
                        PDFPreviewView(fileURL: activeURL)
                            .id(item.id)
                    } else {
                        Color(nsColor: .underPageBackgroundColor)
                        NativeQLPreviewRepresentable(
                            fileURL: shouldSuspendBackgroundVideo ? nil : activeURL,
                            reloadToken: mediaPreviewReloadToken
                        )
                        .id("\(item.id.absoluteString)::\(mediaPreviewReloadToken)")
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
        .sheet(item: $activeQuickActionSheet) { sheet in
            switch sheet {
            case .imageConvert(let url):
                QuickActionImageConvertModalView(viewModel: viewModel, targetURLs: [url])
            case .videoConvert(let url):
                QuickActionVideoConvertModalView(viewModel: viewModel, targetURLs: [url])
            case .videoTrim(let url):
                QuickActionVideoTrimModalView(viewModel: viewModel, targetURL: url)
            }
        }
        .onChange(of: viewModel.quickLookCopyFeedbackToken) { _, _ in
            triggerCopyFeedback()
        }
        .onChange(of: activeItem?.id) { _, _ in
            activeQuickActionSheet = nil
            showCopiedBadge = false
            copyFeedbackResetTask?.cancel()
        }
        .onChange(of: viewModel.isQuickLookPresented) { _, presented in
            if !presented {
                activeQuickActionSheet = nil
                showCopiedBadge = false
                quickActionFeedback = nil
                copyFeedbackResetTask?.cancel()
                actionFeedbackResetTask?.cancel()
            }
        }
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

            HStack(spacing: 4) {
                PreviewToolbarIconButton(
                    "chevron.left",
                    help: loc.text(es: "Elemento anterior (↑ / ←)", en: "Previous item (↑ / ←)"),
                    disabled: !viewModel.canSelectPreviousItem
                ) {
                    viewModel.selectAdjacentItem(offset: -1)
                }

                PreviewToolbarIconButton(
                    "chevron.right",
                    help: loc.text(es: "Elemento siguiente (↓ / →)", en: "Next item (↓ / →)"),
                    disabled: !viewModel.canSelectNextItem
                ) {
                    viewModel.selectAdjacentItem(offset: 1)
                }
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
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                        Text(loc.text(es: "Abrir carpeta", en: "Open Folder"))
                            .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                }
                .buttonStyle(PreviewToolbarButtonStyle(variant: .prominent))
                .fixedSize()
                .help(loc.text(
                    es: "Entrar en esta carpeta",
                    en: "Open this folder"
                ))
            } else {
                if officePrefs.isSendToDriveEnabled {
                    sendToDriveHeaderControl(for: item)
                }

                Button {
                    viewModel.openInNativePreviewApp(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                        Text(loc.text(es: "Abrir en Vista Previa", en: "Open in Preview"))
                            .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                }
                .buttonStyle(PreviewToolbarButtonStyle(variant: .prominent))
                .fixedSize()
                .help(loc.text(
                    es: "Abrir este archivo en la aplicación nativa 'Preview' (Vista Previa) de macOS",
                    en: "Open this file in macOS native 'Preview' application"
                ))
            }

            // Botón de compartir nativo (misma altura e icono 13 pt que el resto de la barra)
            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                    .frame(width: PreviewToolbarMetrics.iconButtonWidth, height: PreviewToolbarMetrics.controlHeight)
            }
            .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
            .fixedSize()
            .help(loc.text(es: "Compartir archivo", en: "Share file"))

            // Botón para maximizar / restaurar (complementa el doble clic en la barra de título)
            PreviewToolbarIconButton(
                panelState.isMaximized
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                help: loc.text(
                    es: panelState.isMaximized
                        ? "Restaurar tamaño (doble clic en la barra de título)"
                        : "Maximizar ventana (doble clic en la barra de título)",
                    en: panelState.isMaximized
                        ? "Restore size (double-click title bar)"
                        : "Maximize window (double-click title bar)"
                )
            ) {
                onToggleMaximize?()
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background {
            Rectangle()
                .fill(.bar)
            QuickLookTitleBarDragZoomRepresentable(onDoubleClickTitleBar: onToggleMaximize)
        }
    }

    /// Control dividido «Enviar a Drive» en la barra superior de Quick Look:
    /// clic directo sube a la carpeta configurada y abre en Google Sheets / Docs / Slides; el menú permite elegir cuenta, Chrome externo o carpeta.
    private func sendToDriveHeaderControl(for item: FileItem) -> some View {
        let loc = LocalizationManager.shared
        let target = OfficePreviewSupport.googleEditorTarget(for: item.url)
        let targetName = target.localizedName(using: loc)
        let preferredAccount = GoogleDriveUploadService.shared.resolvePreferredAccount()
        let folderName = preferredAccount.map { drivePrefs.displayFolderName(for: $0.id, using: loc) }
            ?? loc.text(es: "Mi unidad", en: "My Drive")
        let shortTarget: String = {
            switch target {
            case .sheets: return "Sheets"
            case .docs: return "Docs"
            case .slides: return "Slides"
            case .driveViewer: return "Drive"
            }
        }()

        return HStack(spacing: 0) {
            // Acción directa: subir a la carpeta configurada y abrir en Google Sheets / Docs / Slides
            Button {
                let targetURL = item.url
                viewModel.closeQuickLook()
                GoogleDriveUploadService.shared.sendFileToDriveAndOpen(targetURL)
            } label: {
                HStack(spacing: 6) {
                    GoogleServiceIconView(service: .drive, size: PreviewToolbarMetrics.iconSize + 1)
                    Text(
                        target == .driveViewer
                            ? loc.text(es: "Enviar a Drive", en: "Send to Drive")
                            : loc.text(es: "Drive · \(shortTarget)", en: "Drive · \(shortTarget)")
                    )
                    .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                }
                .padding(.leading, 9)
                .padding(.trailing, 7)
                .frame(height: PreviewToolbarMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 0.8, height: 15)

            // Menú desplegable de opciones (cuenta, Chrome externo, carpeta destino)
            Menu {
                if let preferredAccount {
                    Button {
                        let targetURL = item.url
                        viewModel.closeQuickLook()
                        GoogleDriveUploadService.shared.sendFileToDriveAndOpen(targetURL, account: preferredAccount)
                    } label: {
                        Label(
                            loc.text(
                                es: "Enviar a «\(folderName)» y abrir en \(targetName)",
                                en: "Send to \"\(folderName)\" & open in \(targetName)"
                            ),
                            systemImage: target.symbolName
                        )
                    }

                    if googleManager.accounts.count > 1 {
                        Divider()
                        Section(loc.text(es: "Elegir cuenta de Google", en: "Choose Google Account")) {
                            ForEach(googleManager.accounts) { account in
                                let acctFolder = drivePrefs.displayFolderName(for: account.id, using: loc)
                                Button {
                                    let targetURL = item.url
                                    viewModel.closeQuickLook()
                                    GoogleDriveUploadService.shared.sendFileToDriveAndOpen(targetURL, account: account)
                                } label: {
                                    Label("\(account.displayLabel) · \(acctFolder)", systemImage: "person.crop.circle")
                                }
                            }
                        }
                    }
                } else {
                    Button {
                        viewModel.closeQuickLook()
                        GoogleAccountsManager.shared.startAddGoogleAccount()
                    } label: {
                        Label(
                            loc.text(es: "Iniciar sesión en cuenta de Google…", en: "Sign in to Google Account…"),
                            systemImage: "person.badge.plus"
                        )
                    }
                }

                Divider()

                Button {
                    drivePrefs.openInExternalChrome.toggle()
                } label: {
                    Label(
                        drivePrefs.openInExternalChrome
                            ? loc.text(es: "✓ Abrir en Google Chrome externo", en: "✓ Open in external Google Chrome")
                            : loc.text(es: "Abrir en Google Chrome externo", en: "Open in external Google Chrome"),
                        systemImage: "safari"
                    )
                }

                Button {
                    GoogleDriveSettingsWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Configurar carpeta de Drive…", en: "Configure Drive Folder…"),
                        systemImage: "folder.badge.gearshape"
                    )
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: PreviewToolbarMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: PreviewToolbarMetrics.controlHeight)
        }
        .frame(height: PreviewToolbarMetrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
        )
        .fixedSize()
        .help(loc.text(
            es: "Copia automáticamente este archivo a tu carpeta de Google Drive (\(folderName)) y lo abre en \(targetName)",
            en: "Automatically uploads this file to your Google Drive folder (\(folderName)) and opens it in \(targetName)"
        ))
    }

    // MARK: - Barra de Acciones Rápidas (Quick Actions) y Copiar para Imágenes y Videos

    private func mediaQuickActionsBar(for item: FileItem, isImage: Bool, isVideo: Bool) -> some View {
        let loc = LocalizationManager.shared
        let supportsPrivacy = QuickActionsService.supportsPrivacyStripper(item.url)

        return HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // 1. Botón Copiar (con selector de modo en imágenes: imagen+archivo, solo imagen o solo archivo)
                    if isImage {
                        imageCopySplitControl(for: item)
                    } else {
                        Button {
                            viewModel.copyQuickLookMedia(item.url, isImage: false, mode: .fileOnly)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: showCopiedBadge ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                                Text(
                                    showCopiedBadge
                                        ? loc.text(es: "Copiado", en: "Copied")
                                        : loc.text(es: "Copiar", en: "Copy")
                                )
                                .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                            }
                            .padding(.horizontal, 9)
                        }
                        .buttonStyle(PreviewToolbarButtonStyle(variant: showCopiedBadge ? .active : .standard))
                        .fixedSize()
                        .help(loc.text(
                            es: "Copiar archivo de video al portapapeles (⌘C)",
                            en: "Copy video file to clipboard (⌘C)"
                        ))
                    }

                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)

                    // 2. Acciones rápidas para IMÁGENES (idénticas al menú contextual -> Acciones rápidas)
                    if isImage {
                        mediaToolbarButton(
                            icon: "person.and.background.dotted",
                            title: loc.text(es: "Eliminar fondo", en: "Remove Background"),
                            help: loc.text(
                                es: "Eliminar fondo y guardar un PNG transparente nuevo",
                                en: "Remove background and save a new transparent PNG"
                            ),
                            disabled: isRunningQuickAction
                        ) {
                            let targetURL = item.url
                            runMediaQuickAction(
                                statusText: loc.text(es: "Eliminando fondo…", en: "Removing background…"),
                                successText: loc.text(es: "PNG transparente guardado", en: "Transparent PNG saved")
                            ) {
                                await viewModel.removeBackgroundFromImages([targetURL])
                            }
                        }

                        mediaToolbarButton(
                            icon: "photo.badge.arrow.down",
                            title: loc.text(es: "Convertir…", en: "Convert…"),
                            help: loc.text(
                                es: "Convertir a JPG / PNG con calidad, resolución (DPI) y peso máximo",
                                en: "Convert to JPG / PNG with quality, DPI, and max file size"
                            ),
                            disabled: isRunningQuickAction
                        ) {
                            activeQuickActionSheet = .imageConvert(item.url)
                        }

                        HStack(spacing: 4) {
                            PreviewToolbarIconButton(
                                "rotate.left",
                                help: loc.text(es: "Rotar 90° a la izquierda", en: "Rotate 90° Left"),
                                disabled: isRunningQuickAction
                            ) {
                                rotateCurrentImage(item.url, rotation: .left90)
                            }

                            PreviewToolbarIconButton(
                                "rotate.right",
                                help: loc.text(es: "Rotar 90° a la derecha", en: "Rotate 90° Right"),
                                disabled: isRunningQuickAction
                            ) {
                                rotateCurrentImage(item.url, rotation: .right90)
                            }

                            PreviewToolbarIconButton(
                                "arrow.triangle.2.circlepath",
                                help: loc.text(es: "Rotar 180°", en: "Rotate 180°"),
                                disabled: isRunningQuickAction
                            ) {
                                rotateCurrentImage(item.url, rotation: .rotate180)
                            }
                        }
                    }

                    // 3. Acciones rápidas para VIDEOS (idénticas al menú contextual -> Acciones rápidas)
                    if isVideo {
                        mediaToolbarButton(
                            icon: "film.stack",
                            title: loc.text(es: "Convertir a MP4…", en: "Convert to MP4…"),
                            help: loc.text(
                                es: "Convertir video a MP4 eligiendo calidad y peso máximo",
                                en: "Convert video to MP4 with custom quality and max file size"
                            ),
                            disabled: isRunningQuickAction
                        ) {
                            activeQuickActionSheet = .videoConvert(item.url)
                        }

                        mediaToolbarButton(
                            icon: "scissors",
                            title: loc.text(es: "Recortar (Trim)…", en: "Trim…"),
                            help: loc.text(
                                es: "Recortar inicio y fin del video con vista previa y Fade In/Out",
                                en: "Trim video start and end with live preview and Fade In/Out"
                            ),
                            disabled: isRunningQuickAction
                        ) {
                            activeQuickActionSheet = .videoTrim(item.url)
                        }

                        mediaToolbarButton(
                            icon: "speaker.slash",
                            title: loc.text(es: "Silenciar", en: "Mute"),
                            help: loc.text(
                                es: "Eliminar pista de audio y guardar copia silenciosa",
                                en: "Remove audio track and save a muted copy"
                            ),
                            disabled: isRunningQuickAction
                        ) {
                            let targetURL = item.url
                            runMediaQuickAction(
                                statusText: loc.text(es: "Eliminando audio…", en: "Removing audio…"),
                                successText: loc.text(es: "Video sin audio guardado", en: "Muted video saved")
                            ) {
                                let muted = try await QuickActionsService.removeAudioFromVideos([targetURL])
                                await viewModel.reloadDirectoryAndSelect(muted, startRenameOn: nil)
                            }
                        }
                    }

                    // 4. Privacy Stripper (imágenes y videos)
                    if supportsPrivacy {
                        mediaToolbarButton(
                            icon: "shield.lefthalf.filled",
                            title: loc.text(es: "Limpiar metadatos", en: "Strip Metadata"),
                            help: loc.text(
                                es: "Limpiar metadatos privados (GPS, cámara, autor) en una copia nueva",
                                en: "Strip private metadata (GPS, camera, author) into a clean copy"
                            ),
                            disabled: isRunningQuickAction
                        ) {
                            let targetURL = item.url
                            runMediaQuickAction(
                                statusText: loc.text(es: "Limpiando metadatos…", en: "Stripping metadata…"),
                                successText: loc.text(es: "Metadatos limpiados", en: "Metadata stripped")
                            ) {
                                await viewModel.stripMetadataFromItems([targetURL])
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // Indicador de progreso / confirmación en vivo dentro del propio panel de Quick Look
            if isRunningQuickAction {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(quickActionStatusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize()
            } else if let feedback = quickActionFeedback {
                HStack(spacing: 5) {
                    Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(feedback.isError ? Color.red : Color.green)
                    Text(feedback.message)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(feedback.isError ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((feedback.isError ? Color.red : Color.green).opacity(0.11))
                )
                .fixedSize()
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }

    private func imageCopySplitControl(for item: FileItem) -> some View {
        let loc = LocalizationManager.shared
        let fill: Color = showCopiedBadge ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.085)
        let stroke: Color = showCopiedBadge ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.11)
        let fg: Color = showCopiedBadge ? .accentColor : .primary

        return HStack(spacing: 0) {
            Button {
                viewModel.copyQuickLookMedia(item.url, isImage: true, mode: .imageAndFile)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showCopiedBadge ? "checkmark" : "doc.on.doc")
                        .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                    Text(
                        showCopiedBadge
                            ? loc.text(es: "Copiado", en: "Copied")
                            : loc.text(es: "Copiar", en: "Copy")
                    )
                    .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                }
                .foregroundStyle(fg)
                .padding(.leading, 9)
                .padding(.trailing, 7)
                .frame(height: PreviewToolbarMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(showCopiedBadge ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.14))
                .frame(width: 0.8, height: 15)

            Menu {
                Button {
                    viewModel.copyQuickLookMedia(item.url, isImage: true, mode: .imageAndFile)
                } label: {
                    Label(
                        loc.text(
                            es: "Copiar imagen y archivo (Recomendado)",
                            en: "Copy Image & File (Recommended)"
                        ),
                        systemImage: "doc.on.doc"
                    )
                }

                Button {
                    viewModel.copyQuickLookMedia(item.url, isImage: true, mode: .imageOnly)
                } label: {
                    Label(
                        loc.text(
                            es: "Copiar solo imagen (chats, Docs, Preview)",
                            en: "Copy Image Only (chats, Docs, Preview)"
                        ),
                        systemImage: "photo"
                    )
                }

                Button {
                    viewModel.copyQuickLookMedia(item.url, isImage: true, mode: .fileOnly)
                } label: {
                    Label(
                        loc.text(
                            es: "Copiar solo archivo (carpetas / Finder)",
                            en: "Copy File Only (folders / Finder)"
                        ),
                        systemImage: "doc"
                    )
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(showCopiedBadge ? Color.accentColor : .secondary)
                    .frame(width: 22, height: PreviewToolbarMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: PreviewToolbarMetrics.controlHeight)
        }
        .frame(height: PreviewToolbarMetrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                .strokeBorder(stroke, lineWidth: 0.75)
        )
        .fixedSize()
        .help(loc.text(
            es: "Copiar imagen y archivo al portapapeles (⌘C). Usá la flecha para copiar solo imagen o solo archivo.",
            en: "Copy image & file to clipboard (⌘C). Use the arrow to copy image only or file only."
        ))
    }

    private func mediaToolbarButton(
        icon: String,
        title: String,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                Text(title)
                    .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
            }
            .padding(.horizontal, 9)
        }
        .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .fixedSize()
        .help(help)
    }

    private func rotateCurrentImage(_ url: URL, rotation: QuickActionImageRotation) {
        let loc = LocalizationManager.shared
        let successLabel: String = {
            switch rotation {
            case .left90: return loc.text(es: "Rotada 90° izq.", en: "Rotated 90° Left")
            case .right90: return loc.text(es: "Rotada 90° der.", en: "Rotated 90° Right")
            case .rotate180: return loc.text(es: "Rotada 180°", en: "Rotated 180°")
            }
        }()

        runMediaQuickAction(
            statusText: loc.text(es: "Rotando imagen…", en: "Rotating image…"),
            successText: successLabel
        ) {
            let rotated = try await QuickActionsService.rotateImages([url], rotation: rotation)
            await viewModel.reloadDirectoryAndSelect(rotated, startRenameOn: nil)
            mediaPreviewReloadToken &+= 1
        }
    }

    private func runMediaQuickAction(
        statusText: String,
        successText: String,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        guard !isRunningQuickAction else { return }
        actionFeedbackResetTask?.cancel()
        quickActionFeedback = nil
        quickActionStatusText = statusText
        isRunningQuickAction = true

        Task { @MainActor in
            defer {
                isRunningQuickAction = false
                quickActionStatusText = ""
            }
            let previousError = viewModel.errorMessage
            do {
                try await operation()
                if let newError = viewModel.errorMessage,
                   !newError.isEmpty,
                   newError != previousError {
                    showTransientActionFeedback(message: newError, isError: true)
                } else {
                    showTransientActionFeedback(message: successText, isError: false)
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
                showTransientActionFeedback(message: error.localizedDescription, isError: true)
            }
        }
    }

    private func triggerCopyFeedback() {
        copyFeedbackResetTask?.cancel()
        showCopiedBadge = true
        let loc = LocalizationManager.shared
        let msg: String = {
            switch viewModel.quickLookLastCopyMode {
            case .imageAndFile:
                return loc.text(es: "Imagen y archivo copiados", en: "Image & file copied")
            case .imageOnly:
                return loc.text(es: "Imagen copiada", en: "Image copied")
            case .fileOnly:
                return loc.text(es: "Archivo copiado", en: "File copied")
            }
        }()
        showTransientActionFeedback(message: msg, isError: false)
        copyFeedbackResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled {
                showCopiedBadge = false
            }
        }
    }

    private func showTransientActionFeedback(message: String, isError: Bool) {
        actionFeedbackResetTask?.cancel()
        quickActionFeedback = QuickActionFeedbackBanner(message: message, isError: isError)
        actionFeedbackResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(isError ? 4.0 : 2.2))
            if !Task.isCancelled {
                quickActionFeedback = nil
            }
        }
    }
}
