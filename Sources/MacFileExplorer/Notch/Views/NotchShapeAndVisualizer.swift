import AppKit
import SwiftUI

// MARK: - Forma Orgánica del Notch (Curvas Cóncavas Superiores + Esquinas Inferiores Continuas)

/// Silueta orgánica estilo Dynamic Island / Notchy:
/// - Anclada al borde superior (`isFloatingIsland == false`): dibuja orejas cóncavas fluidas
///   en las esquinas superior izquierda y superior derecha que nacen a ras de `y = 0`,
///   combinadas con esquinas inferiores redondeadas continuas (`bottomCornerRadius`).
/// - En pantallas sin notch físico (`isFloatingIsland == true`): cápsula / squircle continuo
///   flotante con radios suaves animados.
public struct OrganicNotchShape: Shape {
    public var topFlareRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var isFloatingIsland: Bool

    public init(
        topFlareRadius: CGFloat = 12,
        bottomCornerRadius: CGFloat = 16,
        isFloatingIsland: Bool = false
    ) {
        self.topFlareRadius = topFlareRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isFloatingIsland = isFloatingIsland
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFlareRadius, bottomCornerRadius) }
        set {
            topFlareRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 1, h > 1 else { return Path() }

        if isFloatingIsland {
            let r = min(max(bottomCornerRadius, 0), min(w, h) * 0.5)
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }

        let t = min(max(topFlareRadius, 0), min(w * 0.18, h * 0.48))
        let innerWidth = max(0, w - 2 * t)
        let b = min(max(bottomCornerRadius, 0), min(innerWidth * 0.48, max(0, h - t)))
        // Factor de curvatura superelíptica estilo Apple (más orgánico que un cuarto de círculo rígido)
        let kTop: CGFloat = 0.60
        let kBot: CGFloat = 0.58

        var path = Path()
        // Borde superior a ras de y = 0
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Oreja cóncava superior derecha: (maxX, minY) -> (maxX - t, minY + t)
        if t > 0.01 {
            path.addCurve(
                to: CGPoint(x: rect.maxX - t, y: rect.minY + t),
                control1: CGPoint(x: rect.maxX - t * kTop, y: rect.minY),
                control2: CGPoint(x: rect.maxX - t, y: rect.minY + t * (1 - kTop))
            )
        }

        // Lateral derecho
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b))

        // Esquina inferior derecha convexa continua
        if b > 0.01 {
            path.addCurve(
                to: CGPoint(x: rect.maxX - t - b, y: rect.maxY),
                control1: CGPoint(x: rect.maxX - t, y: rect.maxY - b * (1 - kBot)),
                control2: CGPoint(x: rect.maxX - t - b * (1 - kBot), y: rect.maxY)
            )
        }

        // Borde inferior
        path.addLine(to: CGPoint(x: rect.minX + t + b, y: rect.maxY))

        // Esquina inferior izquierda convexa continua
        if b > 0.01 {
            path.addCurve(
                to: CGPoint(x: rect.minX + t, y: rect.maxY - b),
                control1: CGPoint(x: rect.minX + t + b * (1 - kBot), y: rect.maxY),
                control2: CGPoint(x: rect.minX + t, y: rect.maxY - b * (1 - kBot))
            )
        }

        // Lateral izquierdo
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.minY + t))

        // Oreja cóncava superior izquierda: (minX + t, minY + t) -> (minX, minY)
        if t > 0.01 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control1: CGPoint(x: rect.minX + t, y: rect.minY + t * (1 - kTop)),
                control2: CGPoint(x: rect.minX + t * kTop, y: rect.minY)
            )
        }

        path.closeSubpath()
        return path
    }
}

/// Trazo de borde luminoso fino para `OrganicNotchShape`.
/// Cuando está anclado al borde superior (`isFloatingIsland == false`), omite la línea recta superior
/// `y = 0` para que el contorno se funda de forma invisible contra el bisel físico de la pantalla.
public struct OrganicNotchRimShape: Shape {
    public var topFlareRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var isFloatingIsland: Bool

