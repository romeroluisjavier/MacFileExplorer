import AppKit
import Observation
import SwiftUI

// MARK: - PreferenceKey y ViewModifier para Anclas del Tour Interactivo

/// Recolecta las coordenadas en pantalla de las regiones objetivo del Tour interactivo (`commandBar`, `addressBar`, `sidebar`, `fileArea`, `statusBar`).
public struct TourTargetAnchorKey: PreferenceKey {
    public static var defaultValue: [String: Anchor<CGRect>] { [:] }

    public static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Registra esta vista como región objetivo resaltable para el Tour interactivo de `MacFileExplorer`.
    public func tourTarget(_ id: String) -> some View {
        anchorPreference(key: TourTargetAnchorKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}

// MARK: - Dirección y Geometría de los Globitos Desplegables

private enum TourBubbleArrowEdge: Equatable {
    case top
    case bottom
    case leading
    case trailing
    case none
}

private struct TourCalloutPlacement {
    let bubbleOrigin: CGPoint
    let bubbleWidth: CGFloat
    let arrowEdge: TourBubbleArrowEdge
    let arrowOffsetFromLeadingOrTop: CGFloat
    let highlightRect: CGRect?
    let topMenuPointerX: CGFloat?
}

/// Forma continua de globito desplegable con puntero triangular integrado sin costuras.
private struct TourSpeechBubbleShape: Shape {
    let cornerRadius: CGFloat
    let arrowEdge: TourBubbleArrowEdge
    let arrowOffset: CGFloat
    let arrowWidth: CGFloat = 18
    let arrowHeight: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) * 0.4)
        let bodyRect: CGRect = {
            switch arrowEdge {
            case .top:
                return CGRect(x: rect.minX, y: rect.minY + arrowHeight, width: rect.width, height: max(0, rect.height - arrowHeight))
            case .bottom:
                return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, rect.height - arrowHeight))
            case .leading:
                return CGRect(x: rect.minX + arrowHeight, y: rect.minY, width: max(0, rect.width - arrowHeight), height: rect.height)
            case .trailing:
                return CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - arrowHeight), height: rect.height)
            case .none:
                return rect
            }
        }()

        let halfW = arrowWidth * 0.5
        let clampedX = min(max(arrowOffset, bodyRect.minX + r + halfW + 6), bodyRect.maxX - r - halfW - 6)
        let clampedY = min(max(arrowOffset, bodyRect.minY + r + halfW + 6), bodyRect.maxY - r - halfW - 6)

        var path = Path()

        // Comenzamos arriba a la izquierda (después del arco superior izquierdo)
        path.move(to: CGPoint(x: bodyRect.minX + r, y: bodyRect.minY))

        // Borde superior
        if arrowEdge == .top {
            path.addLine(to: CGPoint(x: clampedX - halfW, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: clampedX, y: rect.minY))
            path.addLine(to: CGPoint(x: clampedX + halfW, y: bodyRect.minY))
        }
        path.addLine(to: CGPoint(x: bodyRect.maxX - r, y: bodyRect.minY))
        path.addArc(
            center: CGPoint(x: bodyRect.maxX - r, y: bodyRect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Borde derecho
        if arrowEdge == .trailing {
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: clampedY - halfW))
            path.addLine(to: CGPoint(x: rect.maxX, y: clampedY))
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: clampedY + halfW))
        }
        path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - r))
        path.addArc(
            center: CGPoint(x: bodyRect.maxX - r, y: bodyRect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Borde inferior
        if arrowEdge == .bottom {
            path.addLine(to: CGPoint(x: clampedX + halfW, y: bodyRect.maxY))
            path.addLine(to: CGPoint(x: clampedX, y: rect.maxY))
            path.addLine(to: CGPoint(x: clampedX - halfW, y: bodyRect.maxY))
        }
        path.addLine(to: CGPoint(x: bodyRect.minX + r, y: bodyRect.maxY))
        path.addArc(
            center: CGPoint(x: bodyRect.minX + r, y: bodyRect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Borde izquierdo
        if arrowEdge == .leading {
            path.addLine(to: CGPoint(x: bodyRect.minX, y: clampedY + halfW))
            path.addLine(to: CGPoint(x: rect.minX, y: clampedY))
            path.addLine(to: CGPoint(x: bodyRect.minX, y: clampedY - halfW))
        }
        path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + r))
        path.addArc(
            center: CGPoint(x: bodyRect.minX + r, y: bodyRect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

/// Fondo oscurecido translúcido con recorte redondeado (regla even-odd) alrededor del objetivo resaltado.
private struct TourSpotlightBackdropShape: Shape {
    let cutoutRect: CGRect?
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let cutoutRect, cutoutRect.width > 4, cutoutRect.height > 4 {
            path.addRoundedRect(
                in: cutoutRect,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
        }
        return path
    }
}

// MARK: - Overlay Interactivo del Tour con Globitos Desplegables

/// Superposición interactiva del Tour guiado sobre `MainExplorerView` con recorte iluminado,
/// anillo brillante y globitos desplegables con puntero direccional.
/// Se puede suspender en cualquier momento con «Suspender tour», el botón `✕` o la tecla `Esc`.
public struct InteractiveTourOverlayView: View {
    public let anchors: [String: Anchor<CGRect>]

    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var onboarding: AppOnboardingManager

    @ViewState private var keyMonitor: Any? = nil
    @ViewState private var isRingGlowing: Bool = false

    private let isPreviewMode: Bool

    public init(
        anchors: [String: Anchor<CGRect>],
        onboarding: AppOnboardingManager = .shared
    ) {
        self.anchors = anchors
        self._onboarding = Bindable(onboarding)
        self.isPreviewMode = false
    }

    /// Inicializador determinista para capturas / previsualización de una parada específica del tour.
    public init(
        anchors: [String: Anchor<CGRect>],
        previewStep: InteractiveTourStep
    ) {
        let previewDefaults = UserDefaults(suiteName: "com.macfileexplorer.tour.preview.\(previewStep.rawValue)") ?? .standard
        let previewManager = AppOnboardingManager(defaults: previewDefaults)
        previewManager.currentTourStep = previewStep
        previewManager.isTourActive = true
        self.anchors = anchors
        self._onboarding = Bindable(previewManager)
        self.isPreviewMode = true
    }

    private var step: InteractiveTourStep {
        onboarding.currentTourStep
    }

    public var body: some View {
        GeometryReader { proxy in
            let placement = computePlacement(in: proxy)

            ZStack(alignment: .topLeading) {
                // 1. Fondo atenuado con recorte suave sobre la región destacada
                TourSpotlightBackdropShape(
                    cutoutRect: placement.highlightRect,
                    cornerRadius: 11
                )
                .fill(Color.black.opacity(colorScheme == .dark ? 0.44 : 0.30), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: step)

                // 2. Anillo luminoso alrededor del elemento destacado
                if let highlightRect = placement.highlightRect {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.4)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.accentColor.opacity(isRingGlowing ? 0.55 : 0.25), lineWidth: 5)
                                .blur(radius: 4)
                        )
                        .frame(width: highlightRect.width, height: highlightRect.height)
                        .position(x: highlightRect.midX, y: highlightRect.midY)
                        .allowsHitTesting(false)
                        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: step)
                }

                // 3. Píldora indicadora superior para paradas de la barra de menús de macOS
                if step.pointsToTopMenuBar, let pointerX = placement.topMenuPointerX {
                    topMenuBarIndicatorPill
                        .position(x: pointerX, y: 26)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 4. Globito desplegable (speech bubble) con puntero direccional
                calloutBubbleCard(placement: placement)
                    .frame(width: placement.bubbleWidth, alignment: .leading)
                    .offset(x: placement.bubbleOrigin.x, y: placement.bubbleOrigin.y)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: step)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .zIndex(120)
        .onAppear {
            guard !isPreviewMode else {
                isRingGlowing = true
                return
            }
            installKeyboardMonitorIfNeeded()
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                isRingGlowing = true
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    // MARK: - Píldora Indicadora hacia la Barra de Menús de macOS

    private var topMenuBarIndicatorPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.system(size: 10.5, weight: .bold))
            Text(
                step == .topMenus
                    ? loc.text(es: "Menús superiores de macOS (Barra de tareas · AltTab · Notch · Office)", en: "macOS Top Menu Bar (Taskbar · AltTab · Notch · Office)")
                    : loc.text(es: "Menús superiores: Ayuda (⌘?) y MacFileExplorer → Acerca de", en: "Top Menu Bar: Help (⌘?) & MacFileExplorer → About")
            )
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor)
        )
        .shadow(color: Color.accentColor.opacity(0.42), radius: 10, y: 3)
    }

    // MARK: - Tarjeta del Globito Desplegable

    private func calloutBubbleCard(placement: TourCalloutPlacement) -> some View {
        let arrowPadTop: CGFloat = placement.arrowEdge == .top ? 10 : 0
        let arrowPadBottom: CGFloat = placement.arrowEdge == .bottom ? 10 : 0
        let arrowPadLeading: CGFloat = placement.arrowEdge == .leading ? 10 : 0
        let arrowPadTrailing: CGFloat = placement.arrowEdge == .trailing ? 10 : 0

        let bubbleShape = TourSpeechBubbleShape(
            cornerRadius: 15,
            arrowEdge: placement.arrowEdge,
            arrowOffset: placement.arrowOffsetFromLeadingOrTop
        )

        return VStack(alignment: .leading, spacing: 10) {
            // Cabecera del globito: badge de paso + puntitos + botón cerrar ✕
            HStack(spacing: 8) {
                Text(step.localizedBadgeText(using: loc))
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.13))
                    )

                // Indicador compacto de los 7 pasos
                HStack(spacing: 3.5) {
                    ForEach(InteractiveTourStep.allCases) { dotStep in
                        let isCurrent = dotStep == step
                        let isDone = dotStep.rawValue < step.rawValue
                        Capsule(style: .continuous)
                            .fill(
                                isCurrent
                                    ? Color.accentColor
                                    : (isDone ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.16))
                            )
                            .frame(width: isCurrent ? 14 : 5, height: 5)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    suspendTour()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07))
                        )
                }
                .buttonStyle(.plain)
                .help(loc.text(es: "Suspender tour (Esc)", en: "Stop tour (Esc)"))
            }

            // Ícono y título principal
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.13))
                        .frame(width: 32, height: 32)
                    Image(systemName: step.symbolName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(step.localizedTitle(using: loc))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Explicación amigable en lenguaje natural
            Text(step.localizedBody(using: loc))
                .font(.system(size: 12.2))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2.0)

            // Píldora opcional de atajo de teclado
            if let shortcutHint = step.localizedShortcutHint(using: loc), !shortcutHint.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(shortcutHint)
                        .font(.system(size: 10.8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                )
            }

            Divider()
                .padding(.top, 1)

            // Controles de pie: Suspender tour + Anterior + Siguiente / ¡Entendido!
            HStack(spacing: 8) {
                Button {
                    suspendTour()
                } label: {
                    Text(loc.text(es: "Suspender tour", en: "Stop Tour"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 6)

                if !step.isFirst {
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            onboarding.previousTourStep()
                        }
                    } label: {
                        Text(loc.text(es: "Anterior", en: "Back"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    if step.isLast {
                        suspendTour()
                    } else {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            onboarding.nextTourStep()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            step.isLast
                                ? loc.text(es: "¡Entendido!", en: "Got it!")
                                : loc.text(es: "Siguiente", en: "Next")
                        )
                        .font(.system(size: 11.8, weight: .semibold))
                        if !step.isLast {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.top, 14 + arrowPadTop)
        .padding(.bottom, 13 + arrowPadBottom)
        .padding(.leading, 15 + arrowPadLeading)
        .padding(.trailing, 15 + arrowPadTrailing)
        .background(
            bubbleShape
                .fill(.ultraThickMaterial)
                .overlay(
                    bubbleShape
                        .fill(
                            colorScheme == .dark
                                ? Color(white: 0.14).opacity(0.45)
                                : Color.white.opacity(0.60)
                        )
                )
        )
        .overlay(
            bubbleShape
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.18)
                        : Color.black.opacity(0.12),
                    lineWidth: 1.0
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 18, y: 8)
    }

    // MARK: - Motor de Posicionamiento Inteligente (Sin Recortes Fuera de Ventana)

    private func computePlacement(in proxy: GeometryProxy) -> TourCalloutPlacement {
        let bounds = CGRect(origin: .zero, size: proxy.size)
        let margin: CGFloat = 16
        let bubbleWidth = min(344, max(270, bounds.width - margin * 2))
        let estimatedHeight: CGFloat = 228
        let gap: CGFloat = 10

        // Caso especial: pasos que apuntan hacia la barra superior de menús de macOS
        if step.pointsToTopMenuBar {
            let preferredCenterX: CGFloat = step == .topMenus
                ? bounds.width * 0.46
                : min(bounds.width - 190, bounds.width * 0.68)
            let clampedPointerX = min(max(preferredCenterX, 180), max(180, bounds.width - 180))
            let rawX = clampedPointerX - bubbleWidth * 0.5
            let clampedX = min(max(rawX, margin), max(margin, bounds.width - bubbleWidth - margin))
            let y: CGFloat = 46
            return TourCalloutPlacement(
                bubbleOrigin: CGPoint(x: clampedX, y: y),
                bubbleWidth: bubbleWidth,
                arrowEdge: .top,
                arrowOffsetFromLeadingOrTop: clampedPointerX - clampedX,
                highlightRect: nil,
                topMenuPointerX: clampedPointerX
            )
        }

        // Resolver rectángulo del objetivo anclado
        guard let anchor = anchors[step.targetID] else {
            let centeredX = max(margin, (bounds.width - bubbleWidth) * 0.5)
            let centeredY = max(margin, (bounds.height - estimatedHeight) * 0.42)
            return TourCalloutPlacement(
                bubbleOrigin: CGPoint(x: centeredX, y: centeredY),
                bubbleWidth: bubbleWidth,
                arrowEdge: .none,
                arrowOffsetFromLeadingOrTop: bubbleWidth * 0.5,
                highlightRect: nil,
                topMenuPointerX: nil
            )
        }

        let rawTarget = proxy[anchor]
        let highlightRect = rawTarget
            .insetBy(dx: -3, dy: -3)
            .intersection(bounds.insetBy(dx: 3, dy: 3))

        // Estrategia óptima según el tipo de región destacada
        switch step {
        case .commandBar, .addressBar:
            // Colocar debajo apuntando hacia arriba
            let anchorX = min(max(highlightRect.minX + min(220, highlightRect.width * 0.34), margin + 40), bounds.width - margin - 40)
            let x = clampX(anchorX - bubbleWidth * 0.5, width: bubbleWidth, in: bounds, margin: margin)
            let y = clampY(highlightRect.maxY + gap, height: estimatedHeight, in: bounds, margin: margin)
            return TourCalloutPlacement(
                bubbleOrigin: CGPoint(x: x, y: y),
                bubbleWidth: bubbleWidth,
                arrowEdge: .top,
                arrowOffsetFromLeadingOrTop: anchorX - x,
                highlightRect: highlightRect,
                topMenuPointerX: nil
            )

        case .sidebar:
            // Colocar a la derecha de la barra lateral apuntando hacia la izquierda
            let roomRight = bounds.maxX - highlightRect.maxX - gap - margin
            if roomRight >= bubbleWidth {
                let x = highlightRect.maxX + gap
                let preferredY = highlightRect.minY + min(86, highlightRect.height * 0.22)
                let y = clampY(preferredY, height: estimatedHeight, in: bounds, margin: margin)
                let targetPointerY = min(max(highlightRect.minY + 96, y + 36), y + estimatedHeight - 36)
                return TourCalloutPlacement(
                    bubbleOrigin: CGPoint(x: x, y: y),
                    bubbleWidth: bubbleWidth,
                    arrowEdge: .leading,
                    arrowOffsetFromLeadingOrTop: targetPointerY - y,
                    highlightRect: highlightRect,
                    topMenuPointerX: nil
                )
            } else {
                let x = clampX(highlightRect.midX - bubbleWidth * 0.5, width: bubbleWidth, in: bounds, margin: margin)
                let y = clampY(highlightRect.minY + 24, height: estimatedHeight, in: bounds, margin: margin)
                return TourCalloutPlacement(
                    bubbleOrigin: CGPoint(x: x, y: y),
                    bubbleWidth: bubbleWidth,
                    arrowEdge: .none,
                    arrowOffsetFromLeadingOrTop: bubbleWidth * 0.5,
                    highlightRect: highlightRect,
                    topMenuPointerX: nil
                )
            }

        case .fileArea:
            // Área de archivos ocupa la mayor parte de la ventana: flotar de forma elegante
            // cerca del cuadrante superior derecho del área de archivos para dejar los archivos visibles
            let preferredX = highlightRect.maxX - bubbleWidth - 22
            let x = clampX(preferredX, width: bubbleWidth, in: bounds, margin: margin)
            let preferredY = highlightRect.minY + 26
            let y = clampY(preferredY, height: estimatedHeight, in: bounds, margin: margin)
            return TourCalloutPlacement(
                bubbleOrigin: CGPoint(x: x, y: y),
                bubbleWidth: bubbleWidth,
                arrowEdge: .leading,
                arrowOffsetFromLeadingOrTop: 58,
                highlightRect: highlightRect,
                topMenuPointerX: nil
            )

        case .statusBar:
            // Colocar encima de la barra inferior apuntando hacia abajo
            let anchorX = min(max(highlightRect.minX + min(240, highlightRect.width * 0.35), margin + 40), bounds.width - margin - 40)
            let x = clampX(anchorX - bubbleWidth * 0.5, width: bubbleWidth, in: bounds, margin: margin)
            let y = clampY(highlightRect.minY - estimatedHeight - gap, height: estimatedHeight, in: bounds, margin: margin)
            return TourCalloutPlacement(
                bubbleOrigin: CGPoint(x: x, y: y),
                bubbleWidth: bubbleWidth,
                arrowEdge: .bottom,
                arrowOffsetFromLeadingOrTop: anchorX - x,
                highlightRect: highlightRect,
                topMenuPointerX: nil
            )

        case .topMenus, .helpAndAbout:
            // Ya resuelto arriba
            return TourCalloutPlacement(
                bubbleOrigin: CGPoint(x: margin, y: 48),
                bubbleWidth: bubbleWidth,
                arrowEdge: .top,
                arrowOffsetFromLeadingOrTop: bubbleWidth * 0.5,
                highlightRect: nil,
                topMenuPointerX: bounds.midX
            )
        }
    }

    private func clampX(_ x: CGFloat, width: CGFloat, in bounds: CGRect, margin: CGFloat) -> CGFloat {
        min(max(x, margin), max(margin, bounds.width - width - margin))
    }

    private func clampY(_ y: CGFloat, height: CGFloat, in bounds: CGRect, margin: CGFloat) -> CGFloat {
        min(max(y, margin), max(margin, bounds.height - height - margin))
    }

    // MARK: - Atajos de Teclado (`Esc` suspende al instante, flechas navegan)

    private func suspendTour() {
        guard !isPreviewMode else { return }
        onboarding.suspendOrFinishTour()
    }

    @MainActor
    private func installKeyboardMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard onboarding.isTourActive else { return false }
                switch keyCode {
                case 53: // Escape -> Suspender tour inmediatamente
                    onboarding.suspendOrFinishTour()
                    return true
                case 124, 36, 76: // Flecha derecha o Enter -> Siguiente paso
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        onboarding.nextTourStep()
                    }
                    return true
                case 123: // Flecha izquierda -> Paso anterior
                    if !onboarding.currentTourStep.isFirst {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            onboarding.previousTourStep()
                        }
                    }
                    return true
                default:
                    return false
                }
            }
            return consumed ? nil : event
        }
    }

    @MainActor
    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// MARK: - Vista de Previsualización Determinista del Tour (QA & Sandbox Captures)

