import Foundation

// MARK: - Utilidad Compartida para Archivos OOXML (.xlsx / .pptx)

public enum OOXMLArchiveUtility {
    public static func unzip(archiveURL: URL, to destinationDir: URL) throws {
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-qq", "-o", archiveURL.path(percentEncoded: false), "-d", destinationDir.path(percentEncoded: false)]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 && proc.terminationStatus != 1 {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let isES = LocalizationManager.currentLanguageIsSpanish()
            throw NSError(
                domain: "MacFileExplorer.OOXML",
                code: Int(proc.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: isES
                        ? "No se pudo descomprimir el archivo OOXML: \(errText)"
                        : "Failed to unpack OOXML archive: \(errText)"
                ]
            )
        }
    }

    public static func zip(directory: URL, to destinationArchiveURL: URL) throws {
        let tempZipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfe_ooxml_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tempZipURL) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = directory
        proc.arguments = ["-qq", "-r", tempZipURL.path(percentEncoded: false), "."]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let isES = LocalizationManager.currentLanguageIsSpanish()
            throw NSError(
                domain: "MacFileExplorer.OOXML",
                code: Int(proc.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: isES
                        ? "No se pudo volver a empaquetar el archivo OOXML: \(errText)"
                        : "Failed to repack OOXML archive: \(errText)"
                ]
            )
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: destinationArchiveURL.path(percentEncoded: false)) {
            _ = try fm.replaceItemAt(destinationArchiveURL, withItemAt: tempZipURL)
        } else {
            try fm.copyItem(at: tempZipURL, to: destinationArchiveURL)
        }
    }

    /// Helpers de navegación XML tolerantes a prefijos de namespaces.
    public static func childElements(of element: XMLElement, localName: String) -> [XMLElement] {
        (element.children ?? []).compactMap { node in
            guard let el = node as? XMLElement else { return nil }
            let name = el.localName ?? el.name ?? ""
            return name == localName ? el : nil
        }
    }

    public static func firstChild(of element: XMLElement, localName: String) -> XMLElement? {
        childElements(of: element, localName: localName).first
    }

    public static func attributeValue(of element: XMLElement, localName: String) -> String? {
        for attr in element.attributes ?? [] {
            if attr.name == localName {
                return attr.stringValue
            }
        }
        for attr in element.attributes ?? [] {
            let name = attr.localName ?? attr.name ?? ""
            if name == localName {
                return attr.stringValue
            }
        }
        return nil
    }

    public static func relationshipID(of element: XMLElement) -> String? {
        for attr in element.attributes ?? [] {
            if attr.name == "r:id" || (attr.name?.hasSuffix(":id") == true) {
                return attr.stringValue
            }
        }
        return nil
    }

    public static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Modelo de Libro Excel (.xlsx)

public struct XLSXSheetModel: Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    /// Ruta relativa dentro del ZIP (ej. `"xl/worksheets/sheet1.xml"`).
    public var archivePath: String
    public var table: SpreadsheetTableData
    public var isModified: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        archivePath: String,
        table: SpreadsheetTableData,
        isModified: Bool = false
    ) {
        self.id = id
        self.name = name
        self.archivePath = archivePath
        self.table = table
        self.isModified = isModified
    }
}

public struct XLSXWorkbookModel: Sendable, Equatable {
    public var sourceURL: URL
    public var sheets: [XLSXSheetModel]

    public init(sourceURL: URL, sheets: [XLSXSheetModel]) {
        self.sourceURL = sourceURL
        self.sheets = sheets
    }
}

// MARK: - Motor OOXML Nativo para Microsoft Excel (.xlsx)

public enum XLSXDocumentEngine {

    /// Carga todas las hojas, fórmulas, valores y estilos básicos de un libro `.xlsx`.
    public static func load(from url: URL) throws -> XLSXWorkbookModel {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfe_xlsx_read_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try OOXMLArchiveUtility.unzip(archiveURL: url, to: tempDir)

        let sharedStrings = parseSharedStrings(in: tempDir)
        let cellStyleMap = parseCellStyles(in: tempDir)
        let sheetSpecs = parseSheetDirectory(in: tempDir)

        var sheets: [XLSXSheetModel] = []
        for spec in sheetSpecs {
            let sheetURL = tempDir.appendingPathComponent(spec.archivePath)
            guard FileManager.default.fileExists(atPath: sheetURL.path(percentEncoded: false)) else { continue }
            let table = parseWorksheet(
                at: sheetURL,
                sheetName: spec.name,
                sharedStrings: sharedStrings,
                cellStyleMap: cellStyleMap
            )
            sheets.append(XLSXSheetModel(
                id: spec.archivePath,
                name: spec.name,
                archivePath: spec.archivePath,
                table: table,
                isModified: false
            ))
        }

        if sheets.isEmpty {
            sheets.append(XLSXSheetModel(
                name: "Sheet1",
                archivePath: "xl/worksheets/sheet1.xml",
                table: SpreadsheetTableData(sheetName: "Sheet1", rows: [[""]])
            ))
        }

        return XLSXWorkbookModel(sourceURL: url, sheets: sheets)
    }

