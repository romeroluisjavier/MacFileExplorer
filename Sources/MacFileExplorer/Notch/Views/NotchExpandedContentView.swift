import AppKit
import SwiftUI

// MARK: - Vista Expandida del Reproductor Notch (2 Columnas + Vista Dividida con Letras Sincronizadas)

/// Contenido expandido estilo Notchy:
/// - Barra superior limpia debajo del área segura del notch físico (insignia de fuente, píldora de letras,
///   selector de salida de audio CoreAudio integrado, fijar abierto, ajustes y contraer).
/// - Dos diseños que se transforman suavemente con animación de resorte:
///   1. Reproductor compacto de 2 columnas (carátula 78×78 con resplandor + título marquee + barra
///      de progreso interactiva + controles de transporte + ecualizador animado).
///   2. Vista dividida con letras sincronizadas estilo karaoke en vivo (LRCLIB / Demo).
private enum NotchExpandedTopOverlay: Equatable {
    case none
    case calendar
    case volume
    case equalizer
    case audioOutput
}

public struct NotchExpandedContentView: View {
    public let track: NotchTrackInfo?
    public let artworkImage: NSImage?
    public let topSafeInset: CGFloat
    public let horizontalInset: CGFloat
    public let isLyricsPaneOpen: Bool
    public let isPinnedOpen: Bool
    public let onToggleLyrics: () -> Void
    public let onTogglePin: () -> Void
    public let onOpenSettings: () -> Void
    public let onClose: () -> Void

    @Bindable private var prefs = NotchPreferences.shared
    @Bindable private var media = NotchMediaService.shared
    @Bindable private var lyricsAudio = NotchLyricsAndAudioService.shared
    @Bindable private var eqEngine = NotchAudioEqualizerEngine.shared
    @Bindable private var calService = NotchCalendarService.shared
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var activeTopOverlay: NotchExpandedTopOverlay = .none
    @ViewState private var showRemainingTime: Bool = false
    @ViewState private var isArtworkHovered: Bool = false
    @ViewState private var hoveredControlID: String? = nil

    public init(
        track: NotchTrackInfo?,
        artworkImage: NSImage?,
        topSafeInset: CGFloat,
        horizontalInset: CGFloat = 18,
        isLyricsPaneOpen: Bool,
        isPinnedOpen: Bool,
        onToggleLyrics: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.track = track
        self.artworkImage = artworkImage
        self.topSafeInset = topSafeInset
        self.horizontalInset = horizontalInset
        self.isLyricsPaneOpen = isLyricsPaneOpen
        self.isPinnedOpen = isPinnedOpen
        self.onToggleLyrics = onToggleLyrics
        self.onTogglePin = onTogglePin
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
    }

    private var accentColor: Color {
        prefs.resolvedAccentColor(for: track)
    }

    private var shouldTickTimeline: Bool {
        guard let track else { return false }
        return track.isPlaying && activeTopOverlay == .none
    }

