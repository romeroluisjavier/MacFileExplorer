import AppKit
import SwiftUI
import WebKit

// MARK: - Visor / Editor Interactivo de CSV y TSV

public struct CSVSpreadsheetPreviewView: View {
    public let fileURL: URL

    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var officePrefs = OfficePreferences.shared
    @ViewState private var table = SpreadsheetTableData(rows: [[""]])
    @ViewState private var delimiterOption: CSVDelimiterOption = .auto
    @ViewState private var activeDelimiter: Character = ","
    @ViewState private var encodingName: String = "UTF-8"
    @ViewState private var firstRowIsHeader: Bool = true
    @ViewState private var isLoading: Bool = true
    @ViewState private var loadError: String? = nil
    @ViewState private var hasUnsavedChanges: Bool = false
    @ViewState private var statusToast: String? = nil
    @ViewState private var wasTruncated: Bool = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        _firstRowIsHeader = ViewState(initialValue: OfficePreferences.shared.csvFirstRowIsHeaderByDefault)
    }

    private var detectedDelimiterLabel: String {
        switch activeDelimiter {
        case ",": return ","
        case ";": return ";"
        case "\t": return "Tab"
        case "|": return "|"
        default: return String(activeDelimiter)
        }
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if wasTruncated {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                            Text(loc.text(
                                es: "Archivo muy grande (> 12 MB): se cargaron los primeros 12 MB para vista rápida instantánea. Usá «Guardar copia…» para exportar.",
                                en: "Large file (> 12 MB): loaded the first 12 MB for instant preview. Use \"Save Copy…\" to export."
                            ))
                            .font(.system(size: 11))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.12))
                    }

                    SpreadsheetEditorView(
                        table: $table,
                        isCSVMode: true,
                        isEditingEnabled: officePrefs.isOfficeEditingEnabled,
                        showFormattingControls: false,
                        firstRowIsHeader: $firstRowIsHeader,
                        csvDelimiterOption: $delimiterOption,
                        detectedDelimiterLabel: detectedDelimiterLabel,
                        encodingLabel: encodingName,
                        hasUnsavedChanges: hasUnsavedChanges,
                        statusToast: statusToast,
                        onMarkDirty: { hasUnsavedChanges = true },
                        onReloadCSVDelimiter: { newOpt in
                            Task { await loadCSV(delimiter: newOpt) }
                        },
                        onSave: { saveCSV(to: fileURL) },
                        onSaveCopy: { saveCSVCopy() }
                    )
                }
            }
        }
        .task(id: fileURL) {
            await loadCSV(delimiter: .auto)
        }
    }

    private func loadCSV(delimiter: CSVDelimiterOption) async {
        isLoading = true
        loadError = nil
        let targetURL = fileURL
        let result = await Task.detached(priority: .userInitiated) {
            Result { try CSVDocumentEngine.load(from: targetURL, forcedDelimiter: delimiter) }
        }.value

        switch result {
        case .success(let doc):
            table = doc.table
            activeDelimiter = doc.detectedDelimiter
            encodingName = doc.encodingName
            wasTruncated = doc.wasTruncated
            hasUnsavedChanges = false
        case .failure(let err):
            loadError = err.localizedDescription
        }
        isLoading = false
    }

    private func saveCSV(to url: URL) {
        if wasTruncated && url == fileURL {
            saveCSVCopy()
            return
        }
        do {
            let delimiterToWrite = delimiterOption.character ?? activeDelimiter
            try CSVDocumentEngine.save(rows: table.rows, delimiter: delimiterToWrite, to: url)
            if url == fileURL {
                hasUnsavedChanges = false
            }
            showToast(loc.text(es: "Guardado correctamente", en: "Saved successfully"))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func saveCSVCopy() {
        guard let dest = OfficeSavePanelHelper.chooseCopyDestination(
            originalURL: fileURL,
            preferredExtension: fileURL.pathExtension.isEmpty ? "csv" : fileURL.pathExtension,
            title: loc.text(es: "Guardar copia de CSV", en: "Save CSV Copy")
        ) else { return }
        saveCSV(to: dest)
    }

    private func showToast(_ message: String) {
        statusToast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            if statusToast == message { statusToast = nil }
        }
    }
}

// MARK: - Visor / Editor Multi-Hoja de Microsoft Excel (.xlsx / .xls)

public struct OfficeExcelPreviewView: View {
    public let fileURL: URL

    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var officePrefs = OfficePreferences.shared
    @ViewState private var workbook: XLSXWorkbookModel? = nil
    @ViewState private var originalPreviewSource: ExcelOriginalPreviewSource? = nil
    @ViewState private var activeSheetIndex: Int = 0
    @ViewState private var showOriginalQuickLook: Bool = true
    @ViewState private var firstRowIsHeader: Bool = false
    @ViewState private var isLoading: Bool = true
    @ViewState private var loadError: String? = nil
    @ViewState private var hasUnsavedChanges: Bool = false
    @ViewState private var statusToast: String? = nil

