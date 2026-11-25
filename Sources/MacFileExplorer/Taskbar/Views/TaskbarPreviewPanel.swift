import AppKit
import CoreGraphics
import Foundation
import Observation
import QuartzCore
import SwiftUI

// MARK: - Geometría Fija Determinista de la Tarjeta de Vista Previa (Cero Cambios de Tamaño)

/// Calcula de antemano las dimensiones exactas del recuadro de miniatura y de la tarjeta
/// a partir del `frameAX` real de la ventana para que el popover jamás salte ni cambie de tamaño al cargarse la imagen.
public struct TaskbarPreviewLayout: Equatable, Sendable {
    public let imageWidth: CGFloat
    public let imageHeight: CGFloat
    public let headerHeight: CGFloat
    public let cardWidth: CGFloat
    public let cardHeight: CGFloat

    public static let placeholder = TaskbarPreviewLayout(
        imageWidth: 210,
        imageHeight: 132,
        headerHeight: 32,
        cardWidth: 226,
        cardHeight: 172
    )

    public static func compute(
        windowFrame: CGRect,
        maxDimension: CGFloat,
        hasPermission: Bool,
        showTitle: Bool
    ) -> TaskbarPreviewLayout {
        let headerHeight: CGFloat = showTitle ? 32 : 24
        let horizontalPadding: CGFloat = 16 // 8 pt izquierda + 8 pt derecha
        let bottomPadding: CGFloat = 8

        guard hasPermission else {
            return TaskbarPreviewLayout(
                imageWidth: 0,
                imageHeight: 0,
                headerHeight: headerHeight,
                cardWidth: 256,
                cardHeight: 118
            )
        }

        let rawAspect: CGFloat
        if windowFrame.width >= 60 && windowFrame.height >= 60 {
            rawAspect = windowFrame.width / windowFrame.height
        } else {
            rawAspect = 16.0 / 10.0
        }
        // Acotar proporciones extremas para mantener una tarjeta equilibrada en cualquier monitor/ventana
        let aspect = min(max(rawAspect, 0.72), 2.15)

        let maxImgW = max(180, maxDimension)
        let maxImgH = max(112, round(maxDimension * 0.72))

        var imgW: CGFloat
        var imgH: CGFloat
        if aspect >= 1.0 {
            imgW = maxImgW
            imgH = imgW / aspect
            if imgH > maxImgH {
                imgH = maxImgH
                imgW = imgH * aspect
            }
        } else {
            imgH = maxImgH
            imgW = imgH * aspect
            if imgW > maxImgW {
                imgW = maxImgW
                imgH = imgW / aspect
            }
        }

        imgW = round(max(150, imgW))
        imgH = round(max(92, imgH))

        let cardW = round(max(196, imgW + horizontalPadding))
        let cardH = round(headerHeight + imgH + bottomPadding)

        return TaskbarPreviewLayout(
            imageWidth: imgW,
            imageHeight: imgH,
            headerHeight: headerHeight,
            cardWidth: cardW,
            cardHeight: cardH
        )
    }
}

// MARK: - Panel Flotante de Vista Previa al Pasar el Cursor

@MainActor
private final class TaskbarPreviewNSPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
public final class TaskbarPreviewPanelController {

    public static let shared = TaskbarPreviewPanelController()

    /// Márgenes transparentes del panel flotante para que las sombras suaves, el rebote elástico
    /// y la inclinación 3D nunca se recorten, manteniendo el borde inferior apoyado exacto sobre la barra.
    public static let panelHorizontalInset: CGFloat = 20
    public static let panelTopInset: CGFloat = 22
    public static let cardBottomGap: CGFloat = 8

    public private(set) var currentItem: TaskbarWindowItem?
    public private(set) var currentLayout: TaskbarPreviewLayout = .placeholder
    public private(set) var previewImage: NSImage?
    public private(set) var previousPreviewImage: NSImage?
    public private(set) var imageTransitionToken: UInt64 = 0
    public private(set) var isCrossfadeUpdate: Bool = false
    public private(set) var isLoadingThumbnail: Bool = false
    public private(set) var isPresented: Bool = false
    public private(set) var activeAnimationStyle: TaskbarHoverPreviewAnimation = .fadeLift

