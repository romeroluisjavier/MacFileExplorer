import Foundation
import AppKit
import UniformTypeIdentifiers

/// Modelo inmutable y `Sendable` que representa un archivo, carpeta o volumen en el sistema de archivos.
/// Diseñado para precargar metadatos en lote (`URLResourceKey`) fuera del hilo principal sin bloquear la UI.
public struct FileItem: Identifiable, Hashable, Sendable {

    // MARK: - Identidad

    /// Identificador único basado en la URL estandarizada del elemento.
    /// Permite mantener la selección (`Set<FileItem.ID>`) y el estado de "Cortar" (`Cmd+X`) de forma consistente.
    public let id: URL

    /// URL completa en el sistema de archivos local.
    public let url: URL

    // MARK: - Propiedades Principales (Columnas de Windows Explorer)

    /// Nombre visible o de archivo (ej. "Reporte.pdf").
    public let name: String

    /// Extensión del archivo en minúsculas (vacío para carpetas sin extensión).
    public let fileExtension: String

    /// Indica si el elemento es un directorio navegable (excluyendo paquetes `.app` / bundles si se desea tratarlos como archivo).
    public let isDirectory: Bool

    /// Indica si el directorio es un paquete de macOS (ej. `.app`, `.bundle`, `.rtfd`).
    public let isPackage: Bool

    /// Indica si es un elemento oculto en el sistema de archivos (prefijo `.` o flag UF_HIDDEN).
    public let isHidden: Bool

    /// Indica si el elemento es un enlace simbólico o alias.
    public let isSymbolicLink: Bool

    /// Fecha de última modificación del elemento.
    public let modificationDate: Date

    /// Fecha de creación del elemento.
    public let creationDate: Date

    /// Tamaño físico o lógico en bytes (`nil` para directorios, emulando el comportamiento de Windows Explorer).
    public let size: Int64?

    /// Tipo uniforme del archivo (`UTType`) para clasificación y filtrado rápido.
    public let contentType: UTType?

    /// Descripción localizada del tipo (columna "Tipo" en Windows Explorer, ej. "Carpeta de archivos", "Documento PDF").
    public let kindDescription: String

    // MARK: - Propiedades Auxiliares para Ordenamiento en Tablas (`KeyPathComparator`)

    /// Valor numérico seguro para ordenar la columna "Tamaño" en `SwiftUI.Table` (carpetas = -1 para agrupar).
    public var sortableSize: Int64 {
        size ?? -1
    }

    /// Clave de ordenamiento insensible a mayúsculas/minúsculas.
    public var sortableName: String {
        name.localizedLowercase
    }

    /// Indica si el nodo puede expandirse o abrirse como carpeta dentro del explorador.
    public var isNavigableFolder: Bool {
        isDirectory && !isPackage
    }

    /// Indica si el archivo es un archivo comprimido `.zip` que puede desarchivarse.
    public var isZipArchive: Bool {
        guard !isDirectory else { return false }
        if fileExtension.lowercased() == "zip" {
            return true
        }
        if let contentType, contentType.conforms(to: .zip) {
            return true
        }
        return false
    }

    // MARK: - Claves de Precarga I/O (`FileManager`)

    /// Conjunto de claves `URLResourceKey` solicitadas en bloque a `FileManager.contentsOfDirectory`
    /// para evitar llamadas adicionales a `stat()` por cada archivo en directorios masivos.
    public static let prefetchedResourceKeys: [URLResourceKey] = [
        .nameKey,
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .isSymbolicLinkKey,
        .contentModificationDateKey,
        .creationDateKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .contentTypeKey,
        .localizedTypeDescriptionKey
    ]

    public static let prefetchedResourceKeySet: Set<URLResourceKey> = Set(prefetchedResourceKeys)

    // MARK: - Inicializadores

    public init(
        url: URL,
        name: String,
        fileExtension: String? = nil,
        isDirectory: Bool,
        isPackage: Bool = false,
        isHidden: Bool = false,
        isSymbolicLink: Bool = false,
        modificationDate: Date = .distantPast,
        creationDate: Date = .distantPast,
        size: Int64? = nil,
        contentType: UTType? = nil,
        kindDescription: String? = nil
    ) {
        let standardized = url.standardizedFileURL
        self.id = standardized
        self.url = standardized
        self.name = name
        self.fileExtension = fileExtension ?? standardized.pathExtension.lowercased()
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.isSymbolicLink = isSymbolicLink
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.size = (isDirectory && !isPackage) ? nil : size
        self.contentType = contentType
        if let kindDescription, !kindDescription.isEmpty {
            self.kindDescription = kindDescription
        } else if isDirectory && !isPackage {
            self.kindDescription = "Carpeta de archivos"
        } else {
            self.kindDescription = contentType?.localizedDescription ?? "Archivo"
        }
    }