    public init(
        topFlareRadius: CGFloat = 12,
        bottomCornerRadius: CGFloat = 16,
        isFloatingIsland: Bool = false
    ) {
        self.topFlareRadius = topFlareRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isFloatingIsland = isFloatingIsland
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFlareRadius, bottomCornerRadius) }
        set {
            topFlareRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 1, h > 1 else { return Path() }

        if isFloatingIsland {
            let r = min(max(bottomCornerRadius, 0), min(w, h) * 0.5)
            return Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: max(0, r - 0.5), style: .continuous)
        }

        let insetRect = CGRect(
            x: rect.minX + 0.5,
            y: rect.minY,
            width: max(0, rect.width - 1.0),
            height: max(0, rect.height - 0.5)
        )
        let iw = insetRect.width
        let ih = insetRect.height
        let t = min(max(topFlareRadius, 0), min(iw * 0.18, ih * 0.48))
        let innerWidth = max(0, iw - 2 * t)
        let b = min(max(bottomCornerRadius, 0), min(innerWidth * 0.48, max(0, ih - t)))
        let kTop: CGFloat = 0.60
        let kBot: CGFloat = 0.58

        var path = Path()
        // Comenzamos en la esquina superior derecha sin trazar el segmento recto superior
        path.move(to: CGPoint(x: insetRect.maxX, y: insetRect.minY))

        if t > 0.01 {
            path.addCurve(
                to: CGPoint(x: insetRect.maxX - t, y: insetRect.minY + t),
                control1: CGPoint(x: insetRect.maxX - t * kTop, y: insetRect.minY),
                control2: CGPoint(x: insetRect.maxX - t, y: insetRect.minY + t * (1 - kTop))
            )
        }

        path.addLine(to: CGPoint(x: insetRect.maxX - t, y: insetRect.maxY - b))

        if b > 0.01 {
            path.addCurve(
                to: CGPoint(x: insetRect.maxX - t - b, y: insetRect.maxY),
                control1: CGPoint(x: insetRect.maxX - t, y: insetRect.maxY - b * (1 - kBot)),
                control2: CGPoint(x: insetRect.maxX - t - b * (1 - kBot), y: insetRect.maxY)
            )
        }

        path.addLine(to: CGPoint(x: insetRect.minX + t + b, y: insetRect.maxY))

        if b > 0.01 {
            path.addCurve(
                to: CGPoint(x: insetRect.minX + t, y: insetRect.maxY - b),
                control1: CGPoint(x: insetRect.minX + t + b * (1 - kBot), y: insetRect.maxY),
                control2: CGPoint(x: insetRect.minX + t, y: insetRect.maxY - b * (1 - kBot))
            )
        }

        path.addLine(to: CGPoint(x: insetRect.minX + t, y: insetRect.minY + t))

        if t > 0.01 {
            path.addCurve(
                to: CGPoint(x: insetRect.minX, y: insetRect.minY),
                control1: CGPoint(x: insetRect.minX + t, y: insetRect.minY + t * (1 - kTop)),
                control2: CGPoint(x: insetRect.minX + t * kTop, y: insetRect.minY)
            )
        }

        return path
    }
}

// MARK: - Fondo OLED + Brillo Radial Ambiental de Carátula

/// Fondo característico estilo Notchy: negro puro `#000000` en la zona del bisel superior
/// fundiéndose en un resplandor radial ambiental teñido por el color dominante de la carátula,
/// rematado con un borde especular ultrafino.
public struct NotchAmbientBackdropView: View {
    public let accentColor: Color
    public let topFlareRadius: CGFloat
    public let bottomCornerRadius: CGFloat
    public let isFloatingIsland: Bool
    public let showAmbientGlow: Bool
    public let glowStrength: Double
    public let backgroundOpacity: Double
    public let isExpanded: Bool

