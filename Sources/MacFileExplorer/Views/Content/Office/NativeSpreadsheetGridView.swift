import AppKit
import SwiftUI

// MARK: - Grilla Nativa AppKit (`NSTableView`) de Alto Rendimiento (120 FPS) para CSV y Excel

/// Reemplaza la grilla SwiftUI 2D por un `NSTableView` nativo con reciclado real de celdas,
/// encabezados fijos redimensionables/ordenables, selección rectangular arrastrando con el mouse
/// (celdas, filas desde `#` y columnas desde encabezados) con auto-scroll suave,
/// navegación por teclado (flechas/Tab/Enter) y edición en línea a 120 FPS.
struct NativeSpreadsheetGridView: NSViewRepresentable {
    let table: SpreadsheetTableData
    let visibleRowIndices: [Int]
    let firstRowIsHeader: Bool
    let isEditingEnabled: Bool
    let wrapText: Bool
    let sortColumn: Int?
    let sortDirection: SpreadsheetSortDirection
    let selectedCell: SpreadsheetCellCoord?
    let selectedRange: Set<SpreadsheetCellCoord>
    let selectedDisplayRect: SpreadsheetDisplayRect?
    let columnWidths: [Int: CGFloat]

    let dataVersion: UInt64
    let selectionVersion: UInt64
    let columnWidthVersion: UInt64

    let onSelectCell: (SpreadsheetCellCoord, NSEvent.ModifierFlags) -> Void
    let onSelectDisplayRange: (SpreadsheetDisplayRect, SpreadsheetCellCoord, Bool) -> Void
    let onSelectRow: (Int) -> Void
    let onSelectAll: () -> Void
    let onCommitCellEdit: (SpreadsheetCellCoord, String) -> Void
    let onClearSelectedCells: () -> Void
    let onSortColumn: (Int) -> Void
    let onColumnResized: (Int, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let tableView = SpreadsheetNSTableView()
        tableView.coordinator = context.coordinator
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.32)
        tableView.backgroundColor = .textBackgroundColor
        tableView.rowHeight = wrapText ? 44 : 26
        tableView.focusRingType = .none