/// Vista autocontenida que renderiza un marco limpio de `MacFileExplorer` con todas sus anclas `.tourTarget(...)`
/// y el globito desplegable de `InteractiveTourOverlayView` para pruebas visuales y capturas de documentación.
public struct InteractiveTourPreviewView: View {
    public let step: InteractiveTourStep

    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared

    public init(step: InteractiveTourStep = .addressBar) {
        self.step = step
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Mock Command Bar
            HStack(spacing: 12) {
                mockToolbarButton(icon: "plus.circle.fill", tint: .accentColor, title: loc.text(es: "Nuevo", en: "New"))
                Divider().frame(height: 16)
                mockToolbarIcon("scissors")
                mockToolbarIcon("doc.on.doc")
                mockToolbarIcon("doc.on.clipboard")
                mockToolbarIcon("pencil")
                mockToolbarIcon("trash")
                Spacer()
                mockToolbarButton(icon: "arrow.up.arrow.down", tint: .secondary, title: loc.text(es: "Ordenar", en: "Sort"))
                mockToolbarButton(icon: "square.grid.2x2", tint: .secondary, title: loc.text(es: "Vista", en: "View"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor))
            .tourTarget(InteractiveTourTargetID.commandBar)

            Divider()

            // 2. Mock Address Bar & OCR Search
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    Image(systemName: "arrow.up").foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5, weight: .semibold))

                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    Text("Macintosh HD")
                    Image(systemName: "chevron.right").font(.system(size: 8.5)).foregroundStyle(.tertiary)
                    Text(loc.text(es: "Documentos", en: "Documents"))
                    Image(systemName: "chevron.right").font(.system(size: 8.5)).foregroundStyle(.tertiary)
                    Text(loc.text(es: "Proyectos", en: "Projects")).fontWeight(.semibold)
                    Spacer()
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                )

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(loc.text(es: "Buscar y OCR…", en: "Search & OCR…"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(width: 195)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            .tourTarget(InteractiveTourTargetID.addressBar)

            Divider()

            // 3. Body: Sidebar + File List
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text(es: "ACCESO RÁPIDO", en: "QUICK ACCESS"))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    mockSidebarRow(icon: "clock.arrow.circlepath", tint: .orange, title: loc.text(es: "Modificados hoy (24h)", en: "Modified Today (24h)"), selected: false)
                    mockSidebarRow(icon: "desktopcomputer", tint: .blue, title: loc.text(es: "Escritorio", en: "Desktop"), selected: false)
                    mockSidebarRow(icon: "folder.fill", tint: .accentColor, title: loc.text(es: "Documentos", en: "Documents"), selected: true)
                    mockSidebarRow(icon: "arrow.down.circle.fill", tint: .green, title: loc.text(es: "Descargas", en: "Downloads"), selected: false)
                    mockSidebarRow(icon: "doc.on.clipboard.fill", tint: .purple, title: loc.text(es: "Portapapeles", en: "Clipboard"), selected: false)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(width: 215, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .tourTarget(InteractiveTourTargetID.sidebar)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(loc.text(es: "Nombre", en: "Name")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(loc.text(es: "Modificado", en: "Modified")).frame(width: 120, alignment: .leading)
                        Text(loc.text(es: "Tamaño", en: "Size")).frame(width: 80, alignment: .trailing)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.03))

                    Divider()

                    VStack(spacing: 2) {
                        mockFileRow(
                            icon: "folder.fill",
                            tint: .blue,
                            name: loc.text(es: "Diseño Producto 2026", en: "Product Design 2026"),
                            date: loc.text(es: "Hoy, 10:12", en: "Today, 10:12"),
                            size: "—",
                            selected: false
                        )
                        mockFileRow(
                            icon: "doc.richtext.fill",
                            tint: .orange,
                            name: loc.text(es: "Presupuesto_Q4.xlsx", en: "Q4_Budget.xlsx"),
                            date: loc.text(es: "Hoy, 09:48", en: "Today, 09:48"),
                            size: loc.text(es: "2,4 MB", en: "2.4 MB"),
                            selected: true
                        )
                        mockFileRow(
                            icon: "photo.fill",
                            tint: .pink,
                            name: loc.text(es: "Banner_Lanzamiento.png", en: "Launch_Banner.png"),
                            date: loc.text(es: "Ayer, 18:30", en: "Yesterday, 18:30"),
                            size: loc.text(es: "6,8 MB", en: "6.8 MB"),
                            selected: false
                        )
                        mockFileRow(
                            icon: "doc.text.fill",
                            tint: .teal,
                            name: loc.text(es: "Notas_Reunion.docx", en: "Meeting_Notes.docx"),
                            date: loc.text(es: "Ayer, 15:10", en: "Yesterday, 15:10"),
                            size: "418 KB",
                            selected: false
                        )
                        mockFileRow(
                            icon: "tablecells.fill",
                            tint: .green,
                            name: loc.text(es: "Clientes_Export.csv", en: "Customers_Export.csv"),
                            date: loc.text(es: "12 Nov", en: "Nov 12"),
                            size: loc.text(es: "1,1 MB", en: "1.1 MB"),
                            selected: false
                        )
                    }
                    .padding(8)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .tourTarget(InteractiveTourTargetID.fileArea)
            }

            Divider()

            // 4. Mock Status Bar
            HStack {
                Text(loc.text(es: "5 elementos · 1 seleccionado (2,4 MB)", en: "5 items · 1 selected (2.4 MB)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet").foregroundStyle(Color.accentColor)
                    Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .tourTarget(InteractiveTourTargetID.statusBar)
        }
        .overlayPreferenceValue(TourTargetAnchorKey.self) { anchors in
            InteractiveTourOverlayView(anchors: anchors, previewStep: step)
        }
        .frame(width: 920, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func mockToolbarButton(icon: String, tint: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(.system(size: 11.5, weight: .medium))
        }
    }

    private func mockToolbarIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private func mockSidebarRow(icon: String, tint: Color, title: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white : tint)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11.8, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : .primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(selected ? Color.accentColor : Color.clear)
        )
    }

    private func mockFileRow(icon: String, tint: Color, name: String, date: String, size: String, selected: Bool) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : tint)
                Text(name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(date)
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                .frame(width: 120, alignment: .leading)

            Text(size)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor : Color.clear)
        )
    }
}