    /// Crea un `FileItem` extrayendo los metadatos precargados de `URL`.
    /// Seguro para ejecutarse en tareas concurrentes en segundo plano (`Task.detached` / `DispatchQueue`).
    public init(url: URL) throws {
        let standardized = url.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: Self.prefetchedResourceKeySet)
        self.init(url: standardized, resourceValues: values)
    }

    /// Inicializador directo a partir de `URLResourceValues` ya obtenidos.
    public init(url: URL, resourceValues values: URLResourceValues) {
        let standardized = url.standardizedFileURL
        let rawIsDirectory = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        let isNavigableDir = rawIsDirectory && !isPackage

        let resolvedName = values.name ?? standardized.lastPathComponent
        let ext = standardized.pathExtension.lowercased()
        let contentType = values.contentType

        let resolvedSize: Int64?
        if isNavigableDir {
            resolvedSize = nil
        } else if let fileSize = values.fileSize {
            resolvedSize = Int64(fileSize)
        } else if let allocated = values.totalFileAllocatedSize {
            resolvedSize = Int64(allocated)
        } else {
            resolvedSize = nil
        }

        let resolvedKind: String
        if isNavigableDir {
            resolvedKind = "Carpeta de archivos"
        } else if let localizedType = values.localizedTypeDescription, !localizedType.isEmpty {
            resolvedKind = localizedType
        } else if let utDescription = contentType?.localizedDescription, !utDescription.isEmpty {
            resolvedKind = utDescription
        } else if !ext.isEmpty {
            resolvedKind = "Archivo \(ext.uppercased())"
        } else {
            resolvedKind = "Archivo"
        }

        self.id = standardized
        self.url = standardized
        self.name = resolvedName
        self.fileExtension = ext
        self.isDirectory = rawIsDirectory
        self.isPackage = isPackage
        self.isHidden = values.isHidden ?? resolvedName.hasPrefix(".")
        self.isSymbolicLink = values.isSymbolicLink ?? false
        self.modificationDate = values.contentModificationDate ?? .distantPast
        self.creationDate = values.creationDate ?? .distantPast
        self.size = resolvedSize
        self.contentType = contentType
        self.kindDescription = resolvedKind
    }

    // MARK: - Formateadores de Presentación (Estilo Windows 11 Explorer)

    /// Tamaño formateado para la columna "Tamaño" (vacío para carpetas, en KB/MB/GB para archivos).
    public var formattedSize: String {
        guard let size else { return "" }
        if size == 0 {
            return "0 KB"
        }
        return size.formatted(
            .byteCount(
                style: .file,
                allowedUnits: [.kb, .mb, .gb, .tb],
                spellsOutZero: false,
                includesActualByteCount: false
            )
        )
    }

    /// Fecha de modificación formateada al estilo compacto de Windows Explorer (`dd/MM/yyyy HH:mm`).
    public var formattedModificationDate: String {
        guard modificationDate != .distantPast else { return "—" }
        return modificationDate.formatted(
            .dateTime
                .day(.twoDigits)
                .month(.twoDigits)
                .year()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    /// Obtiene el icono nativo del sistema para este archivo o carpeta.
    /// Debe invocarse desde `@MainActor` cuando se renderiza en la interfaz.
    @MainActor
    public var systemIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    // MARK: - Ordenamiento Estilo Windows Explorer (Carpetas Primero)

    /// Criterio de columna para ordenar elementos en la vista Detalles o Cuadrícula.
    public enum SortField: String, CaseIterable, Sendable {
        case name = "Nombre"
        case modificationDate = "Fecha de modificación"
        case modificationDateMix = "Fecha de modificación mix"
        case kind = "Tipo"
        case size = "Tamaño"
    }

    /// Ordena una colección de `FileItem` manteniendo siempre las carpetas agrupadas al principio
    /// (excepto en `modificationDateMix`, donde carpetas y archivos se mezclan por fecha de modificación).
    public static func sort(
        _ items: [FileItem],
        by field: SortField,
        ascending: Bool = true,
        foldersFirst: Bool = true
    ) -> [FileItem] {
        let groupFoldersFirst = foldersFirst && (field != .modificationDateMix)
        return items.sorted { lhs, rhs in
            if groupFoldersFirst && lhs.isNavigableFolder != rhs.isNavigableFolder {
                return lhs.isNavigableFolder && !rhs.isNavigableFolder
            }

            let comparison: ComparisonResult
            switch field {
            case .name:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .modificationDate, .modificationDateMix:
                if lhs.modificationDate == rhs.modificationDate {
                    comparison = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    comparison = lhs.modificationDate < rhs.modificationDate ? .orderedAscending : .orderedDescending
                }
            case .kind:
                let kindCmp = lhs.kindDescription.localizedStandardCompare(rhs.kindDescription)
                comparison = (kindCmp == .orderedSame)
                    ? lhs.name.localizedStandardCompare(rhs.name)
                    : kindCmp
            case .size:
                let lSize = lhs.sortableSize
                let rSize = rhs.sortableSize
                if lSize == rSize {
                    comparison = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    comparison = lSize < rSize ? .orderedAscending : .orderedDescending
                }
            }

            return ascending
                ? (comparison == .orderedAscending)
                : (comparison == .orderedDescending)
        }
    }
}