        let headerView = SpreadsheetNSTableHeaderView()
        headerView.coordinator = context.coordinator
        tableView.headerView = headerView

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.sync(from: self, isInitial: true)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.sync(from: self, isInitial: false)
    }

    // MARK: - Coordinator (`NSTableViewDataSource` + `NSTableViewDelegate` + Selección por Arrastre)

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        private static let rowNumberColID = NSUserInterfaceItemIdentifier("__row_number__")
        private static let rowNumberCellID = NSUserInterfaceItemIdentifier("__row_number_cell__")
        private static let dataCellID = NSUserInterfaceItemIdentifier("__data_cell__")

        var parent: NativeSpreadsheetGridView
        weak var tableView: SpreadsheetNSTableView?

        // Caché O(1) de estado y versiones para evitar recargas innecesarias
        private var lastDataVersion: UInt64 = .max
        private var lastSelectionVersion: UInt64 = .max
        private var lastColumnWidthVersion: UInt64 = .max
        private var lastColCount: Int = -1
        private var lastFirstRowIsHeader: Bool = false
        private var lastWrapText: Bool = false
        private var lastSortColumn: Int? = nil
        private var lastSortDirection: SpreadsheetSortDirection = .ascending
        private var displayRowByDataRow: [Int: Int] = [:]

        // Estado instantáneo durante arrastre activo (O(celdas visibles), cero `reloadData`)
        private var liveDragRect: SpreadsheetDisplayRect? = nil
        private var liveDragAnchorCoord: SpreadsheetCellCoord? = nil

        // Estado de edición en línea activa dentro de AppKit (0% diff SwiftUI mientras escribe)
        private var editingCoord: SpreadsheetCellCoord? = nil
        private var editingDisplayRow: Int? = nil
        private var editingDataCol: Int? = nil
        private var editingOriginalText: String = ""
        private var cancelPendingEdit: Bool = false
        private var isSyncingColumns: Bool = false

        init(parent: NativeSpreadsheetGridView) {
            self.parent = parent
        }

        var visibleRowCount: Int {
            parent.visibleRowIndices.count
        }

        var dataColumnCount: Int {
            max(1, parent.table.columnCount)
        }

        var currentAnchorDisplayCell: (displayRow: Int, dataCol: Int)? {
            if let anchor = liveDragAnchorCoord, let dRow = displayRowByDataRow[anchor.row] {
                return (dRow, anchor.col)
            }
            if let sel = parent.selectedCell, let dRow = displayRowByDataRow[sel.row] {
                return (dRow, sel.col)
            }
            return nil
        }

        func sync(from newParent: NativeSpreadsheetGridView, isInitial: Bool) {
            self.parent = newParent
            guard let tableView else { return }

            let dataChanged = isInitial || (newParent.dataVersion != lastDataVersion)
            let headerModeChanged = isInitial || (newParent.firstRowIsHeader != lastFirstRowIsHeader)
            let wrapChanged = isInitial || (newParent.wrapText != lastWrapText)
            let sortChanged = isInitial
                || (newParent.sortColumn != lastSortColumn)
                || (newParent.sortDirection != lastSortDirection)
            let colWidthsChanged = isInitial || (newParent.columnWidthVersion != lastColumnWidthVersion)
            let selectionChanged = isInitial || (newParent.selectionVersion != lastSelectionVersion)

            let targetColCount = max(1, newParent.table.columnCount)
            let columnCountChanged = isInitial || (targetColCount != lastColCount)

            if wrapChanged {
                lastWrapText = newParent.wrapText
                tableView.rowHeight = newParent.wrapText ? 44 : 26
            }

            if columnCountChanged {
                rebuildColumns(tableView: tableView, colCount: targetColCount)
                lastColCount = targetColCount
            }

            if columnCountChanged || headerModeChanged || dataChanged || sortChanged {
                updateColumnHeaders(tableView: tableView, colCount: targetColCount)
                lastFirstRowIsHeader = newParent.firstRowIsHeader
                lastSortColumn = newParent.sortColumn
                lastSortDirection = newParent.sortDirection
            }

            if colWidthsChanged || columnCountChanged {
                applyColumnWidths(tableView: tableView, colCount: targetColCount)
                lastColumnWidthVersion = newParent.columnWidthVersion
            }

            if dataChanged || wrapChanged || columnCountChanged {
                rebuildDisplayRowIndexMap()
                lastDataVersion = newParent.dataVersion
                lastSelectionVersion = newParent.selectionVersion
                tableView.reloadData()
                updateSelectionBorderLayer()
                return
            }

            if selectionChanged {
                lastSelectionVersion = newParent.selectionVersion
                refreshVisibleSelectionAppearance()
                updateSelectionBorderLayer()
            }
        }

        private func rebuildDisplayRowIndexMap() {
            displayRowByDataRow.removeAll(keepingCapacity: true)
            displayRowByDataRow.reserveCapacity(parent.visibleRowIndices.count)
            for (displayIdx, dataRow) in parent.visibleRowIndices.enumerated() {
                displayRowByDataRow[dataRow] = displayIdx
            }
        }

        private var activeVisualDisplayRect: SpreadsheetDisplayRect? {
            liveDragRect ?? parent.selectedDisplayRect
        }

        private var activePrimaryCoord: SpreadsheetCellCoord? {
            liveDragAnchorCoord ?? parent.selectedCell
        }

        private func isCellSelected(displayRow: Int, dataCol: Int, coord: SpreadsheetCellCoord) -> Bool {
            if let dragRect = liveDragRect {
                return dragRect.contains(displayRow: displayRow, col: dataCol)
            }
            if let rect = parent.selectedDisplayRect {
                return rect.contains(displayRow: displayRow, col: dataCol)
            }
            return parent.selectedRange.contains(coord)
        }

        private func isRowIncludedInSelection(displayRow: Int, dataRow: Int) -> Bool {
            if let rect = activeVisualDisplayRect {
                return displayRow >= rect.minDisplayRow && displayRow <= rect.maxDisplayRow
            }
            if parent.selectedCell?.row == dataRow {
                return true
            }
            if parent.selectedRange.count <= 2_000 {
                return parent.selectedRange.contains(where: { $0.row == dataRow })
            }
            return false
        }

        /// Actualiza en vivo únicamente las celdas actualmente visibles en pantalla (O(visibles), < 0.2 ms a 120 FPS).
        func refreshVisibleSelectionAppearance() {
            guard let tableView else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.length > 0 else { return }
            let visibleColIndices = tableView.columnIndexes(in: tableView.visibleRect)
            let primaryCoord = activePrimaryCoord
            let hasRectBorder = (activeVisualDisplayRect != nil)

            let rowEnd = min(visibleRows.location + visibleRows.length, parent.visibleRowIndices.count)

            for dRow in visibleRows.location..<rowEnd {
                let dataRow = parent.visibleRowIndices[dRow]

                if let rowNumView = tableView.view(atColumn: 0, row: dRow, makeIfNecessary: false) as? SpreadsheetRowNumberCellView {
                    rowNumView.updateSelected(isRowIncludedInSelection(displayRow: dRow, dataRow: dataRow))
                }

                for tvCol in visibleColIndices where tvCol >= 1 && tvCol < tableView.numberOfColumns {
                    guard let cellView = tableView.view(atColumn: tvCol, row: dRow, makeIfNecessary: false) as? SpreadsheetDataCellView else {
                        continue
                    }
                    let dataCol = tvCol - 1
                    let coord = SpreadsheetCellCoord(row: dataRow, col: dataCol)
                    let isPrimary = (primaryCoord == coord)
                    let isSelected = isCellSelected(displayRow: dRow, dataCol: dataCol, coord: coord)
                    cellView.updateSelection(
                        isPrimary: isPrimary,
                        isSelected: isSelected,
                        showPrimaryOutline: !hasRectBorder || (activeVisualDisplayRect?.cellCount ?? 0) > 1
                    )
                }
            }
        }

        func updateSelectionBorderLayer() {
            guard let tableView else { return }
            if editingCoord != nil {
                tableView.updateSelectionBorderRect(nil)
                return
            }
            tableView.updateSelectionBorderRect(activeVisualDisplayRect)
        }

        private func rebuildColumns(tableView: NSTableView, colCount: Int) {
            isSyncingColumns = true
            defer { isSyncingColumns = false }

            for existing in tableView.tableColumns.reversed() {
                tableView.removeTableColumn(existing)
            }

            // Columna 0: Número de fila (#)
            let rowCol = NSTableColumn(identifier: Self.rowNumberColID)
            rowCol.title = "#"
            rowCol.width = 48
            rowCol.minWidth = 42
            rowCol.maxWidth = 72
            rowCol.resizingMask = []
            rowCol.headerCell.alignment = .center
            tableView.addTableColumn(rowCol)

            // Columnas de datos 1...colCount
            for c in 0..<colCount {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_\(c)"))
                col.width = parent.columnWidths[c] ?? 135
                col.minWidth = 52
                col.maxWidth = 900
                col.resizingMask = [.userResizingMask]
                tableView.addTableColumn(col)
            }
        }

        private func updateColumnHeaders(tableView: NSTableView, colCount: Int) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            let ascImg = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig)
            let descImg = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig)
            let firstRow = parent.firstRowIsHeader ? parent.table.rows.first : nil

            for c in 0..<colCount {
                let colIndex = c + 1
                guard colIndex < tableView.tableColumns.count else { break }
                let col = tableView.tableColumns[colIndex]
                let letter = SpreadsheetTableData.excelColumnName(for: c)

                if let firstRow, c < firstRow.count {
                    let raw = firstRow[c].trimmingCharacters(in: .whitespacesAndNewlines)
                    col.title = raw.isEmpty ? letter : "\(letter) · \(raw)"
                } else {
                    col.title = letter
                }

                if parent.sortColumn == c {
                    tableView.setIndicatorImage(parent.sortDirection == .ascending ? ascImg : descImg, in: col)
                } else {
                    tableView.setIndicatorImage(nil, in: col)
                }
            }
            tableView.headerView?.needsDisplay = true
        }

        private func applyColumnWidths(tableView: NSTableView, colCount: Int) {
            isSyncingColumns = true
            defer { isSyncingColumns = false }

            for c in 0..<colCount {
                let colIndex = c + 1
                guard colIndex < tableView.tableColumns.count else { break }
                if let targetW = parent.columnWidths[c], abs(tableView.tableColumns[colIndex].width - targetW) > 0.5 {
                    tableView.tableColumns[colIndex].width = targetW
                }
            }
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.visibleRowIndices.count
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row >= 0, row < parent.visibleRowIndices.count else { return nil }
            let dataRow = parent.visibleRowIndices[row]

            if tableColumn.identifier == Self.rowNumberColID {
                let view = (tableView.makeView(withIdentifier: Self.rowNumberCellID, owner: self) as? SpreadsheetRowNumberCellView)
                    ?? SpreadsheetRowNumberCellView(identifier: Self.rowNumberCellID)
                view.configure(rowNumber: dataRow + 1, isSelected: isRowIncludedInSelection(displayRow: row, dataRow: dataRow))
                return view
            }

            guard let colIdx = dataColumnIndex(from: tableColumn.identifier) else { return nil }
            let coord = SpreadsheetCellCoord(row: dataRow, col: colIdx)
            let value = parent.table.value(at: dataRow, col: colIdx)
            let style = parent.table.styles[coord]
            let isPrimary = (activePrimaryCoord == coord)
            let isSelected = isCellSelected(displayRow: row, dataCol: colIdx, coord: coord)
            let isZebra = (row % 2 == 1)
            let hasRectBorder = (activeVisualDisplayRect != nil)

            let cellView = (tableView.makeView(withIdentifier: Self.dataCellID, owner: self) as? SpreadsheetDataCellView)
                ?? SpreadsheetDataCellView(identifier: Self.dataCellID)
            cellView.configure(
                text: value,
                style: style,
                wrapText: parent.wrapText,
                isPrimary: isPrimary,
                isSelected: isSelected,
                isZebra: isZebra,
                showPrimaryOutline: !hasRectBorder || (activeVisualDisplayRect?.cellCount ?? 0) > 1
            )
            return cellView
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            if tableColumn.identifier == Self.rowNumberColID {
                finishActiveEditIfNeeded()
                parent.onSelectAll()
                return
            }
            if let colIdx = dataColumnIndex(from: tableColumn.identifier) {
                finishActiveEditIfNeeded()
                parent.onSortColumn(colIdx)
            }
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            updateSelectionBorderLayer()
            guard !isSyncingColumns,
                  let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  let colIdx = dataColumnIndex(from: col.identifier) else {
                return
            }
            parent.onColumnResized(colIdx, col.width)
        }

        // MARK: - Interacción (Clic, Arrastre Rectangular, Filas/Columnas, Doble Clic y Teclado)

        func handleRowNumberClick(displayRow: Int) {
            guard displayRow >= 0, displayRow < parent.visibleRowIndices.count else { return }
            finishActiveEditIfNeeded()
            let dataRow = parent.visibleRowIndices[displayRow]
            parent.onSelectRow(dataRow)
        }

        func handleCellClick(displayRow: Int, dataCol: Int, modifiers: NSEvent.ModifierFlags) {
            guard displayRow >= 0, displayRow < parent.visibleRowIndices.count,
                  dataCol >= 0, dataCol < parent.table.columnCount else { return }
            finishActiveEditIfNeeded()
            let dataRow = parent.visibleRowIndices[displayRow]
            parent.onSelectCell(SpreadsheetCellCoord(row: dataRow, col: dataCol), modifiers)
        }

        func handleColumnHeaderSortClick(dataCol: Int) {
            guard dataCol >= 0, dataCol < parent.table.columnCount else { return }
            finishActiveEditIfNeeded()
            parent.onSortColumn(dataCol)
        }

        /// Actualiza la selección rectangular en vivo al arrastrar celdas, filas (`#`) o encabezados de columnas.
        func updateLiveDragSelection(
            rect: SpreadsheetDisplayRect,
            anchorDisplayRow: Int,
            anchorDataCol: Int,
            isFinal: Bool
        ) {
            guard !parent.visibleRowIndices.isEmpty, parent.table.columnCount > 0 else { return }
            let clampedAnchorRow = max(0, min(anchorDisplayRow, parent.visibleRowIndices.count - 1))
            let clampedAnchorCol = max(0, min(anchorDataCol, parent.table.columnCount - 1))
            let anchorCoord = SpreadsheetCellCoord(
                row: parent.visibleRowIndices[clampedAnchorRow],
                col: clampedAnchorCol
            )
            let clampedRect = SpreadsheetDisplayRect(
                anchorRow: max(0, min(rect.minDisplayRow, parent.visibleRowIndices.count - 1)),
                anchorCol: max(0, min(rect.minCol, parent.table.columnCount - 1)),
                endRow: max(0, min(rect.maxDisplayRow, parent.visibleRowIndices.count - 1)),
                endCol: max(0, min(rect.maxCol, parent.table.columnCount - 1))
            )

            finishActiveEditIfNeeded()
            liveDragRect = isFinal ? nil : clampedRect
            liveDragAnchorCoord = isFinal ? nil : anchorCoord
            refreshVisibleSelectionAppearance()
            updateSelectionBorderLayer()
            parent.onSelectDisplayRange(clampedRect, anchorCoord, isFinal)
        }

        func finishLiveDragSelection() {
            guard let rect = liveDragRect, let anchor = liveDragAnchorCoord else {
                liveDragRect = nil
                liveDragAnchorCoord = nil
                return
            }
            liveDragRect = nil
            liveDragAnchorCoord = nil
            parent.onSelectDisplayRange(rect, anchor, true)
            refreshVisibleSelectionAppearance()
            updateSelectionBorderLayer()
        }

        func beginInlineEditing(displayRow: Int, dataCol: Int, initialTypedText: String? = nil) {
            guard parent.isEditingEnabled,
                  let tableView,
                  displayRow >= 0, displayRow < parent.visibleRowIndices.count,
                  dataCol >= 0, dataCol < parent.table.columnCount else { return }

            let dataRow = parent.visibleRowIndices[displayRow]
            let coord = SpreadsheetCellCoord(row: dataRow, col: dataCol)

            if parent.selectedCell != coord {
                parent.onSelectCell(coord, [])
            }

            tableView.scrollRowToVisible(displayRow)
            tableView.scrollColumnToVisible(dataCol + 1)

            guard let cellView = tableView.view(atColumn: dataCol + 1, row: displayRow, makeIfNecessary: true) as? SpreadsheetDataCellView else {
                return
            }

            let rawEditable = parent.table.formulas[coord] ?? parent.table.value(at: dataRow, col: dataCol)
            editingCoord = coord
            editingDisplayRow = displayRow
            editingDataCol = dataCol
            editingOriginalText = rawEditable
            cancelPendingEdit = false
            updateSelectionBorderLayer()

            let textField = cellView.textField
            textField.delegate = self
            textField.isEditable = true
            textField.isSelectable = true
            textField.stringValue = initialTypedText ?? rawEditable
            cellView.setEditingAppearance(true)

            tableView.window?.makeFirstResponder(textField)
            if let editor = tableView.window?.fieldEditor(false, for: textField) as? NSTextView {
                if initialTypedText != nil {
                    let end = (textField.stringValue as NSString).length
                    editor.selectedRange = NSRange(location: end, length: 0)
                } else {
                    editor.selectAll(nil)
                }
            }
        }

        func finishActiveEditIfNeeded() {
            guard editingCoord != nil, let tableView else { return }
            tableView.window?.makeFirstResponder(tableView)
        }

        func handleArrowNavigation(rowDelta: Int, colDelta: Int, extendSelection: Bool) {
            guard !parent.visibleRowIndices.isEmpty, parent.table.columnCount > 0 else { return }

            let currentDisplayRow: Int
            let currentCol: Int
            if let sel = parent.selectedCell {
                currentDisplayRow = displayRowByDataRow[sel.row] ?? 0
                currentCol = sel.col
            } else {
                currentDisplayRow = 0
                currentCol = 0
            }

            let nextDisplayRow = min(max(0, currentDisplayRow + rowDelta), parent.visibleRowIndices.count - 1)
            let nextCol = min(max(0, currentCol + colDelta), parent.table.columnCount - 1)
            let nextDataRow = parent.visibleRowIndices[nextDisplayRow]
            let nextCoord = SpreadsheetCellCoord(row: nextDataRow, col: nextCol)

            parent.onSelectCell(nextCoord, extendSelection ? .shift : [])
            tableView?.scrollRowToVisible(nextDisplayRow)
            tableView?.scrollColumnToVisible(nextCol + 1)
        }

        func beginEditOnSelectedCell(initialTypedText: String? = nil) {
            guard let sel = parent.selectedCell,
                  let dRow = displayRowByDataRow[sel.row] else { return }
            beginInlineEditing(displayRow: dRow, dataCol: sel.col, initialTypedText: initialTypedText)
        }

        func clearSelectedCells() {
            guard parent.isEditingEnabled else { return }
            parent.onClearSelectedCells()
        }

        // MARK: - NSTextFieldDelegate (Commit / Cancel / Enter / Tab)

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelPendingEdit = true
                if let tf = control as? NSTextField {
                    tf.stringValue = editingOriginalText
                }
                if let tableView {
                    tableView.window?.makeFirstResponder(tableView)
                }
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let tableView {
                    tableView.window?.makeFirstResponder(tableView)
                }
                handleArrowNavigation(rowDelta: 1, colDelta: 0, extendSelection: false)
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let tableView {
                    tableView.window?.makeFirstResponder(tableView)
                }
                handleArrowNavigation(rowDelta: 0, colDelta: 1, extendSelection: false)
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                if let tableView {
                    tableView.window?.makeFirstResponder(tableView)
                }
                handleArrowNavigation(rowDelta: 0, colDelta: -1, extendSelection: false)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            tf.isEditable = false
            tf.isSelectable = false
            tf.delegate = nil
            (tf.superview as? SpreadsheetDataCellView)?.setEditingAppearance(false)

            let committedCoord = editingCoord
            let wasCancelled = cancelPendingEdit
            let newText = tf.stringValue
            let originalText = editingOriginalText

            editingCoord = nil
            editingDisplayRow = nil
            editingDataCol = nil
            cancelPendingEdit = false
            updateSelectionBorderLayer()

            if !wasCancelled, let coord = committedCoord, newText != originalText {
                parent.onCommitCellEdit(coord, newText)
            } else if wasCancelled, let coord = committedCoord {
                tf.stringValue = parent.table.value(at: coord.row, col: coord.col)
            }
        }

        private func dataColumnIndex(from id: NSUserInterfaceItemIdentifier) -> Int? {
            let raw = id.rawValue
            guard raw.hasPrefix("col_") else { return nil }
            return Int(raw.dropFirst(4))
        }
    }
}

