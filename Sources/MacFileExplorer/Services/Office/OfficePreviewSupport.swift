import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Categorías de documentos Office y tabulares soportados con visor/editor enriquecido en Vista Rápida.
public enum OfficeDocumentKind: String, Sendable, Equatable {
    case csv
    case word
    case excel
    case powerpoint

    @MainActor
    public func localizedBadge(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .csv: return "CSV"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "PowerPoint"
        }
    }

    public var symbolName: String {
        switch self {
        case .csv: return "tablecells.fill"
        case .word: return "doc.richtext.fill"
        case .excel: return "tablecells.badge.ellipsis"
        case .powerpoint: return "play.rectangle.on.rectangle.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .csv: return Color(red: 0.14, green: 0.66, blue: 0.44)
        case .word: return Color(red: 0.16, green: 0.44, blue: 0.88)
        case .excel: return Color(red: 0.12, green: 0.56, blue: 0.34)
        case .powerpoint: return Color(red: 0.84, green: 0.32, blue: 0.18)
        }
    }
}

/// Destino web de Google Workspace al enviar un archivo local con "Send to Drive".
public enum GoogleEditorTarget: String, Sendable, Equatable {
    case sheets
    case docs
    case slides
    case driveViewer

    @MainActor
    public func localizedName(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .sheets: return "Google Sheets"
        case .docs: return "Google Docs"
        case .slides: return "Google Slides"
        case .driveViewer: return "Google Drive"
        }
    }

    public var symbolName: String {
        switch self {
        case .sheets: return "tablecells.fill"
        case .docs: return "doc.text.fill"
        case .slides: return "rectangle.on.rectangle.angled"
        case .driveViewer: return "externaldrive.fill.badge.icloud"
        }
    }

    public var accentColor: Color {
        switch self {
        case .sheets: return Color(red: 0.12, green: 0.62, blue: 0.36)
        case .docs: return Color(red: 0.22, green: 0.48, blue: 0.94)
        case .slides: return Color(red: 0.95, green: 0.66, blue: 0.10)
        case .driveViewer: return Color(red: 0.20, green: 0.66, blue: 0.33)
        }
    }

    /// Construye la URL directa del editor de Google correspondiente para un `fileID` de Google Drive.
    public func editorURL(forFileID fileID: String) -> URL? {
        let clean = fileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        switch self {
        case .sheets:
            return URL(string: "https://docs.google.com/spreadsheets/d/\(clean)/edit")
        case .docs:
            return URL(string: "https://docs.google.com/document/d/\(clean)/edit")
        case .slides:
            return URL(string: "https://docs.google.com/presentation/d/\(clean)/edit")
        case .driveViewer:
            return URL(string: "https://drive.google.com/file/d/\(clean)/view")
        }
    }
}

/// Clasificador central de extensiones Office / CSV y rutas hacia Google Workspace.
public enum OfficePreviewSupport {
    public static let csvExtensions: Set<String> = ["csv", "tsv"]
    public static let editableWordExtensions: Set<String> = ["docx", "doc", "rtf", "odt"]
    public static let editableExcelExtensions: Set<String> = ["xlsx", "xls"]
    public static let legacyExcelExtensions: Set<String> = ["ods"]
    public static let editablePowerPointExtensions: Set<String> = ["pptx"]
    public static let legacyPowerPointExtensions: Set<String> = ["ppt", "odp"]

    public static func documentKind(for url: URL) -> OfficeDocumentKind? {
        let ext = url.pathExtension.lowercased()
        if csvExtensions.contains(ext) { return .csv }
        if editableWordExtensions.contains(ext) { return .word }
        if editableExcelExtensions.contains(ext) || legacyExcelExtensions.contains(ext) { return .excel }
        if editablePowerPointExtensions.contains(ext) || legacyPowerPointExtensions.contains(ext) { return .powerpoint }
        return nil
    }

    public static func supportsOfficePreview(for url: URL) -> Bool {
        documentKind(for: url) != nil
    }

    public static func isNativelyEditable(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return csvExtensions.contains(ext)
            || editableWordExtensions.contains(ext)
            || editableExcelExtensions.contains(ext)
            || editablePowerPointExtensions.contains(ext)
    }

