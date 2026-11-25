import AppKit
import SwiftUI

/// Variantes vectoriales monocromáticas modernas (estilo SF Symbol nativo de macOS con recortes en espacio negativo)
/// para el botón Inicio de la barra de tareas: 3 opciones de MacFileExplorer y 2 opciones de EmonkBrain.
public enum TaskbarCustomMonochromeGlyph: String, CaseIterable, Sendable {
    case macFileExplorerMono
    case macFileExplorerLayers
    case macFileExplorerSquircle
    case emonkBrainMono
    case emonkBrainSquircle
}

/// Renderizador vectorial de precisión infinita en Retina con soporte automático de tema claro/oscuro,
/// estado resaltado (Menú Inicio abierto) y recortes reales en espacio negativo (`.destinationOut`).
public struct TaskbarCustomMonochromeGlyphView: View {
    public let glyph: TaskbarCustomMonochromeGlyph
    public let size: CGFloat
    public let effectiveDark: Bool
    public let isHighlighted: Bool

    public init(
        glyph: TaskbarCustomMonochromeGlyph,
        size: CGFloat,
        effectiveDark: Bool,
        isHighlighted: Bool = false
    ) {
        self.glyph = glyph
        self.size = size
        self.effectiveDark = effectiveDark
        self.isHighlighted = isHighlighted
    }

