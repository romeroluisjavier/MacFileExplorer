import AppKit
import SwiftUI
import UniformTypeIdentifiers

public enum AltTabSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case shortcuts
    case appearance
    case excluded

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .shortcuts: return "keyboard"
        case .appearance: return "rectangle.grid.2x2"
        case .excluded: return "eye.slash"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .general: return loc.text(es: "General y Permisos", en: "General & Permissions")
        case .shortcuts: return loc.text(es: "Atajos", en: "Shortcuts")
        case .appearance: return loc.text(es: "Estilos y Vista Previa", en: "Styles & Preview")
        case .excluded: return loc.text(es: "Apps excluidas", en: "Excluded Apps")
        }
    }
}

/// Controlador singleton de la ventana nativa de Configuración de AltTab.
@MainActor
public final class AltTabSettingsWindowController {
    public static let shared = AltTabSettingsWindowController()

    private var window: NSWindow?

    private init() {}

    public func show(tab: AltTabSettingsTab = .general) {
        let loc = LocalizationManager.shared
        let title = loc.text(es: "Configuración de AltTab", en: "AltTab Settings")
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.title = title
            existing.contentView = NSHostingView(rootView: AltTabSettingsView(initialTab: tab))
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 610),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        created.title = title
        created.minSize = NSSize(width: 680, height: 520)
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.contentView = NSHostingView(rootView: AltTabSettingsView(initialTab: tab))
        created.center()
        created.makeKeyAndOrderFront(nil)
        self.window = created
    }

    public func refreshLocalizedTitle() {
        window?.title = LocalizationManager.shared.text(es: "Configuración de AltTab", en: "AltTab Settings")
    }
}

public struct AltTabSettingsView: View {
    @Bindable private var prefs = AltTabPreferences.shared
    @Bindable private var tracker = TaskbarWindowTracker.shared
    @Bindable private var thumbs = TaskbarThumbnailService.shared
    @Bindable private var hotkeyMonitor = AltTabHotkeyMonitor.shared
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var selectedTab: AltTabSettingsTab
    @ViewState private var recordingProfileID: UUID?
    @ViewState private var localKeyMonitor: Any?

