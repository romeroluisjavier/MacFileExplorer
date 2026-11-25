import AppKit
import SwiftUI
import UniformTypeIdentifiers

public enum TaskbarSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case displays
    case apps
    case dock

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .appearance: return "paintbrush"
        case .displays: return "display.2"
        case .apps: return "pin.square"
        case .dock: return "dock.rectangle"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .general: return loc.text(es: "General", en: "General")
        case .appearance: return loc.text(es: "Apariencia", en: "Appearance")
        case .displays: return loc.text(es: "Monitores y Espacios", en: "Displays & Spaces")
        case .apps: return loc.text(es: "Fijadas y Excluidas", en: "Pinned & Excluded")
        case .dock: return loc.text(es: "Dock de macOS", en: "macOS Dock")
        }
    }
}

/// Controlador singleton de la ventana nativa de Configuración de la Barra de tareas.
@MainActor
public final class TaskbarSettingsWindowController {
    public static let shared = TaskbarSettingsWindowController()

    private var window: NSWindow?

    private init() {}

    public func show(tab: TaskbarSettingsTab = .general) {
        let loc = LocalizationManager.shared
        let title = loc.text(es: "Configuración de la Barra de tareas", en: "Taskbar Settings")
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.title = title
            existing.contentView = NSHostingView(rootView: TaskbarSettingsView(initialTab: tab))
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 590),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        created.title = title
        created.minSize = NSSize(width: 660, height: 500)
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.contentView = NSHostingView(rootView: TaskbarSettingsView(initialTab: tab))
        created.center()
        created.makeKeyAndOrderFront(nil)
        self.window = created
    }
}