    /// Determina qué aplicación web de Google abrir automáticamente tras subir el archivo a Drive.
    public static func googleEditorTarget(for url: URL) -> GoogleEditorTarget {
        let ext = url.pathExtension.lowercased()
        if csvExtensions.contains(ext) || editableExcelExtensions.contains(ext) || legacyExcelExtensions.contains(ext) {
            return .sheets
        }
        if editableWordExtensions.contains(ext) || ext == "txt" || ext == "md" {
            return .docs
        }
        if editablePowerPointExtensions.contains(ext) || legacyPowerPointExtensions.contains(ext) {
            return .slides
        }
        return .driveViewer
    }
}

/// Ayudante reutilizable para diálogos "Guardar copia…" con sugerencia inteligente de nombre y extensión.
@MainActor
public enum OfficeSavePanelHelper {
    public static func chooseCopyDestination(
        originalURL: URL,
        preferredExtension: String? = nil,
        additionalExtensions: [String] = [],
        title: String
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.canCreateDirectories = true
        panel.directoryURL = originalURL.deletingLastPathComponent()

        let ext = preferredExtension ?? originalURL.pathExtension
        let stem = originalURL.deletingPathExtension().lastPathComponent
        let loc = LocalizationManager.shared
        let suffix = loc.text(es: " (Copia)", en: " (Copy)")
        panel.nameFieldStringValue = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"

        let allExts = ([ext] + additionalExtensions).filter { !$0.isEmpty }
        let utTypes = allExts.compactMap { UTType(filenameExtension: $0) }
        if !utTypes.isEmpty {
            panel.allowedContentTypes = utTypes
        }

        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Utilidades de Color Hexadecimal para Estilos de Celdas y Diapositivas

public enum OfficeColorCodec {
    public static func nsColor(fromHex rawHex: String?) -> NSColor? {
        guard var hex = rawHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        // OOXML ARGB (8 dígitos): tomar los últimos 6 (RGB)
        if hex.count == 8 {
            hex = String(hex.suffix(6))
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    public static func swiftUIColor(fromHex rawHex: String?) -> Color? {
        nsColor(fromHex: rawHex).map { Color(nsColor: $0) }
    }

    public static func hexRGB(from color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

// MARK: - Sistema Visual Unificado para Barras de Vista Rápida y Editores Office

public enum PreviewToolbarMetrics {
    public static let controlHeight: CGFloat = 26
    public static let iconButtonWidth: CGFloat = 28
    public static let iconSize: CGFloat = 13
    public static let labelFontSize: CGFloat = 12
    public static let cornerRadius: CGFloat = 6
}

/// Icono vectorial clásico de diskette (Save) con relleno even-odd que hereda el color activo del botón.
public struct FloppyDiskIconView: View {
    public var size: CGFloat = PreviewToolbarMetrics.iconSize

    public init(size: CGFloat = PreviewToolbarMetrics.iconSize) {
        self.size = size
    }

    public var body: some View {
        FloppyDiskShape()
            .fill(style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}

/// Variante de diskette con indicador "+" para «Guardar copia…».
public struct FloppyDiskCopyIconView: View {
    public var size: CGFloat = PreviewToolbarMetrics.iconSize

    public init(size: CGFloat = PreviewToolbarMetrics.iconSize) {
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FloppyDiskShape()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: size, height: size)

            Image(systemName: "plus.circle.fill")
                .font(.system(size: max(6.5, size * 0.50), weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(nsColor: .controlBackgroundColor), Color.primary)
                .offset(x: 2.5, y: 2.0)
        }
        .frame(width: size + 2, height: size)
    }
}

private struct FloppyDiskShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 16.0
        let sy = rect.height / 16.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()

        // 1. Silueta externa del diskette con esquina superior derecha biselada
        path.move(to: pt(2.6, 1.1))
        path.addLine(to: pt(11.4, 1.1))
        path.addLine(to: pt(14.9, 4.6))
        path.addLine(to: pt(14.9, 13.4))
        path.addQuadCurve(to: pt(13.4, 14.9), control: pt(14.9, 14.9))
        path.addLine(to: pt(2.6, 14.9))
        path.addQuadCurve(to: pt(1.1, 13.4), control: pt(1.1, 14.9))
        path.addLine(to: pt(1.1, 2.6))
        path.addQuadCurve(to: pt(2.6, 1.1), control: pt(1.1, 1.1))
        path.closeSubpath()

        // 2. Ventana superior del obturador metálico (hueco)
        path.addRoundedRect(
            in: CGRect(x: rect.minX + 4.0 * sx, y: rect.minY + 1.8 * sy, width: 6.4 * sx, height: 4.1 * sy),
            cornerSize: CGSize(width: 0.7 * sx, height: 0.7 * sy)
        )

        // 3. Ranura metálica vertical dentro del obturador (relleno)
        path.addRoundedRect(
            in: CGRect(x: rect.minX + 8.1 * sx, y: rect.minY + 2.5 * sy, width: 1.4 * sx, height: 2.7 * sy),
            cornerSize: CGSize(width: 0.4 * sx, height: 0.4 * sy)
        )

        // 4. Etiqueta inferior clásica (hueco)
        path.addRoundedRect(
            in: CGRect(x: rect.minX + 3.2 * sx, y: rect.minY + 8.3 * sy, width: 9.6 * sx, height: 5.3 * sy),
            cornerSize: CGSize(width: 0.9 * sx, height: 0.9 * sy)
        )

        // 5. Línea horizontal dentro de la etiqueta (relleno)
        path.addRoundedRect(
            in: CGRect(x: rect.minX + 4.9 * sx, y: rect.minY + 10.4 * sy, width: 6.2 * sx, height: 1.1 * sy),
            cornerSize: CGSize(width: 0.45 * sx, height: 0.45 * sy)
        )

        return path
    }
}

/// Estilo de botón unificado de altura fija (`26 pt`) para las barras de Quick Look y editores Office/CSV.
public struct PreviewToolbarButtonStyle: ButtonStyle {
    public enum Variant {
        case standard
        case prominent
        case active
    }

    public let variant: Variant

    public init(variant: Variant = .standard) {
        self.variant = variant
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let fill: Color = {
            switch variant {
            case .prominent:
                return Color.accentColor.opacity(isPressed ? 0.80 : 1.0)
            case .active:
                return Color.accentColor.opacity(isPressed ? 0.28 : 0.18)
            case .standard:
                return Color.primary.opacity(isPressed ? 0.15 : 0.085)
            }
        }()

        let stroke: Color = {
            switch variant {
            case .prominent:
                return Color.white.opacity(0.14)
            case .active:
                return Color.accentColor.opacity(0.45)
            case .standard:
                return Color.primary.opacity(0.11)
            }
        }()

        let fg: Color = {
            switch variant {
            case .prominent: return .white
            case .active: return .accentColor
            case .standard: return .primary
            }
        }()

        return configuration.label
            .foregroundStyle(fg)
            .frame(height: PreviewToolbarMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous))
    }
}

/// Botón cuadrado de icono unificado (`28 × 26 pt`, icono `13 pt`) para todas las barras de edición.
public struct PreviewToolbarIconButton: View {
    public let systemName: String
    public var active: Bool
    public var helpText: String
    public var disabled: Bool
    public let action: () -> Void

    public init(
        _ systemName: String,
        active: Bool = false,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.active = active
        self.helpText = help
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                .frame(width: PreviewToolbarMetrics.iconButtonWidth, height: PreviewToolbarMetrics.controlHeight)
        }
        .buttonStyle(PreviewToolbarButtonStyle(variant: active ? .active : .standard))
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1.0)
        .help(helpText)
    }
}

/// Botón de carácter de formato (`B`, `I`, `U`, `S`) con el mismo tamaño exacto (`28 × 26 pt`).
public struct PreviewToolbarToggleCharButton: View {
    public let text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var active: Bool
    public var disabled: Bool
    public var helpText: String
    public let action: () -> Void

    public init(
        _ text: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        active: Bool,
        disabled: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.active = active
        self.disabled = disabled
        self.helpText = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: PreviewToolbarMetrics.iconSize, weight: bold ? .bold : .semibold, design: italic ? .serif : .default))
                .italic(italic)
                .underline(underline)
                .strikethrough(strikethrough)
                .frame(width: PreviewToolbarMetrics.iconButtonWidth, height: PreviewToolbarMetrics.controlHeight)
        }
        .buttonStyle(PreviewToolbarButtonStyle(variant: active ? .active : .standard))
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1.0)
        .help(helpText)
    }
}