    public init(
        accentColor: Color,
        topFlareRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        isFloatingIsland: Bool,
        showAmbientGlow: Bool,
        glowStrength: Double = 0.28,
        backgroundOpacity: Double = 1.0,
        isExpanded: Bool
    ) {
        self.accentColor = accentColor
        self.topFlareRadius = topFlareRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isFloatingIsland = isFloatingIsland
        self.showAmbientGlow = showAmbientGlow
        self.glowStrength = glowStrength
        self.backgroundOpacity = min(max(backgroundOpacity, 0.70), 1.0)
        self.isExpanded = isExpanded
    }

    public var body: some View {
        let shape = OrganicNotchShape(
            topFlareRadius: topFlareRadius,
            bottomCornerRadius: bottomCornerRadius,
            isFloatingIsland: isFloatingIsland
        )

        ZStack {
            // Base translúcida estilo vidrio oscuro cuando backgroundOpacity < 0.99
            if backgroundOpacity < 0.99 {
                shape.fill(.ultraThinMaterial)
            }

            // Base OLED negro profundo regulable por opacidad
            shape.fill(Color.black.opacity(backgroundOpacity))

            if showAmbientGlow {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    let h = max(geo.size.height, 1)
                    let strength = isExpanded ? glowStrength : glowStrength * 0.45

                    ZStack {
                        // Resplandor radial principal cerca de la carátula (izquierda-inferior)
                        RadialGradient(
                            colors: [
                                accentColor.opacity(strength),
                                accentColor.opacity(strength * 0.36),
                                Color.clear
                            ],
                            center: isExpanded ? UnitPoint(x: 0.22, y: 0.78) : UnitPoint(x: 0.18, y: 0.60),
                            startRadius: 4,
                            endRadius: max(w * 0.72, h * 1.15)
                        )

                        // Segundo halo atmosférico suave hacia el ecualizador / controles
                        RadialGradient(
                            colors: [
                                accentColor.opacity(strength * 0.50),
                                accentColor.opacity(strength * 0.14),
                                Color.clear
                            ],
                            center: isExpanded ? UnitPoint(x: 0.84, y: 0.76) : UnitPoint(x: 0.84, y: 0.60),
                            startRadius: 2,
                            endRadius: max(w * 0.55, h * 0.95)
                        )

                        // Sutil degradado superior en negro puro cuando está anclado al bisel
                        if !isFloatingIsland {
                            LinearGradient(
                                colors: [
                                    Color.black,
                                    Color.black.opacity(isExpanded ? 0.82 : 0.45),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: isExpanded ? 0.34 : 0.48)
                            )
                        }
                    }
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }

            // Borde especular ultrafino que aporta nitidez incluso sobre fondos oscuros
            OrganicNotchRimShape(
                topFlareRadius: topFlareRadius,
                bottomCornerRadius: bottomCornerRadius,
                isFloatingIsland: isFloatingIsland
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isFloatingIsland ? 0.16 : 0.03),
                        Color.white.opacity(isExpanded ? 0.13 : 0.11),
                        (showAmbientGlow ? accentColor.opacity(isExpanded ? 0.26 : 0.18) : Color.white.opacity(0.12))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.9
            )
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Ecualizador Musical Animado en Tiempo Real (4–5 Barras Orgánicas)

/// Visualizador de espectro animado a 30 fps mediante `TimelineView` con ondas multifrecuencia
/// orgánicas teñidas del color de la carátula. Al pausar, colapsa suavemente a puntos en reposo.
public struct NotchEqualizerVisualizerView: View {
    public let isPlaying: Bool
    public let accentColor: Color
    public let barCount: Int
    public let barWidth: CGFloat
    public let barSpacing: CGFloat
    public let maxHeight: CGFloat
    public let enableAnimations: Bool
    public let style: NotchVisualizerStyle
    public let speedMultiplier: Double

    public init(
        isPlaying: Bool,
        accentColor: Color,
        barCount: Int = 4,
        barWidth: CGFloat = 2.6,
        barSpacing: CGFloat = 2.2,
        maxHeight: CGFloat = 14,
        enableAnimations: Bool = true,
        style: NotchVisualizerStyle = .classicBars,
        speedMultiplier: Double = 1.0
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.barCount = max(3, min(barCount, 6))
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.maxHeight = maxHeight
        self.enableAnimations = enableAnimations
        self.style = style
        self.speedMultiplier = min(max(speedMultiplier, 0.5), 2.0)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || !enableAnimations)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * speedMultiplier
            Group {
                switch style {
                case .classicBars:
                    classicBarsView(time: t)
                case .waveformMirror:
                    waveformMirrorView(time: t)
                case .bouncingDots:
                    bouncingDotsView(time: t)
                case .pulseRing:
                    pulseRingView(time: t)
                }
            }
            .frame(height: maxHeight, alignment: .center)
            .animation(
                enableAnimations ? .spring(response: max(0.14, 0.34 / speedMultiplier), dampingFraction: 0.78) : nil,
                value: isPlaying
            )
        }
    }

