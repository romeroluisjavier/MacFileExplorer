import AppKit
import SwiftUI

// MARK: - Fotograma Calculado y Motor Matemático de Animaciones de Notificación

/// Estado geométrico y visual en un instante `progress ∈ [0, 1]` de la animación de notificación.
public struct TaskbarNotificationAnimationFrame: Sendable, Equatable {
    public let iconOffsetX: CGFloat
    public let iconOffsetY: CGFloat
    public let iconScaleX: CGFloat
    public let iconScaleY: CGFloat
    public let iconRotationDegrees: Double
    public let iconAnchor: UnitPoint
    public let badgeScale: CGFloat
    public let buttonGlowIntensity: Double
    public let ripple1Progress: Double?
    public let ripple2Progress: Double?

    public static let identity = TaskbarNotificationAnimationFrame(
        iconOffsetX: 0,
        iconOffsetY: 0,
        iconScaleX: 1,
        iconScaleY: 1,
        iconRotationDegrees: 0,
        iconAnchor: .center,
        badgeScale: 1,
        buttonGlowIntensity: 0,
        ripple1Progress: nil,
        ripple2Progress: nil
    )
}

/// Motor puro (sin estado ni timers) que calcula cada una de las 6 animaciones de notificación
/// respetando el espacio libre superior para evitar recortes en cualquier altura de barra.
public enum TaskbarNotificationAnimationEngine {

    /// Calcula el espacio vertical seguro hacia arriba para saltos sin recortar el globo rojo.
    public static func safeMaxJumpUp(forBarHeight barHeight: CGFloat, iconSize: CGFloat) -> CGFloat {
        let headroom = (barHeight - iconSize) * 0.5 - 2.6
        return min(9.5, max(4.2, headroom))
    }

