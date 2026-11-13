import Foundation
import AppKit

/// Responder insertado en la cadena `nextResponder` de cada `NSWindow` del explorador
/// para capturar eventos sintéticos de gesto/deslizamiento (`NSEvent.EventType.swipe`)
/// emitidos por Logi Options+ (Logitech MX Master), SensibleSideButtons o trackpad,
/// exactamente igual que Finder y Chrome.
@MainActor
public final class WindowSwipeResponder: NSResponder {
    public weak var hostWindow: NSWindow?

    public init(hostWindow: NSWindow) {
        self.hostWindow = hostWindow
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func swipe(with event: NSEvent) {
        let targetWindow = hostWindow ?? event.window
        if !MouseNavigationManager.shared.handleSwipeEvent(event, targetWindow: targetWindow) {
            super.swipe(with: event)
        }
    }
}

/// Gestor global y centralizado de eventos de navegación por ratón y gestos
/// (botones laterales Atrás y Adelante, y eventos `.swipe` de Logi Options+ / trackpad).
/// Se instala una sola vez a nivel de aplicación en `AppDelegate.applicationDidFinishLaunching`,
/// asegurando que ninguna recreación de vista SwiftUI ni cambio de foco pierda la capacidad
/// de retroceder o avanzar tanto en el Explorador de archivos como en pestañas web.
@MainActor
public final class MouseNavigationManager {
    public static let shared = MouseNavigationManager()

    private static let swipeDeduplicationWindow: TimeInterval = 0.025

    private var localMonitor: Any?
    private var isInstalled = false
    private var downButtonsWithNavigation: Set<Int> = []
    private var lastSwipeTimestamp: TimeInterval?
    private var lastSwipeDirectionIsBack: Bool?
    private let windowSwipeResponders = NSMapTable<NSWindow, WindowSwipeResponder>.weakToStrongObjects()

    private init() {}