    private func classicBarsView(time t: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let height = barHeight(for: index, time: t)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isPlaying ? 0.92 : 0.50),
                                accentColor.opacity(isPlaying ? 0.95 : 0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: height)
                    .shadow(color: isPlaying ? accentColor.opacity(0.45) : .clear, radius: 2.2, y: 0)
            }
        }
    }

    private func waveformMirrorView(time t: TimeInterval) -> some View {
        let needleCount = max(5, barCount + 2)
        let mid = Double(needleCount - 1) * 0.5
        return HStack(alignment: .center, spacing: max(1.4, barSpacing * 0.72)) {
            ForEach(0..<needleCount, id: \.self) { index in
                let dist = abs(Double(index) - mid) / max(mid, 1.0)
                let envelope = max(0.28, 1.0 - dist * 0.68)
                let raw = barHeight(for: index, time: t)
                let h = isPlaying ? max(2.8, raw * CGFloat(envelope)) : 2.6
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.85), Color.white.opacity(0.95), accentColor.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(1.8, barWidth * 0.78), height: h)
                    .shadow(color: isPlaying ? accentColor.opacity(0.50) : .clear, radius: 2.0)
            }
        }
    }

    private func bouncingDotsView(time t: TimeInterval) -> some View {
        let dotSize = max(3.2, barWidth * 1.35)
        let travel = max(2.0, (maxHeight - dotSize) * 0.42)
        return HStack(alignment: .center, spacing: max(2.4, barSpacing * 1.25)) {
            ForEach(0..<barCount, id: \.self) { index in
                let offsetY: CGFloat = {
                    guard isPlaying else { return 0 }
                    guard enableAnimations else {
                        let staticOffsets: [CGFloat] = [-0.5, 0.4, -0.7, 0.3, -0.4, 0.5]
                        return travel * staticOffsets[index % staticOffsets.count]
                    }
                    let phase = sin(t * 6.2 + Double(index) * 1.15)
                    return CGFloat(phase) * travel
                }()
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isPlaying ? 0.96 : 0.55), accentColor.opacity(isPlaying ? 0.95 : 0.48)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: offsetY)
                    .shadow(color: isPlaying ? accentColor.opacity(0.55) : .clear, radius: 2.2)
            }
        }
    }

    private func pulseRingView(time t: TimeInterval) -> some View {
        let pulse: Double = {
            guard isPlaying else { return 0.0 }
            guard enableAnimations else { return 0.65 }
            return sin(t * 5.2) * 0.5 + 0.5
        }()
        let ringSize = max(11, maxHeight)
        return ZStack {
            Circle()
                .stroke(accentColor.opacity(isPlaying ? (0.30 + pulse * 0.55) : 0.25), lineWidth: 1.5)
                .frame(width: ringSize * CGFloat(0.68 + pulse * 0.32), height: ringSize * CGFloat(0.68 + pulse * 0.32))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), accentColor],
                        center: .center,
                        startRadius: 0.5,
                        endRadius: ringSize * 0.36
                    )
                )
                .frame(width: ringSize * CGFloat(0.36 + pulse * 0.14), height: ringSize * CGFloat(0.36 + pulse * 0.14))
                .shadow(color: isPlaying ? accentColor.opacity(0.65) : .clear, radius: 3.5)
        }
        .frame(width: max(ringSize + 4, CGFloat(barCount) * (barWidth + barSpacing)), height: maxHeight)
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        let minDot = max(barWidth * 1.15, 2.8)
        guard isPlaying else { return minDot }
        guard enableAnimations else {
            let staticRatios: [CGFloat] = [0.58, 0.94, 0.72, 0.44, 0.82, 0.60]
            return max(minDot, maxHeight * staticRatios[index % staticRatios.count])
        }

        // Frecuencias primas / irracionales por barra para un movimiento musical natural sin repetición rígida
        let f1: [Double] = [5.4, 7.1, 6.2, 8.3, 5.9, 7.6]
        let f2: [Double] = [9.7, 11.3, 8.9, 12.1, 10.4, 9.1]
        let f3: [Double] = [3.1, 2.6, 3.7, 2.9, 3.4, 2.3]
        let p1: [Double] = [0.4, 1.9, 3.2, 0.8, 2.5, 4.1]
        let p2: [Double] = [1.2, 0.3, 2.7, 4.0, 1.6, 0.9]
        // Envolvente central ligeramente más alta como en Notchy
        let centerWeight: [Double] = [0.76, 1.00, 0.92, 0.74, 0.88, 0.70]

        let i = index % f1.count
        let waveA = sin(time * f1[i] + p1[i]) * 0.50 + 0.50
        let waveB = sin(time * f2[i] + p2[i]) * 0.50 + 0.50
        let groove = sin(time * f3[i] + Double(index) * 0.7) * 0.50 + 0.50
        let combined = (waveA * 0.52 + waveB * 0.30 + groove * 0.18) * centerWeight[i]

        let normalized = 0.24 + combined * 0.76
        return max(minDot, min(maxHeight, maxHeight * CGFloat(normalized)))
    }
}