    public init(fileURL: URL) {
        self.fileURL = fileURL
        _showOriginalQuickLook = ViewState(initialValue: OfficePreferences.shared.shouldOpenInOriginalView)
    }

    private var isXLSFile: Bool {
        fileURL.pathExtension.lowercased() == "xls"
    }

    private var isLegacyReadOnlyFormat: Bool {
        !OfficePreviewSupport.editableExcelExtensions.contains(fileURL.pathExtension.lowercased())
    }

    public var body: some View {
        VStack(spacing: 0) {
            modeHeaderBar
            Divider()

            if isLegacyReadOnlyFormat || !officePrefs.isOfficeEditingEnabled || showOriginalQuickLook {
                if isLegacyReadOnlyFormat {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                        Text(loc.text(
                            es: "Formato (.\(fileURL.pathExtension.lowercased())) en solo lectura. Usá «Enviar a Drive» arriba para editarlo al instante en Google Sheets.",
                            en: "Format (.\(fileURL.pathExtension.lowercased())) shown read-only. Click \"Send to Drive\" above to edit it live in Google Sheets."
                        ))
                        .font(.system(size: 11.5))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.08))
                }
                originalExcelPreviewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Button(loc.text(es: "Ver con Vista original (Quick Look)", en: "View Original Layout (Quick Look)")) {
                        showOriginalQuickLook = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let wb = workbook, !wb.sheets.isEmpty {
                let safeIdx = min(max(0, activeSheetIndex), wb.sheets.count - 1)
                let sheetBinding = Binding<SpreadsheetTableData>(
                    get: { workbook?.sheets[safeIdx].table ?? SpreadsheetTableData() },
                    set: { newVal in
                        workbook?.sheets[safeIdx].table = newVal
                        workbook?.sheets[safeIdx].isModified = true
                    }
                )

                SpreadsheetEditorView(
                    table: sheetBinding,
                    isCSVMode: false,
                    showFormattingControls: true,
                    firstRowIsHeader: $firstRowIsHeader,
                    hasUnsavedChanges: hasUnsavedChanges,
                    statusToast: statusToast,
                    onMarkDirty: {
                        hasUnsavedChanges = true
                        workbook?.sheets[safeIdx].isModified = true
                    },
                    onSave: { saveWorkbook(to: fileURL) },
                    onSaveCopy: { saveWorkbookCopy() },
                    onExportCSV: { exportCurrentSheetToCSV(safeIdx) }
                )

                Divider()
                sheetTabsBar(workbook: wb, activeIndex: safeIdx)
            }
        }
        .task(id: fileURL) {
            await loadOriginalPreviewAndWorkbook()
        }
    }