public struct TaskbarSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var prefs = TaskbarPreferences.shared
    @Bindable private var tracker = TaskbarWindowTracker.shared
    @Bindable private var thumbs = TaskbarThumbnailService.shared
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var selectedTab: TaskbarSettingsTab
    @ViewState private var dockFeedbackMessage: String?
    @ViewState private var sampleNotificationAppIcon: NSImage = TaskbarNotificationAnimationPreviewCard.samplePreviewAppIcon()

    public init(initialTab: TaskbarSettingsTab = .general) {
        _selectedTab = ViewState(initialValue: initialTab)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Barra lateral de pestañas
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "dock.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(loc.text(es: "Barra de tareas", en: "Taskbar"))
                            .font(.system(size: 13.5, weight: .bold))
                        Text(prefs.isEnabled
                             ? loc.text(es: "Activa", en: "Active")
                             : loc.text(es: "Desactivada", en: "Disabled"))
                            .font(.system(size: 11))
                            .foregroundStyle(prefs.isEnabled ? Color.green : Color.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)

                Divider()
                    .padding(.bottom, 6)

                ForEach(TaskbarSettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.systemImage)
                                .frame(width: 16)
                            Text(tab.localizedTitle(using: loc))
                                .font(.system(size: 12.5, weight: selectedTab == tab ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Acceso permanente de emergencia al Dock original en el pie de la barra lateral
                Button {
                    TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock()
                    dockFeedbackMessage = loc.text(
                        es: "Dock original de macOS restaurado.",
                        en: "Original macOS Dock restored."
                    )
                    selectedTab = .dock
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.orange)
                        Text(loc.text(es: "Restaurar Dock", en: "Restore Dock"))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(loc.text(
                    es: "Acción de emergencia: vuelve inmediatamente al Dock original de macOS",
                    en: "Emergency action: immediately restore the original macOS Dock"
                ))
            }
            .padding(10)
            .frame(width: 195)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Contenido de la pestaña seleccionada
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general:
                        generalTabContent
                    case .appearance:
                        appearanceTabContent
                    case .displays:
                        displaysTabContent
                    case .apps:
                        appsTabContent
                    case .dock:
                        dockTabContent
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            tracker.checkAccessibilityPermission(prompt: false)
            thumbs.refreshPermissionStatus()
            tracker.refreshConnectedScreens()
        }
    }

    // MARK: - 1. Pestaña General y Permisos

    private var generalTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Activación e inicio por defecto", en: "Activation & Startup Default")) {
                Toggle(isOn: Binding(
                    get: { prefs.isEnabled },
                    set: { TaskbarManager.shared.setEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Activar barra de tareas ahora", en: "Enable Taskbar Now"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(loc.text(
                            es: "Muestra la barra inferior con un botón por ventana, Menú Inicio y vistas previas.",
                            en: "Shows the bottom bar with one button per window, Start Menu, and hover previews."
                        ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle(isOn: $prefs.startEnabledByDefault) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(
                            es: "Activar barra de tareas por defecto al abrir MacFileExplorer",
                            en: "Start with Taskbar enabled by default when opening MacFileExplorer"
                        ))
                        .font(.system(size: 12.5, weight: .medium))
                        Text(loc.text(
                            es: "De fábrica viene desactivada para mantener intacto tu entorno. Activa esta opción si querés que se encienda automáticamente en cada inicio.",
                            en: "Disabled by default out of the box. Turn this on if you want the taskbar to launch automatically every time you open MacFileExplorer."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            sectionCard(title: loc.text(es: "Permisos de macOS", en: "macOS Permissions")) {
                permissionRow(
                    title: loc.text(es: "Accesibilidad (Requerido)", en: "Accessibility (Required)"),
                    subtitle: loc.text(
                        es: "Necesario para listar cada ventana, cambiar de foco, minimizar, cerrar y evitar superposiciones.",
                        en: "Required to list individual windows, focus, minimize, close, and avoid overlaps."
                    ),
                    granted: tracker.isAccessibilityGranted,
                    actionTitle: loc.text(es: "Abrir Accesibilidad", en: "Open Accessibility")
                ) {
                    tracker.checkAccessibilityPermission(prompt: true)
                    tracker.openAccessibilitySettings()
                }

                Divider()

                permissionRow(
                    title: loc.text(es: "Grabación de pantalla (Opcional)", en: "Screen Recording (Optional)"),
                    subtitle: loc.text(
                        es: "Solo se usa para mostrar miniaturas en vivo al pasar el mouse. Sin este permiso, todo lo demás funciona igual.",
                        en: "Used only for live hover thumbnails. Everything else works without granting it."
                    ),
                    granted: thumbs.hasScreenRecordingPermission,
                    actionTitle: loc.text(es: "Configurar", en: "Configure")
                ) {
                    thumbs.requestScreenRecordingPermission()
                }

                HStack {
                    Button {
                        tracker.checkAccessibilityPermission(prompt: false)
                        thumbs.refreshPermissionStatus()
                    } label: {
                        Label(loc.text(es: "Comprobar permisos", en: "Re-check Permissions"), systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }

                    Spacer()

                    Button {
                        TaskbarSetupWizardWindowController.shared.show()
                    } label: {
                        Label(loc.text(es: "Abrir asistente guiado…", en: "Open Setup Assistant…"), systemImage: "wand.and.stars")
                            .font(.system(size: 11.5))
                    }
                }
                .padding(.top, 4)
            }

            sectionCard(title: loc.text(es: "Comportamiento y controles de mouse", en: "Behavior & Mouse Controls")) {
                Picker(
                    loc.text(es: "Al volver a hacer clic en la ventana activa:", en: "Clicking the already focused window:"),
                    selection: $prefs.clickFocusedAction
                ) {
                    ForEach(TaskbarFocusedClickAction.allCases) { action in
                        Text(action.localizedTitle(using: loc)).tag(action)
                    }
                }

                Toggle(
                    loc.text(es: "Cerrar ventana con clic central (rueda del mouse)", en: "Middle-click button to close window"),
                    isOn: $prefs.middleClickClosesWindow
                )

                Toggle(
                    loc.text(es: "Mantener juntas las ventanas de una misma aplicación", en: "Group windows of the same application together"),
                    isOn: $prefs.groupWindowsByApp
                )

                Toggle(isOn: $prefs.showWindowlessRunningApps) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(
                            es: "Mostrar apps abiertas sin ventanas (como en el Dock de macOS)",
                            en: "Show running apps with no open windows (like macOS Dock)"
                        ))
                        Text(loc.text(
                            es: "Útil para apps como Visual Studio Code, Terminal o Numbers que siguen abiertas en segundo plano tras cerrar su última ventana. Al hacer clic se abre una ventana nueva.",
                            en: "Useful for apps like Visual Studio Code, Terminal, or Numbers that stay running after closing their last window. Clicking reopens a window."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }

                Toggle(
                    loc.text(es: "Redimensionar automáticamente ventanas que se superpongan con la barra", en: "Automatically resize windows that overlap the taskbar"),
                    isOn: $prefs.autoResizeOverlappingWindows
                )
            }
        }
    }

    // MARK: - 2. Pestaña Apariencia y Miniaturas

    private var appearanceTabContent: some View {
        let previewDark = (prefs.themeMode == .dark) || (prefs.themeMode == .system && colorScheme == .dark)
        let iconColumns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 10)]

        return VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Ícono del botón Inicio", en: "Start Button Icon")) {
                Text(loc.text(
                    es: "Elegí qué ícono mostrar a la izquierda de la barra de tareas para abrir el Menú Inicio. También podés cambiarlo haciendo clic derecho directo sobre el botón Inicio.",
                    en: "Choose which icon appears on the left side of the taskbar to open the Start Menu. You can also change it by right-clicking the Start button directly."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

                LazyVGrid(columns: iconColumns, spacing: 10) {
                    ForEach(TaskbarStartButtonIcon.allCases) { option in
                        let isSelected = prefs.startButtonIcon == option
                        Button {
                            prefs.startButtonIcon = option
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(previewDark ? Color(white: 0.14) : Color(white: 0.94))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(
                                                    previewDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                                                    lineWidth: 0.8
                                                )
                                        )
                                        .frame(width: 44, height: 44)

                                    TaskbarStartIconGraphicView(
                                        iconStyle: option,
                                        size: 28,
                                        effectiveDark: previewDark,
                                        isHighlighted: false
                                    )
                                }

                                Text(option.localizedTitle(using: loc))
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
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
                .padding(.top, 2)
            }

            sectionCard(title: loc.text(es: "Estilo y dimensiones de la barra", en: "Bar Style & Dimensions")) {
                Picker(loc.text(es: "Tema:", en: "Theme:"), selection: $prefs.themeMode) {
                    ForEach(TaskbarThemeMode.allCases) { mode in
                        Text(mode.localizedTitle(using: loc)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(loc.text(es: "Alineación de botones:", en: "Button Alignment:"), selection: $prefs.alignment) {
                    ForEach(TaskbarAlignment.allCases) { align in
                        Text(align.localizedTitle(using: loc)).tag(align)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(loc.text(es: "Altura de la barra", en: "Bar Height"))
                        Spacer()
                        Text("\(Int(prefs.barHeight)) px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $prefs.barHeight, in: TaskbarPreferences.minBarHeight...TaskbarPreferences.maxBarHeight, step: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(loc.text(es: "Tamaño de fuente", en: "Font Size"))
                        Spacer()
                        Text(String(format: "%.1f pt", prefs.fontSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $prefs.fontSize, in: TaskbarPreferences.minFontSize...TaskbarPreferences.maxFontSize, step: 0.5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(loc.text(es: "Opacidad / Transparencia", en: "Opacity / Transparency"))
                        Spacer()
                        Text("\(Int(prefs.opacity * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $prefs.opacity, in: TaskbarPreferences.minOpacity...TaskbarPreferences.maxOpacity, step: 0.05)
                }

                Divider()

                Toggle(
                    loc.text(es: "Mostrar títulos de ventanas (desactivar para mostrar solo íconos)", en: "Show window titles (turn off for icons only)"),
                    isOn: $prefs.showWindowTitles
                )

                Toggle(
                    loc.text(es: "Indicar visualmente ventanas minimizadas u ocultas", en: "Visually indicate minimized or hidden windows"),
                    isOn: $prefs.showMinimizedIndicator
                )
            }

            sectionCard(title: loc.text(es: "Notificaciones y animaciones", en: "Notifications & Animations")) {
                Toggle(
                    loc.text(es: "Mostrar globos rojos de notificaciones en íconos de apps (ej. Slack, Mail, WhatsApp)", en: "Show red notification badges on app icons (e.g. Slack, Mail, WhatsApp)"),
                    isOn: $prefs.showNotificationBadges
                )

                if prefs.showNotificationBadges {
                    Text(loc.text(
                        es: "Elegí la animación cuando una app tenga un globo rojo de notificación pendiente. Todas se previsualizan en vivo abajo:",
                        en: "Choose the animation shown when an app has an unread red notification badge. Preview each one live below:"
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                    TimelineView(.animation) { context in
                        LazyVGrid(columns: iconColumns, spacing: 10) {
                            ForEach(TaskbarNotificationAnimation.allCases) { option in
                                TaskbarNotificationAnimationPreviewCard(
                                    style: option,
                                    isSelected: prefs.notificationAnimation == option,
                                    previewDark: previewDark,
                                    sampleIcon: sampleNotificationAppIcon,
                                    timelineDate: context.date
                                ) {
                                    prefs.notificationAnimation = option
                                }
                            }
                        }
                    }
                    .padding(.top, 2)

                    if prefs.notificationAnimation != .none {
                        Divider()
                            .padding(.top, 4)

                        Picker(
                            loc.text(es: "Frecuencia de la animación:", en: "Animation Cadence:"),
                            selection: $prefs.notificationAnimationCadence
                        ) {
                            ForEach(TaskbarNotificationAnimationCadence.allCases) { cadence in
                                Text(cadence.localizedTitle(using: loc)).tag(cadence)
                            }
                        }

                        Text(loc.text(
                            es: "Al enfocarte en la ventana de la app, la animación se pausa automáticamente para no distraerte mientras lees.",
                            en: "When you focus the app window, the animation pauses automatically so it doesn't distract you while reading."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            sectionCard(title: loc.text(es: "Vista previa al pasar el cursor", en: "Hover Window Previews")) {
                Toggle(
                    loc.text(es: "Mostrar vista previa al posar el mouse sobre un botón", en: "Show preview when hovering a window button"),
                    isOn: $prefs.showHoverPreviews
                )

                if prefs.showHoverPreviews {
                    Picker(loc.text(es: "Tamaño de miniatura:", en: "Thumbnail Size:"), selection: $prefs.thumbnailSize) {
                        ForEach(TaskbarThumbnailSize.allCases) { size in
                            Text(size.localizedTitle(using: loc)).tag(size)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(loc.text(es: "Retardo antes de aparecer", en: "Hover Delay"))
                            Spacer()
                            Text("\(Int(prefs.hoverPreviewDelay * 1000)) ms")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $prefs.hoverPreviewDelay, in: TaskbarPreferences.minHoverDelay...TaskbarPreferences.maxHoverDelay, step: 0.05)
                    }

                    Toggle(
                        loc.text(es: "Mostrar título de la ventana en la miniatura", en: "Show window title inside thumbnail"),
                        isOn: $prefs.showTitleInThumbnail
                    )

                    Divider()
                        .padding(.top, 2)

                    Text(loc.text(
                        es: "Animación de aparición de la vista previa (previsualización en vivo):",
                        en: "Preview entrance animation (live preview):"
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                    TimelineView(.animation) { context in
                        LazyVGrid(columns: iconColumns, spacing: 10) {
                            ForEach(TaskbarHoverPreviewAnimation.allCases) { option in
                                TaskbarHoverPreviewAnimationCard(
                                    style: option,
                                    isSelected: prefs.hoverPreviewAnimation == option,
                                    previewDark: previewDark,
                                    timelineDate: context.date
                                ) {
                                    prefs.hoverPreviewAnimation = option
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }

            HStack {
                Spacer()
                Button {
                    prefs.resetVisualDefaults()
                } label: {
                    Label(loc.text(es: "Restablecer valores visuales", en: "Reset Visual Defaults"), systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    // MARK: - 3. Pestaña Monitores y Espacios

    private var displaysTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Soporte multimonitor (hasta 5 pantallas)", en: "Multi-Monitor Support (up to 5 displays)")) {
                Picker(loc.text(es: "Dónde mostrar la barra:", en: "Show Taskbar On:"), selection: $prefs.displayMode) {
                    ForEach(TaskbarDisplayMode.allCases) { mode in
                        Text(mode.localizedTitle(using: loc)).tag(mode)
                    }
                }

                Picker(loc.text(es: "Ventanas en cada barra:", en: "Windows Listed Per Bar:"), selection: $prefs.windowScopeMode) {
                    ForEach(TaskbarWindowScopeMode.allCases) { scope in
                        Text(scope.localizedTitle(using: loc)).tag(scope)
                    }
                }

                Text(loc.text(
                    es: "Tip: Si combinás «Solo pantalla principal» + «Todas las ventanas en cada barra», obtenés una sola barra unificada con todas tus ventanas de todos los monitores.",
                    en: "Tip: Combine 'Main Display Only' + 'All Windows on Every Bar' to get a single unified bar with every window across all monitors."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            sectionCard(title: loc.text(es: "Espacios (Spaces)", en: "Virtual Desktops (Spaces)")) {
                Toggle(
                    loc.text(es: "Sincronizar dinámicamente con el Espacio activo de macOS", en: "Dynamically sync with the active macOS Space"),
                    isOn: $prefs.syncWithActiveSpace
                )
            }

            sectionCard(title: loc.text(es: "Pantallas conectadas actualmente (\(tracker.connectedScreens.count))", en: "Connected Displays (\(tracker.connectedScreens.count))")) {
                ForEach(tracker.connectedScreens) { screen in
                    let isHidden = prefs.hiddenDisplayIDs.contains(screen.id)
                    HStack {
                        Image(systemName: screen.isMain ? "display" : "display.2")
                            .foregroundStyle(isHidden ? Color.secondary : Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(screen.localizedName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                if screen.isMain {
                                    Text(loc.text(es: "Principal", en: "Main"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Text("\(Int(screen.frameCocoa.width)) × \(Int(screen.frameCocoa.height))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(
                            loc.text(es: "Mostrar barra", en: "Show Bar"),
                            isOn: Binding(
                                get: { !isHidden },
                                set: { prefs.setDisplayHidden(!$0, displayID: screen.id) }
                            )
                        )
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }

                if !prefs.hiddenDisplayIDs.isEmpty {
                    Button {
                        prefs.showAllHiddenDisplays()
                    } label: {
                        Label(loc.text(es: "Mostrar todas las pantallas ocultas", en: "Show All Hidden Displays"), systemImage: "eye")
                            .font(.system(size: 11.5))
                    }
                }
            }
        }
    }

    // MARK: - 4. Pestaña Apps Fijadas y Excluidas

    private var appsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Aplicaciones fijadas en la barra (\(prefs.pinnedApps.count))", en: "Pinned Taskbar Apps (\(prefs.pinnedApps.count))")) {
                HStack(spacing: 8) {
                    Button {
                        chooseApplicationToPin()
                    } label: {
                        Label(loc.text(es: "Añadir aplicación…", en: "Add Application…"), systemImage: "plus")
                    }

                    Button {
                        let dockApps = TaskbarAppCatalogService.shared.readCurrentMacOSDockApps()
                        for app in dockApps {
                            prefs.pinApp(bundleIdentifier: app.bundleIdentifier, bundleURL: app.bundleURL, displayName: app.displayName)
                        }
                    } label: {
                        Label(loc.text(es: "Importar desde el Dock", en: "Import from Dock"), systemImage: "square.and.arrow.down")
                    }
                }

                if prefs.pinnedApps.isEmpty {
                    Text(loc.text(es: "No hay aplicaciones fijadas.", en: "No pinned applications."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(prefs.pinnedApps.enumerated()), id: \.element.id) { index, pinned in
                            HStack(spacing: 8) {
                                Image(nsImage: TaskbarAppCatalogService.shared.icon(forAppAt: pinned.bundleURL))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(pinned.displayName)
                                    .font(.system(size: 12.5))
                                Spacer()
                                Button {
                                    if index > 0 {
                                        prefs.movePinnedApp(sourceID: pinned.id, toTargetID: prefs.pinnedApps[index - 1].id)
                                    }
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)

                                Button {
                                    if index + 1 < prefs.pinnedApps.count {
                                        prefs.movePinnedApp(sourceID: pinned.id, toTargetID: prefs.pinnedApps[index + 1].id)
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index + 1 >= prefs.pinnedApps.count)

                                Button(role: .destructive) {
                                    prefs.unpinApp(bundleIdentifier: pinned.bundleIdentifier, bundlePath: pinned.bundlePath)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            sectionCard(title: loc.text(es: "Aplicaciones excluidas de la barra (\(prefs.excludedBundleIDs.count))", en: "Excluded Applications (\(prefs.excludedBundleIDs.count))")) {
                Text(loc.text(
                    es: "Las apps listadas aquí no aparecerán como botones en la barra de tareas.",
                    en: "Apps listed here will never show buttons on the taskbar."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

                Button {
                    chooseApplicationToExclude()
                } label: {
                    Label(loc.text(es: "Excluir aplicación…", en: "Exclude Application…"), systemImage: "eye.slash")
                }

                if prefs.excludedBundleIDs.isEmpty {
                    Text(loc.text(es: "Ninguna aplicación de usuario excluida.", en: "No user applications excluded."))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(prefs.excludedBundleIDs, id: \.self) { bundleID in
                            HStack {
                                Image(nsImage: TaskbarAppCatalogService.shared.icon(forBundleIdentifier: bundleID, fallbackURL: nil))
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Text(bundleID)
                                    .font(.system(size: 12))
                                Spacer()
                                Button {
                                    prefs.removeExcludedApp(bundleIdentifier: bundleID)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Pestaña Gestión del Dock de macOS + Emergencia

    private var dockTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Gestión opcional del Dock nativo de macOS", en: "Optional macOS Dock Management")) {
                Text(loc.text(
                    es: "El Dock original de macOS permanece siempre activo y sin cambios por defecto. Solo se modifica si elegís explícitamente otra opción aquí abajo.",
                    en: "The original macOS Dock stays active and unchanged by default. It is only modified if you explicitly choose another option below."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(TaskbarDockMode.allCases) { mode in
                        Button {
                            TaskbarDockManager.shared.applyUserSelectedDockMode(mode)
                            dockFeedbackMessage = loc.text(
                                es: "Modo del Dock aplicado: \(mode.localizedTitle(using: loc))",
                                en: "Dock mode applied: \(mode.localizedTitle(using: loc))"
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: prefs.dockMode == mode ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(prefs.dockMode == mode ? Color.accentColor : Color.secondary)
                                Image(systemName: mode.systemImage)
                                    .frame(width: 18)
                                    .foregroundStyle(Color.accentColor)
                                Text(mode.localizedTitle(using: loc))
                                    .font(.system(size: 12.5, weight: prefs.dockMode == mode ? .semibold : .regular))
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(prefs.dockMode == mode ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Bloque destacado de Restauración de Emergencia del Dock original
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                    Text(loc.text(
                        es: "Emergencia: Volver al Dock original de macOS",
                        en: "Emergency: Return to Original macOS Dock"
                    ))
                    .font(.system(size: 13.5, weight: .bold))
                }

                Text(loc.text(
                    es: "Si en cualquier momento querés recuperar el Dock original de macOS inmediatamente (incluso con la barra de tareas apagada), usá cualquiera de estos dos botones.",
                    en: "If at any moment you want your original macOS Dock back immediately (even while Taskbar is off), use either button below."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock(forceFactoryDefaults: false)
                        dockFeedbackMessage = loc.text(
                            es: "Dock restaurado a tu configuración original guardada.",
                            en: "Dock restored to your saved original configuration."
                        )
                    } label: {
                        Label(
                            loc.text(es: "Restaurar mi Dock original", en: "Restore My Original Dock"),
                            systemImage: "arrow.uturn.backward.circle.fill"
                        )
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock(forceFactoryDefaults: true)
                        dockFeedbackMessage = loc.text(
                            es: "Dock restablecido a los valores de fábrica de macOS (abajo y visible).",
                            en: "Dock reset to macOS factory defaults (bottom and visible)."
                        )
                    } label: {
                        Label(
                            loc.text(es: "Forzar Dock de fábrica (Abajo y visible)", en: "Force Factory Dock (Bottom & Visible)"),
                            systemImage: "dock.rectangle"
                        )
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }

                if let dockFeedbackMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(dockFeedbackMessage)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers de UI

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text(loc.text(es: "Concedido", en: "Granted"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func chooseApplicationToPin() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier ?? ""
            let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
                .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive, .anchored, .backwards])
            prefs.pinApp(bundleIdentifier: bundleID, bundleURL: url, displayName: name)
        }
    }

    private func chooseApplicationToExclude() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty {
                prefs.excludeApp(bundleIdentifier: bundleID)
            }
        }
    }
}
