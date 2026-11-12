import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Estadísticas detalladas calculadas en segundo plano para el diálogo de "Propiedades" (estilo Windows 11 Explorer).
public struct DetailedItemMetadata: Sendable {
    public var logicalBytes: Int64 = 0
    public var allocatedBytes: Int64 = 0
    public var fileCount: Int = 0
    public var folderCount: Int = 0
    public var isScanningFolder: Bool = false
    public var lastAccessDate: Date? = nil
    public var isReadable: Bool = true
    public var isWritable: Bool = true
    public var isExecutable: Bool = false
    public var posixPermissionsOctal: String = ""
    public var ownerName: String = ""
}

/// Modal "Propiedades / Properties" estilo Windows 11 Explorer con estética nativa de macOS.
public struct ItemPropertiesModalView: View {
    public let item: FileItem
    @Environment(\.dismiss) private var dismiss

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(item: FileItem) {
        self.item = item
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Barra superior estilo pestaña "General" de Propiedades de Windows 11
            headerBar

            Divider()

            ItemPropertiesContentView(item: item)

            Divider()

            // Pie del modal con botón Aceptar / Cerrar
            footerBar
        }
        .frame(width: 440, height: item.isDirectory ? 545 : 515)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Barra Superior y Pie del Modal

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(loc.text(
                es: "Propiedades de \(item.name)",
                en: "\(item.name) Properties"
            ))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer()

            // Píldora de pestaña "General" estilo Windows 11
            Text("General")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private var footerBar: some View {
        HStack {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label(loc.text(es: "Mostrar en Finder", en: "Show in Finder"), systemImage: "macwindow")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()

            Button(loc.text(es: "Aceptar", en: "OK")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }
}

/// Contenido reutilizable de "Propiedades" (identidad, tipo, ubicación, tamaño recursivo, fechas, atributos y permisos).
/// Usado tanto en `ItemPropertiesModalView` como dentro de Quick Look (`Espacio`) al previsualizar carpetas.
public struct ItemPropertiesContentView: View {
    public let item: FileItem
    public var horizontalPadding: CGFloat = 22
    public var verticalPadding: CGFloat = 16

    @ViewState private var metadata = DetailedItemMetadata()
    @ViewState private var previewThumbnail: NSImage? = nil
    @ViewState private var copiedPathFeedback: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(item: FileItem, horizontalPadding: CGFloat = 22, verticalPadding: CGFloat = 16) {
        self.item = item
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Identidad del archivo o carpeta (Icono/Miniatura + Nombre)
                identitySection

                Divider()

                // 2. Tipo de archivo y "Se abre con"
                typeAndAppSection

                Divider()

                // 3. Ubicación, Tamaño, Tamaño en disco y Conteo (para carpetas)
                locationAndSizeSection

                Divider()

                // 4. Fechas (Creado, Modificado, Último acceso)
                timestampsSection

                Divider()

                // 5. Atributos y Permisos (Solo lectura, Oculto, Permisos POSIX)
                attributesSection
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .task(id: item.id) {
            previewThumbnail = nil
            // Cargar miniatura si es imagen/multimedia
            if ThumbnailCacheService.shared.supportsThumbnail(for: item) {
                previewThumbnail = await ThumbnailCacheService.shared.thumbnail(for: item, maxPixelSize: 160)
            }
            // Calcular metadatos extendidos y tamaño recursivo si es carpeta
            await inspectItemMetadata()
        }
    }

    // MARK: - Secciones de la Vista

    private var identitySection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 58, height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                    )

                if let thumb = previewThumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: 48, maxHeight: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(nsImage: FileIconProvider.shared.icon(for: item, size: 44))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                Text(loc.localizedKindDescription(for: item))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var typeAndAppSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            propertyRow(
                label: loc.text(es: "Tipo:", en: "Type of file:"),
                value: formattedTypeDescription
            )

            if !item.isNavigableFolder, let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: item.url) {
                HStack(alignment: .center, spacing: 8) {
                    Text(loc.text(es: "Se abre con:", en: "Opens with:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(nsImage: appIcon(for: defaultAppURL))
                            .resizable()
                            .frame(width: 16, height: 16)

                        Text(appDisplayName(for: defaultAppURL))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                }
            }
        }
    }