    /// Guarda los cambios de las hojas editadas dentro del paquete `.xlsx` preservando el resto del libro.
    public static func save(workbook: XLSXWorkbookModel, to destinationURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfe_xlsx_write_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try OOXMLArchiveUtility.unzip(archiveURL: workbook.sourceURL, to: tempDir)

        for sheet in workbook.sheets where sheet.isModified {
            let sheetURL = tempDir.appendingPathComponent(sheet.archivePath)
            if FileManager.default.fileExists(atPath: sheetURL.path(percentEncoded: false)) {
                try rewriteWorksheetXML(at: sheetURL, with: sheet.table)
            }
        }

        try OOXMLArchiveUtility.zip(directory: tempDir, to: destinationURL)
    }

    /// Genera desde cero un libro `.xlsx` OOXML completo (útil para exportar/convertir libros `.xls` a `.xlsx`).
    public static func createNew(workbook: XLSXWorkbookModel, to destinationURL: URL) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("mfe_xlsx_new_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        let sheets = workbook.sheets.isEmpty
            ? [XLSXSheetModel(name: "Sheet1", archivePath: "xl/worksheets/sheet1.xml", table: SpreadsheetTableData(rows: [[""]]))]
            : workbook.sheets

        func writeXML(_ xml: String, relativePath: String) throws {
            let fileURL = tempDir.appendingPathComponent(relativePath)
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: fileURL, options: .atomic)
        }

        // [Content_Types].xml
        var sheetOverrides = ""
        for idx in sheets.indices {
            sheetOverrides += "  <Override PartName=\"/xl/worksheets/sheet\(idx + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>\n"
        }
        try writeXML("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        \(sheetOverrides)</Types>
        """, relativePath: "[Content_Types].xml")

        // _rels/.rels
        try writeXML("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """, relativePath: "_rels/.rels")

        // xl/workbook.xml & xl/_rels/workbook.xml.rels
        var workbookSheetsXML = ""
        var workbookRelsXML = ""
        let invalidChars = CharacterSet(charactersIn: ":\\/?*[]")
        for (idx, sheet) in sheets.enumerated() {
            let cleaned = sheet.name
                .components(separatedBy: invalidChars)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = OOXMLArchiveUtility.xmlEscape(String((cleaned.isEmpty ? "Sheet\(idx + 1)" : cleaned).prefix(31)))
            let n = idx + 1
            workbookSheetsXML += "    <sheet name=\"\(safeName)\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>\n"
            workbookRelsXML += "  <Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>\n"
        }

        try writeXML("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
        \(workbookSheetsXML)  </sheets>
        </workbook>
        """, relativePath: "xl/workbook.xml")

        try writeXML("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(workbookRelsXML)</Relationships>
        """, relativePath: "xl/_rels/workbook.xml.rels")