// MARK: - Subclase `NSTableView` con Selección Rectangular por Arrastre, Auto-Scroll y Teclado Estilo Excel

@MainActor
final class SpreadsheetNSTableView: NSTableView {
    private enum DragMode {
        case none
        case cells(anchorDisplayRow: Int, anchorDataCol: Int)
        case rows(anchorDisplayRow: Int)
    }

    weak var coordinator: NativeSpreadsheetGridView.Coordinator?

    private var dragMode: DragMode = .none
    private var lastDragEndpoint: (displayRow: Int, dataCol: Int)? = nil
    private var didMoveDuringDrag = false
    nonisolated(unsafe) private var autoScrollTimer: Timer?

    private let selectionBorderLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = nil
        layer.borderWidth = 1.6
        layer.cornerRadius = 1.5
        layer.zPosition = 50
        layer.isHidden = true
        return layer
    }()
    private var currentBorderRect: SpreadsheetDisplayRect? = nil

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSelectionLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSelectionLayer()
    }

    deinit {
        autoScrollTimer?.invalidate()
    }

    private func setupSelectionLayer() {
        wantsLayer = true
        layer?.addSublayer(selectionBorderLayer)
    }

    override var acceptsFirstResponder: Bool { true }

    override func selectAll(_ sender: Any?) {
        coordinator?.finishActiveEditIfNeeded()
        coordinator?.parent.onSelectAll()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopAutoScrollTimer()
            dragMode = .none
            lastDragEndpoint = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySelectionBorderColor()
    }

    override func layout() {
        super.layout()
        repositionSelectionBorderLayer()
    }

    func updateSelectionBorderRect(_ rect: SpreadsheetDisplayRect?) {
        currentBorderRect = rect
        repositionSelectionBorderLayer()
    }

    private func applySelectionBorderColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectionBorderLayer.borderColor = NSColor.controlAccentColor.cgColor
            CATransaction.commit()
        }
    }

    private func repositionSelectionBorderLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let rect = currentBorderRect,
              numberOfRows > 0,
              numberOfColumns > 1 else {
            selectionBorderLayer.isHidden = true
            return
        }

        let r1 = max(0, min(rect.minDisplayRow, numberOfRows - 1))
        let r2 = max(r1, min(rect.maxDisplayRow, numberOfRows - 1))
        let c1 = max(1, min(rect.minCol + 1, numberOfColumns - 1))
        let c2 = max(c1, min(rect.maxCol + 1, numberOfColumns - 1))

        let topLeft = frameOfCell(atColumn: c1, row: r1)
        let bottomRight = frameOfCell(atColumn: c2, row: r2)
        let unionRect = topLeft.union(bottomRight)

        guard !unionRect.isNull, !unionRect.isEmpty else {
            selectionBorderLayer.isHidden = true
            return
        }

        if selectionBorderLayer.superlayer == nil {
            wantsLayer = true
            layer?.addSublayer(selectionBorderLayer)
        }
        applySelectionBorderColor()
        selectionBorderLayer.frame = unionRect.insetBy(dx: -0.5, dy: -0.5)
        selectionBorderLayer.isHidden = false
    }

    override func mouseDown(with event: NSEvent) {
        stopAutoScrollTimer()
        dragMode = .none
        lastDragEndpoint = nil
        didMoveDuringDrag = false

        let localPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: localPoint)
        let clickedCol = column(at: localPoint)

        guard clickedRow >= 0, clickedCol >= 0 else {
            super.mouseDown(with: event)
            return
        }

        // Columna `#`: clic selecciona la fila completa; arrastrar verticalmente selecciona múltiples filas
        if clickedCol == 0 {
            window?.makeFirstResponder(self)
            let maxCol = max(0, numberOfColumns - 2)
            if event.modifierFlags.contains(.shift),
               let anchor = coordinator?.currentAnchorDisplayCell {
                let rect = SpreadsheetDisplayRect(
                    anchorRow: anchor.displayRow,
                    anchorCol: 0,
                    endRow: clickedRow,
                    endCol: maxCol
                )
                dragMode = .rows(anchorDisplayRow: anchor.displayRow)
                lastDragEndpoint = (clickedRow, maxCol)
                didMoveDuringDrag = true
                coordinator?.updateLiveDragSelection(rect: rect, anchorDisplayRow: anchor.displayRow, anchorDataCol: 0, isFinal: false)
            } else {
                dragMode = .rows(anchorDisplayRow: clickedRow)
                lastDragEndpoint = (clickedRow, maxCol)
                let rect = SpreadsheetDisplayRect(
                    anchorRow: clickedRow,
                    anchorCol: 0,
                    endRow: clickedRow,
                    endCol: maxCol
                )
                coordinator?.updateLiveDragSelection(rect: rect, anchorDisplayRow: clickedRow, anchorDataCol: 0, isFinal: false)
            }
            startAutoScrollTimer()
            return
        }

        let dataCol = clickedCol - 1
        if event.clickCount >= 2 {
            coordinator?.beginInlineEditing(displayRow: clickedRow, dataCol: dataCol)
            return
        }

        window?.makeFirstResponder(self)

        // ⌘+Clic: alternar celda individual (selección discontinua) sin iniciar arrastre rectangular
        if event.modifierFlags.contains(.command) {
            coordinator?.handleCellClick(displayRow: clickedRow, dataCol: dataCol, modifiers: event.modifierFlags)
            return
        }

        // ⇧+Clic: extender rango desde ancla actual y permitir continuar arrastrando
        if event.modifierFlags.contains(.shift),
           let anchor = coordinator?.currentAnchorDisplayCell {
            let rect = SpreadsheetDisplayRect(
                anchorRow: anchor.displayRow,
                anchorCol: anchor.dataCol,
                endRow: clickedRow,
                endCol: dataCol
            )
            dragMode = .cells(anchorDisplayRow: anchor.displayRow, anchorDataCol: anchor.dataCol)
            lastDragEndpoint = (clickedRow, dataCol)
            didMoveDuringDrag = true
            coordinator?.updateLiveDragSelection(rect: rect, anchorDisplayRow: anchor.displayRow, anchorDataCol: anchor.dataCol, isFinal: false)
            startAutoScrollTimer()
            return
        }

        // Clic normal: fija el ancla e inicia arrastre rectangular de filas × columnas
        coordinator?.handleCellClick(displayRow: clickedRow, dataCol: dataCol, modifiers: [])
        dragMode = .cells(anchorDisplayRow: clickedRow, anchorDataCol: dataCol)
        lastDragEndpoint = (clickedRow, dataCol)
        startAutoScrollTimer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard case .none = dragMode else {
            autoscroll(with: event)
            let localPoint = convert(event.locationInWindow, from: nil)
            extendDragSelection(to: localPoint)
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        stopAutoScrollTimer()
        defer {
            dragMode = .none
            lastDragEndpoint = nil
            didMoveDuringDrag = false
        }
        guard case .none = dragMode else {
            if didMoveDuringDrag {
                coordinator?.finishLiveDragSelection()
            } else if case .rows = dragMode {
                coordinator?.finishLiveDragSelection()
            }
            return
        }
        super.mouseUp(with: event)
    }

    private func extendDragSelection(to localPoint: NSPoint) {
        guard let targetRow = clampedDisplayRow(for: localPoint) else { return }

        switch dragMode {
        case .none:
            return
        case .cells(let anchorRow, let anchorCol):
            guard let targetCol = clampedDataCol(for: localPoint) else { return }
            if let last = lastDragEndpoint, last.displayRow == targetRow && last.dataCol == targetCol {
                return
            }
            lastDragEndpoint = (targetRow, targetCol)
            didMoveDuringDrag = true
            let rect = SpreadsheetDisplayRect(
                anchorRow: anchorRow,
                anchorCol: anchorCol,
                endRow: targetRow,
                endCol: targetCol
            )
            coordinator?.updateLiveDragSelection(
                rect: rect,
                anchorDisplayRow: anchorRow,
                anchorDataCol: anchorCol,
                isFinal: false
            )
        case .rows(let anchorRow):
            let maxCol = max(0, numberOfColumns - 2)
            if let last = lastDragEndpoint, last.displayRow == targetRow {
                return
            }
            lastDragEndpoint = (targetRow, maxCol)
            didMoveDuringDrag = true
            let rect = SpreadsheetDisplayRect(
                anchorRow: anchorRow,
                anchorCol: 0,
                endRow: targetRow,
                endCol: maxCol
            )
            coordinator?.updateLiveDragSelection(
                rect: rect,
                anchorDisplayRow: anchorRow,
                anchorDataCol: 0,
                isFinal: false
            )
        }
    }

    private func clampedDisplayRow(for localPoint: NSPoint) -> Int? {
        guard numberOfRows > 0 else { return nil }
        let r = row(at: localPoint)
        if r >= 0 { return r }
        return localPoint.y < 0 ? 0 : (numberOfRows - 1)
    }

    private func clampedDataCol(for localPoint: NSPoint) -> Int? {
        guard numberOfColumns > 1 else { return nil }
        let c = column(at: localPoint)
        if c >= 1 { return c - 1 }
        if c == 0 || localPoint.x < rect(ofColumn: 1).minX {
            return 0
        }
        return numberOfColumns - 2
    }

    private func startAutoScrollTimer() {
        stopAutoScrollTimer()
        let timer = Timer(timeInterval: 0.045, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performEdgeAutoScrollTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        autoScrollTimer = timer
    }

    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func performEdgeAutoScrollTick() {
        guard case .none = dragMode else {
            guard let window, let scrollView = enclosingScrollView else {
                stopAutoScrollTimer()
                return
            }
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            let localPoint = convert(mouseInWindow, from: nil)
            let vis = visibleRect

            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if localPoint.y < vis.minY {
                dy = -min(36, max(10, (vis.minY - localPoint.y) * 0.45))
            } else if localPoint.y > vis.maxY {
                dy = min(36, max(10, (localPoint.y - vis.maxY) * 0.45))
            }
            if case .cells = dragMode {
                if localPoint.x < vis.minX + 48 {
                    dx = -min(42, max(10, (vis.minX + 48 - localPoint.x) * 0.45))
                } else if localPoint.x > vis.maxX {
                    dx = min(42, max(10, (localPoint.x - vis.maxX) * 0.45))
                }
            }

            if dx != 0 || dy != 0 {
                let clipView = scrollView.contentView
                let maxOriginX = max(0, bounds.width - clipView.bounds.width)
                let maxOriginY = max(0, bounds.height - clipView.bounds.height)
                let nextOrigin = NSPoint(
                    x: min(max(0, clipView.bounds.origin.x + dx), maxOriginX),
                    y: min(max(0, clipView.bounds.origin.y + dy), maxOriginY)
                )
                clipView.scroll(to: nextOrigin)
                scrollView.reflectScrolledClipView(clipView)
                let updatedLocal = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                extendDragSelection(to: updatedLocal)
            }
            return
        }
        stopAutoScrollTimer()
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])

        // Dejar pasar atajos con Command o Control al responder chain (⌘C, ⌘V, ⌘X, ⌘Z, ⌘S, ⌘F, ⌘B, ⌘I)
        if mods.contains(.command) || mods.contains(.control) {
            super.keyDown(with: event)
            return
        }

        let shift = mods.contains(.shift)
        switch event.keyCode {
        case 126: // Up
            coordinator?.handleArrowNavigation(rowDelta: -1, colDelta: 0, extendSelection: shift)
            return
        case 125: // Down
            coordinator?.handleArrowNavigation(rowDelta: 1, colDelta: 0, extendSelection: shift)
            return
        case 123: // Left
            coordinator?.handleArrowNavigation(rowDelta: 0, colDelta: -1, extendSelection: shift)
            return
        case 124: // Right
            coordinator?.handleArrowNavigation(rowDelta: 0, colDelta: 1, extendSelection: shift)
            return
        case 48: // Tab
            coordinator?.handleArrowNavigation(rowDelta: 0, colDelta: shift ? -1 : 1, extendSelection: false)
            return
        case 36, 76, 120: // Return / Enter / F2
            coordinator?.beginEditOnSelectedCell()
            return
        case 51, 117: // Delete / Forward Delete
            coordinator?.clearSelectedCells()
            return
        case 53, 49: // Escape / Space (dejar que Quick Look los maneje)
            super.keyDown(with: event)
            return
        default:
            break
        }

        // Escribir un carácter imprimible directamente sobre la celda seleccionada inicia la edición al instante (como Excel)
        if !mods.contains(.option),
           let chars = event.characters,
           !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) {
            coordinator?.beginEditOnSelectedCell(initialTypedText: chars)
            return
        }

        super.keyDown(with: event)
    }
}

