import AppKit
import SwiftUI

// MARK: - Pestañas de Configuración de Notch

public enum NotchSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case displays
    case sources
    case calendar

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .appearance: return "sparkles"
        case .displays: return "macbook.gen2"
        case .sources: return "music.note.house"
        case .calendar: return "calendar.badge.clock"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .general: return loc.text(es: "General", en: "General")
        case .appearance: return loc.text(es: "Apariencia y Animaciones", en: "Appearance & Animations")
        case .displays: return loc.text(es: "Pantallas y Visibilidad", en: "Displays & Visibility")
        case .sources: return loc.text(es: "Fuentes y YouTube Music", en: "Sources & YouTube Music")
        case .calendar: return loc.text(es: "Calendario y Meet", en: "Calendar & Meet")
        }
    }
}

// MARK: - Controlador Singleton de la Ventana de Configuración de Notch

/// Controlador nativo de la ventana **Notch Settings / Configuración de Notch**.
/// Libera el árbol SwiftUI (`contentView = nil`) al cerrarse para mantener 0% CPU en reposo.
@MainActor
public final class NotchSettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = NotchSettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show(tab: NotchSettingsTab = .general) {
        let loc = LocalizationManager.shared
        let title = loc.text(es: "Configuración de Notch", en: "Notch Settings")
        NSApplication.shared.activate(ignoringOtherApps: true)

        NotchManager.shared.refreshDisplayGeometries()
        NotchLyricsAndAudioService.shared.refreshOutputDevices()

        if let existing = window {
            existing.title = title
            existing.contentView = NSHostingView(rootView: NotchSettingsView(initialTab: tab))
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 630),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        created.delegate = self
        created.title = title
        created.minSize = NSSize(width: 700, height: 540)
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.contentView = NSHostingView(rootView: NotchSettingsView(initialTab: tab))
        created.center()
        created.makeKeyAndOrderFront(nil)
        self.window = created
    }

    public func refreshLocalizedTitle() {
        window?.title = LocalizationManager.shared.text(es: "Configuración de Notch", en: "Notch Settings")
    }

    public func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
    }
}

// MARK: - Vista Principal de Configuración de Notch

public struct NotchSettingsView: View {
    @Bindable private var prefs = NotchPreferences.shared
    @Bindable private var media = NotchMediaService.shared
    @Bindable private var manager = NotchManager.shared
    @Bindable private var lyricsAudio = NotchLyricsAndAudioService.shared
    @Bindable private var musicDecoy = NotchMusicDecoyService.shared
    @Bindable private var calService = NotchCalendarService.shared
    @Bindable private var googleAccounts = GoogleAccountsManager.shared
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var selectedTab: NotchSettingsTab
    @ViewState private var previewMode: NotchSettingsPreviewMode = .expanded
    @ViewState private var previewFeedback: NotchTransientFeedback = .none
    @ViewState private var previewSqueeze: Bool = false
    @ViewState private var previewNudgeX: CGFloat = 0
    @ViewState private var previewFeedbackTask: Task<Void, Never>?
    @ViewState private var portInputText: String = ""