    public static func frame(
        for style: TaskbarNotificationAnimation,
        progress rawProgress: Double,
        maxJumpUp: CGFloat = 7.0
    ) -> TaskbarNotificationAnimationFrame {
        let p = min(max(rawProgress, 0), 1)
        guard p > 0, p < 1 else { return .identity }

        switch style {
        case .none:
            return .identity

        case .bounce:
            // Salto elástico estilo Dock de macOS: pequeña preparación, salto principal, aterrizaje y rebote corto.
            let jump = max(3.5, maxJumpUp)
            if p < 0.11 {
                let t = p / 0.11
                let sq = sin(t * .pi)
                return TaskbarNotificationAnimationFrame(
                    iconOffsetX: 0,
                    iconOffsetY: CGFloat(1.3 * sq),
                    iconScaleX: CGFloat(1.0 + 0.08 * sq),
                    iconScaleY: CGFloat(1.0 - 0.09 * sq),
                    iconRotationDegrees: 0,
                    iconAnchor: .bottom,
                    badgeScale: CGFloat(1.0 - 0.04 * sq),
                    buttonGlowIntensity: 0,
                    ripple1Progress: nil,
                    ripple2Progress: nil
                )
            } else if p < 0.52 {
                let t = (p - 0.11) / 0.41
                let arc = sin(t * .pi)
                let stretch = sin(min(1, t * 1.4) * .pi) * 0.06
                return TaskbarNotificationAnimationFrame(
                    iconOffsetX: 0,
                    iconOffsetY: -jump * CGFloat(arc),
                    iconScaleX: CGFloat(1.0 - stretch * 0.65),
                    iconScaleY: CGFloat(1.0 + stretch),
                    iconRotationDegrees: 0,
                    iconAnchor: .bottom,
                    badgeScale: CGFloat(1.0 + 0.10 * arc),
                    buttonGlowIntensity: 0,
                    ripple1Progress: nil,
                    ripple2Progress: nil
                )
            } else if p < 0.63 {
                let t = (p - 0.52) / 0.11
                let sq = sin(t * .pi)
                return TaskbarNotificationAnimationFrame(
                    iconOffsetX: 0,
                    iconOffsetY: CGFloat(1.1 * sq),
                    iconScaleX: CGFloat(1.0 + 0.07 * sq),
                    iconScaleY: CGFloat(1.0 - 0.08 * sq),
                    iconRotationDegrees: 0,
                    iconAnchor: .bottom,
                    badgeScale: 1.0,
                    buttonGlowIntensity: 0,
                    ripple1Progress: nil,
                    ripple2Progress: nil
                )
            } else if p < 0.92 {
                let t = (p - 0.63) / 0.29
                let arc = sin(t * .pi)
                return TaskbarNotificationAnimationFrame(
                    iconOffsetX: 0,
                    iconOffsetY: -jump * 0.48 * CGFloat(arc),
                    iconScaleX: CGFloat(1.0 - 0.02 * arc),
                    iconScaleY: CGFloat(1.0 + 0.03 * arc),
                    iconRotationDegrees: 0,
                    iconAnchor: .bottom,
                    badgeScale: CGFloat(1.0 + 0.06 * arc),
                    buttonGlowIntensity: 0,
                    ripple1Progress: nil,
                    ripple2Progress: nil
                )
            } else {
                let t = (p - 0.92) / 0.08
                let settle = sin(t * .pi) * 0.35
                return TaskbarNotificationAnimationFrame(
                    iconOffsetX: 0,
                    iconOffsetY: CGFloat(0.6 * settle),
                    iconScaleX: CGFloat(1.0 + 0.03 * settle),
                    iconScaleY: CGFloat(1.0 - 0.03 * settle),
                    iconRotationDegrees: 0,
                    iconAnchor: .bottom,
                    badgeScale: 1.0,
                    buttonGlowIntensity: 0,
                    ripple1Progress: nil,
                    ripple2Progress: nil
                )
            }

        case .shake:
            // Campana / sacudida con oscilación amortiguada rápida.
            let rampUp = min(1.0, p / 0.10)
            let decay = exp(-2.7 * max(0.0, p - 0.10))
            let tailFade = p > 0.85 ? max(0.0, (1.0 - p) / 0.15) : 1.0
            let envelope = rampUp * decay * tailFade
            let wave = sin(p * 6.0 * .pi)
            let lift = sin(p * .pi)
            return TaskbarNotificationAnimationFrame(
                iconOffsetX: CGFloat(1.8 * wave * envelope),
                iconOffsetY: CGFloat(-1.2 * lift),
                iconScaleX: CGFloat(1.0 + 0.06 * lift),
                iconScaleY: CGFloat(1.0 + 0.06 * lift),
                iconRotationDegrees: 16.5 * wave * envelope,
                iconAnchor: .top,
                badgeScale: CGFloat(1.0 + 0.14 * abs(wave) * envelope),
                buttonGlowIntensity: 0,
                ripple1Progress: nil,
                ripple2Progress: nil
            )

        case .pulse:
            // Latido doble ("lub-dub") rítmico sobre el ícono y el globo rojo.
            let beat1: Double = (p < 0.34) ? pow(sin((p / 0.34) * .pi), 1.4) : 0
            let beat2: Double = (p >= 0.38 && p < 0.80) ? pow(sin(((p - 0.38) / 0.42) * .pi), 1.35) : 0
            let energy = max(beat1 * 0.82, beat2)
            let iconScale = CGFloat(1.0 + 0.17 * energy)
            return TaskbarNotificationAnimationFrame(
                iconOffsetX: 0,
                iconOffsetY: CGFloat(-0.8 * energy),
                iconScaleX: iconScale,
                iconScaleY: iconScale,
                iconRotationDegrees: 0,
                iconAnchor: .center,
                badgeScale: CGFloat(1.0 + 0.28 * energy),
                buttonGlowIntensity: 0.25 * energy,
                ripple1Progress: nil,
                ripple2Progress: nil
            )

        case .flash:
            // Destello luminoso estilo Windows Taskbar: ilumina suavemente el botón entero en dos pulsos cálidos.
            let wave1: Double = (p < 0.52) ? pow(sin((p / 0.52) * .pi), 1.2) : 0
            let wave2: Double = (p >= 0.44) ? pow(sin(((p - 0.44) / 0.56) * .pi), 1.2) : 0
            let glow = max(wave1 * 0.92, wave2)
            return TaskbarNotificationAnimationFrame(
                iconOffsetX: 0,
                iconOffsetY: 0,
                iconScaleX: CGFloat(1.0 + 0.05 * glow),
                iconScaleY: CGFloat(1.0 + 0.05 * glow),
                iconRotationDegrees: 0,
                iconAnchor: .center,
                badgeScale: CGFloat(1.0 + 0.14 * glow),
                buttonGlowIntensity: glow,
                ripple1Progress: nil,
                ripple2Progress: nil
            )

        case .ripple:
            // Dos ondas concéntricas expansivas desde el globo rojo + un leve realce del globo.
            let r1: Double? = p <= 0.78 ? (p / 0.78) : nil
            let r2: Double? = p >= 0.24 ? ((p - 0.24) / 0.76) : nil
            let badgePop = sin(min(1.0, p / 0.45) * .pi) * 0.20
            return TaskbarNotificationAnimationFrame(
                iconOffsetX: 0,
                iconOffsetY: 0,
                iconScaleX: CGFloat(1.0 + 0.03 * sin(p * .pi)),
                iconScaleY: CGFloat(1.0 + 0.03 * sin(p * .pi)),
                iconRotationDegrees: 0,
                iconAnchor: .center,
                badgeScale: CGFloat(1.0 + badgePop),
                buttonGlowIntensity: 0.16 * sin(p * .pi),
                ripple1Progress: r1,
                ripple2Progress: r2
            )

        case .swing:
            // Bamboleo / flotación suave tipo péndulo boyante.
            let envelope = sin(p * .pi)
            let sway = sin(p * 2.0 * .pi) * envelope
            let floatUp = min(maxJumpUp * 0.62, 4.4) * CGFloat(envelope)
            return TaskbarNotificationAnimationFrame(
                iconOffsetX: CGFloat(1.6 * sway),
                iconOffsetY: -floatUp,
                iconScaleX: CGFloat(1.0 + 0.04 * envelope),
                iconScaleY: CGFloat(1.0 + 0.04 * envelope),
                iconRotationDegrees: 13.0 * sway,
                iconAnchor: .bottom,
                badgeScale: CGFloat(1.0 + 0.08 * envelope),
                buttonGlowIntensity: 0,
                ripple1Progress: nil,
                ripple2Progress: nil
            )
        }
    }
}