// MARK: - Encabezado de Columnas con Selección de Columnas por Arrastre (preservando Redimensionado y Ordenamiento)

@MainActor
private final class SpreadsheetNSTableHeaderView: NSTableHeaderView {
    weak var coordinator: NativeSpreadsheetGridView.Coordinator?

    private var dragAnchorDataCol: Int? = nil
    private var dragStartPoint: NSPoint = .zero
    private var lastDraggedDataCol: Int? = nil
    private var didDragColumnRange = false

    override func mouseDown(with event: NSEvent) {
        dragAnchorDataCol = nil
        lastDraggedDataCol = nil
        didDragColumnRange = false

        let localPoint = convert(event.locationInWindow, from: nil)
        let col = column(at: localPoint)

        // Preservar 100% el redimensionado nativo de columnas al arrastrar cerca de cualquier divisor
        if col >= 0 {
            let rect = headerRect(ofColumn: col)
            let nearRightDivider = col >= 1 && abs(localPoint.x - rect.maxX) <= 5.5
            let nearLeftDivider = col >= 2 && abs(localPoint.x - rect.minX) <= 5.5
            if nearRightDivider || nearLeftDivider {
                super.mouseDown(with: event)
                return
            }
        }

        // Columna 0 (`#`): clic selecciona toda la tabla
        guard col >= 1, let coordinator, coordinator.visibleRowCount > 0 else {
            super.mouseDown(with: event)
            return
        }

        let dataCol = col - 1
        tableView?.window?.makeFirstResponder(tableView)
        dragStartPoint = localPoint

        // ⇧+Clic en encabezado: seleccionar columnas desde el ancla actual hasta esta columna
        if event.modifierFlags.contains(.shift),
           let anchor = coordinator.currentAnchorDisplayCell {
            dragAnchorDataCol = anchor.dataCol
            lastDraggedDataCol = dataCol
            didDragColumnRange = true
            let rect = SpreadsheetDisplayRect(
                anchorRow: 0,
                anchorCol: anchor.dataCol,
                endRow: coordinator.visibleRowCount - 1,
                endCol: dataCol
            )
            coordinator.updateLiveDragSelection(rect: rect, anchorDisplayRow: 0, anchorDataCol: anchor.dataCol, isFinal: false)
            return
        }

        dragAnchorDataCol = dataCol
        lastDraggedDataCol = dataCol
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchorCol = dragAnchorDataCol, let coordinator, coordinator.visibleRowCount > 0 else {
            super.mouseDragged(with: event)
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        let targetCol = clampedHeaderDataCol(for: localPoint)
        let dx = abs(localPoint.x - dragStartPoint.x)
        let dy = abs(localPoint.y - dragStartPoint.y)

        if !didDragColumnRange && targetCol == anchorCol && hypot(dx, dy) < 6 {
            return
        }

        if let tv = tableView {
            tv.scrollColumnToVisible(targetCol + 1)
        }

        if didDragColumnRange && lastDraggedDataCol == targetCol {
            return
        }

        didDragColumnRange = true
        lastDraggedDataCol = targetCol

        let rect = SpreadsheetDisplayRect(
            anchorRow: 0,
            anchorCol: anchorCol,
            endRow: coordinator.visibleRowCount - 1,
            endCol: targetCol
        )
        coordinator.updateLiveDragSelection(
            rect: rect,
            anchorDisplayRow: 0,
            anchorDataCol: anchorCol,
            isFinal: false
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragAnchorDataCol = nil
            lastDraggedDataCol = nil
            didDragColumnRange = false
        }

        guard let anchorCol = dragAnchorDataCol, let coordinator else {
            super.mouseUp(with: event)
            return
        }

        if didDragColumnRange {
            coordinator.finishLiveDragSelection()
        } else if event.modifierFlags.contains(.option), coordinator.visibleRowCount > 0 {
            let rect = SpreadsheetDisplayRect(
                anchorRow: 0,
                anchorCol: anchorCol,
                endRow: coordinator.visibleRowCount - 1,
                endCol: anchorCol
            )
            coordinator.updateLiveDragSelection(
                rect: rect,
                anchorDisplayRow: 0,
                anchorDataCol: anchorCol,
                isFinal: true
            )
        } else {
            // Clic simple sobre el encabezado conserva ordenamiento A→Z / Z→A
            coordinator.handleColumnHeaderSortClick(dataCol: anchorCol)
        }
    }

    private func clampedHeaderDataCol(for localPoint: NSPoint) -> Int {
        guard let tv = tableView, tv.numberOfColumns > 1 else { return 0 }
        let c = column(at: localPoint)
        if c >= 1 { return c - 1 }
        if c == 0 || localPoint.x < headerRect(ofColumn: 1).minX {
            return 0
        }
        return tv.numberOfColumns - 2
    }
}

// MARK: - Celdas Reciclables Ultraligeras (Zero Subview Churn)

@MainActor
private final class SpreadsheetRowNumberCellView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var isCurrentlySelected: Bool = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true
        updateLayerBackground()

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerBackground()
    }

    private func updateLayerBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isCurrentlySelected {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
                label.textColor = .controlAccentColor
                label.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            } else {
                layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor
                label.textColor = .secondaryLabelColor
                label.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            }
        }
    }

    func configure(rowNumber: Int, isSelected: Bool) {
        let text = "\(rowNumber)"
        if label.stringValue != text {
            label.stringValue = text
        }
        if isCurrentlySelected != isSelected {
            isCurrentlySelected = isSelected
            updateLayerBackground()
        }
    }

    func updateSelected(_ isSelected: Bool) {
        guard isCurrentlySelected != isSelected else { return }
        isCurrentlySelected = isSelected
        updateLayerBackground()
    }
}