    private var locationAndSizeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Text(loc.text(es: "Ubicación:", en: "Location:"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 118, alignment: .leading)

                Text(parentDirectoryPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(item.url.path(percentEncoded: false), forType: .string)
                    copiedPathFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedPathFeedback = false
                    }
                } label: {
                    Image(systemName: copiedPathFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copiedPathFeedback ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(loc.text(es: "Copiar ruta completa", en: "Copy full path"))
            }

            HStack(alignment: .center, spacing: 8) {
                Text(loc.text(es: "Tamaño:", en: "Size:"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 118, alignment: .leading)

                HStack(spacing: 6) {
                    Text(formattedBytesWithExactCount(metadata.logicalBytes))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    if metadata.isScanningFolder {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    }
                }

                Spacer()
            }

            propertyRow(
                label: loc.text(es: "Tamaño en disco:", en: "Size on disk:"),
                value: formattedBytesWithExactCount(metadata.allocatedBytes),
                monospaced: true
            )

            if item.isDirectory {
                propertyRow(
                    label: loc.text(es: "Contiene:", en: "Contains:"),
                    value: loc.text(
                        es: "\(metadata.fileCount.formatted()) Archivos, \(metadata.folderCount.formatted()) Carpetas",
                        en: "\(metadata.fileCount.formatted()) Files, \(metadata.folderCount.formatted()) Folders"
                    ),
                    monospaced: true
                )
            }
        }
    }

    private var timestampsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            propertyRow(
                label: loc.text(es: "Creado:", en: "Created:"),
                value: formatFullDate(item.creationDate)
            )

            propertyRow(
                label: loc.text(es: "Modificado:", en: "Modified:"),
                value: formatFullDate(item.modificationDate)
            )

