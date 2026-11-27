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
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var isAudioPickerOpen: Bool = false
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
        return track.isPlaying && !isAudioPickerOpen
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
                .padding(.bottom, isLyricsPaneOpen ? 7 : 10)

            // Cuerpo principal: Selector de audio / Estado vacío / Letras divididas / Reproductor 2 columnas
            ZStack {
                if isAudioPickerOpen {
                    audioOutputPickerView
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
                } else {
                    idleEmptyPlayerBody
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.34),
                value: isAudioPickerOpen
            )
            .animation(
                prefs.resolvedAnimation(baseResponse: 0.36),
                value: isLyricsPaneOpen
            )
        }
    }

    // MARK: - Barra Superior de Controles

    private var headerStrip: some View {
        HStack(spacing: 8) {
            // Grupo izquierdo: cápsula oscura con insignia de fuente + píldora de letras + demo
            HStack(spacing: 5) {
                sourceAppPill

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

            Spacer(minLength: 8)

            // Grupo derecho: micro-botones circulares translúcidos
            HStack(spacing: 6) {
                let rawAudioSymbol = lyricsAudio.defaultOutputDevice?.systemImage ?? "speaker.wave.2.fill"
                let safeAudioSymbol = NSImage(systemSymbolName: rawAudioSymbol, accessibilityDescription: nil) != nil
                    ? rawAudioSymbol
                    : "speaker.wave.2.fill"

                NotchHeaderMicroButton(
                    systemName: safeAudioSymbol,
                    isActive: isAudioPickerOpen,
                    activeTint: accentColor,
                    helpText: loc.text(es: "Cambiar salida de audio", en: "Switch Audio Output"),
                    enableAnimations: prefs.enableAnimations
                ) {
                    lyricsAudio.refreshOutputDevices()
                    if prefs.enableAnimations {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            isAudioPickerOpen.toggle()
                        }
                    } else {
                        isAudioPickerOpen.toggle()
                    }
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
            if isAudioPickerOpen {
                isAudioPickerOpen = false
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
                    if prefs.enableAnimations {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isAudioPickerOpen = false
                        }
                    } else {
                        isAudioPickerOpen = false
                    }
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
