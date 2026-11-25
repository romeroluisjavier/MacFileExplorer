import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI

// MARK: - Panel de Vista Previa a Tamaño Completo (Por encima de todas las ventanas, detrás del HUD de AltTab)

@MainActor
private final class AltTabFullPreviewNSPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
public final class AltTabFullPreviewPanelController {

    public static let shared = AltTabFullPreviewPanelController()

    public private(set) var currentItem: TaskbarWindowItem?
    public private(set) var previewImage: NSImage?

    private var panel: AltTabFullPreviewNSPanel?
    private var delayWorkItem: DispatchWorkItem?
    private var captureTask: Task<Void, Never>?

    private init() {}

    public var panelWindowNumber: Int? {
        panel?.windowNumber
    }

    public func prewarmPanel() {
        _ = ensurePanel()
    }

    /// Programa la muestra de la vista previa a tamaño completo de la ventana resaltada.
    public func schedulePreview(
        for item: TaskbarWindowItem,
        delayMs: Double,
        fallbackScreenFrameCocoa: NSRect
    ) {
        delayWorkItem?.cancel()
        captureTask?.cancel()

        // Si el panel ya estaba visible (el usuario está recorriendo ventanas con ⌥⇥), actualizar al instante
        let effectiveDelaySec: TimeInterval = (panel?.isVisible == true) ? 0.0 : (max(0, delayMs) / 1000.0)

        if effectiveDelaySec <= 0.005 {
            presentPreview(for: item, fallbackScreenFrameCocoa: fallbackScreenFrameCocoa)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      AltTabManager.shared.isSwitcherOpen,
                      AltTabManager.shared.selectedWindow?.id == item.id else { return }
                self.presentPreview(for: item, fallbackScreenFrameCocoa: fallbackScreenFrameCocoa)
            }
        }
        delayWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelaySec, execute: work)
    }

    public func hideImmediately() {
        delayWorkItem?.cancel()
        delayWorkItem = nil
        captureTask?.cancel()
        captureTask = nil
        panel?.orderOut(nil)
        currentItem = nil
        previewImage = nil
    }

    private func presentPreview(for item: TaskbarWindowItem, fallbackScreenFrameCocoa: NSRect) {
        let targetPanel = ensurePanel()
        currentItem = item
        previewImage = TaskbarThumbnailService.shared.cachedFullSizePreview(for: item.windowID)

        let targetRect = computeTargetCocoaFrame(for: item, fallbackScreenFrame: fallbackScreenFrameCocoa)
        targetPanel.setFrame(targetRect, display: true)
        targetPanel.orderFrontRegardless()

        // Capturar versión full-size nítida en segundo plano si tenemos Grabación de Pantalla
        if TaskbarThumbnailService.shared.refreshPermissionStatus(), item.windowID != 0 {
            let maxDim = max(targetRect.width, targetRect.height)
            let winID = item.windowID
            let isMini = item.isMinimized
            captureTask = Task { [weak self] in
                let hiRes = await TaskbarThumbnailService.shared.captureFullSizePreview(
                    for: winID,
                    maxScreenDimension: maxDim,
                    isMinimized: isMini
                )
                guard !Task.isCancelled, let self, self.currentItem?.id == item.id, let hiRes else { return }
                self.previewImage = hiRes
            }
        }
    }

    private func computeTargetCocoaFrame(for item: TaskbarWindowItem, fallbackScreenFrame: NSRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? fallbackScreenFrame.height

        // Si la ventana tiene coordenadas reales válidas y pertenece al Space activo sin estar minimizada,
        // mostrarla exactamente en su posición y tamaño reales sobre todas las demás ventanas.
        if !item.isMinimized && item.frameAX.width >= 160 && item.frameAX.height >= 120 {
            let realCocoa = TaskbarGeometry.axRectToCocoa(item.frameAX, primaryScreenHeight: primaryHeight)
            let screens = TaskbarWindowTracker.shared.connectedScreens
            if screens.contains(where: { $0.frameCocoa.intersects(realCocoa) }) {
                return realCocoa
            }
        }

        // Para ventanas minimizadas o en otro Space fuera del monitor visible:
        // mostrar en gran tamaño centrado en el monitor activo manteniendo proporción.
        let maxW = fallbackScreenFrame.width * 0.78
        let maxH = fallbackScreenFrame.height * 0.78
        let aspect: CGFloat = {
            if item.frameAX.width > 50 && item.frameAX.height > 50 {
                return item.frameAX.width / item.frameAX.height
            }
            if let img = previewImage, img.size.height > 0 {
                return img.size.width / img.size.height
            }
            return 16.0 / 10.0
        }()

        var w = maxW
        var h = w / max(0.3, aspect)
        if h > maxH {
            h = maxH
            w = h * max(0.3, aspect)
        }
        return NSRect(
            x: round(fallbackScreenFrame.midX - w / 2),
            y: round(fallbackScreenFrame.midY - h / 2),
            width: round(w),
            height: round(h)
        )
    }

    private func ensurePanel() -> AltTabFullPreviewNSPanel {
        if let existing = panel {
            return existing
        }
        let created = AltTabFullPreviewNSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.ignoresMouseEvents = true
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        // Exactamente debajo del HUD de AltTab (.popUpMenu) y por encima de todas las ventanas normales y de Taskbar
        created.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        created.contentView = NSHostingView(rootView: AltTabFullPreviewOverlayView())
        panel = created
        return created
    }
}

private struct AltTabFullPreviewOverlayView: View {
    @Bindable private var controller = AltTabFullPreviewPanelController.shared
    @Bindable private var prefs = AltTabPreferences.shared

    var body: some View {
        if let item = controller.currentItem {
            ZStack(alignment: .topLeading) {
                if let image = controller.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.65), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.38), radius: 24, y: 10)
                } else {
                    // Respaldo limpio si no hay permiso de Grabación de Pantalla
                    VStack(spacing: 14) {
                        Image(nsImage: TaskbarAppCatalogService.shared.icon(
                            forBundleIdentifier: item.bundleIdentifier,
                            fallbackURL: item.appBundleURL
                        ))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)

                        Text(item.appName)
                            .font(.system(size: 18, weight: .bold))
                        Text(item.displayTitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.65), lineWidth: 2)
                    )
                }

                // Etiqueta sutil en esquina superior izquierda si está minimizada, oculta o en otro Space
                if !item.isOnActiveSpace || item.isMinimized || item.isAppHidden {
                    HStack(spacing: 6) {
                        Image(nsImage: TaskbarAppCatalogService.shared.icon(
                            forBundleIdentifier: item.bundleIdentifier,
                            fallbackURL: item.appBundleURL
                        ))
                        .resizable()
                        .frame(width: 15, height: 15)

                        Text(item.displayTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)

                        AltTabStatusBadgesRow(
                            item: item,
                            showSpaceBadges: prefs.showSpaceBadges,
                            showStateBadges: prefs.showWindowStateBadges,
                            compact: false
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.75))
                    .padding(14)
                }
            }
        }
    }
}
