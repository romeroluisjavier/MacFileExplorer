import Foundation
import Observation

/// Modo inicial al abrir documentos de Office (Word, Excel, PowerPoint) en Vista Rápida (`Espacio`).
public enum OfficePreviewOpenMode: String, CaseIterable, Identifiable, Sendable {
    case originalView
    case editor

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .originalView:
            return loc.text(es: "Vista original (Quick Look)", en: "Original View (Quick Look)")
        case .editor:
            return loc.text(es: "Editor rápido", en: "Quick Editor")
        }
    }

    public var systemImage: String {
        switch self {
        case .originalView: return "eye"
        case .editor: return "pencil.and.outline"
        }
    }
}

/// Preferencias persistentes del menú superior **Office** (modo edición, formatos activos, planillas y «Enviar a Drive»).
@MainActor
@Observable
public final class OfficePreferences {
    public static let shared = OfficePreferences()

    private let defaults: UserDefaults
    private var isBootstrapping = false

    private enum Keys {
        static let isOfficeEditingEnabled = "com.macfileexplorer.office.isEditingEnabled.v1"
        static let defaultOpenMode = "com.macfileexplorer.office.defaultOpenMode.v1"
        static let enableWordPreview = "com.macfileexplorer.office.enableWordPreview.v1"
        static let enableExcelPreview = "com.macfileexplorer.office.enableExcelPreview.v1"
        static let enablePowerPointPreview = "com.macfileexplorer.office.enablePowerPointPreview.v1"
        static let isInteractiveCSVEnabled = "com.macfileexplorer.office.isInteractiveCSVEnabled.v1"
        static let csvFirstRowIsHeader = "com.macfileexplorer.office.csvFirstRowIsHeader.v1"
        static let spreadsheetWrapText = "com.macfileexplorer.office.spreadsheetWrapText.v1"
        static let isSendToDriveEnabled = "com.macfileexplorer.office.isSendToDriveEnabled.v1"
    }

    /// Habilita o deshabilita el modo de edición rápida en Vista Rápida (Word, Excel, PowerPoint y CSV).
    public var isOfficeEditingEnabled: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(isOfficeEditingEnabled, forKey: Keys.isOfficeEditingEnabled)
        }
    }

    /// Modo de apertura inicial en documentos Office (por defecto: Vista original).
    public var defaultOpenMode: OfficePreviewOpenMode = .originalView {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(defaultOpenMode.rawValue, forKey: Keys.defaultOpenMode)
        }
    }

    /// Activa el visor/editor enriquecido para documentos Word (`.docx`, `.doc`, `.rtf`, `.odt`).
    public var enableWordPreview: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(enableWordPreview, forKey: Keys.enableWordPreview)
        }
    }

    /// Activa el visor/editor enriquecido para planillas Excel (`.xlsx`, `.xls`, `.ods`).
    public var enableExcelPreview: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(enableExcelPreview, forKey: Keys.enableExcelPreview)
        }
    }

    /// Activa el visor/editor enriquecido para presentaciones PowerPoint (`.pptx`, `.ppt`, `.odp`).
    public var enablePowerPointPreview: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(enablePowerPointPreview, forKey: Keys.enablePowerPointPreview)
        }
    }

    /// Activa la planilla interactiva de alto rendimiento para archivos `.csv` y `.tsv`.
    public var isInteractiveCSVEnabled: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(isInteractiveCSVEnabled, forKey: Keys.isInteractiveCSVEnabled)
        }
    }

    /// Congela la primera fila como encabezado al abrir archivos `.csv` / `.tsv`.
    public var csvFirstRowIsHeaderByDefault: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(csvFirstRowIsHeaderByDefault, forKey: Keys.csvFirstRowIsHeader)
        }
    }

    /// Activa ajuste de texto en varias líneas por defecto en celdas de CSV y Excel.
    public var spreadsheetWrapTextByDefault: Bool = false {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(spreadsheetWrapTextByDefault, forKey: Keys.spreadsheetWrapText)
        }
    }

    /// Muestra u oculta las acciones de «Enviar a Drive» en Vista Rápida, menú contextual y pestaña de Drive.
    public var isSendToDriveEnabled: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(isSendToDriveEnabled, forKey: Keys.isSendToDriveEnabled)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isBootstrapping = true
        defer { self.isBootstrapping = false }

        self.isOfficeEditingEnabled = defaults.object(forKey: Keys.isOfficeEditingEnabled) as? Bool ?? true
        if let rawMode = defaults.string(forKey: Keys.defaultOpenMode),
           let parsed = OfficePreviewOpenMode(rawValue: rawMode) {
            self.defaultOpenMode = parsed
        } else {
            self.defaultOpenMode = .originalView
        }
        self.enableWordPreview = defaults.object(forKey: Keys.enableWordPreview) as? Bool ?? true
        self.enableExcelPreview = defaults.object(forKey: Keys.enableExcelPreview) as? Bool ?? true
        self.enablePowerPointPreview = defaults.object(forKey: Keys.enablePowerPointPreview) as? Bool ?? true
        self.isInteractiveCSVEnabled = defaults.object(forKey: Keys.isInteractiveCSVEnabled) as? Bool ?? true
        self.csvFirstRowIsHeaderByDefault = defaults.object(forKey: Keys.csvFirstRowIsHeader) as? Bool ?? true
        self.spreadsheetWrapTextByDefault = defaults.object(forKey: Keys.spreadsheetWrapText) as? Bool ?? false
        self.isSendToDriveEnabled = defaults.object(forKey: Keys.isSendToDriveEnabled) as? Bool ?? true
    }

    /// Indica si la categoría de documento indicada tiene habilitado el visor enriquecido de Office/CSV.
    public func isPreviewEnabled(for kind: OfficeDocumentKind) -> Bool {
        switch kind {
        case .csv: return isInteractiveCSVEnabled
        case .word: return enableWordPreview
        case .excel: return enableExcelPreview
        case .powerpoint: return enablePowerPointPreview
        }
    }

    /// Indica si la vista debe abrir inicialmente en Vista Original (`true`) o en modo Editor (`false`).
    public var shouldOpenInOriginalView: Bool {
        !isOfficeEditingEnabled || defaultOpenMode == .originalView
    }

    public var isDefaultConfiguration: Bool {
        isOfficeEditingEnabled
            && defaultOpenMode == .originalView
            && enableWordPreview
            && enableExcelPreview
            && enablePowerPointPreview
            && isInteractiveCSVEnabled
            && csvFirstRowIsHeaderByDefault
            && !spreadsheetWrapTextByDefault
            && isSendToDriveEnabled
    }

    public func resetToDefaults() {
        isOfficeEditingEnabled = true
        defaultOpenMode = .originalView
        enableWordPreview = true
        enableExcelPreview = true
        enablePowerPointPreview = true
        isInteractiveCSVEnabled = true
        csvFirstRowIsHeaderByDefault = true
        spreadsheetWrapTextByDefault = false
        isSendToDriveEnabled = true
    }
}