    private var panel: TaskbarPreviewNSPanel?
    private var showDelayWorkItem: DispatchWorkItem?
    private var hideDelayWorkItem: DispatchWorkItem?
    private var hideCompletionWorkItem: DispatchWorkItem?
    private var prefetchTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var isPointerInsidePreviewCard = false
    private var isHidingWithAnimation = false
    private var presentationGeneration: UInt64 = 0
    private var activeHoverItemID: String?
    private var currentButtonRect: NSRect = .zero
    private var currentDisplayID: String = ""

    private init() {}

    public var panelWindowNumber: Int? {
        panel?.windowNumber
    }

    public func handleButtonHoverEntered(
        item: TaskbarWindowItem,
        buttonScreenRect: NSRect,
        displayID: String
    ) {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled, prefs.showHoverPreviews else { return }
        guard TaskbarManager.shared.draggingWindowID == nil else { return }
        if item.isWindowlessApp {
            hideImmediately()
            return
        }

        hideDelayWorkItem?.cancel()
        hideDelayWorkItem = nil
        hideCompletionWorkItem?.cancel()
        hideCompletionWorkItem = nil
        isHidingWithAnimation = false

        activeHoverItemID = item.id
        currentButtonRect = buttonScreenRect
        currentDisplayID = displayID

        // Pre-captura inmediata en t = 0 ms durante el retardo de hover: cuando el popover aparece,
        // la miniatura fresca suele estar ya lista en RAM sin espera ni cambio brusco.
        let thumbService = TaskbarThumbnailService.shared
        let maxDim = prefs.thumbnailSize.maxDimension
        if item.windowID != 0,
           thumbService.hasScreenRecordingPermission,
           !thumbService.hasFreshThumbnail(for: item.windowID, maxAge: 1.8, minDimension: maxDim) {
            prefetchTask?.cancel()
            let winID = item.windowID
            let isMin = item.isMinimized
            prefetchTask = Task {
                _ = await TaskbarThumbnailService.shared.captureThumbnail(
                    for: winID,
                    maxDimension: maxDim,
                    isMinimized: isMin,
                    maxCacheAge: 1.8
                )
            }
        }

        // Si el panel ya está visible para otro botón, deslizar casi instantáneamente sin repetir el delay largo
        let alreadyVisible = (panel?.isVisible == true) && isPresented
        let delay: TimeInterval = alreadyVisible ? 0.05 : prefs.hoverPreviewDelay

        showDelayWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.activeHoverItemID == item.id else { return }
                self.presentPreview(for: item, anchoredTo: buttonScreenRect, displayID: displayID)
            }
        }
        showDelayWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func handleButtonHoverExited(itemID: String) {
        if activeHoverItemID == itemID {
            activeHoverItemID = nil
        }
        showDelayWorkItem?.cancel()
        showDelayWorkItem = nil
        scheduleHideIfPointerOutside()
    }

    public func handlePreviewCardHoverChanged(isInside: Bool) {
        isPointerInsidePreviewCard = isInside
        if isInside {
            hideDelayWorkItem?.cancel()
            hideDelayWorkItem = nil
            hideCompletionWorkItem?.cancel()
            hideCompletionWorkItem = nil
            if isHidingWithAnimation || !isPresented {
                isHidingWithAnimation = false
                withAnimation(activeAnimationStyle.entranceAnimation) {
                    isPresented = true
                }
            }
        } else {
            scheduleHideIfPointerOutside()
        }
    }

    public func hideImmediately() {
        presentationGeneration &+= 1
        showDelayWorkItem?.cancel()
        showDelayWorkItem = nil
        hideDelayWorkItem?.cancel()
        hideDelayWorkItem = nil
        hideCompletionWorkItem?.cancel()
        hideCompletionWorkItem = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        captureTask?.cancel()
        captureTask = nil
        activeHoverItemID = nil
        isPointerInsidePreviewCard = false
        isHidingWithAnimation = false

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = false
        }

        panel?.orderOut(nil)
        panel?.alphaValue = 1.0
        currentItem = nil
        previewImage = nil
        previousPreviewImage = nil
    }

    private func hideWithSmoothAnimation() {
        guard let targetPanel = panel, targetPanel.isVisible else {
            hideImmediately()
            return
        }
        isHidingWithAnimation = true
        presentationGeneration &+= 1
        let style = activeAnimationStyle

        withAnimation(style.exitAnimation) {
            isPresented = false
        }

        hideCompletionWorkItem?.cancel()
        let completion = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isHidingWithAnimation,
                      !self.isPointerInsidePreviewCard,
                      self.activeHoverItemID == nil else {
                    return
                }
                self.hideImmediately()
            }
        }
        hideCompletionWorkItem = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + style.exitDuration, execute: completion)
    }

    private func scheduleHideIfPointerOutside() {
        hideDelayWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isPointerInsidePreviewCard && self.activeHoverItemID == nil {
                    self.hideWithSmoothAnimation()
                }
            }
        }
        hideDelayWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func presentPreview(for item: TaskbarWindowItem, anchoredTo buttonRect: NSRect, displayID: String) {
        let prefs = TaskbarPreferences.shared
        let thumbService = TaskbarThumbnailService.shared
        let hasPermission = thumbService.refreshPermissionStatus()
        let maxDim = prefs.thumbnailSize.maxDimension
        let animationStyle = prefs.hoverPreviewAnimation

        // Calcular el layout definitivo ANTES de mostrar: el panel NO cambiará de tamaño cuando llegue la captura.
        let layout = TaskbarPreviewLayout.compute(
            windowFrame: item.frameAX,
            maxDimension: maxDim,
            hasPermission: hasPermission,
            showTitle: prefs.showTitleInThumbnail
        )

        let switchingItem = (currentItem?.id != item.id)
        let cached = thumbService.cachedThumbnail(for: item.windowID)

        activeAnimationStyle = animationStyle
        currentItem = item
        currentLayout = layout
        if switchingItem {
            previousPreviewImage = nil
            previewImage = cached
            isCrossfadeUpdate = false
            imageTransitionToken &+= 1
        } else if let cached, cached !== previewImage {
            previousPreviewImage = previewImage
            previewImage = cached
            isCrossfadeUpdate = true
            imageTransitionToken &+= 1
        }
        isLoadingThumbnail = hasPermission && (previewImage == nil)

        let targetPanel = ensurePanel()
        applyAppearance(prefs.themeMode, to: targetPanel)

        let targetFrame = computePanelFrame(
            layout: layout,
            above: buttonRect,
            displayID: displayID
        )

        let wasVisible = targetPanel.isVisible && isPresented && !isHidingWithAnimation
        let wasRetracting = targetPanel.isVisible && isHidingWithAnimation
        hideCompletionWorkItem?.cancel()
        hideCompletionWorkItem = nil
        isHidingWithAnimation = false

        if wasVisible {
            // Deslizamiento suave hacia el nuevo botón de la barra manteniendo fluidez total
            targetPanel.alphaValue = 1.0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                targetPanel.animator().setFrame(targetFrame, display: true)
            }
            isPresented = true
        } else if wasRetracting {
            // Retomando suavemente una vista previa que recién comenzaba a ocultarse
            targetPanel.alphaValue = 1.0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                targetPanel.animator().setFrame(targetFrame, display: true)
            }
            withAnimation(animationStyle.entranceAnimation) {
                isPresented = true
            }
        } else {
            // Confirmar primero el estado inicial oculto en el frame 0 y luego disparar la animación seleccionada
            var resetTransaction = Transaction()
            resetTransaction.disablesAnimations = true
            withTransaction(resetTransaction) {
                isPresented = false
            }

            targetPanel.alphaValue = 1.0
            targetPanel.setFrame(targetFrame, display: true)
            targetPanel.contentView?.layoutSubtreeIfNeeded()
            targetPanel.orderFrontRegardless()

            presentationGeneration &+= 1
            let generation = presentationGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.presentationGeneration == generation,
                      !self.isHidingWithAnimation else {
                    return
                }
                withAnimation(animationStyle.entranceAnimation) {
                    self.isPresented = true
                }
            }
        }

        // Si ya tenemos una captura reciente (< 1.8 s), no hace falta volver a capturar
        if hasPermission && item.windowID != 0 {
            if thumbService.hasFreshThumbnail(for: item.windowID, maxAge: 1.8, minDimension: maxDim), previewImage != nil {
                isLoadingThumbnail = false
                return
            }

            captureTask?.cancel()
            let targetWindowID = item.windowID
            let isMinimized = item.isMinimized
            captureTask = Task { [weak self] in
                let captured = await TaskbarThumbnailService.shared.captureThumbnail(
                    for: targetWindowID,
                    maxDimension: maxDim,
                    isMinimized: isMinimized,
                    maxCacheAge: 1.8
                )
                guard !Task.isCancelled, let self, self.currentItem?.id == item.id else { return }
                self.isLoadingThumbnail = false
                // Actualizar la imagen con crossfade suave DENTRO del mismo tamaño fijo (cero setFrame / cero salto)
                if let captured, captured !== self.previewImage {
                    self.previousPreviewImage = self.previewImage
                    self.previewImage = captured
                    self.isCrossfadeUpdate = true
                    self.imageTransitionToken &+= 1
                }
            }
        }
    }

    private func computePanelFrame(layout: TaskbarPreviewLayout, above buttonRect: NSRect, displayID: String) -> NSRect {
        let screenFrame = TaskbarWindowTracker.shared.connectedScreens
            .first(where: { $0.id == displayID })?.frameCocoa
            ?? NSScreen.screens.first(where: { $0.frame.contains(buttonRect.origin) })?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let horizontalInset = Self.panelHorizontalInset
        let topInset = Self.panelTopInset
        let bottomGap = Self.cardBottomGap

        let screenMargin: CGFloat = 8
        var cardOriginX = buttonRect.midX - (layout.cardWidth / 2)
        cardOriginX = min(
            max(cardOriginX, screenFrame.minX + screenMargin),
            screenFrame.maxX - layout.cardWidth - screenMargin
        )

        // Apoyar el borde inferior del panel exactamente sobre el borde superior de la barra de tareas
        // para que la animación "Desde la barra" emerja y se retraiga directamente desde su borde.
        let barTopY = TaskbarManager.shared.barFrame(for: displayID)?.maxY
            ?? max(buttonRect.maxY, screenFrame.minY + CGFloat(TaskbarPreferences.shared.barHeight))

        let panelWidth = layout.cardWidth + (horizontalInset * 2)
        let panelHeight = layout.cardHeight + topInset + bottomGap
        let panelOriginX = cardOriginX - horizontalInset

        return NSRect(
            x: round(panelOriginX),
            y: round(barTopY),
            width: round(panelWidth),
            height: round(panelHeight)
        )
    }

    private func ensurePanel() -> TaskbarPreviewNSPanel {
        if let existing = panel {
            return existing
        }
        let initialWidth = TaskbarPreviewLayout.placeholder.cardWidth + (Self.panelHorizontalInset * 2)
        let initialHeight = TaskbarPreviewLayout.placeholder.cardHeight + Self.panelTopInset + Self.cardBottomGap
        let created = TaskbarPreviewNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        // La sombra se dibuja directamente en SwiftUI sobre la tarjeta para acompañar
        // limpiamente el recorte desde la barra, el rebote elástico y la inclinación 3D.
        created.hasShadow = false
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.level = .popUpMenu
        created.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        created.contentView = NSHostingView(rootView: TaskbarPreviewCardView())
        panel = created
        return created
    }

    private func applyAppearance(_ themeMode: TaskbarThemeMode, to panel: NSPanel) {
        switch themeMode {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Curvas de Animación de Entrada y Salida

private extension TaskbarHoverPreviewAnimation {
    var entranceAnimation: Animation {
        switch self {
        case .fadeLift:
            return .easeOut(duration: 0.16)
        case .riseFromBar:
            return .spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.08)
        case .springPop:
            return .spring(response: 0.30, dampingFraction: 0.64, blendDuration: 0.08)
        case .flipReveal:
            return .spring(response: 0.32, dampingFraction: 0.78, blendDuration: 0.08)
        }
    }

    var exitAnimation: Animation {
        switch self {
        case .fadeLift:
            return .easeIn(duration: 0.12)
        case .riseFromBar:
            return .easeIn(duration: 0.16)
        case .springPop:
            return .easeIn(duration: 0.13)
        case .flipReveal:
            return .easeIn(duration: 0.14)
        }
    }

    var exitDuration: TimeInterval {
        switch self {
        case .fadeLift: return 0.13
        case .riseFromBar: return 0.17
        case .springPop: return 0.14
        case .flipReveal: return 0.15
        }
    }
}

// MARK: - Vista de Tarjeta de Vista Previa (Tamaño Fijo + 4 Animaciones Seleccionables + Crossfade Suave)

private struct TaskbarPreviewCardView: View {
    @Bindable private var controller = TaskbarPreviewPanelController.shared
    @Bindable private var prefs = TaskbarPreferences.shared
    @Bindable private var thumbService = TaskbarThumbnailService.shared
    @Bindable private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layout = controller.currentLayout
        let horizontalInset = TaskbarPreviewPanelController.panelHorizontalInset
        let topInset = TaskbarPreviewPanelController.panelTopInset
        let bottomGap = TaskbarPreviewPanelController.cardBottomGap
        let panelWidth = layout.cardWidth + (horizontalInset * 2)
        let panelHeight = layout.cardHeight + topInset + bottomGap

        ZStack(alignment: .bottom) {
            if let item = controller.currentItem {
                let presented = controller.isPresented
                let style = controller.activeAnimationStyle
                let cardOpacity: Double = {
                    switch style {
                    case .riseFromBar: return 1.0
                    case .fadeLift, .springPop, .flipReveal: return presented ? 1.0 : 0.0
                    }
                }()
                let cardScale: CGFloat = {
                    guard !presented else { return 1.0 }
                    switch style {
                    case .fadeLift: return 0.96
                    case .riseFromBar: return 0.985
                    case .springPop: return 0.72
                    case .flipReveal: return 0.92
                    }
                }()
                let cardOffsetY: CGFloat = {
                    guard !presented else { return 0 }
                    switch style {
                    case .fadeLift: return 7
                    case .riseFromBar: return layout.cardHeight + bottomGap + 18
                    case .springPop: return 16
                    case .flipReveal: return 14
                    }
                }()
                let cardRotationX: Double = (style == .flipReveal && !presented) ? 38.0 : 0.0

                VStack(spacing: 0) {
                    // Cabecera fija con controles semáforo macOS + título opcional
                    HStack(spacing: 6) {
                        HStack(spacing: 5) {
                            PreviewTrafficDot(color: Color(red: 1.0, green: 0.37, blue: 0.34), symbol: "xmark") {
                                controller.hideImmediately()
                                TaskbarWindowTracker.shared.closeWindow(item)
                            }
                            .help(loc.text(es: "Cerrar ventana", en: "Close Window"))

                            PreviewTrafficDot(color: Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus") {
                                controller.hideImmediately()
                                TaskbarWindowTracker.shared.minimizeWindow(item)
                            }
                            .help(loc.text(es: "Minimizar ventana", en: "Minimize Window"))

                            PreviewTrafficDot(color: Color(red: 0.16, green: 0.79, blue: 0.25), symbol: "arrow.up.left.and.arrow.down.right") {
                                controller.hideImmediately()
                                TaskbarWindowTracker.shared.focusWindow(item)
                            }
                            .help(loc.text(es: "Traer al frente", en: "Bring to Front"))
                        }

                        if prefs.showTitleInThumbnail {
                            Image(nsImage: TaskbarAppCatalogService.shared.icon(
                                forBundleIdentifier: item.bundleIdentifier,
                                fallbackURL: item.appBundleURL
                            ))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 15, height: 15)

                            Text(item.displayTitle)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.primary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: layout.headerHeight)

                    // Contenido principal dentro de un escenario de tamaño estrictamente fijo
                    Group {
                        if thumbService.hasScreenRecordingPermission {
                            TaskbarPreviewImageStage(
                                item: item,
                                image: controller.previewImage,
                                previousImage: controller.previousPreviewImage,
                                transitionToken: controller.imageTransitionToken,
                                isCrossfadeUpdate: controller.isCrossfadeUpdate,
                                isLoading: controller.isLoadingThumbnail,
                                width: layout.imageWidth,
                                height: layout.imageHeight,
                                isDark: colorScheme == .dark
                            )
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        } else {
                            // Respaldo limpio cuando el usuario optó por no dar Grabación de Pantalla
                            HStack(spacing: 10) {
                                Image(nsImage: TaskbarAppCatalogService.shared.icon(
                                    forBundleIdentifier: item.bundleIdentifier,
                                    fallbackURL: item.appBundleURL
                                ))
                                .resizable()
                                .frame(width: 42, height: 42)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.appName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(item.displayTitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(loc.text(
                                        es: "Activa Grabación de pantalla en Ajustes para miniaturas en vivo.",
                                        en: "Enable Screen Recording in Settings for live thumbnails."
                                    ))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller.hideImmediately()
                        TaskbarWindowTracker.shared.focusWindow(item)
                    }
                }
                .frame(width: layout.cardWidth, height: layout.cardHeight)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.42 : 0.18),
                    radius: 10,
                    x: 0,
                    y: 4
                )
                .onHover { inside in
                    controller.handlePreviewCardHoverChanged(isInside: inside)
                }
                .scaleEffect(cardScale, anchor: .bottom)
                .rotation3DEffect(
                    .degrees(cardRotationX),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.55
                )
                .offset(y: cardOffsetY)
                .opacity(cardOpacity)
                .padding(.bottom, bottomGap)
            }
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .bottom)
        .clipped()
    }
}

/// Escenario de miniatura con dimensiones bloqueadas que realiza un crossfade suave (`0.18 s`)
/// cuando se actualiza la captura, evitando parpadeos, saltos y cambios de tamaño.
private struct TaskbarPreviewImageStage: View {
    let item: TaskbarWindowItem
    let image: NSImage?
    let previousImage: NSImage?
    let transitionToken: UInt64
    let isCrossfadeUpdate: Bool
    let isLoading: Bool
    let width: CGFloat
    let height: CGFloat
    let isDark: Bool

    @Bindable private var loc = LocalizationManager.shared
    @ViewState private var foregroundOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Fondo sutil fijo del contenedor de miniatura
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isDark ? Color.black.opacity(0.28) : Color.black.opacity(0.06))

            // Imagen previa retenida debajo durante el crossfade para disimular el refresco sin parpadeo
            if let previousImage, image != nil {
                Image(nsImage: previousImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
                    .opacity(foregroundOpacity)
            } else {
                // Placeholder suave con efecto shimmer mientras llega la primera captura
                ZStack {
                    if isLoading {
                        PreviewShimmerSurface(isDark: isDark)
                    }
                    VStack(spacing: 6) {
                        Image(nsImage: TaskbarAppCatalogService.shared.icon(
                            forBundleIdentifier: item.bundleIdentifier,
                            fallbackURL: item.appBundleURL
                        ))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)
                        .opacity(isLoading ? 0.55 : 0.85)

                        Text(item.isMinimized
                             ? loc.text(es: "Ventana minimizada", en: "Minimized Window")
                             : item.appName)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .onChange(of: transitionToken) { _, _ in
            guard image != nil else {
                foregroundOpacity = 1.0
                return
            }
            if isCrossfadeUpdate {
                foregroundOpacity = 0.0
                withAnimation(.easeInOut(duration: 0.20)) {
                    foregroundOpacity = 1.0
                }
            } else {
                foregroundOpacity = 1.0
            }
        }
    }
}

private struct PreviewShimmerSurface: View {
    let isDark: Bool
    @ViewState private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                colors: [
                    .clear,
                    (isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.45)),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w * 0.65)
            .offset(x: phase * w)
        }
        .onAppear {
            phase = -0.8
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PreviewTrafficDot: View {
    let color: Color
    let symbol: String
    let action: () -> Void

    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 11.5, height: 11.5)
                if isHovered {
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Tarjeta de Previsualización en Vivo para Configuración (4 Animaciones de Vista Previa)

/// Tarjeta interactiva con una mini barra de tareas y una mini ventana flotante que demuestra
/// en vivo cada una de las 4 animaciones de vista previa al pasar el cursor.
public struct TaskbarHoverPreviewAnimationCard: View {
    public let style: TaskbarHoverPreviewAnimation
    public let isSelected: Bool
    public let previewDark: Bool
    public let timelineDate: Date
    public let onSelect: () -> Void

    @Bindable private var loc = LocalizationManager.shared

    public init(
        style: TaskbarHoverPreviewAnimation,
        isSelected: Bool,
        previewDark: Bool,
        timelineDate: Date,
        onSelect: @escaping () -> Void
    ) {
        self.style = style
        self.isSelected = isSelected
        self.previewDark = previewDark
        self.timelineDate = timelineDate
        self.onSelect = onSelect
    }

    private struct PreviewMotionFrame {
        let opacity: Double
        let scale: CGFloat
        let offsetY: CGFloat
        let rotationX: Double
        let isHoveredBarButton: Bool
    }

    private var motionFrame: PreviewMotionFrame {
        let cycle: Double = 2.40
        let rawT = timelineDate.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        let t = rawT >= 0 ? rawT : (rawT + cycle)

        let enterEnd: Double = 0.44
        let holdEnd: Double = 1.56
        let exitEnd: Double = 1.90

        if t < enterEnd {
            let p = max(0.0, min(1.0, t / enterEnd))
            switch style {
            case .fadeLift:
                let e = 1.0 - pow(1.0 - p, 3.0)
                return PreviewMotionFrame(
                    opacity: e,
                    scale: CGFloat(0.95 + 0.05 * e),
                    offsetY: CGFloat(6.0 * (1.0 - e)),
                    rotationX: 0.0,
                    isHoveredBarButton: true
                )
            case .riseFromBar:
                let e = 1.0 - pow(1.0 - p, 3.2)
                return PreviewMotionFrame(
                    opacity: 1.0,
                    scale: CGFloat(0.985 + 0.015 * e),
                    offsetY: CGFloat(44.0 * (1.0 - e)),
                    rotationX: 0.0,
                    isHoveredBarButton: true
                )
            case .springPop:
                let s = 1.0 - exp(-5.8 * p) * cos(p * 2.1 * .pi)
                let clampedForOffset = min(1.08, s)
                return PreviewMotionFrame(
                    opacity: min(1.0, p * 3.4),
                    scale: CGFloat(0.68 + 0.32 * s),
                    offsetY: CGFloat(12.0 * (1.0 - clampedForOffset)),
                    rotationX: 0.0,
                    isHoveredBarButton: true
                )
            case .flipReveal:
                let s = 1.0 - exp(-6.8 * p) * cos(p * 1.35 * .pi)
                return PreviewMotionFrame(
                    opacity: min(1.0, p * 3.0),
                    scale: CGFloat(0.90 + 0.10 * s),
                    offsetY: CGFloat(10.0 * (1.0 - s)),
                    rotationX: 46.0 * (1.0 - s),
                    isHoveredBarButton: true
                )
            }
        } else if t < holdEnd {
            return PreviewMotionFrame(
                opacity: 1.0,
                scale: 1.0,
                offsetY: 0.0,
                rotationX: 0.0,
                isHoveredBarButton: true
            )
        } else if t < exitEnd {
            let p = max(0.0, min(1.0, (t - holdEnd) / (exitEnd - holdEnd)))
            switch style {
            case .fadeLift:
                let e = pow(p, 2.0)
                return PreviewMotionFrame(
                    opacity: 1.0 - e,
                    scale: CGFloat(1.0 - 0.04 * e),
                    offsetY: CGFloat(5.0 * e),
                    rotationX: 0.0,
                    isHoveredBarButton: false
                )
            case .riseFromBar:
                let e = pow(p, 2.1)
                return PreviewMotionFrame(
                    opacity: 1.0,
                    scale: CGFloat(1.0 - 0.015 * e),
                    offsetY: CGFloat(44.0 * e),
                    rotationX: 0.0,
                    isHoveredBarButton: false
                )
            case .springPop:
                let e = pow(p, 2.0)
                return PreviewMotionFrame(
                    opacity: 1.0 - e,
                    scale: CGFloat(1.0 - 0.26 * e),
                    offsetY: CGFloat(10.0 * e),
                    rotationX: 0.0,
                    isHoveredBarButton: false
                )
            case .flipReveal:
                let e = pow(p, 2.0)
                return PreviewMotionFrame(
                    opacity: 1.0 - e,
                    scale: CGFloat(1.0 - 0.08 * e),
                    offsetY: CGFloat(8.0 * e),
                    rotationX: 40.0 * e,
                    isHoveredBarButton: false
                )
            }
        } else {
            return PreviewMotionFrame(
                opacity: 0.0,
                scale: 0.94,
                offsetY: style == .riseFromBar ? 44.0 : 8.0,
                rotationX: style == .flipReveal ? 42.0 : 0.0,
                isHoveredBarButton: false
            )
        }
    }

    public var body: some View {
        let frame = motionFrame
        let cardSurfaceColor = previewDark ? Color(white: 0.22) : Color.white
        let cardStrokeColor = previewDark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
        let barSurfaceColor = previewDark ? Color(white: 0.10) : Color(white: 0.96)
        let stageTopColor = previewDark ? Color(white: 0.13) : Color(red: 0.88, green: 0.92, blue: 0.98)
        let stageBottomColor = previewDark ? Color(white: 0.18) : Color(red: 0.94, green: 0.96, blue: 0.99)
        let miniShadowColor = Color.black.opacity(previewDark ? 0.42 : 0.18)

        Button(action: onSelect) {
            VStack(spacing: 7) {
                // Escenario en miniatura: escritorio + ventana emergente recortada al borde + mini barra de tareas
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        // Mini ventana de vista previa
                        VStack(spacing: 3) {
                            HStack(spacing: 2.5) {
                                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 4, height: 4)
                                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 4, height: 4)
                                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 4, height: 4)
                                Capsule()
                                    .fill(previewDark ? Color.white.opacity(0.26) : Color.black.opacity(0.18))
                                    .frame(width: 20, height: 2.5)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 4.5)
                            .padding(.top, 4)

                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(previewDark ? 0.55 : 0.35),
                                            Color.purple.opacity(previewDark ? 0.38 : 0.22)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    VStack(alignment: .leading, spacing: 2.5) {
                                        Capsule()
                                            .fill(Color.white.opacity(previewDark ? 0.45 : 0.70))
                                            .frame(width: 24, height: 2.5)
                                        Capsule()
                                            .fill(Color.white.opacity(previewDark ? 0.25 : 0.50))
                                            .frame(width: 34, height: 2.5)
                                        Capsule()
                                            .fill(Color.white.opacity(previewDark ? 0.20 : 0.42))
                                            .frame(width: 18, height: 2.5)
                                    }
                                    .padding(4.5),
                                    alignment: .topLeading
                                )
                                .padding(.horizontal, 4)
                                .padding(.bottom, 4)
                        }
                        .frame(width: 62, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(cardSurfaceColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(cardStrokeColor, lineWidth: 0.8)
                        )
                        .shadow(color: miniShadowColor, radius: 4, x: 0, y: 2)
                        .scaleEffect(frame.scale, anchor: .bottom)
                        .rotation3DEffect(
                            .degrees(frame.rotationX),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .bottom,
                            perspective: 0.55
                        )
                        .offset(y: frame.offsetY)
                        .opacity(frame.opacity)
                        .padding(.bottom, 4)
                    }
                    .frame(width: 102, height: 48, alignment: .bottom)
                    .clipped()

                    // Mini barra de tareas en la parte inferior
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(barSurfaceColor)
                        Rectangle()
                            .fill(previewDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10))
                            .frame(height: 0.75)

                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(previewDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                                .frame(width: 7, height: 7)

                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(previewDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .frame(width: 16, height: 8)

                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(
                                    frame.isHoveredBarButton
                                        ? Color.accentColor.opacity(previewDark ? 0.55 : 0.32)
                                        : (previewDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                                )
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: 10, height: 1.5)
                                        .padding(.bottom, 0.5)
                                }
                                .frame(width: 24, height: 8)

                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(previewDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .frame(width: 16, height: 8)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: 102, height: 14)
                }
                .background(
                    LinearGradient(
                        colors: [stageTopColor, stageBottomColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(previewDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 0.8)
                )

                VStack(spacing: 1) {
                    Text(style.localizedTitle(using: loc))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(style.localizedSubtitle(using: loc))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