    private var gradientColors: [Color] {
        if isHighlighted {
            return [Color.accentColor, Color.accentColor.opacity(0.80)]
        }
        if effectiveDark {
            return [Color.white.opacity(0.95), Color.white.opacity(0.75)]
        }
        return [Color.accentColor, Color.blue.opacity(0.76)]
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let originX = (canvasSize.width - side) * 0.5
            let originY = (canvasSize.height - side) * 0.5
            let scale = side / 100.0

            let gradient = Gradient(colors: gradientColors)
            let shading = GraphicsContext.Shading.linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 100, y: 100)
            )

            var ctx = context
            ctx.translateBy(x: originX, y: originY)
            ctx.scaleBy(x: scale, y: scale)

            switch glyph {
            case .macFileExplorerMono:
                Self.drawMacFileExplorerMono(in: &ctx, fill: shading)
            case .macFileExplorerLayers:
                Self.drawMacFileExplorerLayers(in: &ctx, fill: shading)
            case .macFileExplorerSquircle:
                Self.drawMacFileExplorerSquircle(in: &ctx, fill: shading)
            case .emonkBrainMono:
                Self.drawEmonkBrainMono(in: &ctx, fill: shading)
            case .emonkBrainSquircle:
                Self.drawEmonkBrainSquircle(in: &ctx, fill: shading)
            }
        }
        .compositingGroup()
        .frame(width: size, height: size)
    }

    /// Genera una imagen `NSImage` nítida (16×16) para mostrar la miniatura real en el menú contextual.
    @MainActor
    public static func renderMenuImage(
        for glyph: TaskbarCustomMonochromeGlyph,
        pointSize: CGFloat = 16,
        effectiveDark: Bool
    ) -> NSImage? {
        let view = TaskbarCustomMonochromeGlyphView(
            glyph: glyph,
            size: pointSize,
            effectiveDark: effectiveDark,
            isHighlighted: false
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let cgImage = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: pointSize, height: pointSize))
        return image
    }

    // MARK: - 1. MacFileExplorer Mono (Barra lateral curva + Carpeta con barra de ruta y pliegue)

    private static func drawMacFileExplorerMono(in ctx: inout GraphicsContext, fill: GraphicsContext.Shading) {
        // 1A. Riel lateral izquierdo con curvatura orgánica exterior (eco directo del ícono oficial)
        let rail = unevenRoundedRect(
            x: 8, y: 12, width: 20, height: 76,
            topLeft: 12, topRight: 4, bottomRight: 4, bottomLeft: 12
        )
        ctx.fill(rail, with: fill)

        // 1B. Cuerpo principal de la carpeta a la derecha (separada por espacio negativo de 6u)
        let folder = folderSilhouette(x: 34, y: 14, width: 58, height: 72, tabWidth: 25, tabHeight: 11, cornerRadius: 10)
        ctx.fill(folder, with: fill)

        // Recortes en espacio negativo (transparentes / oscuros sobre barra oscura)
        ctx.blendMode = .destinationOut
        let cut = GraphicsContext.Shading.color(.black)

        // 3 mini indicadores en el panel lateral izquierdo
        ctx.fill(Path(roundedRect: CGRect(x: 13.5, y: 24, width: 9, height: 7), cornerRadius: 2.8, style: .continuous), with: cut)
        ctx.fill(Path(roundedRect: CGRect(x: 13.5, y: 46.5, width: 9, height: 7), cornerRadius: 2.8, style: .continuous), with: cut)
        ctx.fill(Path(roundedRect: CGRect(x: 13.5, y: 69, width: 9, height: 7), cornerRadius: 2.8, style: .continuous), with: cut)

        // Barra de direcciones minimalista en la zona superior de la carpeta
        ctx.fill(Path(roundedRect: CGRect(x: 42, y: 31, width: 41, height: 6.5), cornerRadius: 3.2, style: .continuous), with: cut)

        // Ranura escalonada que divide las hojas apiladas de la tapa frontal de la carpeta
        var flapGroove = Path()
        flapGroove.move(to: CGPoint(x: 33, y: 47))
        flapGroove.addLine(to: CGPoint(x: 54, y: 47))
        flapGroove.addLine(to: CGPoint(x: 61, y: 53.5))
        flapGroove.addLine(to: CGPoint(x: 93, y: 53.5))
        ctx.stroke(flapGroove, with: cut, style: StrokeStyle(lineWidth: 5.5, lineCap: .butt, lineJoin: .round))
    }

    // MARK: - 2. MacFileExplorer Capas (Carpeta moderna con hoja superior y distribución Explorador)

    private static func drawMacFileExplorerLayers(in ctx: inout GraphicsContext, fill: GraphicsContext.Shading) {
        // Carpeta principal amplia con pestaña superior izquierda limpia
        let mainFolder = folderSilhouette(x: 9, y: 15, width: 82, height: 71, tabWidth: 33, tabHeight: 11, cornerRadius: 12)
        ctx.fill(mainFolder, with: fill)

        // Hoja/pestaña secundaria minimalista asomándose en la parte superior derecha
        let rightTab = Path(roundedRect: CGRect(x: 54, y: 15, width: 32, height: 14), cornerRadius: 5, style: .continuous)
        ctx.fill(rightTab, with: fill)

        ctx.blendMode = .destinationOut
        let cut = GraphicsContext.Shading.color(.black)

        // Separación limpia entre la pestaña izquierda y la hoja derecha
        ctx.fill(Path(CGRect(x: 47, y: 12, width: 7, height: 17)), with: cut)

        // Ranura horizontal nítida que separa la cabecera/pestañas del cuerpo frontal
        var topGroove = Path()
        topGroove.move(to: CGPoint(x: 8, y: 34.5))
        topGroove.addLine(to: CGPoint(x: 92, y: 34.5))
        ctx.stroke(topGroove, with: cut, style: StrokeStyle(lineWidth: 5.2, lineCap: .butt))

        // Distribución interna tipo Explorador (barra lateral + 2 paneles derechos en espacio negativo)
        ctx.fill(Path(roundedRect: CGRect(x: 19, y: 44.5, width: 16, height: 31.5), cornerRadius: 4.2, style: .continuous), with: cut)
        ctx.fill(Path(roundedRect: CGRect(x: 41, y: 44.5, width: 40, height: 12.8), cornerRadius: 4.2, style: .continuous), with: cut)
        ctx.fill(Path(roundedRect: CGRect(x: 41, y: 63.2, width: 40, height: 12.8), cornerRadius: 4.2, style: .continuous), with: cut)
    }

    // MARK: - 3. MacFileExplorer Sello (Squircle nativo estilo ⌘ con Explorador calado en negativo)

    private static func drawMacFileExplorerSquircle(in ctx: inout GraphicsContext, fill: GraphicsContext.Shading) {
        // Squircle sólido estilo `command.square.fill`
        let squircle = Path(roundedRect: CGRect(x: 10, y: 10, width: 80, height: 80), cornerRadius: 21, style: .continuous)
        ctx.fill(squircle, with: fill)

        // Calar barra lateral + carpeta MacFileExplorer en espacio negativo
        ctx.blendMode = .destinationOut
        let cut = GraphicsContext.Shading.color(.black)

        let innerRail = unevenRoundedRect(
            x: 22, y: 27, width: 11.5, height: 46,
            topLeft: 6, topRight: 2.5, bottomRight: 2.5, bottomLeft: 6
        )
        ctx.fill(innerRail, with: cut)

        let innerFolder = folderSilhouette(x: 38.5, y: 27, width: 39.5, height: 46, tabWidth: 18, tabHeight: 8.5, cornerRadius: 7)
        ctx.fill(innerFolder, with: cut)

        // Detalle positivo blanco dentro de la carpeta calada para un toque moderno tipo SF Symbol
        ctx.blendMode = .normal
        ctx.fill(Path(roundedRect: CGRect(x: 45, y: 44.5, width: 26.5, height: 5.0), cornerRadius: 2.5, style: .continuous), with: fill)
        ctx.fill(Path(roundedRect: CGRect(x: 45, y: 55.5, width: 17.5, height: 5.0), cornerRadius: 2.5, style: .continuous), with: fill)
    }

    // MARK: - 4. EmonkBrain Mono (Cerebro sólido blanco con hendidura y circuitos neuronales calados)

    private static func drawEmonkBrainMono(in ctx: inout GraphicsContext, fill: GraphicsContext.Shading) {
        // Dos hemisferios orgánicos simétricos fieles al logo de EmonkBrain
        let leftLobe = brainHemispherePath(isRight: false)
        let rightLobe = brainHemispherePath(isRight: true)
        ctx.fill(leftLobe, with: fill)
        ctx.fill(rightLobe, with: fill)

        // Calar en espacio negativo la fisura central + trazos y nodos sinápticos simétricos
        ctx.blendMode = .destinationOut
        let cut = GraphicsContext.Shading.color(.black)

        // Fisura central limpia entre ambos hemisferios
        ctx.fill(Path(CGRect(x: 46.5, y: 8, width: 7.0, height: 84)), with: cut)

        drawBrainCircuitOverlay(in: &ctx, shading: cut, isRight: false, lineWidth: 4.2, nodeRadius: 4.3)
        drawBrainCircuitOverlay(in: &ctx, shading: cut, isRight: true, lineWidth: 4.2, nodeRadius: 4.3)
    }

    // MARK: - 5. EmonkBrain Sello (Squircle nativo estilo ⌘ con cerebro calado y nodos sinápticos limpios)

    private static func drawEmonkBrainSquircle(in ctx: inout GraphicsContext, fill: GraphicsContext.Shading) {
        let squircle = Path(roundedRect: CGRect(x: 10, y: 10, width: 80, height: 80), cornerRadius: 21, style: .continuous)
        ctx.fill(squircle, with: fill)

        // Transformar al centro (escala 0.77) para un calado cerebral amplio y ultra legible incluso a 20px
        ctx.translateBy(x: 11.5, y: 11.5)
        ctx.scaleBy(x: 0.77, y: 0.77)

        // Calar silueta completa del cerebro en espacio negativo
        ctx.blendMode = .destinationOut
        let cut = GraphicsContext.Shading.color(.black)
        ctx.fill(brainHemispherePath(isRight: false), with: cut)
        ctx.fill(brainHemispherePath(isRight: true), with: cut)

        // Reponer columna central limpia + circuitos simplificados de peso óptico dentro del cerebro calado
        ctx.blendMode = .normal
        ctx.fill(Path(roundedRect: CGRect(x: 47.6, y: 14, width: 4.8, height: 72), cornerRadius: 2.4, style: .continuous), with: fill)
        drawCompactBrainCircuit(in: &ctx, shading: fill, isRight: false)
        drawCompactBrainCircuit(in: &ctx, shading: fill, isRight: true)
    }

    private static func drawCompactBrainCircuit(
        in ctx: inout GraphicsContext,
        shading: GraphicsContext.Shading,
        isRight: Bool
    ) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: isRight ? (100.0 - x) : x, y: y)
        }

        var lines = Path()
        // Rama superior limpia
        lines.move(to: pt(48.0, 35.0))
        lines.addLine(to: pt(34.5, 25.0))
        // Rama media lateral
        lines.move(to: pt(48.0, 50.0))
        lines.addLine(to: pt(24.5, 50.0))
        // Rama inferior limpia
        lines.move(to: pt(48.0, 65.0))
        lines.addLine(to: pt(33.5, 74.5))

        ctx.stroke(lines, with: shading, style: StrokeStyle(lineWidth: 4.6, lineCap: .round, lineJoin: .round))

        let nodes: [(CGFloat, CGFloat)] = [
            (34.5, 25.0),
            (24.5, 50.0),
            (33.5, 74.5)
        ]
        let r: CGFloat = 5.0
        for (nx, ny) in nodes {
            let p = pt(nx, ny)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: shading)
        }
    }

    // MARK: - Primitivas Geométricas Compartidas (Artboard 100×100)

    /// Silueta orgánica de un hemisferio cerebral lobulado fiel a `StartIcon-EmonkBrain.png`.
    private static func brainHemispherePath(isRight: Bool) -> Path {
        var path = Path()
        // Lóbulos construidos en el hemisferio izquierdo (x: 10...47, y: 10...90) y espejados si `isRight`
        let circles: [(cx: CGFloat, cy: CGFloat, r: CGFloat)] = [
            (36.0, 21.5, 13.0), // Lóbulo frontal superior
            (25.0, 28.0, 11.5), // Lóbulo superior-exterior
            (20.0, 42.0, 12.2), // Lóbulo lateral superior
            (20.5, 57.5, 12.0), // Lóbulo lateral inferior
            (26.5, 72.5, 11.5), // Lóbulo inferior-exterior
            (36.5, 78.5, 12.0)  // Lóbulo base inferior
        ]
        // Núcleo interior para unir todos los lóbulos sin huecos hasta la fisura central (x = 46.8)
        let coreRect = CGRect(x: 24.0, y: 21.5, width: 23.0, height: 57.0)
        path.addRoundedRect(in: coreRect, cornerSize: CGSize(width: 7, height: 7))

        for c in circles {
            path.addEllipse(in: CGRect(x: c.cx - c.r, y: c.cy - c.r, width: c.r * 2, height: c.r * 2))
        }

        // Recortar borde recto interno limpio contra la fisura central
        // (se refuerza también con el rectángulo central en `drawEmonkBrainMono`)
        if isRight {
            let mirror = CGAffineTransform(translationX: 100, y: 0).scaledBy(x: -1, y: 1)
            return path.applying(mirror)
        }
        return path
    }

    /// Trazos y nodos circulares sinápticos inspirados en el patrón neuronal de `StartIcon-EmonkBrain.png`,
    /// calibrados con grosor óptico para máxima nitidez en tamaños de 18–44 px.
    private static func drawBrainCircuitOverlay(
        in ctx: inout GraphicsContext,
        shading: GraphicsContext.Shading,
        isRight: Bool,
        lineWidth: CGFloat,
        nodeRadius: CGFloat
    ) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: isRight ? (100.0 - x) : x, y: y)
        }

        var lines = Path()

        // 1. Rama superior: nace desde la zona interna hacia el lóbulo frontal superior
        lines.move(to: pt(43.5, 34.0))
        lines.addLine(to: pt(35.0, 26.5))
        lines.addLine(to: pt(35.0, 19.0))

        // 2. Tronco central + rama lateral media con bifurcación
        lines.move(to: pt(43.5, 50.0))
        lines.addLine(to: pt(29.5, 50.0))
        lines.addLine(to: pt(21.5, 42.0))

        lines.move(to: pt(31.0, 50.0))
        lines.addLine(to: pt(22.0, 59.0))

        // 3. Rama inferior diagonal hacia el lóbulo base
        lines.move(to: pt(43.5, 65.5))
        lines.addLine(to: pt(33.5, 74.5))
        lines.addLine(to: pt(28.0, 74.5))

        // 4. Columna vertebral interior conectando las ramas
        lines.move(to: pt(43.5, 34.0))
        lines.addLine(to: pt(43.5, 78.0))

        ctx.stroke(lines, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        // Nodos sinápticos circulares en los extremos
        let nodes: [(CGFloat, CGFloat)] = [
            (35.0, 19.0),
            (21.5, 42.0),
            (22.0, 59.0),
            (28.0, 74.5),
            (43.5, 78.0)
        ]
        for (nx, ny) in nodes {
            let p = pt(nx, ny)
            let dot = Path(ellipseIn: CGRect(x: p.x - nodeRadius, y: p.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2))
            ctx.fill(dot, with: shading)
        }
    }

    private static func folderSilhouette(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        tabWidth: CGFloat,
        tabHeight: CGFloat,
        cornerRadius: CGFloat
    ) -> Path {
        let r = min(cornerRadius, height * 0.25)
        let tr = min(r * 0.72, tabHeight * 0.85)
        let left = x
        let right = x + width
        let top = y
        let bodyTop = y + tabHeight
        let bottom = y + height
        let tabEnd = x + tabWidth
        let slopeEnd = min(right - r, tabEnd + tabHeight * 0.85)

        var p = Path()
        p.move(to: CGPoint(x: left + tr, y: top))
        p.addLine(to: CGPoint(x: tabEnd - tr * 0.6, y: top))
        p.addQuadCurve(to: CGPoint(x: tabEnd + tr * 0.5, y: top + tr * 0.5), control: CGPoint(x: tabEnd + tr * 0.1, y: top))
        p.addLine(to: CGPoint(x: slopeEnd - tr * 0.5, y: bodyTop - tr * 0.25))
        p.addQuadCurve(to: CGPoint(x: slopeEnd + tr * 0.6, y: bodyTop), control: CGPoint(x: slopeEnd, y: bodyTop))
        p.addLine(to: CGPoint(x: right - r, y: bodyTop))
        p.addQuadCurve(to: CGPoint(x: right, y: bodyTop + r), control: CGPoint(x: right, y: bodyTop))
        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: left + r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: left, y: bottom - r), control: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: left, y: top + tr))
        p.addQuadCurve(to: CGPoint(x: left + tr, y: top), control: CGPoint(x: left, y: top))
        p.closeSubpath()
        return p
    }

    private static func unevenRoundedRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomRight: CGFloat,
        bottomLeft: CGFloat
    ) -> Path {
        let minX = x
        let maxX = x + width
        let minY = y
        let maxY = y + height

        var p = Path()
        p.move(to: CGPoint(x: minX + topLeft, y: minY))
        p.addLine(to: CGPoint(x: maxX - topRight, y: minY))
        p.addQuadCurve(to: CGPoint(x: maxX, y: minY + topRight), control: CGPoint(x: maxX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: maxY - bottomRight))
        p.addQuadCurve(to: CGPoint(x: maxX - bottomRight, y: maxY), control: CGPoint(x: maxX, y: maxY))
        p.addLine(to: CGPoint(x: minX + bottomLeft, y: maxY))
        p.addQuadCurve(to: CGPoint(x: minX, y: maxY - bottomLeft), control: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX, y: minY + topLeft))
        p.addQuadCurve(to: CGPoint(x: minX + topLeft, y: minY), control: CGPoint(x: minX, y: minY))
        p.closeSubpath()
        return p
    }
}