// MARK: - Texto con Desplazamiento Marquee Suave y Difuminado en Bordes

/// Muestra un texto en una línea y, cuando excede el ancho disponible con `enableMarquee == true`,
/// lo desplaza suavemente con pausa inicial y degradado alfa en los bordes sin saltos ni jitter.
public struct NotchMarqueeTextView: View {
    public let text: String
    public let font: Font
    public let color: Color
    public let enableMarquee: Bool
    public let alignment: Alignment
    public let speed: CGFloat
    public let pauseDuration: Double
    public let gap: CGFloat

    @ViewState private var textWidth: CGFloat = 0
    @ViewState private var containerWidth: CGFloat = 0
    @ViewState private var anchorDate: Date = Date()

    public init(
        text: String,
        font: Font,
        color: Color = .white,
        enableMarquee: Bool = true,
        alignment: Alignment = .leading,
        speed: CGFloat = 28,
        pauseDuration: Double = 2.2,
        gap: CGFloat = 34
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.enableMarquee = enableMarquee
        self.alignment = alignment
        self.speed = speed
        self.pauseDuration = pauseDuration
        self.gap = gap
    }

    private var shouldScroll: Bool {
        enableMarquee && containerWidth > 4 && textWidth > containerWidth + 2
    }

    public var body: some View {
        // Base de layout estrictamente acotada: altura exacta de 1 línea y ancho flexible (0...∞)
        // para que el texto largo jamás empuje ni recorte elementos vecinos (carátula / ecualizador).
        Text(" ")
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
            .background(
                GeometryReader { containerProxy in
                    Color.clear
                        .onAppear {
                            if abs(containerWidth - containerProxy.size.width) > 0.5 {
                                containerWidth = containerProxy.size.width
                            }
                        }
                        .onChange(of: containerProxy.size.width) { _, newValue in
                            if abs(containerWidth - newValue) > 0.5 {
                                containerWidth = newValue
                            }
                        }
                        // Medición oculta del ancho intrínseco real dentro de overlay (sin alterar layout padre)
                        .overlay(alignment: .leading) {
                            Text(text)
                                .font(font)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .hidden()
                                .background(
                                    GeometryReader { textProxy in
                                        Color.clear
                                            .onAppear {
                                                if abs(textWidth - textProxy.size.width) > 0.5 {
                                                    textWidth = textProxy.size.width
                                                }
                                            }
                                            .onChange(of: textProxy.size.width) { _, newValue in
                                                if abs(textWidth - newValue) > 0.5 {
                                                    textWidth = newValue
                                                }
                                            }
                                    }
                                )
                        }
                }
            )
            .overlay(alignment: alignment) {
                if shouldScroll {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                        let offset = computeOffset(at: context.date)
                        HStack(spacing: gap) {
                            Text(text)
                                .font(font)
                                .foregroundStyle(color)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(text)
                                .font(font)
                                .foregroundStyle(color)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .offset(x: -offset)
                        .frame(width: containerWidth, alignment: .leading)
                        .clipped()
                        .mask(edgeFadeMask(isScrolling: offset > 1.0))
                    }
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
                }
            }
            .clipped()
            .onChange(of: text) { _, _ in
                anchorDate = Date()
            }
    }