    private func toggleTopOverlay(_ target: NotchExpandedTopOverlay) {
        let next: NotchExpandedTopOverlay = (activeTopOverlay == target) ? .none : target
        if next == .volume {
            lyricsAudio.refreshVolumeState()
        } else if next == .audioOutput {
            lyricsAudio.refreshOutputDevices()
        } else if next == .equalizer {
            lyricsAudio.refreshOutputDevices()
        } else if next == .calendar {
            calService.refreshNow()
        }
        if prefs.enableAnimations {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                activeTopOverlay = next
            }
        } else {
            activeTopOverlay = next
        }
    }

    private var compactArtworkDimension: CGFloat {
        switch prefs.pillSize {
        case .compact: return 72
        case .normal: return 78
        case .spacious: return 86
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Espacio limpio debajo de la cámara física del MacBook (o margen superior en modo isla flotante)
            Color.clear
                .frame(height: max(8, topSafeInset))

            // Barra superior de estado y micro-controles
            headerStrip
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, activeTopOverlay == .equalizer ? 5 : (isLyricsPaneOpen ? 7 : 10))

            // Cuerpo principal: Calendario / Volumen / Ecualizador / Salida de audio / Alerta Meet exclusiva / Letras / Reproductor
            ZStack {
                if activeTopOverlay == .calendar {
                    NotchCalendarContentView(
                        accentColor: accentColor,
                        showBackButton: true,
                        onBack: { toggleTopOverlay(.calendar) }
                    )
                    .transition(
                        prefs.enableAnimations
                            ? .opacity.combined(with: .scale(scale: 0.96))
                            : .identity
                    )
                } else if activeTopOverlay == .volume {
                    volumeControlView
                        .transition(
                            prefs.enableAnimations
                                ? .opacity.combined(with: .scale(scale: 0.96))
                                : .identity
                        )
                } else if activeTopOverlay == .equalizer {
                    equalizerControlView
                        .transition(
                            prefs.enableAnimations
                                ? .opacity.combined(with: .scale(scale: 0.96))
                                : .identity
                        )
                } else if activeTopOverlay == .audioOutput {
                    audioOutputPickerView
                        .transition(
                            prefs.enableAnimations
                                ? .opacity.combined(with: .scale(scale: 0.96))
                                : .identity
                        )
                } else if prefs.calendarEnabled,
                          prefs.calendarMusicCoexistenceMode != .manualTabOnly,
                          let alertEvent = calService.activeAlertEvent {
                    // Vista exclusiva de notificación de Meet (oculta temporalmente la música para verse limpia y sin recortes)
                    NotchImminentMeetBannerView(
                        event: alertEvent,
                        showDirectJoinButton: prefs.calendarShowDirectJoinMeetButton,
                        enableAnimations: prefs.enableAnimations,
                        onJoin: { calService.joinMeeting(for: alertEvent) },
                        onOpenCalendar: { calService.openCalendar(for: alertEvent) },
                        onDismiss: { calService.dismissActiveAlert() }
                    )
                    .transition(
                        prefs.enableAnimations
                            ? .opacity.combined(with: .scale(scale: 0.96))
                            : .identity
                    )
                } else if let track {
                    TimelineView(.animation(minimumInterval: 0.20, paused: !shouldTickTimeline)) { context in
                        let elapsed = track.interpolatedElapsedTime(at: context.date)
                        let progress = track.progress(at: context.date)

                        if isLyricsPaneOpen && prefs.showSyncedLyrics {
                            splitLyricsPlayerBody(track: track, elapsed: elapsed, progress: progress)
                                .transition(
                                    prefs.enableAnimations
                                        ? .opacity.combined(with: .scale(scale: 0.98))
                                        : .identity
                                )
                        } else {
                            compactTwoColumnPlayerBody(track: track, elapsed: elapsed, progress: progress)
                                .transition(
                                    prefs.enableAnimations
                                        ? .opacity.combined(with: .scale(scale: 0.98))
                                        : .identity
                                )
                        }
                    }
                } else if prefs.calendarEnabled && prefs.calendarShowWhenMusicIdle {
                    NotchCalendarContentView(
                        accentColor: accentColor,
                        showBackButton: false,
                        onBack: {}
                    )
                    .transition(.opacity)
                } else {
                    idleEmptyPlayerBody
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, activeTopOverlay == .equalizer ? 10 : 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.34),
                value: activeTopOverlay
            )
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.36),
                value: isLyricsPaneOpen
            )
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.32),
                value: calService.activeAlertEvent?.id
            )
        }
    }

    // MARK: - Barra Superior de Controles

    private var headerStrip: some View {
        HStack(spacing: 8) {
            // Grupo izquierdo: cápsula oscura con insignia de fuente + calendario (si está a la izquierda) + letras + demo
            HStack(spacing: 5) {
                sourceAppPill

                if prefs.calendarEnabled && prefs.calendarIconPosition == .leftNextToMusic {
                    calendarHeaderControl
                }

                if prefs.showSyncedLyrics && track != nil {
                    lyricsTogglePill
                }

                if media.isDemoMode {
                    demoIndicatorPill
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                    )
            )

            Spacer(minLength: 4)

            if prefs.calendarEnabled && prefs.calendarIconPosition == .center {
                calendarHeaderControl
                Spacer(minLength: 4)
            }

            // Grupo derecho: micro-botones circulares translúcidos (Calendario, Ecualizador, Volumen, Salida de audio, Fijar, Ajustes, Cerrar)
            HStack(spacing: 4.5) {
                if prefs.calendarEnabled && prefs.calendarIconPosition == .rightBeforeControls {
                    calendarHeaderControl
                }

                // 1. Ecualizador de sonido (5 bandas + presets)
                NotchHeaderMicroButton(
                    systemName: "slider.vertical.3",
                    isActive: activeTopOverlay == .equalizer || prefs.isEqualizerEnabled,
                    activeTint: accentColor,
                    helpText: loc.text(es: "Ecualizador de sonido", en: "Sound Equalizer"),
                    enableAnimations: prefs.enableAnimations
                ) {
                    toggleTopOverlay(.equalizer)
                }

                // 2. Control de volumen del sistema + silencio
                let volPercent = Int((lyricsAudio.outputVolume * 100.0).rounded())
                NotchHeaderMicroButton(
                    systemName: lyricsAudio.volumeSymbolName,
                    isActive: activeTopOverlay == .volume || lyricsAudio.isMuted,
                    activeTint: lyricsAudio.isMuted ? Color.orange : accentColor,
                    helpText: lyricsAudio.isMuted
                        ? loc.text(es: "Volumen (Silenciado)", en: "Volume (Muted)")
                        : loc.text(es: "Volumen (\(volPercent)%)", en: "Volume (\(volPercent)%)"),
                    enableAnimations: prefs.enableAnimations
                ) {
                    toggleTopOverlay(.volume)
                }

                // 3. Selector de dispositivo de salida de audio CoreAudio
                let rawAudioSymbol = lyricsAudio.defaultOutputDevice?.systemImage ?? "airplayaudio"
                let distinctAudioSymbol = (rawAudioSymbol == "speaker.wave.2.fill") ? "airplayaudio" : rawAudioSymbol
                let safeAudioSymbol = NSImage(systemSymbolName: distinctAudioSymbol, accessibilityDescription: nil) != nil
                    ? distinctAudioSymbol
                    : "airplayaudio"

                NotchHeaderMicroButton(
                    systemName: safeAudioSymbol,
                    isActive: activeTopOverlay == .audioOutput,
                    activeTint: accentColor,
                    helpText: loc.text(es: "Cambiar salida de audio", en: "Switch Audio Output"),
                    enableAnimations: prefs.enableAnimations
                ) {
                    toggleTopOverlay(.audioOutput)
                }

                NotchHeaderMicroButton(
                    systemName: isPinnedOpen ? "pin.fill" : "pin",
                    isActive: isPinnedOpen,
                    activeTint: accentColor,
                    helpText: isPinnedOpen
                        ? loc.text(es: "Desfijar Notch", en: "Unpin Notch")
                        : loc.text(es: "Fijar Notch abierto", en: "Pin Notch Open"),
                    enableAnimations: prefs.enableAnimations,
                    action: onTogglePin
                )

                NotchHeaderMicroButton(
                    systemName: "gearshape.fill",
                    isActive: false,
                    helpText: loc.text(es: "Configuración de Notch", en: "Notch Settings"),
                    enableAnimations: prefs.enableAnimations,
                    action: onOpenSettings
                )

                if prefs.calendarEnabled && prefs.calendarIconPosition == .rightBeforeClose {
                    calendarHeaderControl
                }

                NotchHeaderMicroButton(
                    systemName: "xmark",
                    isActive: false,
                    helpText: loc.text(es: "Cerrar Notch por completo", en: "Close Notch Completely"),
                    enableAnimations: prefs.enableAnimations,
                    action: onClose
                )
            }
        }
    }

    // MARK: - Botón / Cápsula Configurable de Calendario en la Barra Superior del Notch

    private var calendarHeaderControl: some View {
        let alertEvent = calService.activeAlertEvent
        let hasImminentMeet = alertEvent != nil
        let isActive = activeTopOverlay == .calendar || hasImminentMeet
        let defaultBlue = Color(red: 0.30, green: 0.60, blue: 1.0)
        let defaultMeetGreen = Color(red: 0.20, green: 0.85, blue: 0.50)

        let activeTint: Color = {
            if let alertEvent {
                return prefs.calendarUseNativeEventColors ? alertEvent.color.swiftUIColor : defaultMeetGreen
            }
            if prefs.calendarUseNativeEventColors, let next = calService.nextUpcomingEvent {
                return next.color.swiftUIColor
            }
            return defaultBlue
        }()

        let dayNumberString = "\(Calendar.current.component(.day, from: Date()))"
        let upcomingCount = calService.visibleEvents.filter { !$0.isAllDay && $0.endDate > Date() }.count
        let helpText = hasImminentMeet
            ? loc.text(es: "Meet por iniciar (abrir Calendario)", en: "Meet starting soon (open Calendar)")
            : loc.text(es: "Google Calendar", en: "Google Calendar")

        return Button {
            toggleTopOverlay(.calendar)
        } label: {
            Group {
                switch prefs.calendarIconStyle {
                case .microCircle:
                    let diameter: CGFloat = {
                        switch prefs.calendarIconSize {
                        case .small: return 20
                        case .medium: return 24
                        case .large: return 28
                        }
                    }()
                    let iconFont: CGFloat = {
                        switch prefs.calendarIconSize {
                        case .small: return 9.2
                        case .medium: return 10.5
                        case .large: return 12.2
                        }
                    }()
                    ZStack {
                        if prefs.calendarIconShowDayNumber && !hasImminentMeet {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(activeTint)
                                    .frame(width: diameter * 0.54, height: 2.5)
                                Text(dayNumberString)
                                    .font(.system(size: iconFont * 0.86, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            .frame(width: diameter * 0.58, height: diameter * 0.58)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        } else {
                            Image(systemName: hasImminentMeet ? "video.fill" : "calendar")
                                .font(.system(size: iconFont, weight: .semibold))
                                .foregroundStyle(isActive ? activeTint : Color.white.opacity(0.84))
                        }
                    }
                    .frame(width: diameter, height: diameter)
                    .background(
                        Circle()
                            .fill(isActive ? activeTint.opacity(0.24) : Color.white.opacity(0.08))
                            .overlay(
                                Circle()
                                    .stroke(isActive ? activeTint.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 0.7)
                            )
                    )
                    .contentShape(Circle())

                case .dateBadgeTile:
                    let tileSize: CGFloat = {
                        switch prefs.calendarIconSize {
                        case .small: return 21
                        case .medium: return 25
                        case .large: return 29
                        }
                    }()
                    VStack(spacing: 0) {
                        ZStack {
                            activeTint
                            Text(hasImminentMeet ? "MEET" : Date().formatted(.dateTime.month(.abbreviated)).prefix(3).uppercased())
                                .font(.system(size: max(5.5, tileSize * 0.23), weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .frame(height: tileSize * 0.36)

                        ZStack {
                            Color.white.opacity(isActive ? 0.20 : 0.12)
                            if hasImminentMeet {
                                Image(systemName: "video.fill")
                                    .font(.system(size: tileSize * 0.36, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text(dayNumberString)
                                    .font(.system(size: tileSize * 0.44, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .stroke(isActive ? activeTint.opacity(0.75) : Color.white.opacity(0.18), lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))

                case .pillLikeMusic, .pillWithNextEvent:
                    let iconSize: CGFloat = {
                        switch prefs.calendarIconSize {
                        case .small: return 11
                        case .medium: return 13
                        case .large: return 15
                        }
                    }()
                    let fontSize: CGFloat = {
                        switch prefs.calendarIconSize {
                        case .small: return 10
                        case .medium: return 11
                        case .large: return 12
                        }
                    }()
                    let padH: CGFloat = {
                        switch prefs.calendarIconSize {
                        case .small: return 7
                        case .medium: return 8
                        case .large: return 10
                        }
                    }()
                    let padV: CGFloat = {
                        switch prefs.calendarIconSize {
                        case .small: return 2.5
                        case .medium: return 3.5
                        case .large: return 4.5
                        }
                    }()
                    let pillTitle: String = {
                        if prefs.calendarIconStyle == .pillWithNextEvent {
                            if let alertEvent {
                                return alertEvent.countdownLabel(using: loc)
                            }
                            if let next = calService.nextUpcomingEvent {
                                return next.formattedStartTime
                            }
                            return loc.text(es: "Hoy", en: "Today")
                        }
                        return loc.text(es: "Calendario", en: "Calendar")
                    }()

                    HStack(spacing: 5) {
                        if prefs.calendarIconShowDayNumber && !hasImminentMeet {
                            Text(dayNumberString)
                                .font(.system(size: max(8.5, iconSize * 0.72), weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: iconSize + 2, height: iconSize + 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                        .fill(activeTint)
                                )
                        } else {
                            Image(systemName: hasImminentMeet ? "video.fill" : "calendar")
                                .font(.system(size: iconSize - 2, weight: .bold))
                                .foregroundStyle(activeTint)
                        }

                        Text(pillTitle)
                            .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
                    .background(
                        Capsule(style: .continuous)
                            .fill(activeTint.opacity(isActive ? 0.30 : 0.20))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(activeTint.opacity(isActive ? 0.60 : 0.38), lineWidth: 0.7)
                            )
                    )
                    .contentShape(Capsule())
                }
            }
            .overlay(alignment: .topTrailing) {
                if prefs.calendarIconShowEventBadge && (hasImminentMeet || upcomingCount > 0) {
                    if hasImminentMeet {
                        Circle()
                            .fill(activeTint)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 1))
                            .offset(x: 2, y: -2)
                    } else {
                        Text("\(min(upcomingCount, 9))")
                            .font(.system(size: 7.5, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.2)
                            .padding(.vertical, 0.8)
                            .background(Capsule().fill(activeTint))
                            .overlay(Capsule().stroke(Color.black.opacity(0.75), lineWidth: 0.8))
                            .offset(x: 3, y: -3)
                    }
                }
            }
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
        .help(helpText)
    }

    private var sourceAppPill: some View {
        let source = track?.sourceApp ?? .other
        let sourceColor = track?.sourceApp.swiftUIAccentColor ?? accentColor
        let appIcon = track.flatMap { $0.sourceApp.appIcon(bundleID: $0.sourceBundleID) }
        let label = track?.sourceAppName ?? loc.text(es: "Reproduciendo", en: "Now Playing")

        return Button {
            media.openSourceApp()
        } label: {
            HStack(spacing: 5) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    Image(systemName: source.symbolName)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(sourceColor)
                }

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule(style: .continuous)
                    .fill(sourceColor.opacity(0.20))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(sourceColor.opacity(0.38), lineWidth: 0.7)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.94, enableAnimations: prefs.enableAnimations))
        .help(loc.text(es: "Abrir aplicación de música", en: "Open Music App"))
    }

    private var lyricsTogglePill: some View {
        Button {
            if activeTopOverlay != .none {
                activeTopOverlay = .none
            }
            onToggleLyrics()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(loc.text(es: "Letras", en: "Lyrics"))
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(isLyricsPaneOpen ? Color.white : Color.white.opacity(0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule(style: .continuous)
                    .fill(isLyricsPaneOpen ? accentColor.opacity(0.32) : Color.white.opacity(0.06))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                isLyricsPaneOpen ? accentColor.opacity(0.60) : Color.white.opacity(0.10),
                                lineWidth: 0.7
                            )
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.93, enableAnimations: prefs.enableAnimations))
        .help(loc.text(es: "Mostrar u ocultar letras sincronizadas", en: "Toggle Synced Lyrics"))
    }

    private var demoIndicatorPill: some View {
        Button {
            media.stopDemoPreview()
        } label: {
            HStack(spacing: 3.5) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5.5, height: 5.5)
                Text("DEMO")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange.opacity(0.95))
            }
            .padding(.horizontal, 6.5)
            .padding(.vertical, 3.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.orange.opacity(0.16))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.orange.opacity(0.42), lineWidth: 0.7)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
        .help(loc.text(es: "Modo vista previa activo (clic para salir)", en: "Preview Demo active (click to exit)"))
    }

    // MARK: - Diseño 1: Reproductor Compacto de 2 Columnas (Estilo YouTube Music de Notchy)

    private func compactTwoColumnPlayerBody(
        track: NotchTrackInfo,
        elapsed: TimeInterval,
        progress: Double
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            // Columna izquierda: Carátula redondeada con resplandor (opcional)
            if prefs.showAlbumArtwork {
                expandedArtworkView(
                    track: track,
                    size: compactArtworkDimension,
                    cornerRadius: 16
                )
            }

            // Columna derecha: Metadatos + Ecualizador + Scrubber interactivo + Transporte
            VStack(alignment: .leading, spacing: 9) {
                // Título (marquee), artista/álbum y ecualizador
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        NotchMarqueeTextView(
                            text: track.title,
                            font: .system(size: 14.5, weight: .bold),
                            color: .white,
                            enableMarquee: prefs.enableMarqueeTitle,
                            alignment: .leading,
                            speed: prefs.scaledMarqueeSpeed(28)
                        )
                        .frame(height: 19)

                        NotchMarqueeTextView(
                            text: track.displaySubtitle(includeAlbum: prefs.showAlbumName),
                            font: .system(size: 11.8, weight: .medium),
                            color: Color.white.opacity(0.66),
                            enableMarquee: prefs.enableMarqueeTitle,
                            alignment: .leading,
                            speed: prefs.scaledMarqueeSpeed(24),
                            pauseDuration: 2.8
                        )
                        .frame(height: 15)
                    }

                    if prefs.showVisualizerBars {
                        NotchEqualizerVisualizerView(
                            isPlaying: track.isPlaying,
                            accentColor: accentColor,
                            barCount: 5,
                            barWidth: 2.6,
                            barSpacing: 2.3,
                            maxHeight: 16,
                            enableAnimations: prefs.enableAnimations,
                            style: prefs.visualizerStyle,
                            speedMultiplier: prefs.animationSpeed
                        )
                        .padding(.trailing, 2)
                    }
                }

                // Barra de progreso interactiva con tiempos monoespaciados
                NotchScrubberBarView(
                    elapsed: elapsed,
                    duration: track.duration,
                    progress: progress,
                    accentColor: accentColor,
                    isSeekable: track.supportsSeeking && track.hasKnownDuration,
                    hasKnownDuration: track.hasKnownDuration,
                    showRemainingTime: $showRemainingTime,
                    enableAnimations: prefs.enableAnimations,
                    onSeek: { newSeconds in
                        media.seek(to: newSeconds)
                    }
                )

                // Controles de transporte centrados (+ shuffle / repeat / like cuando están disponibles)
                transportControlsRow(track: track, compact: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Diseño 2: Vista Dividida con Letras Sincronizadas (Estilo Notchy)

    private func splitLyricsPlayerBody(
        track: NotchTrackInfo,
        elapsed: TimeInterval,
        progress: Double
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Columna izquierda: Carátula + Título/Artista/Álbum + Scrubber compacto + Transporte
            VStack(alignment: .center, spacing: 5.5) {
                if prefs.showAlbumArtwork {
                    expandedArtworkView(
                        track: track,
                        size: 56,
                        cornerRadius: 13
                    )
                }

                VStack(spacing: 1.5) {
                    NotchMarqueeTextView(
                        text: track.title,
                        font: .system(size: 12.8, weight: .bold),
                        color: .white,
                        enableMarquee: prefs.enableMarqueeTitle,
                        alignment: .center,
                        speed: prefs.scaledMarqueeSpeed(26)
                    )
                    .frame(height: 16)

                    NotchMarqueeTextView(
                        text: track.displaySubtitle(includeAlbum: prefs.showAlbumName),
                        font: .system(size: 10.8, weight: .medium),
                        color: Color.white.opacity(0.62),
                        enableMarquee: prefs.enableMarqueeTitle,
                        alignment: .center,
                        speed: prefs.scaledMarqueeSpeed(22)
                    )
                    .frame(height: 14)
                }

                NotchScrubberBarView(
                    elapsed: elapsed,
                    duration: track.duration,
                    progress: progress,
                    accentColor: accentColor,
                    isSeekable: track.supportsSeeking && track.hasKnownDuration,
                    hasKnownDuration: track.hasKnownDuration,
                    showRemainingTime: $showRemainingTime,
                    enableAnimations: prefs.enableAnimations,
                    compact: true,
                    onSeek: { newSeconds in
                        media.seek(to: newSeconds)
                    }
                )

                transportControlsRow(track: track, compact: true)
                    .padding(.top, 1)
            }
            .padding(.bottom, 3)
            .frame(width: 206)

            // Separador vertical translúcido
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.02),
                            Color.white.opacity(0.13),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
                .padding(.vertical, 6)

            // Columna derecha: Letras sincronizadas tipo karaoke con scroll automático
            NotchSyncedLyricsColumnView(
                lyricsState: lyricsAudio.lyricsState,
                elapsedTime: elapsed,
                accentColor: accentColor,
                supportsSeeking: track.supportsSeeking,
                enableAnimations: prefs.enableAnimations,
                lyricsFontSize: prefs.lyricsFontSize,
                loc: loc,
                onSeekToLine: { seconds in
                    if track.supportsSeeking {
                        media.seek(to: seconds)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Carátula Expandida con Resplandor + Insignia de Fuente

    private func expandedArtworkView(
        track: NotchTrackInfo,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        let appIcon = track.sourceApp.appIcon(bundleID: track.sourceBundleID)

        return Button {
            media.openSourceApp()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    if let artworkImage {
                        Image(nsImage: artworkImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.88),
                                    accentColor.opacity(0.32),
                                    Color(white: 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: track.sourceApp.symbolName)
                                .font(.system(size: size * 0.36, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                }
                .id(track.id)
                .transition(
                    prefs.enableAnimations
                        ? .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.88)),
                            removal: .opacity.combined(with: .scale(scale: 1.06))
                        )
                        : .identity
                )
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.85)
                )
                .shadow(
                    color: prefs.showAmbientArtworkGlow ? accentColor.opacity(0.68 * prefs.ambientGlowIntensity) : Color.black.opacity(0.55),
                    radius: prefs.showAmbientArtworkGlow ? 14 : 8,
                    x: 0,
                    y: 5
                )

                // Mini-insignia de la app de origen en esquina inferior derecha (configurable)
                if prefs.showSourceBadgeOnArtwork {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.86))
                        if let appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 15, height: 15)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: track.sourceApp.symbolName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(track.sourceApp.swiftUIAccentColor)
                        }
                    }
                    .frame(width: 21, height: 21)
                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.75))
                    .offset(x: 4, y: 4)
                }
            }
            .scaleEffect(
                prefs.enableAnimations
                    ? (isArtworkHovered ? 1.035 : (track.isPlaying ? 1.0 : 0.94))
                    : 1.0
            )
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.36),
                value: track.isPlaying
            )
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.28),
                value: isArtworkHovered
            )
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.38),
                value: track.id
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isArtworkHovered = hovering
        }
        .help(loc.text(es: "Abrir \(track.sourceAppName)", en: "Open \(track.sourceAppName)"))
    }

    // MARK: - Fila de Controles de Transporte

    private func transportControlsRow(track: NotchTrackInfo, compact: Bool) -> some View {
        let playSize: CGFloat = compact ? 31 : 36
        let skipSize: CGFloat = compact ? 26 : 30
        let skipIconSize: CGFloat = compact ? 13 : 15

        return HStack(spacing: compact ? 10 : 12) {
            if !compact && track.supportsShuffleRepeat {
                secondaryTransportButton(
                    id: "shuffle",
                    systemName: "shuffle",
                    isActive: track.isShuffling,
                    activeColor: accentColor,
                    help: loc.text(es: "Aleatorio", en: "Shuffle")
                ) {
                    media.toggleShuffle()
                }
            }

            Spacer(minLength: 0)

            // Canción anterior
            Button {
                media.previousTrack()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(hoveredControlID == "prev" ? 0.14 : 0.0))
                    Image(systemName: "backward.fill")
                        .font(.system(size: skipIconSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(hoveredControlID == "prev" ? 1.0 : 0.88))
                }
                .frame(width: skipSize, height: skipSize)
                .contentShape(Circle())
            }
            .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.84, enableAnimations: prefs.enableAnimations))
            .onHover { hoveredControlID = $0 ? "prev" : (hoveredControlID == "prev" ? nil : hoveredControlID) }
            .help(loc.text(es: "Canción anterior", en: "Previous Track"))

            // Botón principal circular frosted Reproducir / Pausar
            Button {
                media.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(hoveredControlID == "play" ? 0.28 : 0.20),
                                    Color.white.opacity(hoveredControlID == "play" ? 0.16 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .stroke(
                            Color.white.opacity(hoveredControlID == "play" ? 0.36 : 0.22),
                            lineWidth: 0.9
                        )
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 13.5 : 15.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .offset(x: track.isPlaying ? 0 : 1.0)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: playSize, height: playSize)
                .shadow(
                    color: prefs.showAmbientArtworkGlow ? accentColor.opacity(0.32) : Color.black.opacity(0.35),
                    radius: 8,
                    y: 2
                )
                .contentShape(Circle())
            }
            .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.86, enableAnimations: prefs.enableAnimations))
            .onHover { hoveredControlID = $0 ? "play" : (hoveredControlID == "play" ? nil : hoveredControlID) }
            .help(
                track.isPlaying
                    ? loc.text(es: "Pausar", en: "Pause")
                    : loc.text(es: "Reproducir", en: "Play")
            )

            // Siguiente canción
            Button {
                media.nextTrack()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(hoveredControlID == "next" ? 0.14 : 0.0))
                    Image(systemName: "forward.fill")
                        .font(.system(size: skipIconSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(hoveredControlID == "next" ? 1.0 : 0.88))
                }
                .frame(width: skipSize, height: skipSize)
                .contentShape(Circle())
            }
            .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.84, enableAnimations: prefs.enableAnimations))
            .onHover { hoveredControlID = $0 ? "next" : (hoveredControlID == "next" ? nil : hoveredControlID) }
            .help(loc.text(es: "Siguiente canción", en: "Next Track"))

            Spacer(minLength: 0)

            if !compact {
                HStack(spacing: 4) {
                    if track.supportsShuffleRepeat {
                        secondaryTransportButton(
                            id: "repeat",
                            systemName: track.repeatMode.symbolName,
                            isActive: track.repeatMode.isActive,
                            activeColor: accentColor,
                            help: track.repeatMode.localizedTitle(using: loc)
                        ) {
                            media.cycleRepeatMode()
                        }
                    }

                    if let isLiked = track.isLiked {
                        secondaryTransportButton(
                            id: "like",
                            systemName: isLiked ? "heart.fill" : "heart",
                            isActive: isLiked,
                            activeColor: Color(red: 1.0, green: 0.28, blue: 0.44),
                            help: isLiked
                                ? loc.text(es: "Quitar de Me gusta", en: "Unlike")
                                : loc.text(es: "Me gusta", en: "Like")
                        ) {
                            media.toggleLike()
                        }
                    }
                }
            }
        }
    }

    private func secondaryTransportButton(
        id: String,
        systemName: String,
        isActive: Bool,
        activeColor: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredControlID == id
        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isActive
                            ? activeColor.opacity(0.20)
                            : Color.white.opacity(isHovered ? 0.12 : 0.0)
                    )
                Image(systemName: systemName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : Color.white.opacity(isHovered ? 0.90 : 0.54))
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.84, enableAnimations: prefs.enableAnimations))
        .onHover { hoveredControlID = $0 ? id : (hoveredControlID == id ? nil : hoveredControlID) }
        .help(help)
    }

    // MARK: - Selector Integrado de Salida de Audio CoreAudio (Sin Robar Foco)

    private var audioOutputPickerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                    Text(loc.text(es: "Salida de audio", en: "Audio Output"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    toggleTopOverlay(.audioOutput)
                } label: {
                    Text(loc.text(es: "Volver", en: "Done"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
            }

            if lyricsAudio.outputDevices.isEmpty {
                Text(loc.text(es: "No se detectaron dispositivos de salida.", en: "No audio output devices found."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(lyricsAudio.outputDevices) { device in
                            Button {
                                lyricsAudio.setDefaultOutputDevice(device)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(device.isDefault ? accentColor.opacity(0.24) : Color.white.opacity(0.08))
                                        Image(systemName: device.systemImage)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(device.isDefault ? accentColor : Color.white.opacity(0.82))
                                    }
                                    .frame(width: 26, height: 26)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(device.name)
                                            .font(.system(size: 12, weight: device.isDefault ? .semibold : .medium))
                                            .foregroundStyle(Color.white.opacity(device.isDefault ? 0.98 : 0.82))
                                            .lineLimit(1)
                                        Text(device.transportType)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.white.opacity(0.48))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if device.isDefault {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13.5))
                                            .foregroundStyle(accentColor)
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(device.isDefault ? accentColor.opacity(0.14) : Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(
                                                    device.isDefault ? accentColor.opacity(0.42) : Color.white.opacity(0.07),
                                                    lineWidth: 0.75
                                                )
                                        )
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.97, enableAnimations: prefs.enableAnimations))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Panel Integrado de Volumen del Sistema (CoreAudio HAL, Sin Robar Foco)

    private var volumeControlView: some View {
        let volPct = Int((lyricsAudio.outputVolume * 100.0).rounded())
        let deviceName = lyricsAudio.defaultOutputDevice?.name ?? loc.text(es: "Salida del sistema", en: "System Output")

        return VStack(alignment: .leading, spacing: 10) {
            // Cabecera compacta
            HStack(spacing: 6) {
                Image(systemName: lyricsAudio.volumeSymbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(lyricsAudio.isMuted ? Color.orange : accentColor)
                Text(loc.text(es: "Volumen", en: "Volume"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                Text("· \(deviceName)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Button {
                    toggleTopOverlay(.volume)
                } label: {
                    Text(loc.text(es: "Volver", en: "Done"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
            }

            // Fila principal: Silencio + Deslizador interactivo + Porcentaje + Botones -/+
            HStack(spacing: 10) {
                Button {
                    lyricsAudio.toggleMute()
                } label: {
                    ZStack {
                        Circle()
                            .fill(lyricsAudio.isMuted ? Color.orange.opacity(0.24) : Color.white.opacity(0.10))
                            .overlay(
                                Circle()
                                    .stroke(lyricsAudio.isMuted ? Color.orange.opacity(0.60) : Color.white.opacity(0.14), lineWidth: 0.8)
                            )
                        Image(systemName: lyricsAudio.volumeSymbolName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(lyricsAudio.isMuted ? Color.orange : .white)
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.88, enableAnimations: prefs.enableAnimations))
                .help(lyricsAudio.isMuted ? loc.text(es: "Quitar silencio", en: "Unmute") : loc.text(es: "Silenciar", en: "Mute"))

                NotchVolumeSliderBarView(
                    value: lyricsAudio.isMuted ? 0.0 : lyricsAudio.outputVolume,
                    accentColor: lyricsAudio.isMuted ? Color.orange : accentColor,
                    enableAnimations: prefs.enableAnimations
                ) { newVol in
                    lyricsAudio.setOutputVolume(newVol)
                }

                Text(lyricsAudio.isMuted ? loc.text(es: "Mudo", en: "Mute") : "\(volPct)%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(lyricsAudio.isMuted ? Color.orange : .white)
                    .frame(width: 40, alignment: .trailing)

                HStack(spacing: 4) {
                    volumeStepButton(symbol: "minus", help: loc.text(es: "Bajar volumen (-10%)", en: "Volume Down (-10%)")) {
                        lyricsAudio.stepOutputVolume(by: -0.10)
                    }
                    volumeStepButton(symbol: "plus", help: loc.text(es: "Subir volumen (+10%)", en: "Volume Up (+10%)")) {
                        lyricsAudio.stepOutputVolume(by: 0.10)
                    }
                }
            }

            // Fila inferior: Accesos rápidos de nivel (Silencio, 25%, 50%, 75%, 100%)
            HStack(spacing: 6) {
                let quickLevels: [(label: String, level: Double, isMutePreset: Bool)] = [
                    (loc.text(es: "Silencio", en: "Mute"), 0.0, true),
                    ("25%", 0.25, false),
                    ("50%", 0.50, false),
                    ("75%", 0.75, false),
                    ("100%", 1.00, false)
                ]
                ForEach(quickLevels, id: \.label) { preset in
                    let isSelected = preset.isMutePreset
                        ? lyricsAudio.isMuted
                        : (!lyricsAudio.isMuted && abs(lyricsAudio.outputVolume - preset.level) < 0.05)
                    Button {
                        if preset.isMutePreset {
                            if !lyricsAudio.isMuted { lyricsAudio.toggleMute() }
                        } else {
                            lyricsAudio.setOutputVolume(preset.level)
                        }
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.70))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? accentColor.opacity(0.32) : Color.white.opacity(0.07))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(isSelected ? accentColor.opacity(0.65) : Color.white.opacity(0.09), lineWidth: 0.7)
                                    )
                            )
                    }
                    .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.94, enableAnimations: prefs.enableAnimations))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func volumeStepButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.11))
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.7))
                )
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.86, enableAnimations: prefs.enableAnimations))
        .help(help)
    }

    // MARK: - Panel Integrado de Ecualizador de Sonido de 5 Bandas (Real-Time DSP)

    private var equalizerControlView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Cabecera: Título + Switch ON/OFF + Estado + Plano + Volver
            HStack(spacing: 6) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(prefs.isEqualizerEnabled ? accentColor : Color.white.opacity(0.7))
                Text(loc.text(es: "Ecualizador", en: "Equalizer"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)

                // Botón ON / OFF del ecualizador en tiempo real
                Button {
                    prefs.isEqualizerEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(
                                prefs.isEqualizerEnabled
                                    ? (eqEngine.status == .activeSystemDSP ? Color.green : Color.orange)
                                    : Color.white.opacity(0.35)
                            )
                            .frame(width: 6, height: 6)
                        Text(prefs.isEqualizerEnabled ? loc.text(es: "Activo", en: "On") : loc.text(es: "Apagado", en: "Off"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(prefs.isEqualizerEnabled ? .white : Color.white.opacity(0.65))
                    }
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(prefs.isEqualizerEnabled ? accentColor.opacity(0.32) : Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(prefs.isEqualizerEnabled ? accentColor.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 0.7)
                            )
                    )
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.93, enableAnimations: prefs.enableAnimations))

                Spacer(minLength: 4)

                Button {
                    prefs.resetEqualizerToFlat()
                } label: {
                    Text(loc.text(es: "Plano", en: "Flat"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
                .help(loc.text(es: "Restablecer todas las bandas a 0 dB", en: "Reset all bands to 0 dB"))

                Button {
                    toggleTopOverlay(.equalizer)
                } label: {
                    Text(loc.text(es: "Volver", en: "Done"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
            }

            // Presets horizontales en 1 clic
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(NotchEQPreset.selectablePresets) { preset in
                        let selected = prefs.eqPreset == preset
                        Button {
                            prefs.applyEQPreset(preset)
                        } label: {
                            Text(preset.localizedTitle(using: loc))
                                .font(.system(size: 10, weight: selected ? .bold : .medium))
                                .foregroundStyle(selected ? .white : Color.white.opacity(0.72))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selected ? accentColor.opacity(0.36) : Color.white.opacity(0.07))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(selected ? accentColor.opacity(0.72) : Color.white.opacity(0.09), lineWidth: 0.7)
                                        )
                                )
                        }
                        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.94, enableAnimations: prefs.enableAnimations))
                    }
                }
            }

            if eqEngine.status == .permissionRequired && prefs.isEqualizerEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(loc.text(
                        es: "Permití «Grabación de audio del sistema» para aplicar el EQ en vivo.",
                        en: "Allow \"System Audio Recording\" in Privacy to apply live EQ."
                    ))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    Spacer(minLength: 4)
                    Button {
                        eqEngine.openSystemAudioPrivacySettings()
                    } label: {
                        Text(loc.text(es: "Abrir Ajustes", en: "Open Settings"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.orange))
                    }
                    .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.93, enableAnimations: prefs.enableAnimations))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange.opacity(0.45), lineWidth: 0.7))
                )
            } else {
                // 5 faders verticales interactivos (-12 dB .. +12 dB)
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { index in
                        let gain = index < prefs.eqBandGains.count ? prefs.eqBandGains[index] : 0.0
                        NotchEQVerticalBandSlider(
                            label: NotchEQPreset.bandLabels[index],
                            gainDB: gain,
                            accentColor: accentColor,
                            isEnabled: prefs.isEqualizerEnabled
                        ) { newDB in
                            prefs.setEQBandGain(newDB, at: index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Estado Vacío (Sin Música Reproduciéndose — Accesos Rápidos para Reabrir)

    private var idleEmptyPlayerBody: some View {
        let launchers = media.quickLaunchApps()
        let primaryLauncher = launchers.first
        let secondaryLaunchers = Array(launchers.dropFirst())
        let primaryAccent = primaryLauncher?.source.swiftUIAccentColor ?? accentColor

        return HStack(spacing: 14) {
            // Ícono real de la última app reproducida (o YouTube Music) con clic directo para reabrir
            Button {
                if let primaryLauncher {
                    media.launchQuickApp(primaryLauncher)
                } else {
                    media.refreshNow()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    primaryAccent.opacity(0.32),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 0.85)
                        )

                    if let primaryLauncher,
                       let appIcon = primaryLauncher.source.appIcon(bundleID: primaryLauncher.bundleID) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: Color.black.opacity(0.35), radius: 4, y: 2)
                    } else {
                        Image(systemName: primaryLauncher?.source.symbolName ?? "waveform")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                    }
                }
                .frame(width: 62, height: 62)
            }
            .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.94, enableAnimations: prefs.enableAnimations))
            .help(
                primaryLauncher.map {
                    loc.text(es: "Abrir \($0.name)", en: "Open \($0.name)")
                } ?? loc.text(es: "Detectar reproducción", en: "Detect playback")
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(loc.text(es: "Sin música sonando", en: "Nothing playing"))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let lastSubtitle = primaryLauncher?.lastTrackSubtitle, !lastSubtitle.isEmpty {
                    Text(
                        loc.text(
                            es: "Último: \(lastSubtitle)",
                            en: "Last played: \(lastSubtitle)"
                        )
                    )
                    .font(.system(size: 11.2, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .truncationMode(.tail)
                } else {
                    Text(
                        loc.text(
                            es: "Volvé a abrir tu reproductor para escuchar música.",
                            en: "Reopen your music app to start listening."
                        )
                    )
                    .font(.system(size: 11.2))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
                }

                HStack(spacing: 6) {
                    if let primary = primaryLauncher {
                        Button {
                            media.launchQuickApp(primary)
                        } label: {
                            HStack(spacing: 5) {
                                if let icon = primary.source.appIcon(bundleID: primary.bundleID) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 13, height: 13)
                                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                                } else {
                                    Image(systemName: primary.source.symbolName)
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                Text(loc.text(es: "Abrir \(primary.name)", en: "Open \(primary.name)"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(primary.source.swiftUIAccentColor.opacity(0.46))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.white.opacity(0.24), lineWidth: 0.75)
                                    )
                            )
                        }
                        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.94, enableAnimations: prefs.enableAnimations))
                        .help(loc.text(es: "Abrir \(primary.name)", en: "Open \(primary.name)"))
                    }

                    ForEach(secondaryLaunchers) { app in
                        Button {
                            media.launchQuickApp(app)
                        } label: {
                            Group {
                                if let icon = app.source.appIcon(bundleID: app.bundleID) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 15, height: 15)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                } else {
                                    Image(systemName: app.source.symbolName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.84))
                                }
                            }
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.11))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
                                    )
                            )
                        }
                        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
                        .help(loc.text(es: "Abrir \(app.name)", en: "Open \(app.name)"))
                    }

                    Button {
                        media.refreshNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.76))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.09))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                                    )
                            )
                    }
                    .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
                    .help(loc.text(es: "Detectar música ahora", en: "Detect Music Now"))
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Barra de Progreso Interactiva (Scrubber con Arrastre y Clic)