// MARK: - Contenedor Reactivo de Animación con 0% CPU en Reposo

/// Gestiona el ciclo de disparo (periódico, continuo o solo al llegar) y entrega el fotograma
/// actual sin recrear la jerarquía de vistas ni consumir CPU durante los intervalos de pausa.
public struct TaskbarNotificationAnimatedSlot<Content: View>: View {
    public let badgeLabel: String?
    public let style: TaskbarNotificationAnimation
    public let cadence: TaskbarNotificationAnimationCadence
    public let isFocused: Bool
    public let maxJumpUp: CGFloat
    @ViewBuilder public let content: (TaskbarNotificationAnimationFrame) -> Content

    @ViewState private var burstStartTime: TimeInterval?
    @ViewState private var lastAlertedBadgeForOnce: String?
    @ViewState private var lastAlertedStyleForOnce: TaskbarNotificationAnimation?
    @ViewState private var badgeArrivalToken: Int = 0
    @ViewState private var previousBadge: String?

    private struct ScheduleKey: Equatable {
        let badge: String
        let style: TaskbarNotificationAnimation
        let cadence: TaskbarNotificationAnimationCadence
        let isFocused: Bool
        let arrivalToken: Int
    }

    public init(
        badgeLabel: String?,
        style: TaskbarNotificationAnimation,
        cadence: TaskbarNotificationAnimationCadence,
        isFocused: Bool,
        maxJumpUp: CGFloat,
        @ViewBuilder content: @escaping (TaskbarNotificationAnimationFrame) -> Content
    ) {
        self.badgeLabel = badgeLabel
        self.style = style
        self.cadence = cadence
        self.isFocused = isFocused
        self.maxJumpUp = maxJumpUp
        self.content = content
    }

