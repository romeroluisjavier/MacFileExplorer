import AppKit
import SwiftUI

/// Utilidades de teclado y ratón para capturar modificadores nativos (`Shift`, `Cmd`, `Option`)
/// y atajos especiales de Windows Explorer (`F2`, `Enter`, `Delete`/`Backspace`, `Alt+Up`, `Escape`).
@MainActor
public enum KeyboardShortcuts {

    /// Obtiene los `EventModifiers` de SwiftUI correspondientes al evento actual de `NSEvent`.
    public static var currentEventModifiers: EventModifiers {
        let flags = NSEvent.modifierFlags
        var modifiers: EventModifiers = []
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        return modifiers
    }

    /// Quita el foco de edición de cualquier campo de texto (`NSTextView`/`NSText`)
    /// para devolver los atajos de teclado (`Espacio`, `Enter`, `Cmd+Z`, flechas) al explorador.
    public static func resignTextFocus(in window: NSWindow? = nil) {
        guard let targetWindow = window ?? NSApp?.keyWindow else { return }
        if targetWindow.firstResponder is NSTextView || targetWindow.firstResponder is NSText {
            targetWindow.makeFirstResponder(nil)
        }
    }

    /// Determina si un evento de teclado coincide con `Cmd + [` o `Cmd + ]`,
    /// soportando tanto teclado US ANSI (`keyCode 33/30` sin `Shift`) como teclados
    /// internacionales (ej. Latinoamérica donde `[` / `]` requieren `Shift`) y eventos
    /// Unicode sintéticos (`typedCharacters == "[" / "]"`), sin interceptar `Cmd + Shift + [` / `]` en US.
    public static func matchesCommandBracket(
        targetBracket: String,
        ansiKeyCode: UInt16,
        keyCode: UInt16,
        characters: String?,
        typedCharacters: String?,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard flags.contains(.command), !flags.contains(.control) else {
            return false
        }
        if typedCharacters == targetBracket {
            return true
        }
        guard !flags.contains(.shift) else {
            return false
        }
        return keyCode == ansiKeyCode || characters == targetBracket
    }
}

/// Registro débil de ventanas activas -> `ExplorerViewModel` para que el menú `Edición` (`Cmd+Z`/`Cmd+Shift+Z`)
/// siempre encuentre el explorador activo incluso cuando ningún campo SwiftUI tiene `@FocusState`.
@MainActor
public final class ExplorerWindowRegistry {
    public static let shared = ExplorerWindowRegistry()
    private var entries: [ObjectIdentifier: WeakExplorerBox] = [:]

    private init() {}

    public weak var lastActiveViewModel: ExplorerViewModel?

    public func register(viewModel: ExplorerViewModel, for window: NSWindow?) {
        pruneDeadEntries()
        lastActiveViewModel = viewModel
        guard let window else { return }
        entries[ObjectIdentifier(window)] = WeakExplorerBox(window: window, viewModel: viewModel)
        MouseNavigationManager.shared.installSwipeResponderIfNeeded(on: window)
    }

    public func viewModel(for window: NSWindow?) -> ExplorerViewModel? {
        pruneDeadEntries()
        guard let window else { return nil }
        return entries[ObjectIdentifier(window)]?.viewModel
    }

    public var activeViewModel: ExplorerViewModel? {
        pruneDeadEntries()
        if let keyWin = NSApp.keyWindow {
            if let vm = viewModel(for: keyWin) ?? viewModel(for: keyWin.tabGroup?.selectedWindow) {
                return vm
            }
        }
        if let mainWin = NSApp.mainWindow {
            if let vm = viewModel(for: mainWin) ?? viewModel(for: mainWin.tabGroup?.selectedWindow) {
                return vm
            }
        }
        return lastActiveViewModel ?? entries.values.compactMap(\.viewModel).first
    }

    private func pruneDeadEntries() {
        entries = entries.filter { $0.value.window != nil && $0.value.viewModel != nil }
    }

    @MainActor
    private final class WeakExplorerBox {
        weak var window: NSWindow?
        weak var viewModel: ExplorerViewModel?

        init(window: NSWindow, viewModel: ExplorerViewModel) {
            self.window = window
            self.viewModel = viewModel
        }
    }
}