        // xl/worksheets/sheetN.xml
        for (idx, sheet) in sheets.enumerated() {
            let table = sheet.table
            let lastCol = SpreadsheetTableData.excelColumnName(for: max(0, table.columnCount - 1))
            let lastRow = max(1, table.rows.count)
            var sheetDataXML = ""
            for (rIdx, row) in table.rows.enumerated() {
                let excelRow = rIdx + 1
                var cellsXML = ""
                for (cIdx, val) in row.enumerated() {
                    let coord = SpreadsheetCellCoord(row: rIdx, col: cIdx)
                    let formula = table.formulas[coord]
                    if val.isEmpty && formula == nil { continue }
                    let ref = "\(SpreadsheetTableData.excelColumnName(for: cIdx))\(excelRow)"
                    if let formula, !formula.isEmpty {
                        let cleanF = formula.hasPrefix("=") ? String(formula.dropFirst()) : formula
                        let escF = OOXMLArchiveUtility.xmlEscape(cleanF)
                        if let numVal = Double(val), numVal.isFinite {
                            cellsXML += "<c r=\"\(ref)\"><f>\(escF)</f><v>\(val)</v></c>"
                        } else {
                            cellsXML += "<c r=\"\(ref)\"><f>\(escF)</f></c>"
                        }
                    } else if val == "TRUE" || val == "FALSE" {
                        cellsXML += "<c r=\"\(ref)\" t=\"b\"><v>\(val == "TRUE" ? "1" : "0")</v></c>"
                    } else if let numVal = Double(val.trimmingCharacters(in: .whitespaces)),
                              numVal.isFinite,
                              !val.hasPrefix("0") || val == "0" || val.hasPrefix("0.") || val.hasPrefix("-0.") {
                        cellsXML += "<c r=\"\(ref)\"><v>\(val.trimmingCharacters(in: .whitespaces))</v></c>"
                    } else {
                        let esc = OOXMLArchiveUtility.xmlEscape(val)
                        cellsXML += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc)</t></is></c>"
                    }
                }
                if !cellsXML.isEmpty {
                    sheetDataXML += "    <row r=\"\(excelRow)\">\(cellsXML)</row>\n"
                }
            }

