import AppKit
import SwiftUI

// MARK: - Pestañas de Configuración de Notch

public enum NotchSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case displays
    case sources

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .appearance: return "sparkles"
        case .displays: return "macbook.gen2"
        case .sources: return "music.note.house"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .general: return loc.text(es: "General", en: "General")
        case .appearance: return loc.text(es: "Apariencia y Animaciones", en: "Appearance & Animations")
        case .displays: return loc.text(es: "Pantallas y Visibilidad", en: "Displays & Visibility")
        case .sources: return loc.text(es: "Fuentes y YouTube Music", en: "Sources & YouTube Music")
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
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var selectedTab: NotchSettingsTab
    @ViewState private var previewMode: NotchSettingsPreviewMode = .expanded
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

    private var appearanceTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: loc.text(es: "Apariencia y Animaciones", en: "Appearance & Animations"),
                subtitle: loc.text(
                    es: "Personaliza el estilo de la carátula, el tamaño de la píldora, el resplandor ambiental y las letras sincronizadas.",
                    en: "Customize artwork style, pill proportions, ambient album glow, and live synced lyrics."
                )
            )

            settingsCard(title: loc.text(es: "Estilo de carátula y Tamaño", en: "Artwork Style & Pill Size")) {
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
                                        accentColor: Color(red: 0.96, green: 0.24, blue: 0.42),
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

            settingsCard(title: loc.text(es: "Efectos Visuales y Contenido", en: "Visual Effects & Content")) {
                Toggle(loc.text(es: "Animaciones fluidas con resorte", en: "Fluid Spring Animations"), isOn: $prefs.enableAnimations)
                Divider()
                Toggle(loc.text(es: "Brillo radial ambiental según la carátula", en: "Ambient Album-Art Radial Glow"), isOn: $prefs.showAmbientArtworkGlow)
                Divider()
                Toggle(loc.text(es: "Barras animadas del ecualizador musical", en: "Animated Music Equalizer Bars"), isOn: $prefs.showVisualizerBars)
                Divider()
                Toggle(loc.text(es: "Mostrar título en la píldora colapsada", en: "Show Track Title in Collapsed Pill"), isOn: $prefs.showTrackTitleInCollapsedPill)
                Divider()
                Toggle(loc.text(es: "Desplazamiento suave (Marquee) en títulos largos", en: "Smooth Marquee Scrolling for Long Titles"), isOn: $prefs.enableMarqueeTitle)
                Divider()
                Toggle(loc.text(es: "Anunciar nuevas canciones automáticamente", en: "Announce New Tracks Automatically"), isOn: $prefs.announceNewTracks)
                Divider()
                Toggle(loc.text(es: "Habilitar letras sincronizadas en vivo (LRCLIB)", en: "Enable Live Synced Lyrics (LRCLIB)"), isOn: $prefs.showSyncedLyrics)
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
                            : loc.text(es: "Cerrado (no se abrirá automáticamente)", en: "Not running (will never be auto-launched)"),
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
    @Bindable var prefs: NotchPreferences
    @Bindable var media: NotchMediaService
    @Bindable var loc: LocalizationManager

    private var previewAccent: Color {
        media.currentTrack?.dominantColor.swiftUIColor ?? Color(red: 0.96, green: 0.24, blue: 0.42)
    }

    private var previewTitle: String {
        media.currentTrack?.title ?? "Midnight Pulse"
    }

    private var previewArtist: String {
        media.currentTrack?.displaySubtitle ?? "Neon Horizon • YouTube Music"
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
                    .animation(
                        prefs.enableAnimations ? .spring(response: 0.38, dampingFraction: 0.78) : nil,
                        value: previewMode
                    )
                    .animation(
                        prefs.enableAnimations ? .spring(response: 0.34, dampingFraction: 0.80) : nil,
                        value: prefs.artworkStyle
                    )
            }
            .frame(height: previewMode == .collapsed ? 116 : 212)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .animation(
                prefs.enableAnimations ? .spring(response: 0.38, dampingFraction: 0.80) : nil,
                value: previewMode
            )
        }
    }

    @ViewBuilder
    private var previewNotchSilhouette: some View {
        let width: CGFloat = {
            switch previewMode {
            case .collapsed: return prefs.showTrackTitleInCollapsedPill ? 276 : 206
            case .expanded: return 382
            case .lyrics: return 486
            }
        }()
        let height: CGFloat = {
            switch previewMode {
            case .collapsed: return 34
            case .expanded: return 164
            case .lyrics: return 178
            }
        }()
        let topFlare: CGFloat = previewMode == .collapsed ? 11 : 16
        let botRadius: CGFloat = previewMode == .collapsed ? 13 : 22
        let shape = OrganicNotchShape(
            topFlareRadius: topFlare,
            bottomCornerRadius: botRadius,
            isFloatingIsland: false
        )

        ZStack(alignment: .top) {
            NotchAmbientBackdropView(
                accentColor: previewAccent,
                topFlareRadius: topFlare,
                bottomCornerRadius: botRadius,
                isFloatingIsland: false,
                showAmbientGlow: prefs.showAmbientArtworkGlow,
                glowStrength: previewMode == .collapsed ? 0.22 : 0.32,
                isExpanded: previewMode != .collapsed
            )

            switch previewMode {
            case .collapsed:
                HStack(spacing: 9) {
                    NotchAlbumArtBadgeView(
                        artworkImage: media.currentArtworkImage,
                        trackID: media.currentTrack?.id ?? "preview-collapsed",
                        accentColor: previewAccent,
                        progress: 0.62,
                        style: prefs.artworkStyle,
                        size: 21,
                        isPlaying: true,
                        enableAnimations: prefs.enableAnimations,
                        showProgressRing: prefs.artworkStyle == .circleWithRing
                    )

                    if prefs.showTrackTitleInCollapsedPill {
                        Text(previewTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    } else {
                        Spacer(minLength: 4)
                    }

                    Spacer(minLength: 4)

                    if prefs.showVisualizerBars {
                        NotchEqualizerVisualizerView(
                            isPlaying: true,
                            accentColor: previewAccent,
                            barCount: 4,
                            barWidth: 2.3,
                            barSpacing: 2.0,
                            maxHeight: 13,
                            enableAnimations: prefs.enableAnimations
                        )
                    }
                }
                .padding(.horizontal, topFlare + 10)
                .frame(height: height)

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
                            Image(systemName: "speaker.wave.2.fill")
                            Image(systemName: "pin")
                            Image(systemName: "gearshape.fill")
                        }
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.68))
                    }

                    HStack(spacing: 14) {
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
                        .shadow(color: prefs.showAmbientArtworkGlow ? previewAccent.opacity(0.45) : .clear, radius: 10, y: 4)

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
                                        enableAnimations: prefs.enableAnimations
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

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Neon echoes in the quiet rain")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.32))
                        Text("Feel the bassline rising in the dark")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: previewAccent.opacity(0.65), radius: 5)
                        Text("Glowing softly like a distant spark")
                            .font(.system(size: 11.2))
                            .foregroundStyle(Color.white.opacity(0.50))
                        Text("Hold the moment while the colors bloom")
                            .font(.system(size: 11))
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
}
