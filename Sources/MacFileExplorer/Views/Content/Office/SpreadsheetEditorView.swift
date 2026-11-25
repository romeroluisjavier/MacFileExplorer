import AppKit
import SwiftUI

/// Grilla interactiva y barra estilo LibreOffice Calc compartida por los editores de `.csv`/`.tsv` y `.xlsx`.
public struct SpreadsheetEditorView: View {
    @Binding public var table: SpreadsheetTableData
    public let isCSVMode: Bool
    public let isEditingEnabled: Bool
    public let showFormattingControls: Bool
    @Binding public var firstRowIsHeader: Bool
    @Binding public var csvDelimiterOption: CSVDelimiterOption
    public let detectedDelimiterLabel: String?
    public let encodingLabel: String?
    public let hasUnsavedChanges: Bool
    public let statusToast: String?
    public let onMarkDirty: () -> Void
    public let onReloadCSVDelimiter: ((CSVDelimiterOption) -> Void)?
    public let onSave: () -> Void
    public let onSaveCopy: () -> Void
    public let onExportCSV: (() -> Void)?

    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var selectedCell: SpreadsheetCellCoord? = SpreadsheetCellCoord(row: 0, col: 0)
    @ViewState private var selectionAnchor: SpreadsheetCellCoord? = SpreadsheetCellCoord(row: 0, col: 0)
    @ViewState private var selectedRange: Set<SpreadsheetCellCoord> = [SpreadsheetCellCoord(row: 0, col: 0)]
    @ViewState private var selectedDisplayRect: SpreadsheetDisplayRect? = nil
    @ViewState private var searchQuery: String = ""
    @ViewState private var sortColumn: Int? = nil
    @ViewState private var sortDirection: SpreadsheetSortDirection = .ascending
    @ViewState private var wrapText: Bool = false
    @ViewState private var columnWidths: [Int: CGFloat] = [:]

    // Cachés de alto rendimiento y versiones O(1) para evitar re-evaluar miles de filas por clic o tecla
    @ViewState private var cachedVisibleRowIndices: [Int] = []
    @ViewState private var cachedSelectionStats: SpreadsheetSelectionStats = .empty
    @ViewState private var dataVersion: UInt64 = 0
    @ViewState private var selectionVersion: UInt64 = 0
    @ViewState private var columnWidthVersion: UInt64 = 0
    @ViewState private var searchDebounceTask: Task<Void, Never>? = nil

    @ViewState private var undoStack: [SpreadsheetTableData] = []
    @ViewState private var redoStack: [SpreadsheetTableData] = []

    @FocusState private var isSearchFieldFocused: Bool

    private static let statNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    public init(
        table: Binding<SpreadsheetTableData>,
        isCSVMode: Bool,
        isEditingEnabled: Bool = true,
        showFormattingControls: Bool,
        firstRowIsHeader: Binding<Bool>,
        csvDelimiterOption: Binding<CSVDelimiterOption> = .constant(.auto),
        detectedDelimiterLabel: String? = nil,
        encodingLabel: String? = nil,
        hasUnsavedChanges: Bool,
        statusToast: String?,
        onMarkDirty: @escaping () -> Void,
        onReloadCSVDelimiter: ((CSVDelimiterOption) -> Void)? = nil,
        onSave: @escaping () -> Void,
        onSaveCopy: @escaping () -> Void,
        onExportCSV: (() -> Void)? = nil
    ) {
        self._table = table
        self.isCSVMode = isCSVMode
        self.isEditingEnabled = isEditingEnabled
        self.showFormattingControls = showFormattingControls
        self._firstRowIsHeader = firstRowIsHeader
        self._csvDelimiterOption = csvDelimiterOption
        self.detectedDelimiterLabel = detectedDelimiterLabel
        self.encodingLabel = encodingLabel
        self.hasUnsavedChanges = hasUnsavedChanges
        self.statusToast = statusToast
        self.onMarkDirty = onMarkDirty
        self.onReloadCSVDelimiter = onReloadCSVDelimiter
        self.onSave = onSave
        self.onSaveCopy = onSaveCopy
        self.onExportCSV = onExportCSV
        _wrapText = ViewState(initialValue: OfficePreferences.shared.spreadsheetWrapTextByDefault)
    }

    private var dataStartRowIndex: Int {
        (firstRowIsHeader && table.rows.count > 1) ? 1 : 0
    }

    private var activeCellLabel: String {
        if let rect = selectedDisplayRect, !cachedVisibleRowIndices.isEmpty {
            return rect.referenceLabel(visibleRowIndices: cachedVisibleRowIndices)
        }
        guard let c = selectedCell else { return "A1" }
        return "\(SpreadsheetTableData.excelColumnName(for: c.col))\(c.row + 1)"
    }

    private var activeCellEditableText: String {
        guard let c = selectedCell else { return "" }
        return table.formulas[c] ?? table.value(at: c.row, col: c.col)
    }

    private var activeCellStyle: SpreadsheetCellStyle {
        guard let c = selectedCell else { return SpreadsheetCellStyle() }
        return table.styles[c] ?? SpreadsheetCellStyle()
    }

