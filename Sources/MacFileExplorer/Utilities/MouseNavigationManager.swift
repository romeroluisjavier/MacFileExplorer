import Foundation
import AppKit

/// Gestor global y centralizado de eventos de navegación por ratón (botones laterales Atrás y Adelante).
/// Se instala una sola vez a nivel de aplicación en `AppDelegate.applicationDidFinishLaunching`,
/// asegurando que ninguna recreación de vista SwiftUI ni cambio de foco pierda la capacidad
/// de retroceder o avanzar con el ratón tanto en el Explorador de archivos como en pestañas web.
@MainActor
public final class MouseNavigationManager {
    public static let shared = MouseNavigationManager()

    private var localMonitor: Any?
    private var isInstalled = false
    private var didNavigateOnMouseDown = false

    private init() {}

    /// Instala el monitor global de eventos de ratón si aún no está instalado.
    public func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated {
                self.handleMouseEvent(event)
            }
            return consumed ? nil : event
        }
    }

    /// Desinstala el monitor si es necesario (ej. desmontaje o pruebas).
    public func uninstall() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isInstalled = false
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
            didNavigateOnMouseDown = true
            navigate(isBack: isBack, targetWindow: event.window)
            return true
        } else if event.type == .otherMouseUp {
            if !didNavigateOnMouseDown {
                navigate(isBack: isBack, targetWindow: event.window)
            }
            didNavigateOnMouseDown = false
            return true
        }

        return false
    }

    /// Ejecuta la navegación Atrás (`isBack == true`) o Adelante (`isBack == false`).
    public func navigate(isBack: Bool, targetWindow: NSWindow? = nil) {
        let activeWindow = targetWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        let effectiveWindow = activeWindow?.tabGroup?.selectedWindow ?? activeWindow

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
}