    private var normalizedBadge: String {
        (badgeLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scheduleKey: ScheduleKey {
        ScheduleKey(
            badge: normalizedBadge,
            style: style,
            cadence: cadence,
            isFocused: isFocused,
            arrivalToken: badgeArrivalToken
        )
    }

    public var body: some View {
        Group {
            // Cero suscripciones CVDisplayLink / TimelineView cuando no hay una ráfaga activa
            if let start = burstStartTime, style != .none, style.burstDuration > 0 {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate - start
                    let progress = elapsed / style.burstDuration
                    let frame = TaskbarNotificationAnimationEngine.frame(
                        for: style,
                        progress: progress,
                        maxJumpUp: maxJumpUp
                    )
                    content(frame)
                }
            } else {
                content(.identity)
            }
        }
        .onChange(of: normalizedBadge) { oldVal, newVal in
            if newVal.isEmpty {
                lastAlertedBadgeForOnce = nil
                burstStartTime = nil
            } else if newVal != oldVal {
                badgeArrivalToken &+= 1
            }
            previousBadge = newVal.isEmpty ? nil : newVal
        }
        .task(id: scheduleKey) {
            await runAnimationLoop()
        }
    }

    @MainActor
    private func runAnimationLoop() async {
        let badge = normalizedBadge
        guard !badge.isEmpty, style != .none, style.burstDuration > 0 else {
            burstStartTime = nil
            return
        }

        let burstMs = Int((style.burstDuration * 1000).rounded()) + 35

        switch cadence {
        case .onceOnArrival:
            let needsAlert = (lastAlertedBadgeForOnce != badge) || (lastAlertedStyleForOnce != style)
            guard needsAlert else {
                burstStartTime = nil
                return
            }
            lastAlertedBadgeForOnce = badge
            lastAlertedStyleForOnce = style

            // 2 ráfagas limpias al llegar una notificación o al probar un estilo nuevo
            for burstIndex in 0..<2 {
                guard !Task.isCancelled else { break }
                burstStartTime = Date.timeIntervalSinceReferenceDate
                try? await Task.sleep(for: .milliseconds(burstMs))
                burstStartTime = nil
                if burstIndex == 0 && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(220))
                }
            }
            burstStartTime = nil

        case .periodic, .continuous:
            // Si la ventana está enfocada, solo hacemos un aviso puntual si acaba de cambiar el globo;
            // de lo contrario respetamos el foco para no distraer mientras el usuario lee.
            if isFocused {
                let justChanged = (previousBadge != nil && badgeArrivalToken > 0 && lastAlertedBadgeForOnce != badge)
                if justChanged {
                    lastAlertedBadgeForOnce = badge
                    burstStartTime = Date.timeIntervalSinceReferenceDate
                    try? await Task.sleep(for: .milliseconds(burstMs))
                }
                burstStartTime = nil
                return
            }

            let restMs = (cadence == .periodic) ? 2400 : 420
            while !Task.isCancelled {
                burstStartTime = Date.timeIntervalSinceReferenceDate
                try? await Task.sleep(for: .milliseconds(burstMs))
                burstStartTime = nil
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(restMs))
            }
            burstStartTime = nil
        }
    }
}

// MARK: - Globo de Notificación con Escala, Resplandor y Ondas Expansivas

public struct TaskbarNotificationBadgeView: View {
    public let label: String
    public let frame: TaskbarNotificationAnimationFrame

    public init(label: String, frame: TaskbarNotificationAnimationFrame = .identity) {
        self.label = label
        self.frame = frame
    }

    public var body: some View {
        let compact = label.count > 2 ? "•" : label
        ZStack {
            if let r1 = frame.ripple1Progress {
                rippleRing(progress: r1, baseOpacity: 0.88)
            }
            if let r2 = frame.ripple2Progress {
                rippleRing(progress: r2, baseOpacity: 0.72)
            }

            let isGlowing = frame.buttonGlowIntensity > 0.05
            let shadowColor = isGlowing
                ? Color.red.opacity(0.65 * frame.buttonGlowIntensity)
                : Color.black.opacity(0.25)
            let shadowRadius: CGFloat = isGlowing ? 4.0 : 1.0
            let shadowY: CGFloat = isGlowing ? 0.0 : 0.5

            Text(compact)
                .font(Font.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, compact.count > 1 ? 3.5 : 0)
                .frame(minWidth: 13, minHeight: 13)
                .background(Capsule().fill(Color.red))
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
                .scaleEffect(frame.badgeScale)
        }
    }