    public var body: some View {
        VStack(spacing: 0) {
            primaryToolbar
            Divider()
            if isEditingEnabled {
                secondaryFormatAndFormulaBar
                Divider()
            }
            spreadsheetGrid
            Divider()
            bottomStatusBar
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            initializeGridState()
        }
        .onChange(of: table.sheetName) { _, _ in
            initializeGridState()
        }
        .onChange(of: detectedDelimiterLabel) { _, _ in
            initializeGridState()
        }
        .onChange(of: firstRowIsHeader) { _, _ in
            rebuildFilteredRows(immediate: true)
            dataVersion &+= 1
        }
        .onChange(of: searchQuery) { _, _ in
            rebuildFilteredRows(immediate: table.rows.count <= 1_500)
        }
        .background {
            hiddenEditorShortcuts
        }
    }

    // MARK: - Atajos de Teclado Nativos (⌘S, ⇧⌘S, ⌘C, ⌘X, ⌘V, ⌘Z, ⇧⌘Z, ⌘F, ⌘B, ⌘I)

    private var hiddenEditorShortcuts: some View {
        Group {
            if isEditingEnabled {
                Button("") {
                    commitPendingEdits()
                    onSave()
                }.keyboardShortcut("s", modifiers: [.command])
                Button("") {
                    commitPendingEdits()
                    onSaveCopy()
                }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("") { performUndo() }.keyboardShortcut("z", modifiers: [.command])
                Button("") { performRedo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                Button("") { cutSelectedCellsToClipboard() }.keyboardShortcut("x", modifiers: [.command])
                Button("") { pasteClipboardIntoSelection() }.keyboardShortcut("v", modifiers: [.command])
            }
            Button("") { copySelectedCellsToClipboard() }.keyboardShortcut("c", modifiers: [.command])
            Button("") {
                isSearchFieldFocused = true
            }.keyboardShortcut("f", modifiers: [.command])
            if isEditingEnabled && showFormattingControls {
                Button("") { toggleBoldOnSelection() }.keyboardShortcut("b", modifiers: [.command])
                Button("") { toggleItalicOnSelection() }.keyboardShortcut("i", modifiers: [.command])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    // MARK: - Barra 1: Archivo, Portapapeles, Filas/Columnas, Orden, Delimitador y Búsqueda

    private var primaryToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if isEditingEnabled {
                    // Guardar / Guardar copia (icono clásico de diskette y altura unificada 26 pt)
                    Button {
                        commitPendingEdits()
                        onSave()
                    } label: {
                        HStack(spacing: 6) {
                            FloppyDiskIconView(size: PreviewToolbarMetrics.iconSize)
                            Text(loc.text(es: "Guardar", en: "Save"))
                                .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .semibold))
                            if hasUnsavedChanges {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(PreviewToolbarButtonStyle(variant: .prominent))
                    .help(loc.text(es: "Guardar cambios en este archivo (⌘S)", en: "Save changes to this file (⌘S)"))

                    Button {
                        commitPendingEdits()
                        onSaveCopy()
                    } label: {
                        HStack(spacing: 6) {
                            FloppyDiskCopyIconView(size: PreviewToolbarMetrics.iconSize)
                            Text(loc.text(es: "Guardar copia…", en: "Save Copy…"))
                                .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                    }
                    .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
                    .help(loc.text(es: "Guardar una copia nueva sin sobreescribir el original (⇧⌘S)", en: "Save a new copy without overwriting the original (⇧⌘S)"))

                    if let onExportCSV {
                        Button {
                            commitPendingEdits()
                            onExportCSV()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "tablecells.badge.ellipsis")
                                    .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                                Text("CSV")
                                    .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                            }
                            .padding(.horizontal, 9)
                        }
                        .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
                        .help(loc.text(es: "Exportar esta hoja a archivo .csv", en: "Export this sheet to a .csv file"))
                    }

                    Divider().frame(height: 16)

                    // Deshacer / Rehacer
                    toolbarIconButton("arrow.uturn.backward", help: loc.text(es: "Deshacer (⌘Z)", en: "Undo (⌘Z)"), disabled: undoStack.isEmpty) {
                        performUndo()
                    }
                    toolbarIconButton("arrow.uturn.forward", help: loc.text(es: "Rehacer (⇧⌘Z)", en: "Redo (⇧⌘Z)"), disabled: redoStack.isEmpty) {
                        performRedo()
                    }

                    Divider().frame(height: 16)

                    // Cortar / Copiar / Pegar
                    toolbarIconButton("scissors", help: loc.text(es: "Cortar celdas seleccionadas (⌘X)", en: "Cut selected cells (⌘X)")) {
                        cutSelectedCellsToClipboard()
                    }
                    toolbarIconButton("doc.on.doc", help: loc.text(es: "Copiar celdas (⌘C · compatible con Excel/Sheets)", en: "Copy cells (⌘C · Excel/Sheets compatible)")) {
                        copySelectedCellsToClipboard()
                    }
                    toolbarIconButton("doc.on.clipboard", help: loc.text(es: "Pegar desde portapapeles (⌘V)", en: "Paste from clipboard (⌘V)")) {
                        pasteClipboardIntoSelection()
                    }

                    Divider().frame(height: 16)

                    // Insertar / Eliminar Filas y Columnas
                    toolbarIconButton("plus.rectangle.on.rectangle", help: loc.text(es: "Insertar fila debajo", en: "Insert row below")) {
                        insertRowAfterSelection()
                    }
                    toolbarIconButton("minus.rectangle", help: loc.text(es: "Eliminar fila seleccionada", en: "Delete selected row"), disabled: table.rows.count <= 1) {
                        deleteSelectedRow()
                    }
                    toolbarIconButton("rectangle.split.2x1", help: loc.text(es: "Agregar columna", en: "Add column")) {
                        addColumn()
                    }

                    Divider().frame(height: 16)
                } else {
                    Text(loc.text(es: "Solo lectura", en: "Read-Only"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())

                    toolbarIconButton("doc.on.doc", help: loc.text(es: "Copiar celdas seleccionadas (⌘C)", en: "Copy selected cells (⌘C)")) {
                        copySelectedCellsToClipboard()
                    }

                    Divider().frame(height: 16)
                }

                // Ordenar A-Z / Z-A por columna activa
                toolbarIconButton("arrow.up.arrow.down", help: loc.text(es: "Ordenar columna seleccionada A → Z", en: "Sort selected column A → Z")) {
                    sortByColumn(selectedCell?.col ?? 0, direction: .ascending)
                }
                toolbarIconButton("arrow.down.to.line", help: loc.text(es: "Ordenar columna seleccionada Z → A", en: "Sort selected column Z → A")) {
                    sortByColumn(selectedCell?.col ?? 0, direction: .descending)
                }
                toolbarIconButton("arrow.left.and.right.text.vertical", help: loc.text(es: "Auto-ajustar ancho de columnas", en: "Auto-fit column widths")) {
                    autoFitColumns(initial: false)
                }

                if isCSVMode {
                    Divider().frame(height: 16)

                    Menu {
                        ForEach(CSVDelimiterOption.allCases) { opt in
                            Button {
                                csvDelimiterOption = opt
                                onReloadCSVDelimiter?(opt)
                            } label: {
                                HStack {
                                    Text(opt.localizedTitle(using: loc))
                                    if csvDelimiterOption == opt {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                            Text("\(loc.text(es: "Sep:", en: "Sep:")) \(csvDelimiterOption == .auto ? (detectedDelimiterLabel ?? "Auto") : csvDelimiterOption.displaySymbol)")
                                .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: PreviewToolbarMetrics.controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.085))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(loc.text(es: "Cambiar delimitador del archivo CSV", en: "Change CSV delimiter"))

                    Toggle(isOn: $firstRowIsHeader) {
                        Text(loc.text(es: "Encabezado fijo", en: "Header Row"))
                            .font(.system(size: PreviewToolbarMetrics.labelFontSize))
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }

                Divider().frame(height: 16)

                // Buscador / Filtro en vivo (altura unificada 26 pt)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: PreviewToolbarMetrics.iconSize - 0.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(loc.text(es: "Filtrar filas (⌘F)…", en: "Filter rows (⌘F)…"), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: PreviewToolbarMetrics.labelFontSize))
                        .frame(width: 145)
                        .focused($isSearchFieldFocused)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: PreviewToolbarMetrics.controlHeight)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Barra 2: Formato Estilo LibreOffice Calc + Barra de Fórmula (fx)

    private var secondaryFormatAndFormulaBar: some View {
        HStack(spacing: 8) {
            if showFormattingControls {
                HStack(spacing: 3) {
                    formatToggleButton(label: "B", bold: true, active: activeCellStyle.isBold, help: loc.text(es: "Negrita (⌘B)", en: "Bold (⌘B)")) {
                        toggleBoldOnSelection()
                    }
                    formatToggleButton(label: "I", italic: true, active: activeCellStyle.isItalic, help: loc.text(es: "Cursiva (⌘I)", en: "Italic (⌘I)")) {
                        toggleItalicOnSelection()
                    }

                    Divider().frame(height: 14).padding(.horizontal, 2)

                    toolbarIconButton("text.alignleft", active: activeCellStyle.alignment == .leading, help: loc.text(es: "Alinear a la izquierda", en: "Align left")) {
                        setAlignmentOnSelection(.leading)
                    }
                    toolbarIconButton("text.aligncenter", active: activeCellStyle.alignment == .center, help: loc.text(es: "Centrar", en: "Align center")) {
                        setAlignmentOnSelection(.center)
                    }
                    toolbarIconButton("text.alignright", active: activeCellStyle.alignment == .trailing, help: loc.text(es: "Alinear a la derecha", en: "Align right")) {
                        setAlignmentOnSelection(.trailing)
                    }

                    Divider().frame(height: 14).padding(.horizontal, 2)

                    // Color de texto de celda
                    Menu {
                        cellColorMenuButtons(isBackground: false)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "textformat")
                                .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 36, height: PreviewToolbarMetrics.controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.085))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(loc.text(es: "Color de texto de celda", en: "Cell text color"))

                    // Color de relleno de celda
                    Menu {
                        cellColorMenuButtons(isBackground: true)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "paintbrush.fill")
                                .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 36, height: PreviewToolbarMetrics.controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.085))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(loc.text(es: "Color de relleno de celda", en: "Cell background color"))

                    toolbarIconButton("text.justify.left", active: wrapText, help: loc.text(es: "Ajustar texto en varias líneas (Wrap)", en: "Wrap text")) {
                        wrapText.toggle()
                    }
                }

                Divider().frame(height: 16)
            }

            // Referencia de celda activa (ej. B4) + Barra fx aislada (0% re-render de la grilla al escribir)
            SpreadsheetFormulaBarField(
                cellLabel: activeCellLabel,
                externalText: activeCellEditableText,
                hasSelection: selectedCell != nil,
                placeholder: loc.text(es: "Valor o fórmula de la celda seleccionada…", en: "Selected cell value or formula…"),
                applyTitle: loc.text(es: "Aplicar", en: "Apply"),
                onCommit: { newValue in
                    applyFormulaBarEdit(newValue)
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder
    private func cellColorMenuButtons(isBackground: Bool) -> some View {
        let palette: [(es: String, en: String, hex: String?)] = [
            ("Sin color (Automático)", "Default (None)", nil),
            ("Azul", "Blue", isBackground ? "DCEBFF" : "1D4ED8"),
            ("Verde", "Green", isBackground ? "DCFCE7" : "15803D"),
            ("Amarillo / Ámbar", "Amber / Yellow", isBackground ? "FEF3C7" : "B45309"),
            ("Rojo / Coral", "Red / Coral", isBackground ? "FEE2E2" : "DC2626"),
            ("Violeta", "Purple", isBackground ? "F3E8FF" : "7E22CE"),
            ("Gris suave", "Soft Gray", isBackground ? "E5E7EB" : "4B5563")
        ]
        ForEach(palette, id: \.en) { item in
            Button(loc.text(es: item.es, en: item.en)) {
                applyColorToSelection(hex: item.hex, isBackground: isBackground)
            }
        }
    }

    // MARK: - Grilla Nativa AppKit (`NSTableView`) de Alto Rendimiento (120 FPS)

    private var spreadsheetGrid: some View {
        ZStack {
            NativeSpreadsheetGridView(
                table: table,
                visibleRowIndices: cachedVisibleRowIndices,
                firstRowIsHeader: firstRowIsHeader,
                isEditingEnabled: isEditingEnabled,
                wrapText: wrapText,
                sortColumn: sortColumn,
                sortDirection: sortDirection,
                selectedCell: selectedCell,
                selectedRange: selectedRange,
                selectedDisplayRect: selectedDisplayRect,
                columnWidths: columnWidths,
                dataVersion: dataVersion,
                selectionVersion: selectionVersion,
                columnWidthVersion: columnWidthVersion,
                onSelectCell: { coord, mods in
                    handleCellClick(coord, modifiers: mods)
                },
                onSelectDisplayRange: { rect, anchor, isFinal in
                    handleDisplayRangeSelection(rect, anchor: anchor, isFinal: isFinal)
                },
                onSelectRow: { rowIdx in
                    selectEntireRow(rowIdx)
                },
                onSelectAll: {
                    selectAllDataCells()
                },
                onCommitCellEdit: { coord, newText in
                    commitCellEdit(at: coord, newValue: newText)
                },
                onClearSelectedCells: {
                    clearSelectedCells()
                },
                onSortColumn: { colIdx in
                    let nextDir: SpreadsheetSortDirection = (sortColumn == colIdx && sortDirection == .ascending) ? .descending : .ascending
                    sortByColumn(colIdx, direction: nextDir)
                },
                onColumnResized: { colIdx, newWidth in
                    columnWidths[colIdx] = newWidth
                }
            )

            if cachedVisibleRowIndices.isEmpty && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(loc.text(es: "No hay filas que coincidan con el filtro.", en: "No rows match the current filter."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Barra de Estado Inferior (Filas × Columnas + Estadísticas Numéricas en Vivo)

    private var bottomStatusBar: some View {
        let stats = cachedSelectionStats
        let visibleCount = cachedVisibleRowIndices.count
        let totalDataRows = max(0, table.rows.count - dataStartRowIndex)

        return HStack(spacing: 12) {
            if !searchQuery.isEmpty {
                Text(loc.text(
                    es: "\(visibleCount) de \(totalDataRows) filas · \(table.columnCount) cols",
                    en: "\(visibleCount) of \(totalDataRows) rows · \(table.columnCount) cols"
                ))
            } else {
                Text(loc.text(
                    es: "\(totalDataRows) filas · \(table.columnCount) columnas",
                    en: "\(totalDataRows) rows · \(table.columnCount) columns"
                ))
            }

            if let encodingLabel {
                Text("· \(encodingLabel)")
                    .foregroundStyle(.tertiary)
            }
            if let detectedDelimiterLabel, isCSVMode {
                Text("· \(loc.text(es: "Delimitador", en: "Delimiter")): \(detectedDelimiterLabel)")
                    .foregroundStyle(.tertiary)
            }

            if let statusToast {
                Text("· \(statusToast)")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.medium)
            }

            Spacer(minLength: 8)

            if stats.totalSelected > 1 || stats.numericCount > 0 {
                HStack(spacing: 10) {
                    if let rect = selectedDisplayRect, rect.cellCount > 1 {
                        Text(loc.text(
                            es: "\(rect.rowCount)F × \(rect.colCount)C",
                            en: "\(rect.rowCount)R × \(rect.colCount)C"
                        ))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                    }
                    Text("\(loc.text(es: "Conteo", en: "Count")): \(stats.nonEmptyCount)")
                    if stats.numericCount > 0 {
                        Text("\(loc.text(es: "Suma", en: "Sum")): \(formatStatNumber(stats.sum))")
                            .fontWeight(.semibold)
                        Text("\(loc.text(es: "Prom", en: "Avg")): \(formatStatNumber(stats.average))")
                        if stats.numericCount > 1 {
                            Text("\(loc.text(es: "Mín", en: "Min")): \(formatStatNumber(stats.min))")
                            Text("\(loc.text(es: "Máx", en: "Max")): \(formatStatNumber(stats.max))")
                        }
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Inicialización, Caché de Filtros y Estadísticas

    private func initializeGridState() {
        let initialCoord = SpreadsheetCellCoord(row: dataStartRowIndex, col: 0)
        selectedCell = initialCoord
        selectionAnchor = initialCoord
        selectedRange = [initialCoord]
        sortColumn = nil
        autoFitColumns(initial: true)
        rebuildFilteredRows(immediate: true)
        selectedDisplayRect = cachedVisibleRowIndices.isEmpty
            ? nil
            : SpreadsheetDisplayRect(anchorRow: 0, anchorCol: 0, endRow: 0, endCol: 0)
        recomputeSelectionStats()
        dataVersion &+= 1
        selectionVersion &+= 1
    }

    private func rebuildFilteredRows(immediate: Bool) {
        searchDebounceTask?.cancel()
        let startRow = dataStartRowIndex
        let totalRows = table.rows.count
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard totalRows > startRow else {
            cachedVisibleRowIndices = []
            selectedDisplayRect = nil
            dataVersion &+= 1
            return
        }

        if query.isEmpty {
            cachedVisibleRowIndices = Array(startRow..<totalRows)
            syncDisplayRectAfterRowChange()
            dataVersion &+= 1
            return
        }

        if immediate {
            cachedVisibleRowIndices = Self.filterRowIndices(rows: table.rows, startRow: startRow, query: query)
            syncDisplayRectAfterRowChange()
            dataVersion &+= 1
            return
        }

        let rowsSnapshot = table.rows
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let matched = await Task.detached(priority: .userInitiated) {
                Self.filterRowIndices(rows: rowsSnapshot, startRow: startRow, query: query)
            }.value
            guard !Task.isCancelled else { return }
            cachedVisibleRowIndices = matched
            syncDisplayRectAfterRowChange()
            dataVersion &+= 1
        }
    }

    private func syncDisplayRectAfterRowChange() {
        guard !cachedVisibleRowIndices.isEmpty else {
            selectedDisplayRect = nil
            return
        }
        if let sel = selectedCell,
           selectedRange.count <= 1,
           let dRow = cachedVisibleRowIndices.firstIndex(of: sel.row) {
            selectedDisplayRect = SpreadsheetDisplayRect(anchorRow: dRow, anchorCol: sel.col, endRow: dRow, endCol: sel.col)
        } else {
            selectedDisplayRect = nil
        }
    }

    private nonisolated static func filterRowIndices(rows: [[String]], startRow: Int, query: String) -> [Int] {
        guard rows.count > startRow else { return [] }
        var matched: [Int] = []
        matched.reserveCapacity(min(rows.count - startRow, 512))
        for rIdx in startRow..<rows.count {
            let row = rows[rIdx]
            var found = false
            for cell in row {
                if cell.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    found = true
                    break
                }
            }
            if found {
                matched.append(rIdx)
            }
        }
        return matched
    }

    private func recomputeSelectionStats() {
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else {
            cachedSelectionStats = .empty
            return
        }
        // Evitar bloquear el hilo principal si el usuario seleccionó > 20,000 celdas
        if coords.count > 20_000 {
            cachedSelectionStats = SpreadsheetSelectionStats(
                totalSelected: coords.count,
                nonEmptyCount: coords.count,
                numericCount: 0,
                sum: 0,
                average: 0,
                min: 0,
                max: 0
            )
            return
        }
        let values = coords.map { table.value(at: $0.row, col: $0.col) }
        cachedSelectionStats = SpreadsheetTableData.computeStats(for: values)
    }

    // MARK: - Acciones de Selección, Edición, Undo/Redo y Portapapeles

    private func handleDisplayRangeSelection(
        _ rect: SpreadsheetDisplayRect,
        anchor: SpreadsheetCellCoord,
        isFinal: Bool
    ) {
        selectedCell = anchor
        selectionAnchor = anchor
        selectedDisplayRect = rect
        selectedRange = rect.materializeCoords(visibleRowIndices: cachedVisibleRowIndices)

        if isFinal || rect.cellCount <= 4_000 {
            recomputeSelectionStats()
        } else {
            cachedSelectionStats = SpreadsheetSelectionStats(
                totalSelected: rect.cellCount,
                nonEmptyCount: rect.cellCount,
                numericCount: 0,
                sum: 0,
                average: 0,
                min: 0,
                max: 0
            )
        }
        selectionVersion &+= 1
    }

    private func handleCellClick(_ coord: SpreadsheetCellCoord, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor = selectionAnchor {
            if let anchorDisplay = cachedVisibleRowIndices.firstIndex(of: anchor.row),
               let targetDisplay = cachedVisibleRowIndices.firstIndex(of: coord.row) {
                let rect = SpreadsheetDisplayRect(
                    anchorRow: anchorDisplay,
                    anchorCol: anchor.col,
                    endRow: targetDisplay,
                    endCol: coord.col
                )
                selectedDisplayRect = rect
                selectedRange = rect.materializeCoords(visibleRowIndices: cachedVisibleRowIndices)
            } else {
                let minR = min(anchor.row, coord.row)
                let maxR = max(anchor.row, coord.row)
                let minC = min(anchor.col, coord.col)
                let maxC = max(anchor.col, coord.col)
                let cellCount = (maxR - minR + 1) * (maxC - minC + 1)
                if cellCount <= 50_000 {
                    var next = Set<SpreadsheetCellCoord>()
                    next.reserveCapacity(cellCount)
                    for r in minR...maxR {
                        for c in minC...maxC {
                            next.insert(SpreadsheetCellCoord(row: r, col: c))
                        }
                    }
                    selectedRange = next
                } else {
                    selectedRange = [coord]
                }
                selectedDisplayRect = nil
            }
            selectedCell = coord
        } else if modifiers.contains(.command) {
            if selectedRange.contains(coord) {
                selectedRange.remove(coord)
            } else {
                selectedRange.insert(coord)
            }
            selectedCell = coord
            selectedDisplayRect = nil
        } else {
            selectedCell = coord
            selectionAnchor = coord
            selectedRange = [coord]
            if let dRow = cachedVisibleRowIndices.firstIndex(of: coord.row) {
                selectedDisplayRect = SpreadsheetDisplayRect(anchorRow: dRow, anchorCol: coord.col, endRow: dRow, endCol: coord.col)
            } else {
                selectedDisplayRect = nil
            }
        }
        recomputeSelectionStats()
        selectionVersion &+= 1
    }

    private func selectEntireRow(_ rowIdx: Int) {
        commitPendingEdits()
        var next = Set<SpreadsheetCellCoord>()
        next.reserveCapacity(table.columnCount)
        for c in 0..<table.columnCount {
            next.insert(SpreadsheetCellCoord(row: rowIdx, col: c))
        }
        selectedCell = SpreadsheetCellCoord(row: rowIdx, col: 0)
        selectionAnchor = selectedCell
        selectedRange = next
        if let dRow = cachedVisibleRowIndices.firstIndex(of: rowIdx), table.columnCount > 0 {
            selectedDisplayRect = SpreadsheetDisplayRect(anchorRow: dRow, anchorCol: 0, endRow: dRow, endCol: table.columnCount - 1)
        } else {
            selectedDisplayRect = nil
        }
        recomputeSelectionStats()
        selectionVersion &+= 1
    }

    private func selectAllDataCells() {
        commitPendingEdits()
        guard !cachedVisibleRowIndices.isEmpty, table.columnCount > 0 else { return }
        let rect = SpreadsheetDisplayRect(
            anchorRow: 0,
            anchorCol: 0,
            endRow: cachedVisibleRowIndices.count - 1,
            endCol: table.columnCount - 1
        )
        selectedCell = SpreadsheetCellCoord(row: cachedVisibleRowIndices[0], col: 0)
        selectionAnchor = selectedCell
        selectedDisplayRect = rect
        selectedRange = rect.materializeCoords(visibleRowIndices: cachedVisibleRowIndices)
        recomputeSelectionStats()
        selectionVersion &+= 1
    }

    private func commitCellEdit(at coord: SpreadsheetCellCoord, newValue: String) {
        let currentRaw = table.formulas[coord] ?? table.value(at: coord.row, col: coord.col)
        guard newValue != currentRaw else { return }
        pushUndoSnapshot()
        table.setValue(newValue, at: coord.row, col: coord.col)
        recomputeSelectionStats()
        dataVersion &+= 1
        onMarkDirty()
    }

    private func clearSelectedCells() {
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else { return }
        pushUndoSnapshot()
        for coord in coords {
            table.setValue("", at: coord.row, col: coord.col)
        }
        recomputeSelectionStats()
        dataVersion &+= 1
        onMarkDirty()
    }

    private func commitPendingEdits() {
        // Si un NSTextField está editando una celda dentro del panel activo, finalizar edición para persistir cambios
        if let win = NSApp.keyWindow, win.firstResponder is NSTextView {
            win.makeFirstResponder(nil)
        }
    }

    private func applyFormulaBarEdit(_ newValue: String) {
        guard let coord = selectedCell else { return }
        commitCellEdit(at: coord, newValue: newValue)
    }

    private func pushUndoSnapshot() {
        undoStack.append(table)
        let maxSnapshots = table.rows.count > 5_000 ? 10 : 35
        if undoStack.count > maxSnapshots {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func performUndo() {
        commitPendingEdits()
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(table)
        table = prev
        rebuildFilteredRows(immediate: true)
        recomputeSelectionStats()
        dataVersion &+= 1
        onMarkDirty()
    }

    private func performRedo() {
        commitPendingEdits()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(table)
        table = next
        rebuildFilteredRows(immediate: true)
        recomputeSelectionStats()
        dataVersion &+= 1
        onMarkDirty()
    }

    private func copySelectedCellsToClipboard() {
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else { return }

        let selectedRowSet = Set(coords.map(\.row))
        // Respetar el orden visible (evitando filas en blanco fantasma cuando hay un filtro activo)
        let orderedRows: [Int] = {
            let visibleSelected = cachedVisibleRowIndices.filter { selectedRowSet.contains($0) }
            return visibleSelected.isEmpty ? selectedRowSet.sorted() : visibleSelected
        }()
        let minC = coords.map(\.col).min() ?? 0
        let maxC = coords.map(\.col).max() ?? minC

        var matrix: [[String]] = []
        matrix.reserveCapacity(orderedRows.count)
        for r in orderedRows {
            var rowSlice: [String] = []
            rowSlice.reserveCapacity(maxC - minC + 1)
            for c in minC...maxC {
                let coord = SpreadsheetCellCoord(row: r, col: c)
                rowSlice.append(selectedRange.isEmpty || selectedRange.contains(coord) ? table.value(at: r, col: c) : "")
            }
            matrix.append(rowSlice)
        }
        let tsv = CSVDocumentEngine.formatForClipboard(matrix: matrix)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tsv, forType: .string)
    }

    private func cutSelectedCellsToClipboard() {
        copySelectedCellsToClipboard()
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else { return }
        pushUndoSnapshot()
        for coord in coords {
            table.setValue("", at: coord.row, col: coord.col)
        }
        recomputeSelectionStats()
        dataVersion &+= 1
        onMarkDirty()
    }

    private func pasteClipboardIntoSelection() {
        guard let raw = NSPasteboard.general.string(forType: .string), !raw.isEmpty else { return }
        let matrix = CSVDocumentEngine.parseClipboardMatrix(raw)
        guard !matrix.isEmpty else { return }

        pushUndoSnapshot()
        // Si se pega un único valor sobre un rango seleccionado con el mouse, rellenar todas las celdas seleccionadas (como Excel)
        if matrix.count == 1, matrix[0].count == 1, selectedRange.count > 1 {
            let fillVal = matrix[0][0]
            for coord in selectedRange {
                table.setValue(fillVal, at: coord.row, col: coord.col)
            }
            recomputeSelectionStats()
            dataVersion &+= 1
            selectionVersion &+= 1
            onMarkDirty()
            return
        }

        let origin: SpreadsheetCellCoord = {
            if !selectedRange.isEmpty,
               let minR = selectedRange.map(\.row).min(),
               let minC = selectedRange.map(\.col).min() {
                return SpreadsheetCellCoord(row: minR, col: minC)
            }
            return selectedCell ?? SpreadsheetCellCoord(row: dataStartRowIndex, col: 0)
        }()

        var pastedCoords = Set<SpreadsheetCellCoord>()
        for (dr, rowVals) in matrix.enumerated() {
            for (dc, val) in rowVals.enumerated() {
                let target = SpreadsheetCellCoord(row: origin.row + dr, col: origin.col + dc)
                table.setValue(val, at: target.row, col: target.col)
                pastedCoords.insert(target)
            }
        }
        selectedCell = origin
        selectionAnchor = origin
        selectedRange = pastedCoords
        rebuildFilteredRows(immediate: true)
        if let startD = cachedVisibleRowIndices.firstIndex(of: origin.row) {
            let maxColDelta = (matrix.map(\.count).max() ?? 1) - 1
            let endRowIdx = origin.row + matrix.count - 1
            let endD = cachedVisibleRowIndices.firstIndex(of: endRowIdx) ?? min(cachedVisibleRowIndices.count - 1, startD + matrix.count - 1)
            selectedDisplayRect = SpreadsheetDisplayRect(
                anchorRow: startD,
                anchorCol: origin.col,
                endRow: endD,
                endCol: origin.col + max(0, maxColDelta)
            )
        }
        recomputeSelectionStats()
        dataVersion &+= 1
        selectionVersion &+= 1
        onMarkDirty()
    }

    private func insertRowAfterSelection() {
        commitPendingEdits()
        pushUndoSnapshot()
        let insertIdx = min(table.rows.count, (selectedCell?.row ?? (table.rows.count - 1)) + 1)
        table.rows.insert(Array(repeating: "", count: max(1, table.columnCount)), at: insertIdx)
        let nextCoord = SpreadsheetCellCoord(row: insertIdx, col: selectedCell?.col ?? 0)
        selectedCell = nextCoord
        selectionAnchor = nextCoord
        selectedRange = [nextCoord]
        rebuildFilteredRows(immediate: true)
        recomputeSelectionStats()
        dataVersion &+= 1
        selectionVersion &+= 1
        onMarkDirty()
    }

    private func deleteSelectedRow() {
        commitPendingEdits()
        guard table.rows.count > 1, let rowIdx = selectedCell?.row, rowIdx >= 0, rowIdx < table.rows.count else { return }
        pushUndoSnapshot()
        table.rows.remove(at: rowIdx)
        let clamped = min(rowIdx, table.rows.count - 1)
        let nextCoord = SpreadsheetCellCoord(row: clamped, col: selectedCell?.col ?? 0)
        selectedCell = nextCoord
        selectionAnchor = nextCoord
        selectedRange = [nextCoord]
        rebuildFilteredRows(immediate: true)
        recomputeSelectionStats()
        dataVersion &+= 1
        selectionVersion &+= 1
        onMarkDirty()
    }

    private func addColumn() {
        commitPendingEdits()
        pushUndoSnapshot()
        let newCol = table.columnCount
        table.columnCount += 1
        table.normalizeDimensions()
        if firstRowIsHeader && !table.rows.isEmpty {
            table.rows[0][newCol] = loc.text(es: "Columna \(newCol + 1)", en: "Column \(newCol + 1)")
        }
        columnWidths[newCol] = 130
        columnWidthVersion &+= 1
        dataVersion &+= 1
        onMarkDirty()
    }

    private func sortByColumn(_ colIdx: Int, direction: SpreadsheetSortDirection) {
        commitPendingEdits()
        guard table.rows.count > dataStartRowIndex + 1 else { return }
        pushUndoSnapshot()
        let headerRows = Array(table.rows.prefix(dataStartRowIndex))
        var dataRows = Array(table.rows.dropFirst(dataStartRowIndex))
        dataRows.sort { a, b in
            let va = colIdx < a.count ? a[colIdx] : ""
            let vb = colIdx < b.count ? b[colIdx] : ""
            let cmp = CSVDocumentEngine.compareCellValues(va, vb)
            return direction == .ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
        table.rows = headerRows + dataRows
        sortColumn = colIdx
        sortDirection = direction
        rebuildFilteredRows(immediate: true)
        dataVersion &+= 1
        onMarkDirty()
    }

    private func toggleBoldOnSelection() {
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else { return }
        pushUndoSnapshot()
        let targetBold = !activeCellStyle.isBold
        for c in coords {
            var style = table.styles[c] ?? SpreadsheetCellStyle()
            style.isBold = targetBold
            table.styles[c] = style
        }
        dataVersion &+= 1
        onMarkDirty()
    }

    private func toggleItalicOnSelection() {
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else { return }
        pushUndoSnapshot()
        let targetItalic = !activeCellStyle.isItalic
        for c in coords {
            var style = table.styles[c] ?? SpreadsheetCellStyle()
            style.isItalic = targetItalic
            table.styles[c] = style
        }
        dataVersion &+= 1
        onMarkDirty()
    }

    private func setAlignmentOnSelection(_ align: SpreadsheetCellAlignment) {
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else { return }
        pushUndoSnapshot()
        for c in coords {
            var style = table.styles[c] ?? SpreadsheetCellStyle()
            style.alignment = align
            table.styles[c] = style
        }
        dataVersion &+= 1
        onMarkDirty()
    }

    private func applyColorToSelection(hex: String?, isBackground: Bool) {
        let coords = selectedRange.isEmpty ? (selectedCell.map { [$0] } ?? []) : Array(selectedRange)
        guard !coords.isEmpty else { return }
        pushUndoSnapshot()
        for c in coords {
            var style = table.styles[c] ?? SpreadsheetCellStyle()
            if isBackground {
                style.fillColorHex = hex
            } else {
                style.textColorHex = hex
            }
            table.styles[c] = style
        }
        dataVersion &+= 1
        onMarkDirty()
    }

    private func autoFitColumns(initial: Bool) {
        let sampleRows = table.rows.prefix(80)
        var widths: [Int: CGFloat] = [:]
        for col in 0..<table.columnCount {
            var maxChars = 6
            for row in sampleRows where col < row.count {
                maxChars = max(maxChars, min(42, row[col].count))
            }
            let estimated = CGFloat(maxChars) * 7.4 + 26
            widths[col] = min(initial ? 230 : 320, max(78, estimated))
        }
        columnWidths = widths
        columnWidthVersion &+= 1
    }

    private func formatStatNumber(_ value: Double) -> String {
        Self.statNumberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func toolbarIconButton(
        _ systemName: String,
        active: Bool = false,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        PreviewToolbarIconButton(
            systemName,
            active: active,
            help: help,
            disabled: disabled,
            action: action
        )
    }

    private func formatToggleButton(
        label: String,
        bold: Bool = false,
        italic: Bool = false,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        PreviewToolbarToggleCharButton(
            label,
            bold: bold,
            italic: italic,
            active: active,
            help: help,
            action: action
        )
    }
}

/// Subvista aislada para la barra de fórmula (`fx`): mantiene su borrador localmente para que
/// tipear en la barra `fx` nunca invalide ni re-evalúe la grilla de celdas ni la barra de herramientas.
private struct SpreadsheetFormulaBarField: View {
    let cellLabel: String
    let externalText: String
    let hasSelection: Bool
    let placeholder: String
    let applyTitle: String
    let onCommit: (String) -> Void

    @ViewState private var draft: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(cellLabel)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 52, minHeight: PreviewToolbarMetrics.controlHeight, maxHeight: PreviewToolbarMetrics.controlHeight)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous))

            Text("fx")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: PreviewToolbarMetrics.controlHeight)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous).stroke(Color.primary.opacity(0.14), lineWidth: 0.75))
                .onSubmit {
                    onCommit(draft)
                }

            if hasSelection {
                Button {
                    onCommit(draft)
                } label: {
                    Text(applyTitle)
                        .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                        .padding(.horizontal, 10)
                }
                .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
            }
        }
        .onAppear {
            draft = externalText
        }
        .onChange(of: externalText) { _, newValue in
            if draft != newValue {
                draft = newValue
            }
        }
    }
}