    private func computeOffset(at now: Date) -> CGFloat {
        let cycleDistance = textWidth + gap
        guard cycleDistance > 1, speed > 1 else { return 0 }
        let travelDuration = Double(cycleDistance / speed)
        let totalCycle = pauseDuration + travelDuration
        let elapsed = max(0, now.timeIntervalSince(anchorDate))
        let local = elapsed.truncatingRemainder(dividingBy: totalCycle)
        guard local > pauseDuration else { return 0 }
        let movingTime = local - pauseDuration
        return min(cycleDistance, CGFloat(movingTime) * speed)
    }

    private func edgeFadeMask(isScrolling: Bool) -> some View {
        let fadeFraction = min(0.14, 14.0 / max(containerWidth, 40.0))
        return LinearGradient(
            stops: [
                .init(color: isScrolling ? .clear : .black, location: 0.0),
                .init(color: .black, location: isScrolling ? fadeFraction : 0.0),
                .init(color: .black, location: 1.0 - fadeFraction),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Insignia de Carátula (Circular con Anillo de Progreso o Cuadrada Redondeada)

/// Carátula animada compatible con modo circular + anillo de progreso en vivo (`.circleWithRing`)
/// y estilo Dynamic Island cuadrado redondeado (`.roundedSquare`), con crossfade + escala al cambiar de pista.
public struct NotchAlbumArtBadgeView: View {
    public let artworkImage: NSImage?
    public let trackID: String
    public let accentColor: Color
    public let progress: Double
    public let style: NotchArtworkStyle
    public let size: CGFloat
    public let isPlaying: Bool
    public let enableAnimations: Bool
    public let showProgressRing: Bool
    public let fallbackSymbol: String

    public init(
        artworkImage: NSImage?,
        trackID: String,
        accentColor: Color,
        progress: Double,
        style: NotchArtworkStyle,
        size: CGFloat,
        isPlaying: Bool,
        enableAnimations: Bool = true,
        showProgressRing: Bool = true,
        fallbackSymbol: String = "music.note"
    ) {
        self.artworkImage = artworkImage
        self.trackID = trackID
        self.accentColor = accentColor
        self.progress = progress
        self.style = style
        self.size = size
        self.isPlaying = isPlaying
        self.enableAnimations = enableAnimations
        self.showProgressRing = showProgressRing
        self.fallbackSymbol = fallbackSymbol
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    public var body: some View {
        let ringThickness: CGFloat = max(1.8, size * 0.085)
        let innerInset: CGFloat = (style == .circleWithRing && showProgressRing) ? (ringThickness + 1.4) : 0
        let cornerRadius: CGFloat = style == .circleWithRing ? size * 0.5 : max(5, size * 0.24)

        ZStack {
            if style == .circleWithRing && showProgressRing {
                // Pista sutil del anillo
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: ringThickness)

                // Arco de progreso en vivo
                Circle()
                    .trim(from: 0, to: max(0.015, clampedProgress))
                    .stroke(
                        AngularGradient(
                            colors: [
                                accentColor.opacity(0.75),
                                accentColor,
                                Color.white.opacity(0.92)
                            ],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * max(0.05, clampedProgress))
                        ),
                        style: StrokeStyle(lineWidth: ringThickness, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accentColor.opacity(0.55), radius: 2.4)
                    .animation(enableAnimations ? .linear(duration: 0.25) : nil, value: clampedProgress)
            }

            // Contenido de la carátula con crossfade + escala al cambiar de pista
            ZStack {
                if let artworkImage {
                    Image(nsImage: artworkImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.85),
                                accentColor.opacity(0.35),
                                Color(white: 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: max(10, (size - innerInset * 2) * 0.44), weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }
            .id(trackID)
            .transition(
                enableAnimations
                    ? .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.84)),
                        removal: .opacity.combined(with: .scale(scale: 1.08))
                    )
                    : .identity
            )
            .frame(width: max(8, size - innerInset * 2), height: max(8, size - innerInset * 2))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.65)
            )
        }
        .frame(width: size, height: size)
        .scaleEffect(isPlaying || !enableAnimations ? 1.0 : 0.93)
        .animation(
            enableAnimations ? .spring(response: 0.36, dampingFraction: 0.72) : nil,
            value: isPlaying
        )
        .animation(
            enableAnimations ? .spring(response: 0.38, dampingFraction: 0.80) : nil,
            value: trackID
        )
    }
}

// MARK: - Botones Interactivos con Resorte y Micro-Controles Frosted

/// Estilo de botón con feedback táctil de resorte (escala sutil al presionar) para controles del Notch.
public struct NotchSpringPressButtonStyle: ButtonStyle {
    public var pressedScale: CGFloat
    public var enableAnimations: Bool