    public init(initialTab: NotchSettingsTab = .general) {
        _selectedTab = ViewState(initialValue: initialTab)
        _portInputText = ViewState(initialValue: String(NotchPreferences.shared.youtubeMusicAPIPort))
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 214)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case .general:
                        generalTabContent
                    case .appearance:
                        appearanceTabContent
                    case .displays:
                        displaysTabContent
                    case .sources:
                        sourcesTabContent
                    case .calendar:
                        calendarTabContent
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            portInputText = String(prefs.youtubeMusicAPIPort)
            manager.refreshDisplayGeometries()
            lyricsAudio.refreshOutputDevices()
            musicDecoy.refreshStatus()
        }
    }

    // MARK: - Barra Lateral

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.black, Color(red: 0.16, green: 0.14, blue: 0.24)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 1.0, green: 0.36, blue: 0.48)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Notch")
                        .font(.system(size: 14, weight: .bold))
                    Text(
                        prefs.isEnabled
                            ? (media.isDemoMode
                                ? loc.text(es: "Activo (Demo)", en: "Active (Demo)")
                                : loc.text(es: "Activo", en: "Active"))
                            : loc.text(es: "Desactivado", en: "Disabled")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(prefs.isEnabled ? Color.green : Color.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)

            Divider()
                .padding(.bottom, 6)

            ForEach(NotchSettingsTab.allCases) { tab in
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
                    .padding(.vertical, 7.5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            Divider()
                .padding(.horizontal, 10)

            VStack(spacing: 8) {
                Button {
                    manager.toggleDemoPreviewAndReveal()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: media.isDemoMode ? "stop.circle.fill" : "sparkles")
                        Text(
                            media.isDemoMode
                                ? loc.text(es: "Detener Demo", en: "Stop Live Demo")
                                : loc.text(es: "Probar vista previa (Demo)", en: "Test Live Demo")
                        )
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(media.isDemoMode ? .orange : .accentColor)

                Button {
                    prefs.resetDefaults()
                    portInputText = String(prefs.youtubeMusicAPIPort)
                } label: {
                    Text(loc.text(es: "Restablecer valores", en: "Reset Defaults"))
                        .font(.system(size: 11.5))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
        }
    }

    // MARK: - Pestaña 1: General + Vista Previa Interactiva

    private var generalTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: loc.text(es: "Reproductor Notch", en: "Notch Now Playing"),
                subtitle: loc.text(
                    es: "Controla tu música desde la muesca superior con animaciones fluidas, brillo de carátula y letras sincronizadas.",
                    en: "Control your music right from the top notch with fluid animations, ambient album glow, and synced lyrics."
                )
            )

            // Tarjeta de Vista Previa Interactiva en Vivo
            NotchSettingsInteractivePreviewCard(
                previewMode: $previewMode,
                previewFeedback: previewFeedback,
                previewSqueeze: previewSqueeze,
                previewNudgeX: previewNudgeX,
                prefs: prefs,
                media: media,
                loc: loc
            )

            settingsCard(title: loc.text(es: "Activación e Inicio", en: "Activation & Startup")) {
                Toggle(
                    isOn: Binding(
                        get: { prefs.isEnabled },
                        set: { manager.setEnabled($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Activar Notch (Reproductor de música)", en: "Enable Notch (Now Playing)"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(
                            loc.text(
                                es: "Muestra la píldora musical orgánica en la parte superior de la pantalla sin robar el foco.",
                                en: "Displays the organic music pill at the top of your screen without stealing window focus."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle(isOn: $prefs.startEnabledByDefault) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Activar por defecto al iniciar MacFileExplorer", en: "Enable by Default on Launch"))
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            loc.text(
                                es: "Si está desactivado, Notch inicia apagado hasta que lo enciendas desde el menú superior.",
                                en: "When off, Notch stays off on launch until enabled from the top Notch menu."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            musicDecoySettingsCard

            settingsCard(title: loc.text(es: "Interacción y Gestos", en: "Interaction & Gestures")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Modo de expansión", en: "Expand Trigger"))
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            loc.text(
                                es: "Elige si el panel se despliega al pasar el cursor o únicamente al hacer clic.",
                                en: "Choose whether the panel expands on hover or only when clicked."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $prefs.expandTrigger) {
                        ForEach(NotchExpandTrigger.allCases) { mode in
                            Text(mode.localizedTitle(using: loc)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                if prefs.expandTrigger == .hoverAndClick {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(loc.text(es: "Retardo al pasar el cursor", en: "Hover Expand Delay"))
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Text(String(format: "%.2f s", prefs.hoverExpandDelay))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $prefs.hoverExpandDelay,
                            in: NotchPreferences.minHoverExpandDelay...NotchPreferences.maxHoverExpandDelay,
                            step: 0.02
                        )
                    }
                }

                Divider()

                Toggle(isOn: $prefs.enableSwipeToSkip) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Deslizar horizontalmente para cambiar de canción", en: "Swipe Left/Right to Skip Track"))
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            loc.text(
                                es: "Desliza con dos dedos en el trackpad sobre la píldora colapsada para pasar a la pista anterior o siguiente.",
                                en: "Two-finger swipe horizontally over the collapsed pill to jump to the previous or next track."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Pestaña 2: Apariencia y Animaciones

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { prefs.customAccentColor.swiftUIColor },
            set: { newColor in
                let nsColor = NSColor(newColor)
                prefs.customAccentColor = NotchRGBColor(nsColor: nsColor)
            }
        )
    }

    private var animationSpeedLabel: String {
        let s = prefs.animationSpeed
        if s <= 0.7 {
            return String(format: "%.1f× · %@", s, loc.text(es: "Lenta", en: "Slow"))
        } else if s >= 1.65 {
            return String(format: "%.1f× · %@", s, loc.text(es: "Turbo", en: "Turbo"))
        } else if s >= 1.25 {
            return String(format: "%.1f× · %@", s, loc.text(es: "Rápida", en: "Fast"))
        }
        return String(format: "%.1f× · %@", s, loc.text(es: "Normal", en: "Normal"))
    }

    private var appearanceTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: loc.text(es: "Apariencia y Animaciones", en: "Appearance & Animations"),
                subtitle: loc.text(
                    es: "Personaliza colores, tipo y velocidad de animaciones, visualizador, tapa y nombre de álbum, opacidad y letras.",
                    en: "Customize accent colors, animation style & speed, visualizer, album cover & name, backdrop opacity, and lyrics."
                )
            )

            // Vista previa interactiva en vivo para ver cada cambio al instante
            NotchSettingsInteractivePreviewCard(
                previewMode: $previewMode,
                previewFeedback: previewFeedback,
                previewSqueeze: previewSqueeze,
                previewNudgeX: previewNudgeX,
                prefs: prefs,
                media: media,
                loc: loc
            )

            // Tarjeta 1: Color y Fondo (#1 Color de acento, #7 Intensidad brillo, #8 Opacidad fondo)
            settingsCard(title: loc.text(es: "Color y Fondo", en: "Color & Backdrop")) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Color de acento", en: "Accent Color"))
                            .font(.system(size: 13, weight: .medium))
                        Text(loc.text(es: "Tiñe el brillo ambiental, el ecualizador y la barra de progreso.", en: "Tints the ambient glow, equalizer, and progress bar."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Picker("", selection: $prefs.accentColorMode) {
                        ForEach(NotchAccentColorMode.allCases) { mode in
                            Text(mode.localizedTitle(using: loc)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)

                    if prefs.accentColorMode == .custom {
                        HStack(spacing: 10) {
                            ForEach(NotchRGBColor.presetPalette, id: \.id) { swatch in
                                let isSelected = abs(prefs.customAccentColor.r - swatch.color.r) < 0.03 &&
                                    abs(prefs.customAccentColor.g - swatch.color.g) < 0.03 &&
                                    abs(prefs.customAccentColor.b - swatch.color.b) < 0.03
                                Button {
                                    prefs.customAccentColor = swatch.color
                                } label: {
                                    Circle()
                                        .fill(swatch.color.swiftUIColor)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.22), lineWidth: isSelected ? 2.2 : 0.9)
                                        )
                                        .scaleEffect(isSelected ? 1.12 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .help(loc.text(es: swatch.nameES, en: swatch.nameEN))
                            }

                            Spacer(minLength: 6)

                            ColorPicker(
                                loc.text(es: "Otro color", en: "Custom"),
                                selection: customColorBinding,
                                supportsOpacity: false
                            )
                            .font(.system(size: 11.5, weight: .medium))
                            .fixedSize()
                        }
                        .padding(.top, 2)
                    }
                }

                Divider()

                Toggle(loc.text(es: "Brillo radial ambiental según el color activo", en: "Ambient Radial Glow"), isOn: $prefs.showAmbientArtworkGlow)

                if prefs.showAmbientArtworkGlow {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(loc.text(es: "Intensidad del brillo ambiental", en: "Ambient Glow Intensity"))
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Text("\(Int((prefs.ambientGlowIntensity * 100).rounded()))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $prefs.ambientGlowIntensity,
                            in: NotchPreferences.minAmbientGlowIntensity...NotchPreferences.maxAmbientGlowIntensity,
                            step: 0.05
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(loc.text(es: "Opacidad del fondo del Notch", en: "Notch Background Opacity"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "100% negro OLED puro para fundirse con el bisel; valores menores aplican vidrio oscuro translúcido.", en: "100% pure OLED black blends into the bezel; lower values add frosted dark glass."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int((prefs.backgroundOpacity * 100).rounded()))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $prefs.backgroundOpacity,
                        in: NotchPreferences.minBackgroundOpacity...NotchPreferences.maxBackgroundOpacity,
                        step: 0.02
                    )
                }
            }

            // Tarjeta 2: Animaciones y Visualizador (#2 Tipo animación, #3 Velocidad, #6 Estilo visualizador)
            settingsCard(title: loc.text(es: "Animaciones y Visualizador", en: "Animations & Visualizer")) {
                Toggle(loc.text(es: "Animaciones fluidas en transiciones y controles", en: "Fluid Animations for Transitions & Controls"), isOn: $prefs.enableAnimations)

                if prefs.enableAnimations {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.text(es: "Tipo de animación", en: "Animation Style"))
                                    .font(.system(size: 13, weight: .medium))
                                Text(prefs.animationStyle.localizedDescription(using: loc))
                                    .font(.system(size: 11.2))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $prefs.animationStyle) {
                                ForEach(NotchAnimationStyle.allCases) { style in
                                    Text(style.localizedTitle(using: loc)).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 268)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(loc.text(es: "Velocidad de las animaciones", en: "Animation Speed"))
                                    .font(.system(size: 12.5, weight: .medium))
                                Text(loc.text(es: "Controla la rapidez de expansión, ecualizador y texto deslizante.", en: "Controls expansion speed, equalizer motion, and scrolling text."))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(animationSpeedLabel)
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }
                        Slider(
                            value: $prefs.animationSpeed,
                            in: NotchPreferences.minAnimationSpeed...NotchPreferences.maxAnimationSpeed,
                            step: 0.1
                        )
                    }
                }

                Divider()

                Toggle(loc.text(es: "Mostrar ecualizador musical animado", en: "Show Animated Music Visualizer"), isOn: $prefs.showVisualizerBars)

                if prefs.showVisualizerBars {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Estilo del visualizador", en: "Visualizer Style"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Elige cómo se mueve el ritmo junto a la canción.", en: "Pick how the live audio animation moves."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.visualizerStyle) {
                            ForEach(NotchVisualizerStyle.allCases) { style in
                                Text(style.localizedTitle(using: loc)).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 268)
                    }
                }
            }

            // Tarjeta 2B: Avisos y Animaciones al Cambiar de Tema y al Pausar (5 formas cada uno)
            settingsCard(title: loc.text(es: "Cambio de Tema y Pausa", en: "Track Change & Pause Animations")) {
                HStack(alignment: .center, spacing: 10) {
                    Toggle(isOn: $prefs.announceNewTracks) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Animar el Notch cuando cambia de canción", en: "Animate Notch When Track Changes"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(loc.text(
                                es: "Actívalo o desactívalo cuando quieras y elige entre 5 formas visuales distintas.",
                                en: "Turn this on or off anytime and pick from 5 distinct visual notification styles."
                            ))
                            .font(.system(size: 11.2))
                            .foregroundStyle(.secondary)
                        }
                    }

                    if prefs.announceNewTracks {
                        Button {
                            triggerSettingsTrackChangePreview(style: prefs.trackChangeStyle)
                        } label: {
                            Label(loc.text(es: "Probar", en: "Preview"), systemImage: "play.circle")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if prefs.announceNewTracks {
                    VStack(spacing: 6) {
                        ForEach(NotchTrackChangeStyle.allCases) { style in
                            let selected = prefs.trackChangeStyle == style
                            Button {
                                prefs.trackChangeStyle = style
                                triggerSettingsTrackChangePreview(style: style)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(selected ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.06))
                                        Image(systemName: style.symbolName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                    }
                                    .frame(width: 28, height: 28)

                                    VStack(alignment: .leading, spacing: 1.5) {
                                        Text(style.localizedTitle(using: loc))
                                            .font(.system(size: 12.2, weight: selected ? .semibold : .medium))
                                            .foregroundStyle(.primary)
                                        Text(style.localizedDescription(using: loc))
                                            .font(.system(size: 10.8))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 6)

                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08), lineWidth: selected ? 1.3 : 0.7)
                                        )
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                Toggle(isOn: $prefs.showPauseIconWhenPaused) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Cambiar ondas por símbolo de pausa («⏸») al pausar", en: "Swap Waves for Pause Symbol (\"⏸\") When Paused"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(loc.text(
                            es: "Cuando la música se detiene, reemplaza las ondas musicales por el ícono de pausa hasta que vuelvas a reproducir.",
                            en: "Replaces the equalizer waves with a crisp pause icon while music is paused."
                        ))
                        .font(.system(size: 11.2))
                        .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(alignment: .center, spacing: 10) {
                    Toggle(isOn: $prefs.animateOnPause) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Animar el Notch al pausar la música", en: "Animate Notch When Pausing"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(loc.text(
                                es: "Muestra una pequeña animación seleccionable en el Notch al poner pausa.",
                                en: "Plays a subtle selectable animation on the Notch whenever playback is paused."
                            ))
                            .font(.system(size: 11.2))
                            .foregroundStyle(.secondary)
                        }
                    }

                    if prefs.animateOnPause {
                        Button {
                            triggerSettingsPausePreview(style: prefs.pauseAnimationStyle)
                        } label: {
                            Label(loc.text(es: "Probar", en: "Preview"), systemImage: "pause.circle")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if prefs.animateOnPause {
                    VStack(spacing: 6) {
                        ForEach(NotchPauseAnimationStyle.allCases) { style in
                            let selected = prefs.pauseAnimationStyle == style
                            Button {
                                prefs.pauseAnimationStyle = style
                                triggerSettingsPausePreview(style: style)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(selected ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.06))
                                        Image(systemName: style.symbolName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                    }
                                    .frame(width: 28, height: 28)

                                    VStack(alignment: .leading, spacing: 1.5) {
                                        Text(style.localizedTitle(using: loc))
                                            .font(.system(size: 12.2, weight: selected ? .semibold : .medium))
                                            .foregroundStyle(.primary)
                                        Text(style.localizedDescription(using: loc))
                                            .font(.system(size: 10.8))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 6)

                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08), lineWidth: selected ? 1.3 : 0.7)
                                        )
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Tarjeta 3: Carátula, Álbum y Tamaño (#4 Ver tapa de álbum, #5 Ver nombre de álbum, #9 Insignia app)
            settingsCard(title: loc.text(es: "Tapa del Álbum, Metadatos y Tamaño", en: "Album Cover, Metadata & Size")) {
                Toggle(isOn: $prefs.showAlbumArtwork) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Mostrar tapa del álbum (carátula)", en: "Show Album Cover Artwork"))
                            .font(.system(size: 13, weight: .medium))
                        Text(loc.text(es: "Desactívalo para un aspecto minimalista solo con ícono de fuente y controles.", en: "Turn off for a minimalist layout with just the source icon and controls."))
                            .font(.system(size: 11.2))
                            .foregroundStyle(.secondary)
                    }
                }

                if prefs.showAlbumArtwork {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(loc.text(es: "Estilo de carátula en píldora colapsada", en: "Collapsed Pill Artwork Style"))
                            .font(.system(size: 12.5, weight: .semibold))

                        HStack(spacing: 12) {
                            ForEach(NotchArtworkStyle.allCases) { style in
                                let selected = prefs.artworkStyle == style
                                Button {
                                    prefs.artworkStyle = style
                                } label: {
                                    HStack(spacing: 10) {
                                        NotchAlbumArtBadgeView(
                                            artworkImage: media.currentArtworkImage,
                                            trackID: "settings-preview-\(style.rawValue)",
                                            accentColor: prefs.resolvedAccentColor(for: media.currentTrack),
                                            progress: 0.68,
                                            style: style,
                                            size: 32,
                                            isPlaying: true,
                                            enableAnimations: false,
                                            showProgressRing: style == .circleWithRing
                                        )
                                        .padding(4)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(style.localizedShortTitle(using: loc))
                                                .font(.system(size: 12.5, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(
                                                style == .circleWithRing
                                                    ? loc.text(es: "Con anillo de progreso en vivo", en: "With live progress ring")
                                                    : loc.text(es: "Estilo Dynamic Island", en: "Dynamic Island style")
                                            )
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 1.5 : 0.8)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    Toggle(isOn: $prefs.showSourceBadgeOnArtwork) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Mostrar insignia de la app musical sobre la carátula", en: "Show Music App Badge on Album Cover"))
                                .font(.system(size: 13, weight: .medium))
                            Text(loc.text(es: "Muestra el pequeño ícono de YouTube Music, Spotify o Apple Music en la esquina de la tapa.", en: "Displays the small YouTube Music, Spotify, or Apple Music badge in the corner of the cover."))
                                .font(.system(size: 11.2))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                Toggle(isOn: $prefs.showAlbumName) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Mostrar nombre del álbum", en: "Show Album Name"))
                            .font(.system(size: 13, weight: .medium))
                        Text(loc.text(es: "Muestra el nombre del álbum junto al artista cuando la canción incluye ese dato.", en: "Displays the album name alongside the artist whenever provided by the player."))
                            .font(.system(size: 11.2))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Tamaño del Notch", en: "Notch Pill Size"))
                            .font(.system(size: 13, weight: .medium))
                        Text(loc.text(es: "Ajusta la amplitud de las alas y del panel expandido.", en: "Adjusts wing spacing and expanded player dimensions."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $prefs.pillSize) {
                        ForEach(NotchPillSize.allCases) { size in
                            Text(size.localizedTitle(using: loc)).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }

            // Tarjeta 4: Texto y Letras Sincronizadas (#10 Tamaño de texto en letras)
            settingsCard(title: loc.text(es: "Texto y Letras Sincronizadas", en: "Text & Synced Lyrics")) {
                Toggle(loc.text(es: "Mostrar título en la píldora colapsada", en: "Show Track Title in Collapsed Pill"), isOn: $prefs.showTrackTitleInCollapsedPill)
                Divider()
                Toggle(loc.text(es: "Desplazamiento suave (Marquee) en títulos largos", en: "Smooth Marquee Scrolling for Long Titles"), isOn: $prefs.enableMarqueeTitle)
                Divider()
                Toggle(loc.text(es: "Habilitar letras sincronizadas en vivo (LRCLIB)", en: "Enable Live Synced Lyrics (LRCLIB)"), isOn: $prefs.showSyncedLyrics)

                if prefs.showSyncedLyrics {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Tamaño de texto en letras", en: "Lyrics Font Size"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Ajusta el tamaño de las letras tipo karaoke para leer más cómodo.", en: "Adjusts synced karaoke lyrics size for comfortable reading."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.lyricsFontSize) {
                            ForEach(NotchLyricsFontSize.allCases) { size in
                                Text(size.localizedTitle(using: loc)).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                }
            }
        }
    }

    // MARK: - Pestaña 3: Pantallas y Visibilidad

    private var displaysTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: loc.text(es: "Pantallas y Visibilidad", en: "Displays & Visibility"),
                subtitle: loc.text(
                    es: "Controla en qué monitores aparece Notch y cuándo debe ocultarse automáticamente.",
                    en: "Choose which displays host Notch and when it automatically hides."
                )
            )

            settingsCard(title: loc.text(es: "Monitores", en: "Displays")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Modo de pantalla", en: "Display Mode"))
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            loc.text(
                                es: "Las pantallas con notch usan curvas cóncavas; los monitores externos usan modo Isla Dinámica flotante.",
                                en: "Notched displays use concave bezel curves; external displays use Floating Island mode."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $prefs.displayMode) {
                        ForEach(NotchDisplayMode.allCases) { mode in
                            Text(mode.localizedTitle(using: loc)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.text(es: "Monitores detectados", en: "Detected Displays"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(manager.connectedDisplays, id: \.displayID) { geo in
                        HStack(spacing: 10) {
                            Image(systemName: geo.hasHardwareNotch ? "laptopcomputer" : "display")
                                .font(.system(size: 15))
                                .foregroundStyle(geo.hasHardwareNotch ? Color.accentColor : Color.secondary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(geo.localizedName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("\(Int(geo.screenFrame.width)) × \(Int(geo.screenFrame.height))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(
                                geo.hasHardwareNotch
                                    ? loc.text(es: "Notch físico (\(Int(geo.physicalNotchWidth))×\(Int(geo.physicalNotchHeight)) pt)", en: "Hardware Notch (\(Int(geo.physicalNotchWidth))×\(Int(geo.physicalNotchHeight)) pt)")
                                    : loc.text(es: "Isla Dinámica flotante", en: "Floating Dynamic Island")
                            )
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(geo.hasHardwareNotch ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(geo.hasHardwareNotch ? Color.accentColor : Color.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            settingsCard(title: loc.text(es: "Ocultamiento Inteligente", en: "Smart Auto-Hide")) {
                Toggle(isOn: $prefs.hideInFullScreen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Ocultar en aplicaciones a pantalla completa", en: "Hide in Full-Screen Apps"))
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            loc.text(
                                es: "Evita superponerse sobre videos, presentaciones o juegos en pantalla completa.",
                                en: "Automatically hides during full-screen videos, presentations, or games."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle(isOn: $prefs.hideWhenPaused) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Ocultar automáticamente al pausar", en: "Auto-Hide When Paused"))
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            loc.text(
                                es: "Contrae la píldora si la música permanece pausada durante el tiempo elegido.",
                                en: "Hides the pill after music stays paused for the selected duration."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }

                if prefs.hideWhenPaused {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(loc.text(es: "Esperar antes de ocultar", en: "Hide Delay"))
                                .font(.system(size: 12.5))
                            Spacer()
                            Text("\(Int(prefs.hideWhenPausedDelay)) s")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $prefs.hideWhenPausedDelay,
                            in: NotchPreferences.minHideWhenPausedDelay...NotchPreferences.maxHideWhenPausedDelay,
                            step: 5
                        )
                    }
                    .padding(.top, 4)
                }
            }

            settingsCard(title: loc.text(es: "Salida de Audio Activa", en: "Active Audio Output")) {
                HStack(spacing: 10) {
                    Image(systemName: lyricsAudio.defaultOutputDevice?.systemImage ?? "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lyricsAudio.defaultOutputDevice?.name ?? loc.text(es: "Predeterminado del sistema", en: "System Default"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(
                            loc.text(
                                es: "Puedes cambiar de salida en 1 clic directamente desde el icono de altavoz dentro del Notch.",
                                en: "Switch audio output in 1 click directly from the speaker icon inside the expanded Notch."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Pestaña 4: Fuentes y YouTube Music

    private var sourcesTabContent: some View {
        let status = media.connectionStatus

        return VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: loc.text(es: "Fuentes Multimedia y YouTube Music", en: "Media Sources & YouTube Music"),
                subtitle: loc.text(
                    es: "Compatible con YouTube Music (app de escritorio, PWA y navegador), Spotify y Apple Music sin abrir apps cerradas.",
                    en: "Works with YouTube Music (Desktop app, Chrome PWA, and browsers), Spotify, and Apple Music without launching closed apps."
                )
            )

            settingsCard(title: loc.text(es: "Estado de Conexión en Vivo", en: "Live Connection Status")) {
                VStack(spacing: 10) {
                    connectionStatusRow(
                        icon: "play.circle.fill",
                        tint: NotchMediaSource.youtubeMusic.swiftUIAccentColor,
                        title: "YouTube Music Desktop API",
                        detail: status.isYTMDesktopAPIReachable
                            ? loc.text(es: "Conectado en puerto \(prefs.youtubeMusicAPIPort) (control completo y scrubber)", en: "Connected on port \(prefs.youtubeMusicAPIPort) (full control & scrubber)")
                            : loc.text(es: "No detectado en 127.0.0.1:\(prefs.youtubeMusicAPIPort)", en: "Not detected on 127.0.0.1:\(prefs.youtubeMusicAPIPort)"),
                        isOnline: status.isYTMDesktopAPIReachable
                    )

                    Divider()

                    connectionStatusRow(
                        icon: "globe",
                        tint: Color.blue,
                        title: loc.text(es: "YouTube Music en Chrome / PWA / Safari", en: "YouTube Music in Chrome / PWA / Safari"),
                        detail: (status.isYouTubeMusicPWARunning || status.isChromeRunning || status.isSafariRunning)
                            ? loc.text(es: "Navegador/PWA en ejecución (detección automática + carátula)", en: "Browser/PWA running (automatic detection + artwork)")
                            : loc.text(es: "Abre YouTube Music en Chrome, PWA o Safari para detectar canciones", en: "Open YouTube Music in Chrome, PWA, or Safari to detect tracks"),
                        isOnline: status.isYouTubeMusicPWARunning || status.isChromeRunning || status.isSafariRunning
                    )

                    Divider()

                    connectionStatusRow(
                        icon: "dot.radiowaves.left.and.right",
                        tint: NotchMediaSource.spotify.swiftUIAccentColor,
                        title: "Spotify",
                        detail: status.isSpotifyRunning
                            ? loc.text(es: "Spotify abierto (scrubber, carátula y controles completos)", en: "Spotify running (scrubber, artwork & full controls)")
                            : loc.text(es: "Cerrado (no se abrirá automáticamente)", en: "Not running (will never be auto-launched)"),
                        isOnline: status.isSpotifyRunning
                    )

                    Divider()

                    connectionStatusRow(
                        icon: "music.note",
                        tint: NotchMediaSource.appleMusic.swiftUIAccentColor,
                        title: "Apple Music",
                        detail: status.isAppleMusicRunning
                            ? loc.text(es: "Apple Music abierto (scrubber y controles completos)", en: "Apple Music running (scrubber & full controls)")
                            : (prefs.blockAppleMusicAutoLaunch && musicDecoy.isDecoyRunning
                                ? loc.text(es: "Bloqueado con Music Decoy (0% CPU · no se abrirá al presionar ▶ Play)", en: "Blocked via Music Decoy (0% CPU · won't auto-launch on ▶ Play)")
                                : loc.text(es: "Cerrado (no se abrirá automáticamente)", en: "Not running (will never be auto-launched)")),
                        isOnline: status.isAppleMusicRunning
                    )

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Motor activo actual", en: "Current Active Backend"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(status.activeBackendName.isEmpty ? loc.text(es: "En espera", en: "Idle") : status.activeBackendName)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            media.refreshNow()
                        } label: {
                            Label(loc.text(es: "Detectar ahora", en: "Refresh Now"), systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            settingsCard(title: loc.text(es: "API Local de YouTube Music Desktop", en: "YouTube Music Desktop Local API")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(loc.text(es: "Puerto API local:", en: "Local API Port:"))
                            .font(.system(size: 13, weight: .medium))

                        TextField("26538", text: $portInputText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 92)
                            .onSubmit { commitPortInput() }
                            .onChange(of: portInputText) { _, newValue in
                                if let parsed = Int(newValue.trimmingCharacters(in: .whitespaces)),
                                   parsed >= NotchPreferences.minYouTubeMusicAPIPort,
                                   parsed <= NotchPreferences.maxYouTubeMusicAPIPort {
                                    prefs.youtubeMusicAPIPort = parsed
                                }
                            }

                        Button(loc.text(es: "Puerto por defecto (26538)", en: "Default (26538)")) {
                            prefs.youtubeMusicAPIPort = NotchPreferences.defaultYouTubeMusicAPIPort
                            portInputText = String(NotchPreferences.defaultYouTubeMusicAPIPort)
                            media.refreshNow()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(
                        loc.text(
                            es: "Consejo: Si usas la app de escritorio YouTube Music (th-ch / Pear Desktop), activa el plugin «API Server» en el puerto 26538 para tener barra de progreso interactiva, Me gusta, Aleatorio y Repetir en tiempo real. Si usas YouTube Music en Chrome o PWA, funciona automáticamente sin configurar nada.",
                            en: "Tip: If you use the YouTube Music desktop app (th-ch / Pear Desktop), enable its \"API Server\" plugin on port 26538 for live seeking, Like, Shuffle, and Repeat. If you use YouTube Music in Chrome or as a Chrome PWA, detection and media controls work automatically."
                        )
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            musicDecoySettingsCard
        }
    }

    // MARK: - Pestaña 5: Calendario (Google Calendar) y Alertas de Meet (10+ Configuraciones)

    private var calendarTabContent: some View {
        let authAccounts = googleAccounts.accounts.filter { $0.isAuthenticated }

        return VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: loc.text(es: "Google Calendar y Alertas de Meet", en: "Google Calendar & Meet Alerts"),
                subtitle: loc.text(
                    es: "Mostrá tu agenda con formato Google Calendar (diario o semanal), abrí eventos en Chrome y recibí avisos con botón directo «Unirse a Meet» incluso mientras suena música.",
                    en: "Display your schedule in Google Calendar style (daily or weekly), open events in Chrome, and get live Meet alerts with a 1-click \"Join Meet\" button even while music plays."
                )
            )

            // Tarjeta 1: Activación, Fuente, Cuenta, Diario/Semanal, Formato y Navegador (Configs 1–5)
            settingsCard(title: loc.text(es: "Calendario, Formato y Apertura", en: "Calendar, Format & Opening")) {
                // Config 1: Activar Calendario en el Notch
                Toggle(isOn: $prefs.calendarEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Mostrar Calendario y avisos de Meet en el Notch", en: "Show Calendar & Meet Alerts in Notch"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(loc.text(
                            es: "Agrega el botón de Google Calendar en la barra del Notch y activa alertas antes de tus reuniones.",
                            en: "Adds the Google Calendar control to the Notch top bar and enables pre-meeting alerts."
                        ))
                        .font(.system(size: 11.3))
                        .foregroundStyle(.secondary)
                    }
                }

                if prefs.calendarEnabled {
                    Divider()

                    // Config 2: Elegir fuente de calendario (Google Calendar / macOS / Ambos)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Calendario a mostrar", en: "Calendar Source"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Usa tu cuenta de Gmail ya logueada en MacFileExplorer o el Calendario de macOS.",
                                en: "Uses your Gmail account signed into MacFileExplorer or native macOS Calendar."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarSource) {
                            ForEach(NotchCalendarSourceMode.allCases) { mode in
                                Text(mode.localizedTitle(using: loc)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    if prefs.calendarSource == .googleCalendar || prefs.calendarSource == .both {
                        HStack {
                            Text(loc.text(es: "Cuenta de Google Calendar", en: "Google Calendar Account"))
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            if authAccounts.isEmpty {
                                Button(loc.text(es: "Conectar cuenta Gmail…", en: "Sign in to Gmail…")) {
                                    googleAccounts.startAddGoogleAccount()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Picker("", selection: $prefs.calendarSelectedGoogleAccountID) {
                                    Text(loc.text(es: "Todas las cuentas (\(authAccounts.count))", en: "All Accounts (\(authAccounts.count))")).tag("")
                                    ForEach(authAccounts) { acc in
                                        Text(acc.displayLabel).tag(acc.id.uuidString)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 220)
                            }
                        }
                    }

                    if (prefs.calendarSource == .macOSCalendar || prefs.calendarSource == .both) && !calService.eventKitAuthorized {
                        HStack {
                            Text(loc.text(es: "Permiso de Calendario de macOS requerido", en: "macOS Calendar permission required"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.orange)
                            Spacer()
                            Button(loc.text(es: "Permitir acceso", en: "Grant Access")) {
                                calService.requestMacOSCalendarPermission()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    // Config 3: Vista Diario o Semanal
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Rango de agenda", en: "Schedule Range"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Elegí si querés ver solo hoy (diario) o los próximos 7 días (semanal).", en: "Choose today only (daily) or the next 7 days (weekly)."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarRangeMode) {
                            ForEach(NotchCalendarRangeMode.allCases) { mode in
                                Text(mode.localizedTitle(using: loc)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    Divider()

                    // Config 4: Formato visual estilo Google Calendar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Formato visual estilo Google Calendar", en: "Google Calendar Display Format"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Tarjetas con barra de color, línea de tiempo por hora o lista compacta.", en: "Color-striped agenda cards, hourly timeline, or compact list."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarDisplayFormat) {
                            ForEach(NotchCalendarDisplayFormat.allCases) { fmt in
                                Text(fmt.localizedTitle(using: loc)).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 270)
                    }

                    Divider()

                    // Config 5: Dónde abrir al hacer clic (Google Chrome por defecto)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Al hacer clic en Google Calendar o Meet", en: "When Clicking Google Calendar or Meet"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Por defecto abre Google Calendar y los links de Meet directamente en Google Chrome.", en: "Opens Google Calendar and Meet links directly in Google Chrome by default."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarOpenTarget) {
                            ForEach(NotchCalendarOpenTarget.allCases) { target in
                                Text(target.localizedTitle(using: loc)).tag(target)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }
            }

            if prefs.calendarEnabled {
                // Tarjeta 2: Ícono del Calendario en el Notch (5 configs de estilo/tamaño/posición) + Colores de eventos y Meets
                settingsCard(title: loc.text(es: "Ícono en la Barra del Notch y Colores de Eventos", en: "Notch Bar Calendar Icon & Event Colors")) {
                    // Config 11: Estilo del ícono en el Notch (incluye Cápsula igual a "YouTube Music")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Estilo del botón de Calendario", en: "Calendar Button Style"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Elegí entre botón circular, cápsula igual a «YouTube Music», mosaico con fecha o cápsula con próxima hora.",
                                en: "Choose circle icon, pill matching \"YouTube Music\", date badge tile, or pill with next event time."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarIconStyle) {
                            ForEach(NotchCalendarIconStyle.allCases) { style in
                                Text(style.localizedTitle(using: loc)).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    Divider()

                    // Config 12: Posición del botón en la barra superior del Notch
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Posición en la barra del Notch", en: "Position in Notch Top Bar"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Ubicalo junto a «YouTube Music», en el centro, antes del ecualizador o junto al botón cerrar.",
                                en: "Place it beside \"YouTube Music\", centered, before Equalizer, or next to Close."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarIconPosition) {
                            ForEach(NotchCalendarIconPosition.allCases) { pos in
                                Text(pos.localizedTitle(using: loc)).tag(pos)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    Divider()

                    // Config 13: Tamaño del botón / cápsula
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Tamaño del ícono / cápsula", en: "Icon / Pill Size"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Mediano coincide exactamente con el tamaño de la cápsula de «YouTube Music».",
                                en: "Medium matches the exact height and proportions of the \"YouTube Music\" pill."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarIconSize) {
                            ForEach(NotchCalendarIconSize.allCases) { sz in
                                Text(sz.localizedTitle(using: loc)).tag(sz)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }

                    Divider()

                    // Config 14: Mostrar insignia / contador de eventos pendientes
                    Toggle(isOn: $prefs.calendarIconShowEventBadge) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Mostrar contador de eventos de hoy en el ícono", en: "Show Today's Event Counter Badge on Icon"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Agrega una mini insignia con la cantidad de eventos restantes del día (o punto activo si hay una Meet).",
                                en: "Adds a small badge showing remaining events today (or an active dot when a Meet is starting)."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Config 15: Mostrar número del día actual en el ícono
                    Toggle(isOn: $prefs.calendarIconShowDayNumber) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Mostrar número del día actual en el ícono", en: "Show Current Day Number Inside Icon"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Muestra el número de hoy (ej. \(Calendar.current.component(.day, from: Date()))) en lugar del ícono genérico de calendario.",
                                en: "Displays today's day number (e.g. \(Calendar.current.component(.day, from: Date()))) instead of the generic calendar symbol."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Config 16: Usar los mismos colores de eventos y Meets configurados en Google Calendar / macOS
                    Toggle(isOn: $prefs.calendarUseNativeEventColors) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Usar los mismos colores de eventos y Meets de tu calendario", en: "Use Native Event & Meet Colors From Your Calendar"))
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(loc.text(
                                es: "Aplica en tarjetas, avisos y botones «Unirse a Meet» el color real que configuraste en Google Calendar / macOS (si lo desactivás, usa azul estándar y verde Meet).",
                                en: "Applies your actual Google Calendar / macOS event colors to cards, Meet alerts, and Join buttons (when off, uses uniform blue and Meet green)."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // Tarjeta 3: Notificaciones de Meet (Configs 6–9)
                settingsCard(title: loc.text(es: "Notificaciones y Alertas de Meet", en: "Meet Notifications & Alerts")) {
                    // Config 6: Anticipación del aviso
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Avisar antes de iniciar la reunión", en: "Alert Before Meeting Starts"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Cuándo mostrar la alerta de Meet en la parte superior del Notch.", en: "How early to alert you in the Notch before a meeting starts."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarAlertLeadMinutes) {
                            Text(loc.text(es: "1 min antes", en: "1 min before")).tag(1)
                            Text(loc.text(es: "2 min antes", en: "2 min before")).tag(2)
                            Text(loc.text(es: "5 min antes", en: "5 min before")).tag(5)
                            Text(loc.text(es: "10 min antes", en: "10 min before")).tag(10)
                            Text(loc.text(es: "15 min antes", en: "15 min before")).tag(15)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }

                    Divider()

                    // Config 7: Sonido de notificación ON/OFF + selector de sonido
                    HStack {
                        Toggle(loc.text(es: "Reproducir sonido al avisar una Meet", en: "Play Sound on Meet Alert"), isOn: $prefs.calendarAlertSoundEnabled)
                            .font(.system(size: 12.5, weight: .medium))

                        Spacer()

                        if prefs.calendarAlertSoundEnabled {
                            Picker("", selection: $prefs.calendarAlertSound) {
                                ForEach(NotchCalendarAlertSound.allCases) { s in
                                    Text(s.displayName).tag(s)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)

                            Button {
                                calService.playAlertSound(prefs.calendarAlertSound)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(loc.text(es: "Escuchar sonido", en: "Preview sound"))
                        }
                    }

                    Divider()

                    // Config 8: Animación superior en el Notch al avisar Meet
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Animación superior en el Notch", en: "Top Notch Alert Animation"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Cómo se anima la muesca cuando está por comenzar una videollamada.", en: "How the top notch animates when a video call is about to start."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarAlertAnimationStyle) {
                            ForEach(NotchCalendarAlertAnimationStyle.allCases) { style in
                                Text(style.localizedTitle(using: loc)).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    Divider()

                    // Config 9: Link directo a «Unirse a Meet» en el Notch + botón de prueba en vivo
                    HStack {
                        Toggle(isOn: $prefs.calendarShowDirectJoinMeetButton) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.text(es: "Botón directo «Unirse a Meet» en el Notch", en: "Direct \"Join Meet\" Button in Notch"))
                                    .font(.system(size: 12.5, weight: .medium))
                                Text(loc.text(es: "Muestra el botón verde de 1 clic para entrar a Google Meet o Zoom sin buscar el enlace.", en: "Shows a 1-click green button to join Google Meet or Zoom directly."))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            if !prefs.isEnabled { manager.setEnabled(true) }
                            calService.triggerTestMeetingAlert()
                        } label: {
                            Label(loc.text(es: "Probar alerta Meet", en: "Test Meet Alert"), systemImage: "video.badge.waveform")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }
                }

                // Tarjeta 3: Convivencia con Música y Filtros (Configs 10–12)
                settingsCard(title: loc.text(es: "Convivencia con Música y Filtros", en: "Music Coexistence & Filters")) {
                    // Config 10: Prioridad cuando hay música reproduciendo
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Cuando hay música reproduciéndose", en: "When Music Is Playing"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: "Define cómo convive el aviso de Meet con tu reproductor musical.", en: "Controls how Meet alerts appear alongside your music player."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.calendarMusicCoexistenceMode) {
                            ForEach(NotchCalendarMusicCoexistenceMode.allCases) { mode in
                                Text(mode.localizedTitle(using: loc)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }

                    Divider()

                    Toggle(loc.text(es: "Mostrar Calendario automáticamente cuando no suena música", en: "Show Calendar Automatically When No Music Is Playing"), isOn: $prefs.calendarShowWhenMusicIdle)
                        .font(.system(size: 12.5))

                    Divider()

                    Toggle(loc.text(es: "Ocultar eventos de todo el día (feriados / recordatorios)", en: "Hide All-Day Events (Holidays / Reminders)"), isOn: $prefs.calendarHideAllDayEvents)
                        .font(.system(size: 12.5))

                    Divider()

                    HStack {
                        Text(
                            loc.text(
                                es: "Eventos cargados: \(calService.visibleEvents.count)",
                                en: "Loaded events: \(calService.visibleEvents.count)"
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            calService.refreshNow()
                        } label: {
                            Label(loc.text(es: "Sincronizar ahora", en: "Sync Now"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Tarjeta Tecla ▶ Play y Bloqueador de Apple Music (Music Decoy · 0% CPU)

    private var musicDecoySettingsCard: some View {
        let detectedApps = musicDecoy.availableRedirectApps()
        let playKeySelection = Binding<String>(
            get: { musicDecoy.currentPlayKeySelectionTag },
            set: { newTag in
                musicDecoy.applyPlayKeyTargetSelection(newTag)
            }
        )

        return settingsCard(
            title: loc.text(
                es: "Tecla ▶ Play y Reproductor por Defecto (Bloquear Apple Music)",
                en: "▶ Play Key & Default Music Player (Block Apple Music)"
            )
        ) {
            // 1. Selector principal siempre visible: qué hacer cuando presionás ▶ Play sin nada abierto
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            loc.text(
                                es: "Al presionar ▶ Play sin ningún reproductor abierto",
                                en: "When pressing ▶ Play with nothing open"
                            )
                        )
                        .font(.system(size: 13, weight: .semibold))
                        Text(
                            loc.text(
                                es: "Elegí tu reproductor favorito (por ejemplo YouTube Music) o bloqueá la apertura automática de Apple Music sin consumir CPU.",
                                en: "Pick your preferred music player (such as YouTube Music) or block Apple Music from opening automatically at 0% CPU."
                            )
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if prefs.blockAppleMusicAutoLaunch {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(musicDecoy.isDecoyRunning ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(
                                musicDecoy.isDecoyRunning
                                    ? loc.text(es: "Activo · 0% CPU", en: "Active · 0% CPU")
                                    : loc.text(es: "Iniciando…", en: "Starting…")
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(musicDecoy.isDecoyRunning ? Color.green : Color.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill((musicDecoy.isDecoyRunning ? Color.green : Color.orange).opacity(0.13))
                        )
                        .fixedSize()
                    }
                }

                HStack(spacing: 8) {
                    Picker("", selection: playKeySelection) {
                        Text(loc.text(es: "Apple Music (comportamiento de macOS)", en: "Apple Music (macOS Default)"))
                            .tag(NotchMusicDecoyService.systemAppleMusicSelectionTag)
                        Text(loc.text(es: "No abrir nada (solo bloquear Apple Music)", en: "Do nothing (just block Apple Music)"))
                            .tag("")
                        Divider()
                        ForEach(detectedApps) { option in
                            Text(option.name).tag(option.path)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)

                    Button(loc.text(es: "Elegir otra app…", en: "Choose App…")) {
                        if let chosen = musicDecoy.chooseCustomRedirectApp() {
                            musicDecoy.applyPlayKeyTargetSelection(chosen)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if prefs.blockAppleMusicAutoLaunch && !prefs.musicDecoyRedirectAppPath.isEmpty {
                        Button {
                            musicDecoy.testConfiguredRedirectApp()
                        } label: {
                            Label(loc.text(es: "Probar", en: "Test"), systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(loc.text(es: "Abrir ahora el reproductor elegido para verificar", en: "Launch the selected player now to verify"))
                    }
                }
            }

            Divider()

            // 2. Interruptor directo de bloqueo (sincronizado con el selector de arriba)
            Toggle(isOn: $prefs.blockAppleMusicAutoLaunch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        loc.text(
                            es: "Evitar que macOS abra Apple Music automáticamente",
                            en: "Prevent macOS from Auto-Launching Apple Music"
                        )
                    )
                    .font(.system(size: 12.5, weight: .medium))
                    Text(
                        loc.text(
                            es: "Funciona tanto con la tecla ▶ Play del teclado como al conectar auriculares Bluetooth (estilo Music Decoy).",
                            en: "Works both for the keyboard ▶ Play key and when connecting Bluetooth headphones (Music Decoy style)."
                        )
                    )
                    .font(.system(size: 11.2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if prefs.blockAppleMusicAutoLaunch && musicDecoy.isRealAppleMusicRunning {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(
                        loc.text(
                            es: "Apple Music está abierto en este momento. Cerralo para que el bloqueador tome el control de la tecla ▶ Play.",
                            en: "Apple Music is currently open. Quit it so the blocker takes over the ▶ Play key."
                        )
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(loc.text(es: "Cerrar Apple Music", en: "Quit Apple Music")) {
                        musicDecoy.quitRealAppleMusicAndActivateDecoy()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
            }

            if let errorMsg = musicDecoy.lastErrorMessage, !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            if prefs.blockAppleMusicAutoLaunch {
                Divider()

                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(
                        loc.text(
                            es: "Mientras el bloqueo esté activo, macOS tampoco abrirá Apple Music manualmente. Si algún día querés usarlo, desactivá la opción o hacé clic aquí.",
                            en: "While active, macOS won't launch Apple Music even manually. Whenever you want to use it, turn this off or click here."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(loc.text(es: "Abrir Apple Music", en: "Open Apple Music")) {
                        musicDecoy.openAppleMusicTemporarily()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func triggerSettingsTrackChangePreview(style: NotchTrackChangeStyle) {
        previewMode = .collapsed
        previewFeedbackTask?.cancel()
        previewSqueeze = false
        previewNudgeX = 0
        let token = UUID()
        previewFeedback = .trackChanged(style, token: token)

        if style == .slideNudge && prefs.enableAnimations {
            previewNudgeX = 11
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 170_000_000)
                previewNudgeX = 0
            }
        }

        // También disparar la vista previa en el Notch real si está activo
        manager.previewTrackChangeFeedback(style: style)

        previewFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled else { return }
            if case .trackChanged(_, let currentToken) = previewFeedback, currentToken == token {
                previewFeedback = .none
            }
        }
    }

    private func triggerSettingsPausePreview(style: NotchPauseAnimationStyle) {
        previewMode = .collapsed
        previewFeedbackTask?.cancel()
        previewNudgeX = 0
        previewSqueeze = false
        let token = UUID()
        previewFeedback = .paused(style, token: token)

        if style == .gentleSqueeze && prefs.enableAnimations {
            previewSqueeze = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 240_000_000)
                previewSqueeze = false
            }
        }

        // También disparar la vista previa en el Notch real si está activo
        manager.previewPauseFeedback(style: style)

        previewFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            if case .paused(_, let currentToken) = previewFeedback, currentToken == token {
                previewFeedback = .none
            }
        }
    }

    private func commitPortInput() {
        if let parsed = Int(portInputText.trimmingCharacters(in: .whitespaces)) {
            prefs.youtubeMusicAPIPort = parsed
            portInputText = String(prefs.youtubeMusicAPIPort)
            media.refreshNow()
        } else {
            portInputText = String(prefs.youtubeMusicAPIPort)
        }
    }

    // MARK: - Componentes de Tarjeta Reutilizables

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 11) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
    }

    private func connectionStatusRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        isOnline: Bool
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.2))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(isOnline ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                Text(isOnline ? loc.text(es: "Activo", en: "Active") : loc.text(es: "Inactivo", en: "Idle"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOnline ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill((isOnline ? Color.green : Color.secondary).opacity(0.12)))
        }
    }
}

// MARK: - Vista Previa Interactiva Orgánica del Notch dentro de Configuración

private enum NotchSettingsPreviewMode: String, CaseIterable, Identifiable {
    case collapsed
    case expanded
    case lyrics

    var id: String { rawValue }
}

private struct NotchSettingsInteractivePreviewCard: View {
    @Binding var previewMode: NotchSettingsPreviewMode
    var previewFeedback: NotchTransientFeedback = .none
    var previewSqueeze: Bool = false
    var previewNudgeX: CGFloat = 0
    @Bindable var prefs: NotchPreferences
    @Bindable var media: NotchMediaService
    @Bindable var loc: LocalizationManager

    private var previewAccent: Color {
        prefs.resolvedAccentColor(for: media.currentTrack)
    }

    private var previewTitle: String {
        media.currentTrack?.title ?? "Midnight Pulse"
    }

    private var previewArtist: String {
        if let track = media.currentTrack {
            return track.displaySubtitle(includeAlbum: prefs.showAlbumName)
        }
        return prefs.showAlbumName ? "Neon Horizon · Afterglow" : "Neon Horizon"
    }

    private var isPreviewDropDown: Bool {
        guard previewMode == .collapsed else { return false }
        switch previewFeedback {
        case .trackChanged(.dropDown, _), .paused(.dropDown, _):
            return true
        default:
            return false
        }
    }

    private var isPreviewSideways: Bool {
        guard previewMode == .collapsed else { return false }
        return previewFeedback.isSidewaysPeeking
    }

    private var isPreviewColorFlash: Bool {
        guard previewMode == .collapsed else { return false }
        if case .trackChanged(.colorFlash, _) = previewFeedback { return true }
        return false
    }

    private var isPreviewColorDim: Bool {
        guard previewMode == .collapsed else { return false }
        if case .paused(.colorDimPulse, _) = previewFeedback { return true }
        return false
    }

    private var isPreviewSkipSwap: Bool {
        guard previewMode == .collapsed else { return false }
        switch previewFeedback {
        case .trackChanged(.skipIconSwap, _), .trackChanged(.slideNudge, _):
            return true
        default:
            return false
        }
    }

    private var isPreviewPausePop: Bool {
        guard previewMode == .collapsed else { return false }
        if case .paused(.pauseIconPop, _) = previewFeedback { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc.text(es: "Vista previa en tiempo real", en: "Live Interactive Preview"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $previewMode) {
                    Text(loc.text(es: "Colapsado", en: "Collapsed")).tag(NotchSettingsPreviewMode.collapsed)
                    Text(loc.text(es: "Expandido", en: "Expanded")).tag(NotchSettingsPreviewMode.expanded)
                    Text(loc.text(es: "Letras", en: "Lyrics")).tag(NotchSettingsPreviewMode.lyrics)
                }
                .pickerStyle(.segmented)
                .frame(width: 248)
            }

            // Lienzo con fondo estilo escritorio macOS y muesca orgánica cóncava arriba
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.26, blue: 0.48),
                        Color(red: 0.19, green: 0.14, blue: 0.34),
                        Color(red: 0.08, green: 0.10, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Simulación sutil de barra de menús macOS detrás de la muesca
                HStack {
                    Text("  MacFileExplorer  Notch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.68))
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100")
                        Text("14:30")
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                }
                .padding(.horizontal, 14)
                .frame(height: 24)
                .background(Color.black.opacity(0.24))

                // Silueta orgánica animada del Notch
                previewNotchSilhouette
                    .scaleEffect(
                        x: previewSqueeze ? 0.93 : 1.0,
                        y: previewSqueeze ? 0.90 : 1.0,
                        anchor: .top
                    )
                    .offset(x: previewNudgeX)
                    .animation(
                        prefs.resolvedAnimation(baseResponse: 0.38),
                        value: previewMode
                    )
                    .animation(
                        prefs.resolvedAnimation(baseResponse: 0.34),
                        value: previewFeedback
                    )
                    .animation(
                        prefs.enableAnimations ? .spring(response: 0.24, dampingFraction: 0.58) : nil,
                        value: previewSqueeze
                    )
                    .animation(
                        prefs.enableAnimations ? .spring(response: 0.26, dampingFraction: 0.60) : nil,
                        value: previewNudgeX
                    )
                    .animation(
                        prefs.resolvedAnimation(baseResponse: 0.34),
                        value: prefs.artworkStyle
                    )
                    .animation(
                        prefs.resolvedAnimation(baseResponse: 0.30),
                        value: prefs.showAlbumArtwork
                    )
            }
            .frame(height: previewMode == .collapsed ? (isPreviewDropDown ? 132 : 116) : 212)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.38),
                value: previewMode
            )
        }
    }

    @ViewBuilder
    private var previewNotchSilhouette: some View {
        let width: CGFloat = {
            switch previewMode {
            case .collapsed:
                if isPreviewSideways {
                    return 378
                }
                if isPreviewDropDown {
                    return previewFeedback.isPauseFeedback ? 304 : 338
                }
                return prefs.showTrackTitleInCollapsedPill ? 276 : 206
            case .expanded: return 382
            case .lyrics: return 486
            }
        }()
        let height: CGFloat = {
            switch previewMode {
            case .collapsed:
                if isPreviewDropDown {
                    return previewFeedback.isPauseFeedback ? 64 : 70
                }
                return 34
            case .expanded: return 164
            case .lyrics: return 178
            }
        }()
        let topFlare: CGFloat = previewMode == .collapsed ? (isPreviewDropDown ? 14 : (isPreviewSideways ? 13 : 11)) : 16
        let botRadius: CGFloat = previewMode == .collapsed ? (isPreviewDropDown ? 18 : 13) : 22
        let shape = OrganicNotchShape(
            topFlareRadius: topFlare,
            bottomCornerRadius: botRadius,
            isFloatingIsland: false
        )

        let baseGlow = prefs.effectiveGlowStrength(isExpanded: previewMode != .collapsed)
        let previewGlowStrength = isPreviewColorFlash
            ? min(0.95, max(0.68, baseGlow * 2.1))
            : (isPreviewColorDim ? min(0.68, max(0.45, baseGlow * 1.45)) : baseGlow)

        ZStack(alignment: .top) {
            NotchAmbientBackdropView(
                accentColor: isPreviewColorDim ? Color.white.opacity(0.85) : previewAccent,
                topFlareRadius: topFlare,
                bottomCornerRadius: botRadius,
                isFloatingIsland: false,
                showAmbientGlow: prefs.showAmbientArtworkGlow || isPreviewColorFlash || isPreviewColorDim,
                glowStrength: previewGlowStrength,
                backgroundOpacity: prefs.backgroundOpacity,
                isExpanded: previewMode != .collapsed || isPreviewColorFlash
            )

            if isPreviewColorFlash || isPreviewColorDim {
                OrganicNotchRimShape(
                    topFlareRadius: topFlare,
                    bottomCornerRadius: botRadius,
                    isFloatingIsland: false
                )
                .stroke(
                    (isPreviewColorFlash ? previewAccent : Color.white).opacity(isPreviewColorFlash ? 0.92 : 0.68),
                    lineWidth: isPreviewColorFlash ? 1.8 : 1.3
                )
                .shadow(color: (isPreviewColorFlash ? previewAccent : Color.white).opacity(0.65), radius: 5)
            }

            switch previewMode {
            case .collapsed:
                if isPreviewDropDown {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 24)
                        HStack(spacing: 10) {
                            if prefs.showAlbumArtwork {
                                NotchAlbumArtBadgeView(
                                    artworkImage: media.currentArtworkImage,
                                    trackID: media.currentTrack?.id ?? "preview-drop",
                                    accentColor: previewAccent,
                                    progress: 0.62,
                                    style: prefs.artworkStyle,
                                    size: previewFeedback.isPauseFeedback ? 22 : 26,
                                    isPlaying: !previewFeedback.isPauseFeedback,
                                    enableAnimations: prefs.enableAnimations,
                                    showProgressRing: prefs.artworkStyle == .circleWithRing
                                )
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(previewTitle)
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if previewFeedback.isPauseFeedback {
                                    HStack(spacing: 4) {
                                        Image(systemName: "pause.fill").font(.system(size: 8.5, weight: .bold))
                                        Text(loc.text(es: "Reproducción en pausa", en: "Playback paused"))
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(previewAccent)
                                } else {
                                    Text(previewArtist)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.white.opacity(0.68))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            previewCollapsedRightIndicator
                        }
                        .padding(.horizontal, topFlare + 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    HStack(spacing: 9) {
                        if prefs.showAlbumArtwork {
                            NotchAlbumArtBadgeView(
                                artworkImage: media.currentArtworkImage,
                                trackID: media.currentTrack?.id ?? "preview-collapsed",
                                accentColor: previewAccent,
                                progress: 0.62,
                                style: prefs.artworkStyle,
                                size: 21,
                                isPlaying: !previewFeedback.isPauseFeedback,
                                enableAnimations: prefs.enableAnimations,
                                showProgressRing: prefs.artworkStyle == .circleWithRing
                            )
                        } else {
                            ZStack {
                                Circle().fill(previewAccent.opacity(0.24))
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(previewAccent)
                            }
                            .frame(width: 21, height: 21)
                        }

                        if isPreviewSideways && previewFeedback.isPauseFeedback {
                            HStack(spacing: 5) {
                                Text(loc.text(es: "En pausa", en: "Paused"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(previewAccent)
                                Text("·")
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(previewTitle)
                                    .font(.system(size: 11.2, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)
                            }
                        } else if prefs.showTrackTitleInCollapsedPill || isPreviewSideways {
                            Text(isPreviewSideways ? "\(previewTitle) · \(previewArtist)" : previewTitle)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        } else {
                            Spacer(minLength: 4)
                        }

                        Spacer(minLength: 4)

                        previewCollapsedRightIndicator
                    }
                    .padding(.horizontal, topFlare + 10)
                    .frame(height: height)
                }

            case .expanded:
                VStack(spacing: 10) {
                    // Cabecera compacta
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(NotchMediaSource.youtubeMusic.swiftUIAccentColor)
                            Text("YouTube Music")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.10)))

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "slider.vertical.3")
                            Image(systemName: "speaker.wave.2.fill")
                            Image(systemName: "airplayaudio")
                            Image(systemName: "pin")
                            Image(systemName: "gearshape.fill")
                            Image(systemName: "xmark")
                        }
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.68))
                    }

                    HStack(spacing: 14) {
                        if prefs.showAlbumArtwork {
                            ZStack(alignment: .bottomTrailing) {
                                NotchAlbumArtBadgeView(
                                    artworkImage: media.currentArtworkImage,
                                    trackID: media.currentTrack?.id ?? "preview-expanded",
                                    accentColor: previewAccent,
                                    progress: 0.62,
                                    style: .roundedSquare,
                                    size: 66,
                                    isPlaying: true,
                                    enableAnimations: prefs.enableAnimations,
                                    showProgressRing: false
                                )
                                .shadow(color: prefs.showAmbientArtworkGlow ? previewAccent.opacity(0.65 * prefs.ambientGlowIntensity) : .clear, radius: 10, y: 4)

                                if prefs.showSourceBadgeOnArtwork {
                                    ZStack {
                                        Circle().fill(Color.black.opacity(0.88))
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(NotchMediaSource.youtubeMusic.swiftUIAccentColor)
                                    }
                                    .frame(width: 19, height: 19)
                                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.7))
                                    .offset(x: 3, y: 3)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(previewTitle)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(previewArtist)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.white.opacity(0.65))
                                        .lineLimit(1)
                                }
                                Spacer()
                                if prefs.showVisualizerBars {
                                    NotchEqualizerVisualizerView(
                                        isPlaying: true,
                                        accentColor: previewAccent,
                                        barCount: 5,
                                        barWidth: 2.3,
                                        barSpacing: 2.0,
                                        maxHeight: 14,
                                        enableAnimations: prefs.enableAnimations,
                                        style: prefs.visualizerStyle,
                                        speedMultiplier: prefs.animationSpeed
                                    )
                                }
                            }

                            // Mini scrubber
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                                .frame(height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(LinearGradient(colors: [previewAccent, .white], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 118, height: 4)
                                }

                            HStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.85))
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.20))
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 28, height: 28)
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, topFlare + 14)

            case .lyrics:
                HStack(spacing: 14) {
                    VStack(spacing: 7) {
                        if prefs.showAlbumArtwork {
                            NotchAlbumArtBadgeView(
                                artworkImage: media.currentArtworkImage,
                                trackID: media.currentTrack?.id ?? "preview-lyrics",
                                accentColor: previewAccent,
                                progress: 0.62,
                                style: .roundedSquare,
                                size: 50,
                                isPlaying: true,
                                enableAnimations: prefs.enableAnimations,
                                showProgressRing: false
                            )
                        }
                        Text(previewTitle)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(previewArtist)
                            .font(.system(size: 9.8))
                            .foregroundStyle(Color.white.opacity(0.60))
                            .lineLimit(1)
                        HStack(spacing: 12) {
                            Image(systemName: "backward.fill")
                            Image(systemName: "pause.circle.fill").font(.system(size: 18))
                            Image(systemName: "forward.fill")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                    }
                    .frame(width: 150)

                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1)
                        .padding(.vertical, 12)

                    VStack(alignment: .leading, spacing: max(5, prefs.lyricsFontSize.lineSpacing - 2)) {
                        Text("Neon echoes in the quiet rain")
                            .font(.system(size: prefs.lyricsFontSize.inactiveFontSize - 1.0))
                            .foregroundStyle(Color.white.opacity(0.32))
                        Text("Feel the bassline rising in the dark")
                            .font(.system(size: prefs.lyricsFontSize.activeFontSize - 0.8, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: previewAccent.opacity(0.65), radius: 5)
                        Text("Glowing softly like a distant spark")
                            .font(.system(size: prefs.lyricsFontSize.inactiveFontSize - 0.8))
                            .foregroundStyle(Color.white.opacity(0.50))
                        Text("Hold the moment while the colors bloom")
                            .font(.system(size: prefs.lyricsFontSize.inactiveFontSize - 1.0))
                            .foregroundStyle(Color.white.opacity(0.32))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 22)
                .padding(.horizontal, topFlare + 16)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .clipShape(shape)
        .shadow(color: Color.black.opacity(0.55), radius: 14, y: 6)
    }

    @ViewBuilder
    private var previewCollapsedRightIndicator: some View {
        if isPreviewSkipSwap {
            ZStack {
                Circle().fill(previewAccent.opacity(0.24)).frame(width: 20, height: 20)
                Image(systemName: "forward.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(previewAccent)
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if previewFeedback.isPauseFeedback {
            ZStack {
                if isPreviewPausePop {
                    Circle()
                        .fill(previewAccent.opacity(0.22))
                        .overlay(Circle().stroke(previewAccent.opacity(0.75), lineWidth: 1.1))
                        .frame(width: 20, height: 20)
                }
                Image(systemName: "pause.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isPreviewPausePop ? previewAccent : Color.white.opacity(0.90))
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if prefs.showVisualizerBars {
            NotchEqualizerVisualizerView(
                isPlaying: true,
                accentColor: previewAccent,
                barCount: 4,
                barWidth: 2.3,
                barSpacing: 2.0,
                maxHeight: 13,
                enableAnimations: prefs.enableAnimations,
                style: prefs.visualizerStyle,
                speedMultiplier: prefs.animationSpeed
            )
            .transition(.opacity)
        }
    }
}
