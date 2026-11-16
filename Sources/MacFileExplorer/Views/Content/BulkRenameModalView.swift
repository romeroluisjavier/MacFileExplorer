import SwiftUI

/// Modal de Renombrado Masivo (Bulk Rename) activado al presionar `Enter` / `F2` / `Renombrar` con múltiples archivos seleccionados.
/// Soporta expresiones regulares (Regex), numeración secuencial, fechas de metadatos EXIF y transformación de mayúsculas,
/// con vista previa en tiempo real y detección de colisiones antes de aplicar.
public struct BulkRenameModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Environment(\.dismiss) private var dismiss

    @ViewState private var config = BulkRenameConfiguration()
    @ViewState private var isApplying = false
    @ViewState private var exifDateCache: [URL: Date] = [:]

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    private var orderedSelectedItems: [FileItem] {
        let selectedSet = viewModel.selectedItemIDs
        return viewModel.displayedItems.filter { selectedSet.contains($0.id) }
    }

    private var existingSiblingNames: Set<String> {
        Set(viewModel.allItems.map(\.name))
    }

    private var previewResult: (previews: [BulkRenamePreviewItem], regexError: String?) {
        BulkRenameService.generatePreview(
            for: orderedSelectedItems,
            configuration: config,
            existingSiblingNames: existingSiblingNames,
            exifDateCache: exifDateCache,
            using: loc
        )
    }

    public var body: some View {
        let result = previewResult
        let validChangesCount = result.previews.filter(\.isValidToApply).count
        let conflictsCount = result.previews.filter { $0.conflictMessage != nil }.count

        VStack(spacing: 0) {
            // Cabecera
            HStack(spacing: 10) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(es: "Renombrado masivo", en: "Bulk Rename"))
                        .font(.system(size: 15, weight: .semibold))

                    Text(loc.text(
                        es: "\(orderedSelectedItems.count) elementos seleccionados",
                        en: "\(orderedSelectedItems.count) items selected"
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $config.mode) {
                    ForEach(BulkRenameMode.allCases) { mode in
                        Label(mode.localizedTitle(using: loc), systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            // Controles según el modo seleccionado
            VStack(alignment: .leading, spacing: 10) {
                modeControlsView(regexError: result.regexError)

                HStack(spacing: 16) {
                    if config.mode != .caseTransform {
                        HStack(spacing: 6) {
                            Text(loc.text(es: "Mayúsculas:", en: "Case:"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $config.caseOption) {
                                ForEach(BulkRenameCaseOption.allCases) { option in
                                    Text(option.localizedTitle(using: loc)).tag(option)
                                }
                            }
                            .frame(width: 145)
                        }
                    }

                    Toggle(
                        loc.text(es: "Aplicar también a la extensión", en: "Apply to extension too"),
                        isOn: $config.applyToExtension
                    )
                    .font(.system(size: 12))

                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.02))

            Divider()

            // Vista previa en tiempo real
            VStack(spacing: 0) {
                HStack {
                    Text(loc.text(es: "Nombre actual", en: "Original Name"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)

                    Text(loc.text(es: "Nuevo nombre (vista previa en tiempo real)", en: "New Name (live preview)"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04))

                Divider()

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(result.previews) { item in
                            HStack(spacing: 8) {
                                Text(item.originalName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(item.hasChange ? Color.accentColor : Color.secondary.opacity(0.4))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.proposedName)
                                        .font(.system(size: 12, weight: item.hasChange ? .semibold : .regular))
                                        .foregroundStyle(
                                            item.conflictMessage != nil
                                                ? Color.red
                                                : (item.hasChange ? Color.green : Color.secondary)
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    if let conflict = item.conflictMessage {
                                        Text(conflict)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.red)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)

                            Divider()
                                .padding(.leading, 18)
                        }
                    }
                }
                .frame(minHeight: 240, maxHeight: 340)
            }

            Divider()

            // Pie de diálogo con resumen y acciones
            HStack(spacing: 12) {
                if conflictsCount > 0 {
                    Label(
                        loc.text(
                            es: "\(conflictsCount) conflicto(s) detectado(s)",
                            en: "\(conflictsCount) conflict(s) detected"
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                } else {
                    Text(loc.text(
                        es: "\(validChangesCount) de \(result.previews.count) elementos cambiarán de nombre",
                        en: "\(validChangesCount) of \(result.previews.count) items will be renamed"
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(loc.text(es: "Cancelar", en: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    isApplying = true
                    let previewsToApply = result.previews
                    Task { @MainActor in
                        await viewModel.performBulkRename(previews: previewsToApply)
                        isApplying = false
                        dismiss()
                    }
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(loc.text(
                            es: "Renombrar (\(validChangesCount))",
                            en: "Rename (\(validChangesCount))"
                        ))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || validChangesCount == 0 || result.regexError != nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 740, height: 560)
        .task {
            // Precargar fechas EXIF de los archivos seleccionados en segundo plano si hay muchos
            let urls = orderedSelectedItems.map(\.url)
            var cache: [URL: Date] = [:]
            for url in urls {
                if let d = BulkRenameService.extractDate(for: url, fallbackToFileDate: true) {
                    cache[url] = d
                }
            }
            exifDateCache = cache
        }
    }

    @ViewBuilder
    private func modeControlsView(regexError: String?) -> some View {
        switch config.mode {
        case .regexReplace:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Buscar (patrón o Regex):", en: "Find (pattern or Regex):"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField(
                            loc.text(es: "Ej. ^IMG_(\\d+) o texto", en: "e.g. ^IMG_(\\d+) or text"),
                            text: $config.findPattern
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Reemplazar con:", en: "Replace with:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField(
                            loc.text(es: "Ej. Foto_$1", en: "e.g. Photo_$1"),
                            text: $config.replacePattern
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 16) {
                    Toggle(loc.text(es: "Usar Expresión Regular (Regex)", en: "Use Regular Expression (Regex)"), isOn: $config.useRegex)
                        .font(.system(size: 12))
                    Toggle(loc.text(es: "Distinguir mayúsculas/minúsculas", en: "Case sensitive"), isOn: $config.caseSensitive)
                        .font(.system(size: 12))
                }

                if let regexError {
                    Label(regexError, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                }
            }

        case .sequentialNumbering:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Prefijo:", en: "Prefix:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField(loc.text(es: "Ej. Vacaciones_", en: "e.g. Vacation_"), text: $config.numberingPrefix)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Sufijo:", en: "Suffix:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField(loc.text(es: "Ej. _final", en: "e.g. _final"), text: $config.numberingSuffix)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Inicio:", en: "Start:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField("1", value: $config.startNumber, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 65)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Paso:", en: "Step:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField("1", value: $config.step, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Dígitos:", en: "Digits:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $config.zeroPadding) {
                            Text("1 (1, 2)").tag(1)
                            Text("2 (01, 02)").tag(2)
                            Text("3 (001, 002)").tag(3)
                            Text("4 (0001)").tag(4)
                        }
                        .frame(width: 115)
                    }
                }

                Toggle(
                    loc.text(es: "Conservar el nombre original antes del número", en: "Keep original name before number"),
                    isOn: $config.preserveOriginalNameInNumbering
                )
                .font(.system(size: 12))
            }

        case .exifDate:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Formato de fecha:", en: "Date format:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $config.dateFormat) {
                            Text("2026-11-16_20-10-00 (yyyy-MM-dd_HH-mm-ss)").tag("yyyy-MM-dd_HH-mm-ss")
                            Text("2026-11-16 (yyyy-MM-dd)").tag("yyyy-MM-dd")
                            Text("20261116_201000 (yyyyMMdd_HHmmss)").tag("yyyyMMdd_HHmmss")
                            Text("16-11-2026 (dd-MM-yyyy)").tag("dd-MM-yyyy")
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.text(es: "Ubicación:", en: "Placement:"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $config.datePlacement) {
                            ForEach(BulkRenameDatePlacement.allCases) { placement in
                                Text(placement.localizedTitle(using: loc)).tag(placement)
                            }
                        }
                        .frame(width: 210)
                    }
                }

                Toggle(
                    loc.text(
                        es: "Si no hay metadatos EXIF, usar fecha de creación/modificación del archivo",
                        en: "Fallback to file creation/modification date if no EXIF metadata"
                    ),
                    isOn: $config.fallbackToFileDate
                )
                .font(.system(size: 12))
            }

        case .caseTransform:
            HStack(spacing: 12) {
                Text(loc.text(es: "Convertir nombre a:", en: "Transform name to:"))
                    .font(.system(size: 12.5))
                Picker("", selection: $config.caseOption) {
                    ForEach(BulkRenameCaseOption.allCases) { option in
                        Text(option.localizedTitle(using: loc)).tag(option)
                    }
                }
                .frame(width: 200)
                Spacer()
            }
        }
    }
}