    public init(pressedScale: CGFloat = 0.88, enableAnimations: Bool = true) {
        self.pressedScale = pressedScale
        self.enableAnimations = enableAnimations
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && enableAnimations ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(
                enableAnimations ? .spring(response: 0.22, dampingFraction: 0.65) : nil,
                value: configuration.isPressed
            )
    }
}

/// Micro-botón circular translúcido para la barra superior del Notch expandido (audio, fijar, ajustes, cerrar).
public struct NotchHeaderMicroButton: View {
    public let systemName: String
    public let isActive: Bool
    public let activeTint: Color
    public let helpText: String
    public let enableAnimations: Bool
    public let action: () -> Void

    @ViewState private var isHovered = false

    public init(
        systemName: String,
        isActive: Bool = false,
        activeTint: Color = .white,
        helpText: String,
        enableAnimations: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.isActive = isActive
        self.activeTint = activeTint
        self.helpText = helpText
        self.enableAnimations = enableAnimations
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isActive
                            ? activeTint.opacity(0.26)
                            : Color.white.opacity(isHovered ? 0.18 : 0.09)
                    )
                Circle()
                    .stroke(
                        isActive
                            ? activeTint.opacity(0.55)
                            : Color.white.opacity(isHovered ? 0.24 : 0.10),
                        lineWidth: 0.75
                    )
                Image(systemName: systemName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isActive ? activeTint : Color.white.opacity(isHovered ? 0.96 : 0.78))
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.86, enableAnimations: enableAnimations))
        .onHover { hovering in
            if enableAnimations {
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            } else {
                isHovered = hovering
            }
        }
        .help(helpText)
    }
}

// MARK: - Formateo de Tiempos de Reproducción

public enum NotchTimeFormatter {
    public static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