    /// Instala el monitor global de eventos de ratón y gestos `.swipe` si aún no está instalado.
    public func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp, .swipe]) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated {
                switch event.type {
                case .otherMouseDown, .otherMouseUp:
                    return self.handleMouseEvent(event)
                case .swipe:
                    return self.handleSwipeEvent(event, targetWindow: event.window)
                default:
                    return false
                }
            }
            return consumed ? nil : event
        }
    }

    /// Desinstala el monitor y reinicia el estado interno de seguimiento (útil en pruebas).
    public func uninstall() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isInstalled = false
        downButtonsWithNavigation.removeAll()
        lastSwipeTimestamp = nil
        lastSwipeDirectionIsBack = nil
    }

    /// Instala un `WindowSwipeResponder` en la cadena de respuesta de `window` de forma idempotente.
    public func installSwipeResponderIfNeeded(on window: NSWindow) {
        if let existing = windowSwipeResponders.object(forKey: window) {
            var current: NSResponder? = window.nextResponder
            while let responder = current {
                if responder === existing {
                    return
                }
                current = responder.nextResponder
            }
            existing.nextResponder = window.nextResponder
            window.nextResponder = existing
            return
        }

        var current: NSResponder? = window.nextResponder
        while let responder = current {
            if let existing = responder as? WindowSwipeResponder {
                windowSwipeResponders.setObject(existing, forKey: window)
                return
            }
            current = responder.nextResponder
        }

        let swipeResponder = WindowSwipeResponder(hostWindow: window)
        swipeResponder.nextResponder = window.nextResponder
        window.nextResponder = swipeResponder
        windowSwipeResponders.setObject(swipeResponder, forKey: window)
    }

    /// Determina la dirección de navegación de un evento `.swipe` según la convención estándar de macOS:
    /// `deltaX > 0` (`+1.0`, Swipe Left) = Atrás (`true`); `deltaX < 0` (`-1.0`, Swipe Right) = Adelante (`false`).
    /// Devuelve `nil` si el deslizamiento no tiene componente horizontal dominante.
    public static func swipeDirectionIsBack(deltaX: CGFloat, deltaY: CGFloat) -> Bool? {
        guard abs(deltaX) > 0.0001, abs(deltaX) >= abs(deltaY) else {
            return nil
        }
        return deltaX > 0
    }

    /// Procesa eventos de botones laterales del ratón (`buttonNumber >= 3`).
    /// Devuelve `true` si el evento fue consumido por la navegación.
    public func handleMouseEvent(_ event: NSEvent) -> Bool {
        let button = event.buttonNumber
        // 0 = Izquierdo, 1 = Derecho, 2 = Central (rueda)
        // 3 y 4 (y 5) = Botones laterales
        guard button >= 3 else {
            return false
        }

        let swap = PersistenceService.shared.loadSwapMouseButtons()
        let isBack: Bool

        if button == 3 {
            isBack = !swap
        } else if button == 4 || button == 5 {
            isBack = swap
        } else {
            return false
        }

        if event.type == .otherMouseDown {
            downButtonsWithNavigation.insert(button)
            navigate(isBack: isBack, targetWindow: event.window)
            return true
        } else if event.type == .otherMouseUp {
            let alreadyHandledOnDown = downButtonsWithNavigation.remove(button) != nil
            if !alreadyHandledOnDown {
                navigate(isBack: isBack, targetWindow: event.window)
            }
            return true
        }

        return false
    }

    /// Procesa eventos `.swipe` de AppKit (emitidos por Logi Options+, SensibleSideButtons o trackpad).
    /// Devuelve `true` si el evento fue consumido por la navegación (incluyendo duplicados de un mismo gesto).
    public func handleSwipeEvent(_ event: NSEvent, targetWindow: NSWindow? = nil) -> Bool {
        guard event.type == .swipe else {
            return false
        }
        guard let rawIsBack = Self.swipeDirectionIsBack(deltaX: event.deltaX, deltaY: event.deltaY) else {
            return false
        }

        let resolvedWindow = resolveEffectiveWindow(from: targetWindow ?? event.window)
        if let resolvedWindow,
           resolvedWindow.attachedSheet != nil || resolvedWindow.sheetParent != nil {
            return false
        }

        let isBack = PersistenceService.shared.loadSwapMouseButtons() ? !rawIsBack : rawIsBack
        let timestamp = event.timestamp > 0 ? event.timestamp : ProcessInfo.processInfo.systemUptime

        if let lastTimestamp = lastSwipeTimestamp,
           let lastDirection = lastSwipeDirectionIsBack,
           lastDirection == isBack,
           abs(timestamp - lastTimestamp) < Self.swipeDeduplicationWindow {
            return true
        }

        lastSwipeTimestamp = timestamp
        lastSwipeDirectionIsBack = isBack

        navigate(isBack: isBack, targetWindow: resolvedWindow ?? targetWindow ?? event.window)
        return true
    }

    /// Ejecuta la navegación Atrás (`isBack == true`) o Adelante (`isBack == false`).
    public func navigate(isBack: Bool, targetWindow: NSWindow? = nil) {
        let activeWindow = targetWindow ?? windowUnderMousePointer() ?? NSApp.keyWindow ?? NSApp.mainWindow
        let effectiveWindow = activeWindow?.tabGroup?.selectedWindow ?? activeWindow

        // No navegar subyacentemente mientras haya un diálogo modal (sheet) abierto en la ventana
        if let effectiveWindow,
           effectiveWindow.attachedSheet != nil || effectiveWindow.sheetParent != nil {
            return
        }

        // 1. Si hay una pestaña web activa de Google Workspace, navegar en la página web
        if let webTabID = GoogleAccountsManager.shared.activeTabID(for: effectiveWindow)
            ?? (effectiveWindow == nil ? GoogleAccountsManager.shared.activeTabID : nil) {
            if isBack {
                GoogleAccountsManager.shared.goBackInTab(webTabID)
            } else {
                GoogleAccountsManager.shared.goForwardInTab(webTabID)
            }
            return
        }

        // 2. Si es una pestaña del explorador de archivos local:
        let vm = ExplorerWindowRegistry.shared.viewModel(for: effectiveWindow)
            ?? ExplorerWindowRegistry.shared.viewModel(for: activeWindow)
            ?? ExplorerWindowRegistry.shared.activeViewModel
            ?? ExplorerWindowRegistry.shared.lastActiveViewModel

        guard let vm else { return }

        // Si estaba renombrando o editando ruta, cancelar edición para devolver el foco a la carpeta
        if vm.renamingItemID != nil {
            vm.cancelRename()
            if let effectiveWindow {
                KeyboardShortcuts.resignTextFocus(in: effectiveWindow)
            }
        }
        if vm.isEditingAddressBar {
            vm.cancelAddressBarEditing()
            if let effectiveWindow {
                KeyboardShortcuts.resignTextFocus(in: effectiveWindow)
            }
        }

        if isBack {
            if vm.canGoBack {
                vm.goBack()
            }
        } else {
            if vm.canGoForward {
                vm.goForward()
            }
        }
    }

    private func resolveEffectiveWindow(from targetWindow: NSWindow?) -> NSWindow? {
        let activeWindow = targetWindow ?? windowUnderMousePointer() ?? NSApp.keyWindow ?? NSApp.mainWindow
        return activeWindow?.tabGroup?.selectedWindow ?? activeWindow
    }

    private func windowUnderMousePointer() -> NSWindow? {
        let mouseLocation = NSEvent.mouseLocation
        return NSApp.orderedWindows.first { window in
            window.isVisible
                && !window.isMiniaturized
                && window.level == .normal
                && window.frame.contains(mouseLocation)
        }
    }
}