public struct NotchScrubberBarView: View {
    public let elapsed: TimeInterval
    public let duration: TimeInterval
    public let progress: Double
    public let accentColor: Color
    public let isSeekable: Bool
    public let hasKnownDuration: Bool
    @Binding public var showRemainingTime: Bool
    public let enableAnimations: Bool
    public let compact: Bool
    public let onSeek: (TimeInterval) -> Void

    @ViewState private var isHovered: Bool = false
    @ViewState private var isDragging: Bool = false
    @ViewState private var dragProgress: Double = 0
    @ViewState private var didPushCursor: Bool = false

    public init(
        elapsed: TimeInterval,
        duration: TimeInterval,
        progress: Double,
        accentColor: Color,
        isSeekable: Bool,
        hasKnownDuration: Bool,
        showRemainingTime: Binding<Bool>,
        enableAnimations: Bool = true,
        compact: Bool = false,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.elapsed = elapsed
        self.duration = duration
        self.progress = progress
        self.accentColor = accentColor
        self.isSeekable = isSeekable
        self.hasKnownDuration = hasKnownDuration
        self._showRemainingTime = showRemainingTime
        self.enableAnimations = enableAnimations
        self.compact = compact
        self.onSeek = onSeek
    }

    private var effectiveProgress: Double {
        min(max(isDragging ? dragProgress : progress, 0), 1)
    }