            try writeXML("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <dimension ref="A1:\(lastCol)\(lastRow)"/>
              <sheetData>
            \(sheetDataXML)  </sheetData>
            </worksheet>
            """, relativePath: "xl/worksheets/sheet\(idx + 1).xml")
        }

        try OOXMLArchiveUtility.zip(directory: tempDir, to: destinationURL)
    }

    // MARK: - Parseo de Relaciones, Cadenas Compartidas y Estilos

    private struct SheetSpec {
        let name: String
        let archivePath: String
    }

    private static func parseSheetDirectory(in rootDir: URL) -> [SheetSpec] {
        let workbookURL = rootDir.appendingPathComponent("xl/workbook.xml")
        let relsURL = rootDir.appendingPathComponent("xl/_rels/workbook.xml.rels")

        var targetByRelID: [String: String] = [:]
        if let relsDoc = try? XMLDocument(contentsOf: relsURL, options: []),
           let root = relsDoc.rootElement() {
            for rel in OOXMLArchiveUtility.childElements(of: root, localName: "Relationship") {
                if let id = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Id"),
                   let target = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Target") {
                    let cleanTarget = target.hasPrefix("/")
                        ? String(target.dropFirst())
                        : (target.hasPrefix("xl/") ? target : "xl/\(target)")
                    targetByRelID[id] = cleanTarget
                }
            }
        }

        var specs: [SheetSpec] = []
        if let wbDoc = try? XMLDocument(contentsOf: workbookURL, options: []),
           let root = wbDoc.rootElement(),
           let sheetsNode = OOXMLArchiveUtility.firstChild(of: root, localName: "sheets") {
            let sheetEls = OOXMLArchiveUtility.childElements(of: sheetsNode, localName: "sheet")
            for (idx, el) in sheetEls.enumerated() {
                let name = OOXMLArchiveUtility.attributeValue(of: el, localName: "name") ?? "Sheet\(idx + 1)"
                let relID = OOXMLArchiveUtility.relationshipID(of: el)
                let path = relID.flatMap { targetByRelID[$0] } ?? "xl/worksheets/sheet\(idx + 1).xml"
                specs.append(SheetSpec(name: name, archivePath: path))
            }
        }

        return specs
    }

    private static func parseSharedStrings(in rootDir: URL) -> [String] {
        let sstURL = rootDir.appendingPathComponent("xl/sharedStrings.xml")
        guard let doc = try? XMLDocument(contentsOf: sstURL, options: []),
              let root = doc.rootElement() else {
            return []
        }

        var result: [String] = []
        let items = OOXMLArchiveUtility.childElements(of: root, localName: "si")
        result.reserveCapacity(items.count)

        for si in items {
            if let t = OOXMLArchiveUtility.firstChild(of: si, localName: "t") {
                result.append(t.stringValue ?? "")
            } else {
                // Rich text runs (<r><t>...</t></r>)
                let runs = OOXMLArchiveUtility.childElements(of: si, localName: "r")
                let joined = runs.compactMap { OOXMLArchiveUtility.firstChild(of: $0, localName: "t")?.stringValue }.joined()
                result.append(joined)
            }
        }
        return result
    }

    private struct FontStyleInfo {
        var isBold = false
        var isItalic = false
        var colorHex: String? = nil
    }

    private static func parseCellStyles(in rootDir: URL) -> [Int: SpreadsheetCellStyle] {
        let stylesURL = rootDir.appendingPathComponent("xl/styles.xml")
        guard let doc = try? XMLDocument(contentsOf: stylesURL, options: []),
              let root = doc.rootElement() else {
            return [:]
        }

        var fonts: [FontStyleInfo] = []
        if let fontsEl = OOXMLArchiveUtility.firstChild(of: root, localName: "fonts") {
            for f in OOXMLArchiveUtility.childElements(of: fontsEl, localName: "font") {
                var info = FontStyleInfo()
                info.isBold = OOXMLArchiveUtility.firstChild(of: f, localName: "b") != nil
                info.isItalic = OOXMLArchiveUtility.firstChild(of: f, localName: "i") != nil
                if let colorEl = OOXMLArchiveUtility.firstChild(of: f, localName: "color"),
                   let rgb = OOXMLArchiveUtility.attributeValue(of: colorEl, localName: "rgb") {
                    info.colorHex = rgb
                }
                fonts.append(info)
            }
        }

        var fills: [String?] = []
        if let fillsEl = OOXMLArchiveUtility.firstChild(of: root, localName: "fills") {
            for fill in OOXMLArchiveUtility.childElements(of: fillsEl, localName: "fill") {
                var hex: String? = nil
                if let pattern = OOXMLArchiveUtility.firstChild(of: fill, localName: "patternFill"),
                   OOXMLArchiveUtility.attributeValue(of: pattern, localName: "patternType") == "solid",
                   let fg = OOXMLArchiveUtility.firstChild(of: pattern, localName: "fgColor"),
                   let rgb = OOXMLArchiveUtility.attributeValue(of: fg, localName: "rgb"),
                   rgb.uppercased() != "00000000" {
                    hex = rgb
                }
                fills.append(hex)
            }
        }

        var styleMap: [Int: SpreadsheetCellStyle] = [:]
        if let xfsEl = OOXMLArchiveUtility.firstChild(of: root, localName: "cellXfs") {
            let xfs = OOXMLArchiveUtility.childElements(of: xfsEl, localName: "xf")
            for (idx, xf) in xfs.enumerated() {
                var style = SpreadsheetCellStyle()
                if let fontIdStr = OOXMLArchiveUtility.attributeValue(of: xf, localName: "fontId"),
                   let fontId = Int(fontIdStr), fontId >= 0, fontId < fonts.count {
                    style.isBold = fonts[fontId].isBold
                    style.isItalic = fonts[fontId].isItalic
                    style.textColorHex = fonts[fontId].colorHex
                }
                if let fillIdStr = OOXMLArchiveUtility.attributeValue(of: xf, localName: "fillId"),
                   let fillId = Int(fillIdStr), fillId >= 0, fillId < fills.count {
                    style.fillColorHex = fills[fillId]
                }
                if let alignEl = OOXMLArchiveUtility.firstChild(of: xf, localName: "alignment"),
                   let horiz = OOXMLArchiveUtility.attributeValue(of: alignEl, localName: "horizontal") {
                    switch horiz.lowercased() {
                    case "center": style.alignment = .center
                    case "right": style.alignment = .trailing
                    default: style.alignment = .leading
                    }
                }
                if !style.isDefault {
                    styleMap[idx] = style
                }
            }
        }

        return styleMap
    }

    private static func parseWorksheet(
        at url: URL,
        sheetName: String,
        sharedStrings: [String],
        cellStyleMap: [Int: SpreadsheetCellStyle]
    ) -> SpreadsheetTableData {
        guard let doc = try? XMLDocument(contentsOf: url, options: []),
              let root = doc.rootElement(),
              let sheetData = OOXMLArchiveUtility.firstChild(of: root, localName: "sheetData") else {
            return SpreadsheetTableData(sheetName: sheetName, rows: [[""]])
        }

        var cellsByCoord: [SpreadsheetCellCoord: String] = [:]
        var formulas: [SpreadsheetCellCoord: String] = [:]
        var styles: [SpreadsheetCellCoord: SpreadsheetCellStyle] = [:]
        var maxRow = 0
        var maxCol = 0

        let rowEls = OOXMLArchiveUtility.childElements(of: sheetData, localName: "row")
        // Límite seguro para hojas con 1 millón de filas fantasma vacías
        let maxParsedRows = 15_000

        for (seqRowIdx, rowEl) in rowEls.enumerated() {
            if seqRowIdx >= maxParsedRows { break }
            let explicitRowNum = OOXMLArchiveUtility.attributeValue(of: rowEl, localName: "r").flatMap(Int.init)
            let rowIdx = max(0, (explicitRowNum ?? (seqRowIdx + 1)) - 1)
            if rowIdx >= maxParsedRows { continue }

            let cellEls = OOXMLArchiveUtility.childElements(of: rowEl, localName: "c")
            for (seqColIdx, cEl) in cellEls.enumerated() {
                let ref = OOXMLArchiveUtility.attributeValue(of: cEl, localName: "r") ?? ""
                let coord = parseCellReference(ref) ?? SpreadsheetCellCoord(row: rowIdx, col: seqColIdx)
                if coord.row >= maxParsedRows || coord.col >= 256 { continue }

                let typeAttr = OOXMLArchiveUtility.attributeValue(of: cEl, localName: "t") ?? ""
                let styleAttr = OOXMLArchiveUtility.attributeValue(of: cEl, localName: "s").flatMap(Int.init)

                if let fEl = OOXMLArchiveUtility.firstChild(of: cEl, localName: "f"),
                   let formulaBody = fEl.stringValue, !formulaBody.isEmpty {
                    formulas[coord] = formulaBody.hasPrefix("=") ? formulaBody : "=\(formulaBody)"
                }

                var valueText = ""
                if typeAttr == "s" {
                    if let vStr = OOXMLArchiveUtility.firstChild(of: cEl, localName: "v")?.stringValue,
                       let idx = Int(vStr), idx >= 0, idx < sharedStrings.count {
                        valueText = sharedStrings[idx]
                    }
                } else if typeAttr == "inlineStr" {
                    if let isEl = OOXMLArchiveUtility.firstChild(of: cEl, localName: "is") {
                        if let t = OOXMLArchiveUtility.firstChild(of: isEl, localName: "t") {
                            valueText = t.stringValue ?? ""
                        } else {
                            let runs = OOXMLArchiveUtility.childElements(of: isEl, localName: "r")
                            valueText = runs.compactMap { OOXMLArchiveUtility.firstChild(of: $0, localName: "t")?.stringValue }.joined()
                        }
                    }
                } else if typeAttr == "b" {
                    let vStr = OOXMLArchiveUtility.firstChild(of: cEl, localName: "v")?.stringValue ?? "0"
                    valueText = (vStr == "1") ? "TRUE" : "FALSE"
                } else {
                    valueText = OOXMLArchiveUtility.firstChild(of: cEl, localName: "v")?.stringValue ?? ""
                }

                if valueText.isEmpty, let formula = formulas[coord] {
                    valueText = formula
                }

                if !valueText.isEmpty || formulas[coord] != nil {
                    cellsByCoord[coord] = valueText
                    maxRow = max(maxRow, coord.row)
                    maxCol = max(maxCol, coord.col)
                }

                if let styleIdx = styleAttr, let style = cellStyleMap[styleIdx] {
                    styles[coord] = style
                }
            }
        }

        let rowCount = max(1, maxRow + 1)
        let colCount = max(1, maxCol + 1)
        var matrix = Array(repeating: Array(repeating: "", count: colCount), count: rowCount)
        for (coord, val) in cellsByCoord where coord.row < rowCount && coord.col < colCount {
            matrix[coord.row][coord.col] = val
        }

        return SpreadsheetTableData(
            sheetName: sheetName,
            rows: matrix,
            formulas: formulas,
            styles: styles
        )
    }

    public static func parseCellReference(_ ref: String) -> SpreadsheetCellCoord? {
        guard !ref.isEmpty else { return nil }
        var letters = ""
        var digits = ""
        for ch in ref {
            if ch.isLetter {
                letters.append(ch)
            } else if ch.isNumber {
                digits.append(ch)
            }
        }
        guard let col = SpreadsheetTableData.excelColumnIndex(from: letters),
              let rowOneBased = Int(digits), rowOneBased >= 1 else {
            return nil
        }
        return SpreadsheetCellCoord(row: rowOneBased - 1, col: col)
    }

    // MARK: - Re-escritura Segura de Hoja XML al Guardar (.xlsx)

    private static func rewriteWorksheetXML(at sheetURL: URL, with table: SpreadsheetTableData) throws {
        let doc = try XMLDocument(contentsOf: sheetURL, options: [.nodePreserveAll])
        guard let root = doc.rootElement() else { return }

        // Preservar mapa de atributos `s="..."` (estilo original de cada celda) antes de regenerar `<sheetData>`
        var existingStyleAttrByRef: [String: String] = [:]
        if let oldSheetData = OOXMLArchiveUtility.firstChild(of: root, localName: "sheetData") {
            for rowEl in OOXMLArchiveUtility.childElements(of: oldSheetData, localName: "row") {
                for cEl in OOXMLArchiveUtility.childElements(of: rowEl, localName: "c") {
                    if let ref = OOXMLArchiveUtility.attributeValue(of: cEl, localName: "r"),
                       let s = OOXMLArchiveUtility.attributeValue(of: cEl, localName: "s") {
                        existingStyleAttrByRef[ref] = s
                    }
                }
            }
        }

        // Construir nuevo `<sheetData>` limpio con inlineStr / numérico / fórmulas
        var xmlRows = "<sheetData>"
        for (rIdx, row) in table.rows.enumerated() {
            var cellsXML = ""
            let excelRow = rIdx + 1
            for (cIdx, val) in row.enumerated() {
                let coord = SpreadsheetCellCoord(row: rIdx, col: cIdx)
                let formula = table.formulas[coord]
                if val.isEmpty && formula == nil { continue }

                let ref = "\(SpreadsheetTableData.excelColumnName(for: cIdx))\(excelRow)"
                let styleFragment = existingStyleAttrByRef[ref].map { " s=\"\($0)\"" } ?? ""

                if let formula, !formula.isEmpty {
                    let cleanFormula = formula.hasPrefix("=") ? String(formula.dropFirst()) : formula
                    let escapedFormula = OOXMLArchiveUtility.xmlEscape(cleanFormula)
                    if let numVal = Double(val), numVal.isFinite {
                        cellsXML += "<c r=\"\(ref)\"\(styleFragment)><f>\(escapedFormula)</f><v>\(val)</v></c>"
                    } else {
                        cellsXML += "<c r=\"\(ref)\"\(styleFragment)><f>\(escapedFormula)</f></c>"
                    }
                } else if val == "TRUE" || val == "FALSE" {
                    cellsXML += "<c r=\"\(ref)\"\(styleFragment) t=\"b\"><v>\(val == "TRUE" ? "1" : "0")</v></c>"
                } else if let numVal = Double(val.trimmingCharacters(in: .whitespaces)),
                          numVal.isFinite,
                          !val.hasPrefix("0") || val == "0" || val.hasPrefix("0.") {
                    cellsXML += "<c r=\"\(ref)\"\(styleFragment)><v>\(val.trimmingCharacters(in: .whitespaces))</v></c>"
                } else {
                    let escaped = OOXMLArchiveUtility.xmlEscape(val)
                    cellsXML += "<c r=\"\(ref)\"\(styleFragment) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped)</t></is></c>"
                }
            }
            if !cellsXML.isEmpty {
                xmlRows += "<row r=\"\(excelRow)\">\(cellsXML)</row>"
            }
        }
        xmlRows += "</sheetData>"

        let newSheetDataDoc = try XMLDocument(xmlString: xmlRows, options: [])
        guard let newSheetDataEl = newSheetDataDoc.rootElement()?.copy() as? XMLElement else { return }

        if let oldSheetData = OOXMLArchiveUtility.firstChild(of: root, localName: "sheetData"),
           let oldIndex = root.children?.firstIndex(of: oldSheetData) {
            root.replaceChild(at: oldIndex, with: newSheetDataEl)
        } else {
            root.addChild(newSheetDataEl)
        }

        // Actualizar `<dimension ref="A1:..."/>` si existe
        if let dimEl = OOXMLArchiveUtility.firstChild(of: root, localName: "dimension") {
            let lastCol = SpreadsheetTableData.excelColumnName(for: max(0, table.columnCount - 1))
            let lastRow = max(1, table.rows.count)
            dimEl.removeAttribute(forName: "ref")
            if let attr = XMLNode.attribute(withName: "ref", stringValue: "A1:\(lastCol)\(lastRow)") as? XMLNode {
                dimEl.addAttribute(attr)
            }
        }

        let xmlData = doc.xmlData(options: [.nodePreserveAll])
        try xmlData.write(to: sheetURL, options: .atomic)
    }
}