    private func rippleRing(progress: Double, baseOpacity: Double) -> some View {
        let clamped = min(max(progress, 0), 1)
        let scale = CGFloat(0.95 + 1.85 * clamped)
        let opacity = pow(1.0 - clamped, 1.35) * baseOpacity
        let lineWidth = CGFloat(max(0.7, 2.0 * (1.0 - 0.5 * clamped)))
        return Circle()
            .stroke(Color.red.opacity(opacity), lineWidth: lineWidth)
            .frame(width: 13, height: 13)
            .scaleEffect(scale)
            .allowsHitTesting(false)
    }
}

// MARK: - Tarjeta de Vista Previa en Vivo para Configuración

/// Tarjeta interactiva que demuestra cada animación de notificación en tiempo real
/// con un ícono de ejemplo (Slack si está instalado, o ícono de mensajes) y un globo rojo «1».
public struct TaskbarNotificationAnimationPreviewCard: View {
    public let style: TaskbarNotificationAnimation
    public let isSelected: Bool
    public let previewDark: Bool
    public let sampleIcon: NSImage
    public let timelineDate: Date
    public let onSelect: () -> Void

    @Bindable private var loc = LocalizationManager.shared

    public init(
        style: TaskbarNotificationAnimation,
        isSelected: Bool,
        previewDark: Bool,
        sampleIcon: NSImage,
        timelineDate: Date,
        onSelect: @escaping () -> Void
    ) {
        self.style = style
        self.isSelected = isSelected
        self.previewDark = previewDark
        self.sampleIcon = sampleIcon
        self.timelineDate = timelineDate
        self.onSelect = onSelect
    }

    private var currentFrame: TaskbarNotificationAnimationFrame {
        guard style != .none, style.burstDuration > 0 else { return .identity }
        let cycleLength = style.burstDuration + 0.85
        let t = timelineDate.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleLength)
        let normalizedT = t >= 0 ? t : (t + cycleLength)
        guard normalizedT < style.burstDuration else { return .identity }
        return TaskbarNotificationAnimationEngine.frame(
            for: style,
            progress: normalizedT / style.burstDuration,
            maxJumpUp: 7.5
        )
    }

    public var body: some View {
        let animFrame = currentFrame
        Button(action: onSelect) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(previewDark ? Color(white: 0.14) : Color(white: 0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    Color(red: 1.0, green: 0.34, blue: 0.22)
                                        .opacity((previewDark ? 0.34 : 0.24) * animFrame.buttonGlowIntensity)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    animFrame.buttonGlowIntensity > 0.05
                                        ? Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.85 * animFrame.buttonGlowIntensity)
                                        : (previewDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)),
                                    lineWidth: animFrame.buttonGlowIntensity > 0.05 ? 1.3 : 0.8
                                )
                        )
                        .frame(width: 56, height: 42)

                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: sampleIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 24, height: 24)

                        TaskbarNotificationBadgeView(label: "1", frame: animFrame)
                            .offset(x: 4, y: -3)
                    }
                    .scaleEffect(x: animFrame.iconScaleX, y: animFrame.iconScaleY, anchor: animFrame.iconAnchor)
                    .rotationEffect(.degrees(animFrame.iconRotationDegrees), anchor: animFrame.iconAnchor)
                    .offset(x: animFrame.iconOffsetX, y: animFrame.iconOffsetY)
                }

                VStack(spacing: 1) {
                    Text(style.localizedTitle(using: loc))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(style.localizedSubtitle(using: loc))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
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

    @MainActor
    public static func samplePreviewAppIcon() -> NSImage {
        let candidates = [
            "/Applications/Slack.app",
            "/Applications/WhatsApp.app",
            "/System/Applications/Messages.app",
            "/System/Applications/Mail.app"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}
