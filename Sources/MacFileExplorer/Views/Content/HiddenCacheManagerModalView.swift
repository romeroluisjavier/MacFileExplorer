import AppKit
import SwiftUI

/// Modal para inspeccionar cuántos archivos ocultos `.macfileexplorer_*.cache` existen,
/// cuánto espacio ocupan en total y eliminarlos para regenerarlos limpiamente.
public struct HiddenCacheManagerModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Environment(\.dismiss) private var dismiss

    @ViewState private var scope: HiddenCacheScanScope = .homeAndCurrentFolder
    @ViewState private var report: HiddenCacheScanReport?
    @ViewState private var isScanning: Bool = true
    @ViewState private var isDeleting: Bool = false
    @ViewState private var clearSummaryMessage: String?

    private var loc: LocalizationManager { LocalizationManager.shared }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            Divider()

            summaryCardsSection
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.025))

            Divider()

            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerSection
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .frame(width: 660, height: 500)
        .task {
            await runScan()
        }
    }

    // MARK: - Secciones

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(loc.text(
                    es: "Caché oculta de MacFileExplorer (.macfileexplorer)",
                    en: "MacFileExplorer Hidden Cache (.macfileexplorer)"
                ))
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)

                Text(loc.text(
                    es: "Índices de carpetas, miniaturas e índices OCR regenerables",
                    en: "Regenerable folder indexes, thumbnails, and OCR caches"
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $scope) {
                ForEach(HiddenCacheScanScope.allCases) { item in
                    Text(item.localizedTitle(using: loc)).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 215)
            .onChange(of: scope) { _, _ in
                clearSummaryMessage = nil
                Task { await runScan() }
            }
        }
    }

    private var summaryCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                summaryMetricCard(
                    icon: "doc.on.doc.fill",
                    tint: .accentColor,
                    title: loc.text(es: "Archivos ocultos", en: "Hidden Files"),
                    value: isScanning && report == nil
                        ? "—"
                        : "\(report?.totalCount ?? 0)"
                )

                summaryMetricCard(
                    icon: "externaldrive.fill",
                    tint: .orange,
                    title: loc.text(es: "Espacio total ocupado", en: "Total Space Used"),
                    value: isScanning && report == nil
                        ? "—"
                        : Self.byteFormatter.string(fromByteCount: report?.totalSizeBytes ?? 0)
                )
            }

            if let report, !report.entries.isEmpty {
                HStack(spacing: 8) {
                    ForEach(HiddenCacheKind.allCases) { kind in
                        let count = report.countsByKind[kind] ?? 0
                        if count > 0 {
                            let sizeStr = Self.byteFormatter.string(fromByteCount: report.sizesByKind[kind] ?? 0)
                            HStack(spacing: 5) {
                                Image(systemName: kind.systemImage)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.accentColor)
                                Text("\(kind.localizedTitle(using: loc)): \(count) (\(sizeStr))")
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                    }
                    Spacer()
                }
            }

            if let clearSummaryMessage {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(clearSummaryMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.green.opacity(0.11))
                )
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if isScanning && report == nil {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(loc.text(
                    es: "Buscando archivos ocultos .macfileexplorer…",
                    en: "Scanning for hidden .macfileexplorer files…"
                ))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let report, report.entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                Text(loc.text(
                    es: "No hay archivos ocultos de caché .macfileexplorer en este alcance.",
                    en: "No hidden .macfileexplorer cache files found in this scope."
                ))
                .font(.system(size: 13.5, weight: .medium))
                Text(loc.text(
                    es: "Se irán creando automáticamente conforme explores carpetas, veas miniaturas o indexes imágenes.",
                    en: "They will be generated automatically as you browse folders, view thumbnails, or index images."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if let report {
            List {
                ForEach(report.entries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.kind.systemImage)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.fileName)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)

                                Text("· \(entry.kind.localizedTitle(using: loc))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Text(displayFolderPath(entry.folderURL))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Text(Self.byteFormatter.string(fromByteCount: entry.sizeBytes))
                            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)

                        Button {
                            viewModel.navigate(to: entry.folderURL, recordHistory: true)
                            dismiss()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(loc.text(es: "Abrir esta carpeta", en: "Open this folder"))
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
        }
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            Button {
                clearSummaryMessage = nil
                Task { await runScan() }
            } label: {
                Label(loc.text(es: "Actualizar", en: "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(isScanning || isDeleting)

            Spacer()

            Button(loc.text(es: "Cerrar", en: "Close")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            let totalCount = report?.totalCount ?? 0
            Button(role: .destructive) {
                Task { await deleteAllAndRegenerate() }
            } label: {
                HStack(spacing: 5) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text(loc.text(
                        es: "Borrar todos (\(totalCount)) y regenerar",
                        en: "Delete All (\(totalCount)) & Regenerate"
                    ))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isScanning || isDeleting || totalCount == 0)
        }
    }

    private func summaryMetricCard(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
        )
    }

    private func displayFolderPath(_ folderURL: URL) -> String {
        let full = folderURL.standardizedFileURL.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path(percentEncoded: false)
        if full == home { return "~" }
        if full.hasPrefix(home + "/") {
            return "~\(String(full.dropFirst(home.count)))"
        }
        return full
    }

    // MARK: - Acciones

    private func runScan() async {
        isScanning = true
        let result = await HiddenCacheManagerService.scanHiddenCaches(
            scope: scope,
            currentDirectoryURL: viewModel.currentDirectoryURL
        )
        self.report = result
        self.isScanning = false
    }

    private func deleteAllAndRegenerate() async {
        guard let entries = report?.entries, !entries.isEmpty else { return }
        isDeleting = true
        let clearResult = await HiddenCacheManagerService.deleteAllCaches(entries)
        await runScan()
        isDeleting = false

        let freedText = Self.byteFormatter.string(fromByteCount: clearResult.freedBytes)
        if clearResult.failedCount > 0 {
            clearSummaryMessage = loc.text(
                es: "Se eliminaron \(clearResult.deletedCount) archivos (\(freedText) liberados). No se pudieron eliminar \(clearResult.failedCount). Se regenerarán al navegar.",
                en: "Deleted \(clearResult.deletedCount) files (\(freedText) freed). Could not delete \(clearResult.failedCount). Caches will regenerate as you browse."
            )
        } else {
            clearSummaryMessage = loc.text(
                es: "Se eliminaron \(clearResult.deletedCount) archivos ocultos (\(freedText) liberados). Las cachés se regenerarán limpias automáticamente.",
                en: "Deleted \(clearResult.deletedCount) hidden files (\(freedText) freed). Caches will regenerate cleanly as you browse."
            )
        }

        // Regenerar de inmediato los índices limpios de la carpeta actualmente abierta
        viewModel.refresh(preservingSelection: true)
    }
}