    @ViewBuilder
    private var originalExcelPreviewContent: some View {
        switch originalPreviewSource {
        case .htmlDocument(let html):
            LocalHTMLSpreadsheetPreviewRepresentable(html: html)
                .id(fileURL)
        case .nativeQuickLook(let qlURL):
            NativeQLPreviewRepresentable(fileURL: qlURL)
                .id(qlURL)
        case nil:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var modeHeaderBar: some View {
        HStack(spacing: 10) {
            Label(
                isXLSFile
                    ? loc.text(es: "Microsoft Excel 97–2003 (.xls) · Editor rápido", en: "Microsoft Excel 97–2003 (.xls) · Quick Editor")
                    : loc.text(es: "Microsoft Excel · Editor rápido", en: "Microsoft Excel · Quick Editor"),
                systemImage: OfficeDocumentKind.excel.symbolName
            )
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(OfficeDocumentKind.excel.accentColor)

            if hasUnsavedChanges {
                Text(loc.text(es: "Sin guardar", en: "Unsaved"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }

            Spacer()

            if isXLSFile && workbook != nil {
                Button {
                    saveAsModernXLSXCopy()
                } label: {
                    HStack(spacing: 5) {
                        FloppyDiskCopyIconView(size: PreviewToolbarMetrics.iconSize)
                        Text(loc.text(es: "Guardar como .xlsx…", en: "Save as .xlsx…"))
                            .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                }
                .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
                .help(loc.text(
                    es: "Convertir y guardar una copia en formato moderno de Excel (.xlsx)",
                    en: "Convert and save a copy in modern Excel format (.xlsx)"
                ))
            }

            if !isLegacyReadOnlyFormat && officePrefs.isOfficeEditingEnabled {
                Picker("", selection: $showOriginalQuickLook) {
                    Text(loc.text(es: "Vista original", en: "Original View")).tag(true)
                    Text(loc.text(es: "Editor", en: "Editor")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            } else if !isLegacyReadOnlyFormat {
                Text(loc.text(es: "Solo lectura", en: "Read-Only"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035))
    }

    private func sheetTabsBar(workbook: XLSXWorkbookModel, activeIndex: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(workbook.sheets.enumerated()), id: \.element.id) { idx, sheet in
                    let isSelected = (idx == activeIndex)
                    Button {
                        activeSheetIndex = idx
                    } label: {
                        HStack(spacing: 4) {
                            Text(sheet.name)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            if sheet.isModified {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? OfficeDocumentKind.excel.accentColor.opacity(0.16) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isSelected ? OfficeDocumentKind.excel.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
    }

    private func loadOriginalPreviewAndWorkbook() async {
        isLoading = true
        loadError = nil
        originalPreviewSource = nil
        let targetURL = fileURL
        let useXLSEngine = isXLSFile
        let skipEditableLoad = isLegacyReadOnlyFormat

        // 1. Resolver inmediatamente el origen de Vista Original (Quick Look nativo vs HTML local fiel)
        let resolvedOriginal = await Task.detached(priority: .userInitiated) {
            XLSDocumentEngine.resolveOriginalPreviewSource(for: targetURL)
        }.value
        originalPreviewSource = resolvedOriginal

        if skipEditableLoad {
            isLoading = false
            return
        }

        // 2. Precargar el libro editable en segundo plano para cambiar a "Editor" al instante
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                if useXLSEngine {
                    return try XLSDocumentEngine.load(from: targetURL)
                }
                do {
                    return try XLSXDocumentEngine.load(from: targetURL)
                } catch {
                    // Fallback por si un archivo con extensión .xlsx contiene en realidad HTML o BIFF
                    return try XLSDocumentEngine.load(from: targetURL)
                }
            }
        }.value

        switch result {
        case .success(let wb):
            workbook = wb
            activeSheetIndex = 0
            hasUnsavedChanges = false
        case .failure(let err):
            loadError = err.localizedDescription
        }
        isLoading = false
    }

    private func saveWorkbook(to destinationURL: URL) {
        guard var wb = workbook else { return }
        do {
            let destExt = destinationURL.pathExtension.lowercased()
            if destExt == "xls" {
                try XLSDocumentEngine.save(workbook: wb, to: destinationURL)
            } else if isXLSFile {
                try XLSXDocumentEngine.createNew(workbook: wb, to: destinationURL)
            } else {
                try XLSXDocumentEngine.save(workbook: wb, to: destinationURL)
            }
            if destinationURL == fileURL {
                for i in wb.sheets.indices { wb.sheets[i].isModified = false }
                workbook = wb
                hasUnsavedChanges = false
            }
            showToast(loc.text(es: "Libro Excel guardado", en: "Excel workbook saved"))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func saveWorkbookCopy() {
        let primaryExt = isXLSFile ? "xls" : "xlsx"
        let extraExts = isXLSFile ? ["xlsx"] : ["xls"]
        guard let dest = OfficeSavePanelHelper.chooseCopyDestination(
            originalURL: fileURL,
            preferredExtension: primaryExt,
            additionalExtensions: extraExts,
            title: isXLSFile
                ? loc.text(es: "Guardar copia de Excel (.xls / .xlsx)", en: "Save Excel Copy (.xls / .xlsx)")
                : loc.text(es: "Guardar copia de Excel (.xlsx)", en: "Save Excel Copy (.xlsx)")
        ) else { return }
        saveWorkbook(to: dest)
    }

    private func saveAsModernXLSXCopy() {
        guard let dest = OfficeSavePanelHelper.chooseCopyDestination(
            originalURL: fileURL.deletingPathExtension().appendingPathExtension("xlsx"),
            preferredExtension: "xlsx",
            title: loc.text(es: "Convertir y guardar como Excel moderno (.xlsx)", en: "Convert & Save as Modern Excel (.xlsx)")
        ) else { return }
        saveWorkbook(to: dest)
    }

    private func exportCurrentSheetToCSV(_ sheetIdx: Int) {
        guard let wb = workbook, sheetIdx < wb.sheets.count else { return }
        let sheet = wb.sheets[sheetIdx]
        guard let dest = OfficeSavePanelHelper.chooseCopyDestination(
            originalURL: fileURL.deletingPathExtension().appendingPathExtension("csv"),
            preferredExtension: "csv",
            title: loc.text(es: "Exportar hoja «\(sheet.name)» a CSV", en: "Export sheet \"\(sheet.name)\" to CSV")
        ) else { return }
        do {
            try CSVDocumentEngine.save(rows: sheet.table.rows, delimiter: ",", to: dest)
            showToast(loc.text(es: "Hoja exportada a CSV", en: "Sheet exported to CSV"))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func showToast(_ message: String) {
        statusToast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            if statusToast == message { statusToast = nil }
        }
    }
}

// MARK: - Visor HTML Local Sin Conexión para `.xls`/`.xlsx` en formato HTML o XML SpreadsheetML

private struct LocalHTMLSpreadsheetPreviewRepresentable: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 880, height: 560), configuration: config)
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != html {
            context.coordinator.lastLoadedHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String = ""

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // Permitir únicamente carga inicial del HTML local en memoria (sin salidas a red)
            if navigationAction.navigationType == .other,
               navigationAction.request.url?.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }
    }
}