/// Alias explícito hacia el `@propertyWrapper struct SwiftUI.State<Value>` para evitar que el SDK de CommandLineTools
/// lo resuelva hacia la macro experimental `SwiftUIMacros.StateMacro`.
public typealias ViewState<Value> = SwiftUI.State<Value>

/// ViewModifier que instala un monitor local de teclado (`NSEvent`) para soportar atajos clásicos
/// de Windows Explorer (`F2`, `Enter` para renombrar, `Backspace`/`Delete` para Papelera, `Alt+Up` para subir)
/// sin interferir cuando un `TextField` (búsqueda, barra de ruta o renombrado) tiene el foco.
public struct ExplorerKeyEventMonitorModifier: ViewModifier {
    let viewModel: ExplorerViewModel

    @ViewState private var eventMonitor: Any? = nil
    @ViewState private var hostWindowBox = WeakWindowBox()

    public func body(content: Content) -> some View {
        content
            .background(HostWindowCaptureView(box: hostWindowBox, viewModel: viewModel))
            .onAppear {
                installMonitorIfNeeded()
            }
            .onDisappear {
                removeMonitor()
            }
    }

    @MainActor
    private func installMonitorIfNeeded() {
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = event.keyCode
                let rawModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let characters = event.charactersIgnoringModifiers?.lowercased()
                let typedCharacters = event.characters?.lowercased()
                let eventWindow = event.window
                let consumed = MainActor.assumeIsolated {
                    handleKeyDown(
                        keyCode: keyCode,
                        characters: characters,
                        typedCharacters: typedCharacters,
                        rawModifiers: rawModifiers,
                        eventWindow: eventWindow
                    )
                }
                return consumed ? nil : event
            }
        }
    }

    @MainActor
    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Devuelve `true` si el atajo fue consumido por el explorador, o `false` para propagar el evento.
    @MainActor
    private func handleKeyDown(
        keyCode: UInt16,
        characters: String?,
        typedCharacters: String?,
        rawModifiers: UInt,
        eventWindow: NSWindow?
    ) -> Bool {
        // Ignorar eventos destinados a otras pestañas del tabGroup, hojas modales, alertas o ventanas externas
        guard let hostWindow = hostWindowBox.window else {
            return false
        }
        let selectedInGroup = hostWindow.tabGroup?.selectedWindow ?? hostWindow
        guard selectedInGroup === hostWindow else {
            return false
        }
        if let activeWin = eventWindow ?? NSApp.keyWindow {
            let sameActiveTabGroup = (hostWindow.tabGroup != nil && activeWin.tabGroup === hostWindow.tabGroup)
            guard activeWin === hostWindow || sameActiveTabGroup else {
                return false
            }
        }

        // Si un NSTextView / TextField está editando texto activamente, solo interceptamos Escape
        let activeResponderWindow = selectedInGroup
        let isEditingText: Bool = {
            guard let firstResponder = activeResponderWindow.firstResponder ?? NSApp.keyWindow?.firstResponder else { return false }
            return firstResponder is NSTextView || firstResponder is NSText
        }()

        let flags = NSEvent.ModifierFlags(rawValue: rawModifiers)

        // Escape (keyCode 53)
        if keyCode == 53 {
            if viewModel.isQuickLookPresented {
                viewModel.closeQuickLook()
                return true
            }
            if viewModel.renamingItemID != nil {
                viewModel.cancelRename()
                KeyboardShortcuts.resignTextFocus(in: activeResponderWindow)
                return true
            }
            if viewModel.isEditingAddressBar {
                viewModel.cancelAddressBarEditing()
                KeyboardShortcuts.resignTextFocus(in: activeResponderWindow)
                return true
            }
            if isEditingText {
                if !viewModel.searchQuery.isEmpty {
                    viewModel.searchQuery = ""
                }
                KeyboardShortcuts.resignTextFocus(in: activeResponderWindow)
                return true
            }
            if viewModel.clipboardManager.activeMode == .cut {
                viewModel.clipboardManager.clear()
                return true
            }
            if !viewModel.selectedItemIDs.isEmpty {
                viewModel.clearSelection()
                return true
            }
            return false
        }

        // Si el usuario está escribiendo dentro de un TextField (búsqueda, ruta o renombrando), dejamos pasar las teclas
        if isEditingText {
            return false
        }

        let cleanFlags = flags.subtracting([.numericPad, .function, .capsLock])

        // Barra espaciadora (Spacebar, keyCode 49) sin modificadores -> Abrir/Cerrar Vista Rápida (Quick Look igual que Finder)
        if keyCode == 49 && cleanFlags.isEmpty {
            if viewModel.isQuickLookPresented || viewModel.quickLookItem != nil {
                viewModel.toggleQuickLook()
                return true
            }
        }

        // F2 (keyCode 120) o Enter/Return (keyCode 36 / 76) sin modificadores -> Renombrar en línea
        if (keyCode == 120 || keyCode == 36 || keyCode == 76) && cleanFlags.isEmpty {
            if viewModel.canRename && !viewModel.isQuickLookPresented {
                viewModel.beginRenamingSelectedItem()
                return true
            }
        }

        // Shift + Flechas Arriba / Izquierda -> Extender/ajustar selección hacia arriba/anterior
        if (keyCode == 126 || keyCode == 123) && cleanFlags == .shift {
            viewModel.extendSelection(offset: -1)
            return true
        }

        // Shift + Flechas Abajo / Derecha -> Extender/ajustar selección hacia abajo/siguiente
        if (keyCode == 125 || keyCode == 124) && cleanFlags == .shift {
            viewModel.extendSelection(offset: 1)
            return true
        }

        // Flechas Arriba / Izquierda sin modificadores -> Seleccionar elemento anterior (también actualiza Quick Look en vivo)
        if (keyCode == 126 || keyCode == 123) && cleanFlags.isEmpty {
            viewModel.selectAdjacentItem(offset: -1)
            return true
        }

        // Flechas Abajo / Derecha sin modificadores -> Seleccionar elemento siguiente (también actualiza Quick Look en vivo)
        if (keyCode == 125 || keyCode == 124) && cleanFlags.isEmpty {
            viewModel.selectAdjacentItem(offset: 1)
            return true
        }

        // Cmd + Down Arrow (keyCode 125) -> Abrir carpeta o archivo seleccionado (estándar macOS)
        if keyCode == 125 && flags.contains(.command) {
            if let firstSelected = viewModel.selectedItems.first {
                viewModel.openItem(firstSelected)
                return true
            }
        }

        // Alt/Option + Up Arrow o Cmd + Up Arrow (keyCode 126) -> Subir un nivel
        if keyCode == 126 && (flags.contains(.option) || flags.contains(.command)) {
            if viewModel.canGoUp {
                viewModel.goUp()
                return true
            }
        }

        // Alt/Option + Left Arrow, Cmd + Left Arrow o Cmd + [ (keyCode 123, US keyCode 33 o "[") -> Atrás
        if (keyCode == 123 && (flags.contains(.option) || flags.contains(.command)))
            || KeyboardShortcuts.matchesCommandBracket(
                targetBracket: "[",
                ansiKeyCode: 33,
                keyCode: keyCode,
                characters: characters,
                typedCharacters: typedCharacters,
                flags: flags
            ) {
            if viewModel.canGoBack {
                viewModel.goBack()
                return true
            }
        }

        // Alt/Option + Right Arrow, Cmd + Right Arrow o Cmd + ] (keyCode 124, US keyCode 30 o "]") -> Adelante
        if (keyCode == 124 && (flags.contains(.option) || flags.contains(.command)))
            || KeyboardShortcuts.matchesCommandBracket(
                targetBracket: "]",
                ansiKeyCode: 30,
                keyCode: keyCode,
                characters: characters,
                typedCharacters: typedCharacters,
                flags: flags
            ) {
            if viewModel.canGoForward {
                viewModel.goForward()
                return true
            }
        }

        // Cmd+Z / Cmd+Shift+Z -> Deshacer / Rehacer operaciones de archivos (eliminar, mover, pegar, renombrar, etc.)
        if characters == "z" || keyCode == 6 {
            let mainModifiers = flags.intersection([.shift, .command, .option, .control])
            if mainModifiers == .command {
                if viewModel.canUndo {
                    viewModel.undoLastOperation()
                    return true
                }
            } else if mainModifiers == [.command, .shift] {
                if viewModel.canRedo {
                    viewModel.redoLastOperation()
                    return true
                }
            }
        }

        // Delete / Backspace (keyCode 51) o Supr / Forward Delete (keyCode 117)
        if keyCode == 51 || keyCode == 117 {
            let mainModifiers = flags.intersection([.shift, .command, .option, .control])
            if mainModifiers == .shift {
                // Shift + Delete -> Borrar permanentemente sin pasar por la Papelera
                if viewModel.canDelete {
                    viewModel.requestPermanentDeleteSelectedItems()
                    return true
                }
            } else if mainModifiers.isEmpty || mainModifiers == .command {
                // Delete / Cmd+Delete -> Enviar a la Papelera
                if viewModel.canDelete {
                    viewModel.moveSelectedItemsToTrash()
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Eventos de Ratón (Botones Atrás / Adelante del Mouse)



    /// Lógica centralizada para manejar la navegación por botones de ratón (3 = Atrás, 4 = Adelante).
    @MainActor
    public static func handleMouseNavigation(
        buttonNumber: Int,
        eventType: NSEvent.EventType,
        viewModel: ExplorerViewModel,
        activeWindow: NSWindow? = nil
    ) -> Bool {
        guard buttonNumber >= 3 else {
            return false
        }

        let swap = PersistenceService.shared.loadSwapMouseButtons()
        let isBack: Bool
        let isForward: Bool

        if buttonNumber == 3 {
            isBack = !swap
            isForward = swap
        } else if buttonNumber == 4 || buttonNumber == 5 {
            isBack = swap
            isForward = !swap
        } else {
            return false
        }

        if eventType == .otherMouseDown {
            if viewModel.renamingItemID != nil {
                viewModel.cancelRename()
                if let activeWindow {
                    KeyboardShortcuts.resignTextFocus(in: activeWindow)
                }
            }
            if viewModel.isEditingAddressBar {
                viewModel.cancelAddressBarEditing()
                if let activeWindow {
                    KeyboardShortcuts.resignTextFocus(in: activeWindow)
                }
            }
            if isBack {
                if viewModel.canGoBack {
                    viewModel.goBack()
                }
            } else if isForward {
                if viewModel.canGoForward {
                    viewModel.goForward()
                }
            }
            return true
        } else if eventType == .otherMouseUp {
            return true
        }

        return false
    }
}

@MainActor
private final class WeakWindowBox {
    weak var window: NSWindow?
}

private struct HostWindowCaptureView: NSViewRepresentable {
    let box: WeakWindowBox
    let viewModel: ExplorerViewModel

    func makeNSView(context: Context) -> NSView {
        let view = CaptureNSView()
        view.box = box
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let capture = nsView as? CaptureNSView {
            capture.box = box
            capture.viewModel = viewModel
            capture.box?.window = capture.window
            if let window = capture.window {
                ExplorerWindowRegistry.shared.register(viewModel: viewModel, for: window)
            }
        }
    }

    private final class CaptureNSView: NSView {
        var box: WeakWindowBox?
        weak var viewModel: ExplorerViewModel?
        private var clearedWindowID: ObjectIdentifier?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
            guard let window else { return }
            if let viewModel {
                ExplorerWindowRegistry.shared.register(viewModel: viewModel, for: window)
            }
            let winID = ObjectIdentifier(window)
            if clearedWindowID != winID {
                clearedWindowID = winID
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window else { return }
                    if self.viewModel?.renamingItemID == nil && self.viewModel?.isEditingAddressBar != true {
                        KeyboardShortcuts.resignTextFocus(in: window)
                    }
                }
            }
        }
    }
}

extension View {
    /// Adjunta el monitor de teclado para atajos estilo Windows Explorer (`F2`, `Enter`, `Delete`, `Alt+Up`).
    public func explorerKeyboardShortcuts(viewModel: ExplorerViewModel) -> some View {
        modifier(ExplorerKeyEventMonitorModifier(viewModel: viewModel))
    }
}