            propertyRow(
                label: loc.text(es: "Último acceso:", en: "Accessed:"),
                value: formatFullDate(metadata.lastAccessDate ?? item.modificationDate)
            )
        }
    }

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(loc.text(es: "Atributos:", en: "Attributes:"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 118, alignment: .leading)

                HStack(spacing: 14) {
                    attributeBadge(
                        title: loc.text(es: "Solo lectura", en: "Read-only"),
                        isActive: !metadata.isWritable
                    )

                    attributeBadge(
                        title: loc.text(es: "Oculto", en: "Hidden"),
                        isActive: item.isHidden
                    )
                }

                Spacer()
            }

            if !metadata.posixPermissionsOctal.isEmpty {
                propertyRow(
                    label: loc.text(es: "Permisos:", en: "Permissions:"),
                    value: metadata.ownerName.isEmpty
                        ? metadata.posixPermissionsOctal
                        : "\(metadata.posixPermissionsOctal) (\(metadata.ownerName))",
                    monospaced: true
                )
            }
        }
    }

    // MARK: - Componentes de Fila

    private func propertyRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text(value)
                .font(monospaced ? .system(size: 12).monospacedDigit() : .system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func attributeBadge(title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isActive ? "checkmark.square.fill" : "square")
                .font(.system(size: 12.5))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.6))

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Formateo de Datos

    private var formattedTypeDescription: String {
        let baseKind = loc.localizedKindDescription(for: item)
        if item.isNavigableFolder {
            return baseKind
        }
        if !item.fileExtension.isEmpty {
            return "\(baseKind) (.\(item.fileExtension.lowercased()))"
        }
        return baseKind
    }

    private var parentDirectoryPath: String {
        let parent = item.url.deletingLastPathComponent().path(percentEncoded: false)
        return parent.isEmpty ? "/" : parent
    }

    private func formattedBytesWithExactCount(_ bytes: Int64) -> String {
        if bytes <= 0 {
            let zeroBytes = loc.text(es: "0 bytes", en: "0 bytes")
            return "0 KB (\(zeroBytes))"
        }
        let shortFormatted = bytes.formatted(
            .byteCount(
                style: .file,
                allowedUnits: [.kb, .mb, .gb, .tb],
                spellsOutZero: false,
                includesActualByteCount: false
            )
        )
        let exactNumber = bytes.formatted(.number)
        return "\(shortFormatted) (\(exactNumber) bytes)"
    }

    private func formatFullDate(_ date: Date) -> String {
        guard date != .distantPast else { return "—" }
        let locale = Locale(identifier: loc.isSpanish ? "es_ES" : "en_US")
        return date.formatted(
            .dateTime
                .locale(locale)
                .day(.twoDigits)
                .month(.wide)
                .year()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }

    private func appDisplayName(for appURL: URL) -> String {
        let rawName = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
        if rawName.lowercased().hasSuffix(".app") {
            return String(rawName.dropLast(4))
        }
        return rawName
    }

    private func appIcon(for appURL: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false))
        let copy = (icon.copy() as? NSImage) ?? icon
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: - Inspección Asíncrona de Metadatos y Tamaño de Carpeta

    private func inspectItemMetadata() async {
        let targetURL = item.url
        let isDir = item.isDirectory

        // 1. Leer atributos directos del elemento
        let initial = await Task.detached(priority: .userInitiated) { () -> DetailedItemMetadata in
            var result = DetailedItemMetadata()
            let fm = FileManager.default
            let keys: Set<URLResourceKey> = [
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .contentAccessDateKey,
                .isReadableKey,
                .isWritableKey,
                .isExecutableKey
            ]

            if let values = try? targetURL.resourceValues(forKeys: keys) {
                result.lastAccessDate = values.contentAccessDate
                result.isReadable = values.isReadable ?? true
                result.isWritable = values.isWritable ?? true
                result.isExecutable = values.isExecutable ?? false

                if !isDir {
                    let logical = Int64(values.fileSize ?? 0)
                    let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? Int(logical))
                    result.logicalBytes = logical
                    result.allocatedBytes = max(logical, allocated)
                }
            }

            if let attrs = try? fm.attributesOfItem(atPath: targetURL.path(percentEncoded: false)) {
                if let posix = attrs[.posixPermissions] as? NSNumber {
                    let mode = posix.uint16Value & 0o777
                    result.posixPermissionsOctal = Self.formatPermissions(mode)
                }
                if let owner = attrs[.ownerAccountName] as? String {
                    result.ownerName = owner
                }
            }

            result.isScanningFolder = isDir
            return result
        }.value

        metadata = initial

        guard isDir else { return }

        // 2. Si es carpeta o paquete, calcular recursivamente tamaño, tamaño en disco y cantidad de archivos/carpetas
        let stream = AsyncStream<(Int64, Int64, Int, Int, Bool)> { continuation in
            let task = Task.detached(priority: .utility) {
                let fm = FileManager.default
                let resourceKeys: [URLResourceKey] = [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .fileSizeKey,
                    .totalFileAllocatedSizeKey,
                    .fileAllocatedSizeKey
                ]
                let keySet = Set(resourceKeys)

                guard let enumerator = fm.enumerator(
                    at: targetURL,
                    includingPropertiesForKeys: resourceKeys,
                    options: [],
                    errorHandler: { _, _ in true }
                ) else {
                    continuation.yield((0, 0, 0, 0, false))
                    continuation.finish()
                    return
                }

                var totalLogical: Int64 = 0
                var totalAllocated: Int64 = 0
                var files = 0
                var folders = 0
                var counter = 0

                while let nextObj = enumerator.nextObject() {
                    if Task.isCancelled { break }
                    guard let fileURL = nextObj as? URL else { continue }
                    if fileURL.lastPathComponent.hasPrefix(".macfileexplorer_") {
                        continue
                    }

                    if let values = try? fileURL.resourceValues(forKeys: keySet) {
                        if values.isDirectory == true {
                            folders += 1
                        } else {
                            files += 1
                            let logical = Int64(values.fileSize ?? 0)
                            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? Int(logical))
                            totalLogical += logical
                            totalAllocated += max(logical, allocated)
                        }
                    }

                    counter += 1
                    if counter % 250 == 0 {
                        continuation.yield((totalLogical, totalAllocated, files, folders, true))
                    }
                }

                continuation.yield((totalLogical, totalAllocated, files, folders, false))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        for await (logical, allocated, files, folders, scanning) in stream {
            if Task.isCancelled { break }
            metadata.logicalBytes = logical
            metadata.allocatedBytes = allocated
            metadata.fileCount = files
            metadata.folderCount = folders
            metadata.isScanningFolder = scanning
        }
    }

    private nonisolated static func formatPermissions(_ mode: UInt16) -> String {
        let chars: [Character] = [
            (mode & 0o400) != 0 ? "r" : "-",
            (mode & 0o200) != 0 ? "w" : "-",
            (mode & 0o100) != 0 ? "x" : "-",
            (mode & 0o040) != 0 ? "r" : "-",
            (mode & 0o020) != 0 ? "w" : "-",
            (mode & 0o010) != 0 ? "x" : "-",
            (mode & 0o004) != 0 ? "r" : "-",
            (mode & 0o002) != 0 ? "w" : "-",
            (mode & 0o001) != 0 ? "x" : "-"
        ]
        let rwx = String(chars)
        let octal = String(format: "%03o", mode)
        return "\(rwx) (\(octal))"
    }
}