@MainActor
private final class SpreadsheetDataCellView: NSView {
    private static let regularFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let boldFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let italicFont = NSFontManager.shared.convert(regularFont, toHaveTrait: .italicFontMask)
    private static let boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)

    let textField = NSTextField(string: "")
    private var baseCustomFill: NSColor? = nil
    private var isCurrentlyZebra: Bool = false
    private var isCurrentlySelected: Bool = false
    private var isCurrentlyPrimary: Bool = false
    private var showPrimaryOutline: Bool = true
    private var isCurrentlyEditing: Bool = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true

        textField.isBordered = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.focusRingType = .none
        textField.font = Self.regularFont
        textField.textColor = .labelColor
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.cell?.truncatesLastVisibleLine = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        text: String,
        style: SpreadsheetCellStyle?,
        wrapText: Bool,
        isPrimary: Bool,
        isSelected: Bool,
        isZebra: Bool,
        showPrimaryOutline: Bool
    ) {
        isCurrentlyPrimary = isPrimary
        isCurrentlySelected = isSelected
        isCurrentlyZebra = isZebra
        self.showPrimaryOutline = showPrimaryOutline

        if textField.stringValue != text {
            textField.stringValue = text
        }

        let isBold = style?.isBold ?? false
        let isItalic = style?.isItalic ?? false
        let targetFont: NSFont = {
            switch (isBold, isItalic) {
            case (false, false): return Self.regularFont
            case (true, false): return Self.boldFont
            case (false, true): return Self.italicFont
            case (true, true): return Self.boldItalicFont
            }
        }()
        if textField.font != targetFont {
            textField.font = targetFont
        }

        let targetAlign: NSTextAlignment = {
            switch style?.alignment ?? .leading {
            case .leading: return .left
            case .center: return .center
            case .trailing: return .right
            }
        }()
        if textField.alignment != targetAlign {
            textField.alignment = targetAlign
        }

        textField.usesSingleLineMode = !wrapText
        textField.maximumNumberOfLines = wrapText ? 3 : 1
        textField.lineBreakMode = wrapText ? .byWordWrapping : .byTruncatingTail

        if let hex = style?.textColorHex, let customColor = OfficeColorCodec.nsColor(fromHex: hex) {
            textField.textColor = customColor
        } else {
            textField.textColor = .labelColor
        }

        if let fillHex = style?.fillColorHex, let fill = OfficeColorCodec.nsColor(fromHex: fillHex) {
            baseCustomFill = fill.withAlphaComponent(0.65)
        } else {
            baseCustomFill = nil
        }

        applyResolvedLayerAppearance()
    }

    func updateSelection(isPrimary: Bool, isSelected: Bool, showPrimaryOutline: Bool) {
        guard isCurrentlyPrimary != isPrimary
            || isCurrentlySelected != isSelected
            || self.showPrimaryOutline != showPrimaryOutline else {
            return
        }
        isCurrentlyPrimary = isPrimary
        isCurrentlySelected = isSelected
        self.showPrimaryOutline = showPrimaryOutline
        applyResolvedLayerAppearance()
    }

    func setEditingAppearance(_ isEditing: Bool) {
        isCurrentlyEditing = isEditing
        applyResolvedLayerAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyResolvedLayerAppearance()
    }

    private func resolvedBackgroundColor() -> NSColor {
        if let customFill = baseCustomFill {
            if isCurrentlySelected {
                return customFill.blended(withFraction: isCurrentlyPrimary ? 0.36 : 0.25, of: .controlAccentColor) ?? customFill
            }
            return customFill
        }
        if isCurrentlySelected {
            return NSColor.controlAccentColor.withAlphaComponent(isCurrentlyPrimary ? 0.28 : 0.19)
        }
        if isCurrentlyZebra {
            return NSColor.labelColor.withAlphaComponent(0.025)
        }
        return .clear
    }

    private func applyResolvedLayerAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isCurrentlyEditing {
                layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
                layer?.borderColor = NSColor.controlAccentColor.cgColor
                layer?.borderWidth = 1.8
            } else {
                layer?.backgroundColor = resolvedBackgroundColor().cgColor
                if isCurrentlyPrimary && showPrimaryOutline {
                    layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
                    layer?.borderWidth = 1.2
                } else {
                    layer?.borderColor = nil
                    layer?.borderWidth = 0
                }
            }
        }
    }
}