    public init(initialTab: AltTabSettingsTab = .general) {
        _selectedTab = ViewState(initialValue: initialTab)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Barra lateral de pestañas
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AltTab")
                            .font(.system(size: 14, weight: .bold))
                        Text(prefs.isEnabled
                             ? loc.text(es: "Activo (\(prefs.primaryShortcutDisplay))", en: "Active (\(prefs.primaryShortcutDisplay))")
                             : loc.text(es: "Desactivado", en: "Disabled"))
                            .font(.system(size: 11))
                            .foregroundStyle(prefs.isEnabled ? Color.green : Color.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)

                Divider()
                    .padding(.bottom, 6)

                ForEach(AltTabSettingsTab.allCases) { tab in
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

                Button {
                    AltTabManager.shared.openInteractiveTestSwitcher()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                        Text(loc.text(es: "Probar selector", en: "Test Switcher"))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(width: 198)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general:
                        generalTabContent
                    case .shortcuts:
                        shortcutsTabContent
                    case .appearance:
                        appearanceTabContent
                    case .excluded:
                        excludedTabContent
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            tracker.checkAccessibilityPermission(prompt: false)
            thumbs.refreshPermissionStatus()
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    // MARK: - 1. General y Permisos

    private var generalTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Activación e inicio por defecto", en: "Activation & Launch Default")) {
                Toggle(isOn: Binding(
                    get: { prefs.isEnabled },
                    set: { AltTabManager.shared.setEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Activar AltTab ahora", en: "Enable AltTab Now"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(loc.text(
                            es: "Alterna entre ventanas individuales con vista previa, etiquetas de Space y atajos personalizables (comparte motor con Barra de tareas sin duplicar recursos).",
                            en: "Switch between individual windows with previews, Space badges, and custom shortcuts (shares engine with Taskbar with zero duplication)."
                        ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle(isOn: $prefs.startEnabledByDefault) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(
                            es: "Activar AltTab por defecto al abrir MacFileExplorer",
                            en: "Start with AltTab enabled by default when opening MacFileExplorer"
                        ))
                        .font(.system(size: 12.5, weight: .medium))
                        Text(loc.text(
                            es: "De fábrica viene desactivado. Activa esta opción si querés que AltTab se encienda automáticamente cada vez que abrís MacFileExplorer.",
                            en: "Off by default out of the box. Enable this to have AltTab active automatically every time you launch MacFileExplorer."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            sectionCard(title: loc.text(es: "Permisos y estado del monitor global", en: "Permissions & Global Hotkey Engine")) {
                permissionRow(
                    title: loc.text(es: "Accesibilidad y Monitor de Atajos (Requerido)", en: "Accessibility & Hotkey Monitor (Required)"),
                    subtitle: loc.text(
                        es: "Compartido con Barra de tareas: permite interceptar ⌥⇥ / ⌘⇥ y listar/enfocar ventanas en todos los Spaces.",
                        en: "Shared with Taskbar: intercepts ⌥⇥ / ⌘⇥ and lists/focuses windows across all Spaces."
                    ),
                    granted: tracker.isAccessibilityGranted && (!prefs.isEnabled || hotkeyMonitor.isTapActive),
                    actionTitle: loc.text(es: "Abrir Accesibilidad", en: "Open Accessibility")
                ) {
                    tracker.checkAccessibilityPermission(prompt: true)
                    tracker.openAccessibilitySettings()
                }

                Divider()

                permissionRow(
                    title: loc.text(es: "Grabación de pantalla (Opcional — Miniaturas y vista previa)", en: "Screen Recording (Optional — Thumbnails & Full Preview)"),
                    subtitle: loc.text(
                        es: "Compartido con Barra de tareas: habilita miniaturas en vivo y vista previa a tamaño completo.",
                        en: "Shared with Taskbar: enables live thumbnails and full-size window previews."
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
                        hotkeyMonitor.retryInstallationIfNeeded()
                    } label: {
                        Label(loc.text(es: "Comprobar estado", en: "Re-check Status"), systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }

            sectionCard(title: loc.text(es: "Controles rápidos dentro del selector", en: "Quick Controls Inside Switcher")) {
                VStack(alignment: .leading, spacing: 5) {
                    shortcutHintRow(keys: "⇥ / ⇧⇥ / ←→↑↓", desc: loc.text(es: "Navegar entre ventanas", en: "Navigate between windows"))
                    shortcutHintRow(keys: "W", desc: loc.text(es: "Cerrar la ventana seleccionada", en: "Close selected window"))
                    shortcutHintRow(keys: "M", desc: loc.text(es: "Minimizar o restaurar ventana", en: "Minimize or restore window"))
                    shortcutHintRow(keys: "H", desc: loc.text(es: "Ocultar o mostrar la aplicación", en: "Hide or show application"))
                    shortcutHintRow(keys: "Q", desc: loc.text(es: "Salir de la aplicación", en: "Quit application"))
                    shortcutHintRow(keys: "F", desc: loc.text(es: "Alternar pantalla completa", en: "Toggle full screen"))
                    shortcutHintRow(keys: "/", desc: loc.text(es: "Activar búsqueda en vivo por título o app", en: "Start live search by title or app"))
                    shortcutHintRow(keys: "Esc", desc: loc.text(es: "Cancelar sin cambiar de ventana", en: "Cancel without switching"))
                }
            }
        }
    }

    // MARK: - 2. Atajos Personalizables

    private var shortcutsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Preset rápido para el atajo principal", en: "Quick Preset for Primary Shortcut")) {
                HStack(spacing: 8) {
                    presetButton("⌥ ⇥ (Option + Tab)", isSelected: isPrimaryPreset(cmd: false, opt: true, ctrl: false)) {
                        prefs.setPrimaryShortcutPreset(command: false, option: true, control: false)
                    }
                    presetButton("⌘ ⇥ (Command + Tab)", isSelected: isPrimaryPreset(cmd: true, opt: false, ctrl: false)) {
                        prefs.setPrimaryShortcutPreset(command: true, option: false, control: false)
                    }
                    presetButton("⌃ ⇥ (Control + Tab)", isSelected: isPrimaryPreset(cmd: false, opt: false, ctrl: true)) {
                        prefs.setPrimaryShortcutPreset(command: false, option: false, control: true)
                    }
                }
                Text(loc.text(
                    es: "Si elegís ⌘ ⇥, AltTab reemplaza al selector nativo de macOS mientras esté encendido (al apagarlo vuelve el ⌘ ⇥ nativo).",
                    en: "If you pick ⌘ ⇥, AltTab replaces macOS's native switcher while enabled (disabling restores native ⌘ ⇥ immediately)."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            sectionCard(title: loc.text(
                es: "Perfiles de atajos configurables (\(prefs.shortcutProfiles.count)/\(AltTabPreferences.maxShortcutProfiles))",
                en: "Configurable Shortcut Profiles (\(prefs.shortcutProfiles.count)/\(AltTabPreferences.maxShortcutProfiles))"
            )) {
                ForEach(Array(prefs.shortcutProfiles.enumerated()), id: \.element.id) { index, profile in
                    profileEditorCard(index: index, profile: profile)
                    if index + 1 < prefs.shortcutProfiles.count {
                        Divider()
                    }
                }

                HStack {
                    Button {
                        prefs.addShortcutProfile()
                    } label: {
                        Label(loc.text(es: "Añadir otro atajo", en: "Add Shortcut Profile"), systemImage: "plus")
                    }
                    .disabled(prefs.shortcutProfiles.count >= AltTabPreferences.maxShortcutProfiles)

                    Spacer()

                    Button {
                        stopShortcutRecording()
                        prefs.resetShortcutsToDefaults()
                    } label: {
                        Label(loc.text(es: "Restablecer predeterminados", en: "Reset Defaults"), systemImage: "arrow.counterclockwise")
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func profileEditorCard(index: Int, profile: AltTabShortcutProfile) -> some View {
        let isRecordingThis = (recordingProfileID == profile.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("", isOn: bindingForProfile(index: index, keyPath: \.isEnabled))
                    .labelsHidden()

                TextField(
                    loc.text(es: "Nombre del atajo", en: "Shortcut name"),
                    text: bindingForProfile(index: index, keyPath: \.name)
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .semibold))

                Button {
                    if isRecordingThis {
                        stopShortcutRecording()
                    } else {
                        startShortcutRecording(for: profile.id)
                    }
                } label: {
                    Text(isRecordingThis
                         ? loc.text(es: "Pulsa combinación…", en: "Press keys…")
                         : profile.displayString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isRecordingThis ? Color.orange.opacity(0.22) : Color.accentColor.opacity(0.14))
                        )
                        .foregroundStyle(isRecordingThis ? Color.orange : Color.accentColor)
                }
                .buttonStyle(.plain)

                if prefs.shortcutProfiles.count > 1 {
                    Button(role: .destructive) {
                        if isRecordingThis { stopShortcutRecording() }
                        prefs.removeShortcutProfile(id: profile.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 10) {
                Picker(loc.text(es: "Apps:", en: "Apps:"), selection: bindingForProfile(index: index, keyPath: \.appsScope)) {
                    ForEach(AltTabWindowScopeApps.allCases) { scope in
                        Text(scope.localizedTitle(using: loc)).tag(scope)
                    }
                }
                .font(.system(size: 11.5))

                Picker(loc.text(es: "Espacios (Spaces):", en: "Spaces:"), selection: bindingForProfile(index: index, keyPath: \.spacesScope)) {
                    ForEach(AltTabWindowScopeSpaces.allCases) { scope in
                        Text(scope.localizedTitle(using: loc)).tag(scope)
                    }
                }
                .font(.system(size: 11.5))
            }

            HStack(spacing: 10) {
                Picker(loc.text(es: "Monitores:", en: "Displays:"), selection: bindingForProfile(index: index, keyPath: \.screensScope)) {
                    ForEach(AltTabWindowScopeScreens.allCases) { scope in
                        Text(scope.localizedTitle(using: loc)).tag(scope)
                    }
                }
                .font(.system(size: 11.5))

                Picker(loc.text(es: "Al soltar:", en: "On release:"), selection: bindingForProfile(index: index, keyPath: \.releaseBehavior)) {
                    ForEach(AltTabReleaseBehavior.allCases) { mode in
                        Text(mode.localizedTitle(using: loc)).tag(mode)
                    }
                }
                .font(.system(size: 11.5))
            }

            HStack(spacing: 18) {
                Toggle(loc.text(es: "Incluir minimizadas", en: "Include minimized"), isOn: bindingForProfile(index: index, keyPath: \.includeMinimized))
                    .font(.system(size: 11.5))
                Toggle(loc.text(es: "Incluir apps ocultas", en: "Include hidden apps"), isOn: bindingForProfile(index: index, keyPath: \.includeHidden))
                    .font(.system(size: 11.5))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 3. Estilos y Vista Previa

    private var appearanceTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: loc.text(es: "Estilo de visualización y tamaño", en: "Display Style & Sizing")) {
                Picker(loc.text(es: "Estilo del selector:", en: "Switcher Style:"), selection: $prefs.displayStyle) {
                    ForEach(AltTabDisplayStyle.allCases) { style in
                        Label(style.localizedTitle(using: loc), systemImage: style.systemImage).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(
                    loc.text(es: "Ajuste de tamaño automático según cantidad de ventanas", en: "Auto-size cards based on number of open windows"),
                    isOn: $prefs.autoSizeEnabled
                )

                if !prefs.autoSizeEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(loc.text(es: "Ancho manual de miniatura", en: "Manual Thumbnail Width"))
                            Spacer()
                            Text("\(Int(prefs.manualThumbnailWidth)) px")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $prefs.manualThumbnailWidth,
                            in: AltTabPreferences.minManualThumbnailWidth...AltTabPreferences.maxManualThumbnailWidth,
                            step: 8
                        )
                    }
                }

                Picker(loc.text(es: "Tema:", en: "Theme:"), selection: $prefs.themeMode) {
                    ForEach(TaskbarThemeMode.allCases) { mode in
                        Text(mode.localizedTitle(using: loc)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(loc.text(es: "Mostrar selector en:", en: "Show Switcher On:"), selection: $prefs.hudScreenMode) {
                    Text(AltTabWindowScopeScreens.activeMouseScreen.localizedTitle(using: loc))
                        .tag(AltTabWindowScopeScreens.activeMouseScreen)
                    Text(AltTabWindowScopeScreens.mainScreenOnly.localizedTitle(using: loc))
                        .tag(AltTabWindowScopeScreens.mainScreenOnly)
                }
            }

            sectionCard(title: loc.text(es: "Vista previa a tamaño completo y etiquetas", en: "Full-Size Preview & Badges")) {
                Toggle(
                    loc.text(es: "Mostrar vista previa a tamaño completo encima del resto", en: "Show full-size preview above other windows"),
                    isOn: $prefs.showFullSizePreview
                )

                if prefs.showFullSizePreview {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(loc.text(es: "Retardo antes de mostrar vista previa completa", en: "Delay before showing full preview"))
                            Spacer()
                            Text(prefs.fullSizePreviewDelayMs == 0
                                 ? loc.text(es: "Instantáneo (0 ms)", en: "Instant (0 ms)")
                                 : "\(Int(prefs.fullSizePreviewDelayMs)) ms")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $prefs.fullSizePreviewDelayMs,
                            in: AltTabPreferences.minPreviewDelayMs...AltTabPreferences.maxPreviewDelayMs,
                            step: 20
                        )
                    }
                }

                Divider()

                Toggle(
                    loc.text(es: "Mostrar barra de búsqueda siempre visible (siempre accesible con /)", en: "Always show search bar (always accessible via /)"),
                    isOn: $prefs.showSearchBar
                )
                Toggle(
                    loc.text(es: "Mostrar etiquetas de escritorio virtual (Space 2, Space 3…)", en: "Show virtual desktop Space badges (Space 2, Space 3…)"),
                    isOn: $prefs.showSpaceBadges
                )
                Toggle(
                    loc.text(es: "Mostrar etiquetas de estado (Minimizada, Oculta, Pantalla completa)", en: "Show window state badges (Minimized, Hidden, Full Screen)"),
                    isOn: $prefs.showWindowStateBadges
                )
                Toggle(
                    loc.text(es: "Mostrar botones rápidos al pasar el mouse (Cerrar / Minimizar / Completa)", en: "Show hover quick actions (Close / Minimize / Full Screen)"),
                    isOn: $prefs.showHoverQuickActions
                )
            }
        }
    }

    // MARK: - 4. Apps Excluidas

    private var excludedTabContent: some View {
        sectionCard(title: loc.text(es: "Aplicaciones excluidas de AltTab (\(prefs.excludedBundleIDs.count))", en: "Excluded Applications (\(prefs.excludedBundleIDs.count))")) {
            Text(loc.text(
                es: "Dejá fuera del selector máquinas virtuales, escritorios remotos o apps que prefieras ocultar.",
                en: "Keep virtual machines, remote desktops, or specific apps out of the switcher."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    chooseApplicationToExclude()
                } label: {
                    Label(loc.text(es: "Excluir aplicación…", en: "Exclude Application…"), systemImage: "plus")
                }

                Button {
                    prefs.importExcludedAppsFromTaskbar()
                } label: {
                    Label(loc.text(es: "Importar excluidas de Barra de tareas", en: "Import from Taskbar Exclusions"), systemImage: "square.and.arrow.down")
                }
                .disabled(TaskbarPreferences.shared.excludedBundleIDs.isEmpty)
            }

            if prefs.excludedBundleIDs.isEmpty {
                Text(loc.text(es: "Ninguna aplicación excluida.", en: "No applications excluded."))
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

    // MARK: - Grabador Interactivo de Atajos

    private func startShortcutRecording(for profileID: UUID) {
        stopShortcutRecording()
        recordingProfileID = profileID
        AltTabHotkeyMonitor.shared.isRecordingShortcut = true
        ToolsShortcutManager.shared.setRecordingSuspended(true)
        ClipboardHistoryManager.shared.setRecordingSuspended(true)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard self.recordingProfileID == profileID else { return false }

                if event.keyCode == 53 { // Escape cancela la grabación
                    self.stopShortcutRecording()
                    return true
                }

                // Ignorar teclas que sean solo modificadores
                let modifierOnlyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
                guard !modifierOnlyCodes.contains(event.keyCode) else { return true }

                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                guard !flags.isEmpty else { return true }

                let label = AltTabShortcutProfile.keyLabel(
                    for: event.keyCode,
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers
                )

                var updated = self.prefs.shortcutProfiles
                if let idx = updated.firstIndex(where: { $0.id == profileID }) {
                    updated[idx].triggerKeyCode = event.keyCode
                    updated[idx].triggerKeyLabel = label
                    updated[idx].holdCommand = flags.contains(.command)
                    updated[idx].holdOption = flags.contains(.option)
                    updated[idx].holdControl = flags.contains(.control)
                    updated[idx].holdShift = flags.contains(.shift)
                    self.prefs.shortcutProfiles = updated
                }
                self.stopShortcutRecording()
                return true
            }
            return consumed ? nil : event
        }
    }

    private func stopShortcutRecording() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        recordingProfileID = nil
        AltTabHotkeyMonitor.shared.isRecordingShortcut = false
        ToolsShortcutManager.shared.setRecordingSuspended(false)
        ClipboardHistoryManager.shared.setRecordingSuspended(false)
    }

    // MARK: - Helpers de UI y Bindings

    private func bindingForProfile<Value>(
        index: Int,
        keyPath: WritableKeyPath<AltTabShortcutProfile, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                guard index < prefs.shortcutProfiles.count else {
                    return AltTabShortcutProfile.makeDefaultProfiles()[0][keyPath: keyPath]
                }
                return prefs.shortcutProfiles[index][keyPath: keyPath]
            },
            set: { newValue in
                guard index < prefs.shortcutProfiles.count else { return }
                var copy = prefs.shortcutProfiles
                copy[index][keyPath: keyPath] = newValue
                prefs.shortcutProfiles = copy
            }
        )
    }

    private func isPrimaryPreset(cmd: Bool, opt: Bool, ctrl: Bool) -> Bool {
        guard let first = prefs.shortcutProfiles.first else { return false }
        return first.triggerKeyCode == 48 &&
            first.holdCommand == cmd &&
            first.holdOption == opt &&
            first.holdControl == ctrl &&
            !first.holdShift
    }

    private func presetButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

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
                Text(loc.text(es: "Activo", en: "Active"))
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

    private func shortcutHintRow(keys: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(width: 110, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(desc)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
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