    private var displayedElapsed: TimeInterval {
        isDragging ? (effectiveProgress * duration) : elapsed
    }

    public var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let trackHeight: CGFloat = (isHovered || isDragging) && isSeekable ? 5.5 : 4.0
                let thumbSize: CGFloat = isDragging ? 11.5 : (isHovered ? 9.5 : 0)
                let filledWidth = max(hasKnownDuration ? 2 : width * 0.35, width * CGFloat(hasKnownDuration ? effectiveProgress : 0.35))

                ZStack(alignment: .leading) {
                    // Pista base translúcida
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(height: trackHeight)

                    // Progreso relleno luminoso
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.92),
                                    Color.white.opacity(0.96)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: min(width, filledWidth), height: trackHeight)
                        .shadow(color: accentColor.opacity(0.45), radius: 3, y: 0)

                    // Cabezal blanco brillante al pasar el puntero o arrastrar
                    if isSeekable && thumbSize > 0.1 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: thumbSize, height: thumbSize)
                            .shadow(color: accentColor.opacity(0.70), radius: 4)
                            .shadow(color: Color.black.opacity(0.45), radius: 2)
                            .offset(x: min(max(0, width * CGFloat(effectiveProgress) - thumbSize * 0.5), width - thumbSize))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isSeekable, duration > 0.5 else { return }
                            isDragging = true
                            let ratio = min(max(Double(value.location.x / width), 0), 1)
                            dragProgress = ratio
                        }
                        .onEnded { value in
                            guard isSeekable, duration > 0.5 else {
                                isDragging = false
                                return
                            }
                            let ratio = min(max(Double(value.location.x / width), 0), 1)
                            dragProgress = ratio
                            isDragging = false
                            onSeek(ratio * duration)
                        }
                )
            }
            .frame(height: 18)
            .onHover { hovering in
                if isSeekable {
                    if hovering && !didPushCursor {
                        NSCursor.pointingHand.push()
                        didPushCursor = true
                    } else if !hovering && didPushCursor {
                        NSCursor.pop()
                        didPushCursor = false
                    }
                }
                if enableAnimations {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        isHovered = hovering
                    }
                } else {
                    isHovered = hovering
                }
            }
            .onDisappear {
                if didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }

            if hasKnownDuration {
                HStack {
                    Text(NotchTimeFormatter.string(from: displayedElapsed))
                        .font(.system(size: compact ? 9.5 : 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.62))

                    Spacer()

                    Button {
                        showRemainingTime.toggle()
                    } label: {
                        let rightLabel: String = {
                            if showRemainingTime {
                                let rem = max(0, duration - displayedElapsed)
                                return "-\(NotchTimeFormatter.string(from: rem))"
                            }
                            return NotchTimeFormatter.string(from: duration)
                        }()
                        Text(rightLabel)
                            .font(.system(size: compact ? 9.5 : 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.54))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Columna de Letras Sincronizadas en Vivo (Estilo Karaoke Notchy)

public struct NotchSyncedLyricsColumnView: View {
    public let lyricsState: NotchLyricsState
    public let elapsedTime: TimeInterval
    public let accentColor: Color
    public let supportsSeeking: Bool
    public let enableAnimations: Bool
    public let lyricsFontSize: NotchLyricsFontSize
    public let loc: LocalizationManager
    public let onSeekToLine: (TimeInterval) -> Void

    public init(
        lyricsState: NotchLyricsState,
        elapsedTime: TimeInterval,
        accentColor: Color,
        supportsSeeking: Bool,
        enableAnimations: Bool,
        lyricsFontSize: NotchLyricsFontSize = .normal,
        loc: LocalizationManager,
        onSeekToLine: @escaping (TimeInterval) -> Void
    ) {
        self.lyricsState = lyricsState
        self.elapsedTime = elapsedTime
        self.accentColor = accentColor
        self.supportsSeeking = supportsSeeking
        self.enableAnimations = enableAnimations
        self.lyricsFontSize = lyricsFontSize
        self.loc = loc
        self.onSeekToLine = onSeekToLine
    }

    public var body: some View {
        switch lyricsState {
        case .synced(let lines):
            syncedLinesScrollView(lines: lines)

        case .plain(let lines):
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: lyricsFontSize.lineSpacing - 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: lyricsFontSize.inactiveFontSize, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.76))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .mask(verticalFadeMask)

        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(loc.text(es: "Buscando letras sincronizadas…", en: "Fetching synced lyrics…"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .instrumental:
            VStack(spacing: 6) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accentColor.opacity(0.85))
                Text(loc.text(es: "Pista instrumental", en: "Instrumental Track"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .idle, .unavailable:
            VStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.36))
                Text(
                    loc.text(
                        es: "No hay letras sincronizadas para esta canción",
                        en: "No synced lyrics found for this track"
                    )
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncedLinesScrollView(lines: [NotchLyricLine]) -> some View {
        let activeIdx = NotchLyricsAndAudioService.activeLineIndex(in: lines, at: elapsedTime)
        let activeID = activeIdx.flatMap { lines.indices.contains($0) ? lines[$0].id : nil }

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: lyricsFontSize.lineSpacing) {
                    Color.clear.frame(height: 18)

                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = (index == activeIdx)
                        let isPast = (activeIdx != nil && index < activeIdx!)
                        let distance = activeIdx.map { abs($0 - index) } ?? 2

                        Button {
                            onSeekToLine(line.time)
                        } label: {
                            Text(line.text)
                                .font(.system(size: isActive ? lyricsFontSize.activeFontSize : lyricsFontSize.inactiveFontSize, weight: isActive ? .bold : .medium))
                                .foregroundStyle(
                                    isActive
                                        ? Color.white
                                        : (isPast
                                            ? Color.white.opacity(0.26)
                                            : Color.white.opacity(distance == 1 ? 0.52 : 0.34))
                                )
                                .shadow(
                                    color: isActive ? accentColor.opacity(0.55) : .clear,
                                    radius: isActive ? 6 : 0
                                )
                                .scaleEffect(isActive ? 1.02 : 1.0, anchor: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!supportsSeeking)
                        .id(line.id)
                        .animation(
                            enableAnimations ? .easeInOut(duration: 0.24) : nil,
                            value: isActive
                        )
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 4)
            }
            .mask(verticalFadeMask)
            .onAppear {
                if let activeID {
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
            .onChange(of: activeID) { _, newID in
                guard let newID else { return }
                if enableAnimations {
                    withAnimation(.easeInOut(duration: 0.38)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                } else {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private var verticalFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Deslizador Horizontal de Volumen del Notch (Arrastrable, Sin Robar Foco)

private struct NotchVolumeSliderBarView: View {
    let value: Double
    let accentColor: Color
    let enableAnimations: Bool
    let onChange: (Double) -> Void

    @ViewState private var isDragging: Bool = false
    @ViewState private var dragValue: Double = 0.5

    private var displayedValue: Double {
        min(max(isDragging ? dragValue : value, 0.0), 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let filled = max(6, w * CGFloat(displayedValue))
            let knobSize: CGFloat = isDragging ? 14 : 12

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 6)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.92), Color.white.opacity(0.96)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: min(w, filled), height: 6)
                    .shadow(color: accentColor.opacity(0.50), radius: 3)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: accentColor.opacity(0.65), radius: 4)
                    .shadow(color: Color.black.opacity(0.45), radius: 2)
                    .offset(x: min(max(0, w * CGFloat(displayedValue) - knobSize * 0.5), w - knobSize))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let ratio = min(max(Double(gesture.location.x / w), 0.0), 1.0)
                        dragValue = ratio
                        onChange(ratio)
                    }
                    .onEnded { gesture in
                        let ratio = min(max(Double(gesture.location.x / w), 0.0), 1.0)
                        dragValue = ratio
                        isDragging = false
                        onChange(ratio)
                    }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - Fader Vertical de Banda del Ecualizador (5 Bandas, -12 dB a +12 dB)

private struct NotchEQVerticalBandSlider: View {
    let label: String
    let gainDB: Double
    let accentColor: Color
    let isEnabled: Bool
    let onChange: (Double) -> Void

    @ViewState private var isDragging: Bool = false

    private var formattedGain: String {
        let rounded = (gainDB * 2.0).rounded() / 2.0
        if abs(rounded) < 0.1 { return "0" }
        let prefix = rounded > 0 ? "+" : ""
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(prefix)\(Int(rounded))"
        }
        return String(format: "%@%.1f", prefix, rounded)
    }

    var body: some View {
        VStack(spacing: 1.5) {
            Text(formattedGain)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(
                    abs(gainDB) >= 0.4 && isEnabled
                        ? accentColor
                        : Color.white.opacity(0.55)
                )

            GeometryReader { geo in
                let h = max(geo.size.height, 16)
                let normalized = min(max((gainDB + 12.0) / 24.0, 0.0), 1.0)
                let thumbY = h * (1.0 - CGFloat(normalized))
                let centerY = h * 0.5
                let fillTop = min(thumbY, centerY)
                let fillHeight = max(2, abs(thumbY - centerY))
                let trackTint = isEnabled ? accentColor : Color.white.opacity(0.45)

                ZStack {
                    // Línea central de 0 dB
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 12, height: 1)
                        .position(x: geo.size.width * 0.5, y: centerY)

                    // Pista vertical
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 4, height: h)
                        .position(x: geo.size.width * 0.5, y: h * 0.5)

                    // Relleno desde 0 dB hasta el valor actual
                    Capsule(style: .continuous)
                        .fill(trackTint.opacity(isEnabled ? 0.92 : 0.45))
                        .frame(width: 4, height: fillHeight)
                        .position(x: geo.size.width * 0.5, y: fillTop + fillHeight * 0.5)

                    // Cabezal táctil
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 11 : 9, height: isDragging ? 11 : 9)
                        .shadow(color: trackTint.opacity(0.65), radius: 3)
                        .position(x: geo.size.width * 0.5, y: min(max(5, thumbY), h - 5))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            let ratio = 1.0 - min(max(Double(gesture.location.y / h), 0.0), 1.0)
                            let rawDB = (ratio * 24.0) - 12.0
                            onChange(rawDB)
                        }
                        .onEnded { gesture in
                            let ratio = 1.0 - min(max(Double(gesture.location.y / h), 0.0), 1.0)
                            let rawDB = (ratio * 24.0) - 12.0
                            isDragging = false
                            onChange(rawDB)
                        }
                )
            }
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 56)

            Text(label)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
