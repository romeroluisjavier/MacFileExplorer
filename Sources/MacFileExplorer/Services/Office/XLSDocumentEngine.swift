import Foundation

// MARK: - Estrategia de Vista Original Inteligente para Excel (.xlsx / .xls)

public enum ExcelOriginalPreviewSource: Sendable, Equatable {
    /// Archivo binario nativo (.xlsx OOXML o .xls OLE2/BIFF8) que `QLPreviewView` renderiza fielmente.
    case nativeQuickLook(URL)
    /// Archivo `.xls`/`.xlsx` basado en HTML, SpreadsheetML XML o texto delimitado (que `QLPreviewView` muestra en blanco),
    /// renderizado fielmente en un visor HTML local sin conexión.
    case htmlDocument(String)
}

// MARK: - Motor Nativo para Microsoft Excel 97–2003 (.xls — OLE2/BIFF8, BIFF5, SpreadsheetML XML y HTML-XLS)

public enum XLSDocumentEngine {

    private static let ole2Signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    private static let zipSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]

    /// Inspecciona la firma real del archivo `.xls` / `.xlsx` para elegir la mejor Vista Original:
    /// - Binario real OOXML (`.xlsx`) u OLE2/BIFF8 (`.xls`) → Quick Look nativo de macOS.
    /// - HTML `<table>` guardado como `.xls` (ej. exportaciones bancarias/ERP/Odoo), XML SpreadsheetML o TSV →
    ///   documento HTML local estilizado que renderiza la tabla fiel al original (evitando la hoja blanca de `QLPreviewView`).
    public static func resolveOriginalPreviewSource(for url: URL) -> ExcelOriginalPreviewSource {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .nativeQuickLook(url)
        }
        let bytes = [UInt8](data.prefix(512))

        // 1. Paquete ZIP OOXML (.xlsx real)
        if bytes.count >= 4 && Array(bytes[0..<4]) == zipSignature {
            if url.pathExtension.lowercased() == "xlsx" {
                return .nativeQuickLook(url)
            }
            // `.xlsx` renombrado a `.xls`: crear copia temporal con extensión `.xlsx` para que Quick Look lo reconozca
            let tempCopy = FileManager.default.temporaryDirectory
                .appendingPathComponent("mfe_ql_\(url.deletingPathExtension().lastPathComponent)_\(abs(url.path.hashValue)).xlsx")
            if !FileManager.default.fileExists(atPath: tempCopy.path(percentEncoded: false)) {
                try? data.write(to: tempCopy, options: .atomic)
            }
            return .nativeQuickLook(tempCopy)
        }

        // 2. Contenedor binario OLE2 CFBF (Excel 97–2003 real) o stream BIFF2–4
        if bytes.count >= 8 && Array(bytes[0..<8]) == ole2Signature {
            return .nativeQuickLook(url)
        }
        if bytes.count >= 8 {
            let recType = readUInt16LE(bytes, at: 0)
            if recType == 0x0009 || recType == 0x0209 || recType == 0x0409 || recType == 0x0809 {
                return .nativeQuickLook(url)
            }
        }

        // 3. Archivo de texto (HTML <table>, SpreadsheetML XML o TSV/CSV guardado como .xls/.xlsx)
        let (decodedText, _) = CSVDocumentEngine.decodeText(from: data)
        let sampleLower = decodedText.prefix(4096).lowercased()

        if sampleLower.contains("<table") || sampleLower.contains("<html") || sampleLower.contains("<!doctype") {
            return .htmlDocument(buildStyledHTMLDocument(wrapping: decodedText))
        }

        if let workbook = try? load(from: url) {
            return .htmlDocument(buildWorkbookHTML(from: workbook))
        }

        return .nativeQuickLook(url)
    }

    /// Envuelve un fragmento o documento HTML exportado como `.xls` en una hoja HTML5 limpia estilo Excel
    /// preservando estilos propios, `colspan`, `rowspan`, encabezados y saltos de línea.
    public static func buildStyledHTMLDocument(wrapping rawHTML: String) -> String {
        let baseCSS = """
        <style id="mfe-excel-preview-style">
          :root { color-scheme: light; }
          * { box-sizing: border-box; }
          html, body {
            margin: 0;
            padding: 14px 16px;
            background: #ffffff;
            color: #1f2328;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
            font-size: 12.5px;
            line-height: 1.42;
          }
          table {
            border-collapse: collapse;
            width: max-content;
            min-width: 100%;
            margin-bottom: 18px;
            background: #ffffff;
            border: 1px solid #d0d7de;
          }
          thead th, th {
            background: #f3f6fa;
            color: #1f2328;
            font-weight: 600;
            text-align: left;
            padding: 7px 10px;
            border: 1px solid #d0d7de;
            white-space: nowrap;
            position: sticky;
            top: 0;
            z-index: 2;
          }
          td {
            padding: 6px 10px;
            border: 1px solid #e1e6ec;
            vertical-align: top;
            white-space: pre-wrap;
          }
          tbody tr:nth-child(even) {
            background: #fafbfc;
          }
          tbody tr:hover {
            background: #eef5ff;
          }
        </style>
        """

        let lower = rawHTML.lowercased()
        if lower.contains("<head") {
            if let range = rawHTML.range(of: "</head>", options: .caseInsensitive) {
                var result = rawHTML
                result.insert(contentsOf: "\n<meta charset=\"utf-8\">\n\(baseCSS)\n", at: range.lowerBound)
                return result
            }
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          \(baseCSS)
        </head>
        <body>
        \(rawHTML)
        </body>
        </html>
        """
    }

    /// Genera una vista HTML fiel y de solo lectura para libros XML SpreadsheetML o texto delimitado `.xls`.
    public static func buildWorkbookHTML(from workbook: XLSXWorkbookModel) -> String {
        var body = ""
        for sheet in workbook.sheets {
            if workbook.sheets.count > 1 {
                body += "<h3 style=\"margin: 6px 0 8px 0; font-size: 13px; color: #1b6e41;\">\(OOXMLArchiveUtility.xmlEscape(sheet.name))</h3>\n"
            }
            body += "<table><tbody>\n"
            for (rIdx, row) in sheet.table.rows.enumerated() {
                body += "<tr>"
                for (cIdx, val) in row.enumerated() {
                    let style = sheet.table.styles[SpreadsheetCellCoord(row: rIdx, col: cIdx)]
                    let tag = (rIdx == 0 && (style?.isBold == true || workbook.sheets.count == 1)) ? "th" : "td"
                    let escaped = OOXMLArchiveUtility.xmlEscape(val).replacingOccurrences(of: "\n", with: "<br>")
                    body += "<\(tag)>\(escaped)</\(tag)>"
                }
                body += "</tr>\n"
            }
            body += "</tbody></table>\n"
        }
        return buildStyledHTMLDocument(wrapping: body)
    }

    /// Carga cualquier archivo `.xls` real del mundo:
    /// 1. Excel 97–2003 binario (OLE2 Compound File + BIFF8 / BIFF5)
    /// 2. Stream BIFF2/3/4 sin contenedor OLE2
    /// 3. `.xlsx` renombrado a `.xls` (firma ZIP `PK\x03\x04`)
    /// 4. Excel 2003 SpreadsheetML XML (`<Workbook ...><Worksheet ...>`)
    /// 5. Exportaciones de bancos/ERPs en HTML `<table>` con extensión `.xls`
    /// 6. Texto delimitado (TSV/CSV) guardado con extensión `.xls`
    public static func load(from url: URL) throws -> XLSXWorkbookModel {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let bytes = [UInt8](data)

        // 1. ¿Es en realidad un .xlsx (ZIP) renombrado a .xls?
        if bytes.count >= 4 && Array(bytes[0..<4]) == zipSignature {
            return try XLSXDocumentEngine.load(from: url)
        }

        // 2. Contenedor binario OLE2 CFBF (Excel 97–2003 BIFF8 / Excel 5–95 BIFF5)
        if bytes.count >= 512 && Array(bytes[0..<8]) == ole2Signature {
            let reader = try OLE2CompoundFileReader(bytes: bytes)
            guard let stream = reader.extractWorkbookStream() else {
                throw xlsError("No se encontró el flujo 'Workbook' dentro del archivo .xls.")
            }
            let sheets = try BIFFWorkbookParser(bytes: stream).parse()
            return XLSXWorkbookModel(sourceURL: url, sheets: sheets)
        }

        // 3. Stream BIFF directo sin contenedor OLE2 (Excel 2.x–4.x)
        if bytes.count >= 8 {
            let recType = readUInt16LE(bytes, at: 0)
            if recType == 0x0009 || recType == 0x0209 || recType == 0x0409 || recType == 0x0809 {
                let sheets = try BIFFWorkbookParser(bytes: bytes).parse()
                return XLSXWorkbookModel(sourceURL: url, sheets: sheets)
            }
        }

        // 4. Formatos basados en texto (Excel 2003 XML SpreadsheetML, HTML <table> .xls, o TSV/CSV)
        let (decodedText, _) = CSVDocumentEngine.decodeText(from: data)
        let sampleLower = decodedText.prefix(4096).lowercased()

        if sampleLower.contains("<workbook") && sampleLower.contains("<worksheet") {
            let sheets = try parseSpreadsheetMLXML(data: data, fallbackName: url.deletingPathExtension().lastPathComponent)
            if !sheets.isEmpty {
                return XLSXWorkbookModel(sourceURL: url, sheets: sheets)
            }
        }

        if sampleLower.contains("<table") && sampleLower.contains("<tr") {
            let sheets = parseHTMLTableXLS(decodedText, fallbackName: url.deletingPathExtension().lastPathComponent)
            if !sheets.isEmpty {
                return XLSXWorkbookModel(sourceURL: url, sheets: sheets)
            }
        }

        // 5. Fallback para exportaciones de texto delimitado renombradas a .xls
        if !decodedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let loadedCSV = try CSVDocumentEngine.load(from: url)
            let sheet = XLSXSheetModel(
                id: "xls-sheet-0",
                name: url.deletingPathExtension().lastPathComponent,
                archivePath: "xls/sheet0",
                table: loadedCSV.table,
                isModified: false
            )
            return XLSXWorkbookModel(sourceURL: url, sheets: [sheet])
        }

        throw xlsError("Formato .xls no reconocido o archivo vacío.")
    }

    /// Guarda un `XLSXWorkbookModel` en disco:
    /// - Si el destino termina en `.xlsx`, genera un libro OOXML `.xlsx` completo.
    /// - Si el destino termina en `.xls`, genera un archivo binario OLE2 + BIFF8 válido (Excel 97–2003).
    public static func save(workbook: XLSXWorkbookModel, to destinationURL: URL) throws {
        if destinationURL.pathExtension.lowercased() == "xlsx" {
            try XLSXDocumentEngine.createNew(workbook: workbook, to: destinationURL)
            return
        }
        let biffStream = BIFF8WorkbookWriter.buildWorkbookStream(from: workbook)
        let ole2Data = OLE2CompoundFileWriter.pack(workbookStream: biffStream)
        try ole2Data.write(to: destinationURL, options: .atomic)
    }

    fileprivate static func xlsError(_ message: String) -> NSError {
        NSError(
            domain: "MacFileExplorer.XLS",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    // MARK: - Helpers Little-Endian

    @inline(__always)
    fileprivate static func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        guard offset >= 0 && offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    @inline(__always)
    fileprivate static func readInt16LE(_ bytes: [UInt8], at offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16LE(bytes, at: offset))
    }

    @inline(__always)
    fileprivate static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        guard offset >= 0 && offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    @inline(__always)
    fileprivate static func readInt32LE(_ bytes: [UInt8], at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32LE(bytes, at: offset))
    }

    @inline(__always)
    fileprivate static func readUInt64LE(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        let lo = UInt64(readUInt32LE(bytes, at: offset))
        let hi = UInt64(readUInt32LE(bytes, at: offset + 4))
        return lo | (hi << 32)
    }

    @inline(__always)
    fileprivate static func readDoubleLE(_ bytes: [UInt8], at offset: Int) -> Double {
        Double(bitPattern: readUInt64LE(bytes, at: offset))
    }

    @inline(__always)
    fileprivate static func appendUInt16LE(_ value: UInt16, to out: inout [UInt8]) {
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
    }

    @inline(__always)
    fileprivate static func appendUInt32LE(_ value: UInt32, to out: inout [UInt8]) {
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
        out.append(UInt8((value >> 16) & 0xFF))
        out.append(UInt8((value >> 24) & 0xFF))
    }

    @inline(__always)
    fileprivate static func appendUInt64LE(_ value: UInt64, to out: inout [UInt8]) {
        appendUInt32LE(UInt32(value & 0xFFFF_FFFF), to: &out)
        appendUInt32LE(UInt32((value >> 32) & 0xFFFF_FFFF), to: &out)
    }

    @inline(__always)
    fileprivate static func appendDoubleLE(_ value: Double, to out: inout [UInt8]) {
        appendUInt64LE(value.bitPattern, to: &out)
    }

    // MARK: - Parser de Excel 2003 XML (SpreadsheetML)

    private static func parseSpreadsheetMLXML(data: Data, fallbackName: String) throws -> [XLSXSheetModel] {
        let doc = try XMLDocument(data: data, options: [])
        guard let root = doc.rootElement() else { return [] }

        let worksheets = OOXMLArchiveUtility.childElements(of: root, localName: "Worksheet")
        var result: [XLSXSheetModel] = []

        for (idx, ws) in worksheets.enumerated() {
            let name = OOXMLArchiveUtility.attributeValue(of: ws, localName: "Name")
                ?? (worksheets.count == 1 ? fallbackName : "Sheet\(idx + 1)")
            var rows: [[String]] = []
            var formulas: [SpreadsheetCellCoord: String] = [:]

            if let tableEl = OOXMLArchiveUtility.firstChild(of: ws, localName: "Table") {
                var currentRow = 0
                for rowEl in OOXMLArchiveUtility.childElements(of: tableEl, localName: "Row") {
                    if let explicitRow = OOXMLArchiveUtility.attributeValue(of: rowEl, localName: "Index").flatMap(Int.init),
                       explicitRow > 0 {
                        currentRow = explicitRow - 1
                    }
                    while rows.count <= currentRow { rows.append([]) }

                    var currentCol = 0
                    for cellEl in OOXMLArchiveUtility.childElements(of: rowEl, localName: "Cell") {
                        if let explicitCol = OOXMLArchiveUtility.attributeValue(of: cellEl, localName: "Index").flatMap(Int.init),
                           explicitCol > 0 {
                            currentCol = explicitCol - 1
                        }
                        while rows[currentRow].count <= currentCol { rows[currentRow].append("") }

                        let text = OOXMLArchiveUtility.firstChild(of: cellEl, localName: "Data")?.stringValue ?? ""
                        rows[currentRow][currentCol] = text

                        if let formula = OOXMLArchiveUtility.attributeValue(of: cellEl, localName: "Formula"),
                           !formula.isEmpty {
                            formulas[SpreadsheetCellCoord(row: currentRow, col: currentCol)] =
                                formula.hasPrefix("=") ? formula : "=\(formula)"
                        }
                        currentCol += 1
                    }
                    currentRow += 1
                }
            }

            let table = SpreadsheetTableData(
                sheetName: name,
                rows: rows.isEmpty ? [[""]] : rows,
                formulas: formulas
            )
            result.append(XLSXSheetModel(
                id: "xls-xml-\(idx)",
                name: name,
                archivePath: "xls/sheet\(idx)",
                table: table
            ))
        }

        return result
    }

    // MARK: - Parser de HTML Table .xls (Bancos / ERPs / Portales Web)

    private static func parseHTMLTableXLS(_ html: String, fallbackName: String) -> [XLSXSheetModel] {
        // Extraer cada <table> ... </table> como hoja independiente si hay múltiples tablas con filas
        let tableRegex = try? NSRegularExpression(pattern: "(?is)<table\\b[^>]*>(.*?)</table>")
        let theadRegex = try? NSRegularExpression(pattern: "(?is)<thead\\b[^>]*>(.*?)</thead>")
        let rowRegex = try? NSRegularExpression(pattern: "(?is)<tr\\b[^>]*>(.*?)</tr>")
        let cellRegex = try? NSRegularExpression(pattern: "(?is)<(t[hd])\\b([^>]*)>(.*?)</\\1>")
        let colspanRegex = try? NSRegularExpression(pattern: "(?i)colspan\\s*=\\s*[\"']?(\\d+)")
        let tagStripRegex = try? NSRegularExpression(pattern: "(?is)<[^>]+>")
        let brRegex = try? NSRegularExpression(pattern: "(?i)<br\\s*/?>")

        let nsHTML = html as NSString
        let tableMatches = tableRegex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []
        let tableBodies: [String] = tableMatches.isEmpty
            ? [html]
            : tableMatches.map { nsHTML.substring(with: $0.range(at: 1)) }

        var sheets: [XLSXSheetModel] = []

        for (tIdx, rawBody) in tableBodies.enumerated() {
            // Normalizar `<thead><th>...</th></thead>` sin `<tr>` explícito (común en exportaciones HTML5 de ERPs)
            var body = rawBody
            if let theadRegex {
                let nsRaw = body as NSString
                let theadMatches = theadRegex.matches(in: body, range: NSRange(location: 0, length: nsRaw.length))
                for match in theadMatches.reversed() {
                    let inner = nsRaw.substring(with: match.range(at: 1))
                    let lowerInner = inner.lowercased()
                    if !lowerInner.contains("<tr") && (lowerInner.contains("<th") || lowerInner.contains("<td")) {
                        body = (body as NSString).replacingCharacters(in: match.range(at: 1), with: "<tr>\(inner)</tr>")
                    }
                }
            }

            let nsBody = body as NSString
            let rowMatches = rowRegex?.matches(in: body, range: NSRange(location: 0, length: nsBody.length)) ?? []
            var rows: [[String]] = []
            var styles: [SpreadsheetCellCoord: SpreadsheetCellStyle] = [:]

            for rMatch in rowMatches {
                let rowContent = nsBody.substring(with: rMatch.range(at: 1))
                let nsRow = rowContent as NSString
                let cellMatches = cellRegex?.matches(in: rowContent, range: NSRange(location: 0, length: nsRow.length)) ?? []
                guard !cellMatches.isEmpty else { continue }

                let rIdx = rows.count
                var rowValues: [String] = []
                for cMatch in cellMatches {
                    let tagName = nsRow.substring(with: cMatch.range(at: 1)).lowercased()
                    let attrs = nsRow.substring(with: cMatch.range(at: 2))
                    var rawInner = nsRow.substring(with: cMatch.range(at: 3))

                    if let brRegex {
                        rawInner = brRegex.stringByReplacingMatches(
                            in: rawInner,
                            range: NSRange(location: 0, length: (rawInner as NSString).length),
                            withTemplate: "\n"
                        )
                    }
                    if let tagStripRegex {
                        rawInner = tagStripRegex.stringByReplacingMatches(
                            in: rawInner,
                            range: NSRange(location: 0, length: (rawInner as NSString).length),
                            withTemplate: ""
                        )
                    }
                    let cleanValue = decodeHTMLEntities(rawInner)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    let cIdx = rowValues.count
                    rowValues.append(cleanValue)
                    if tagName == "th" {
                        styles[SpreadsheetCellCoord(row: rIdx, col: cIdx)] = SpreadsheetCellStyle(isBold: true)
                    }

                    if let colspanRegex,
                       let spanMatch = colspanRegex.firstMatch(in: attrs, range: NSRange(location: 0, length: (attrs as NSString).length)),
                       let spanCount = Int((attrs as NSString).substring(with: spanMatch.range(at: 1))),
                       spanCount > 1 {
                        for _ in 1..<min(spanCount, 32) {
                            rowValues.append("")
                        }
                    }
                }
                rows.append(rowValues)
            }

            guard !rows.isEmpty else { continue }
            let name = tableBodies.count == 1 ? fallbackName : "\(fallbackName) \(tIdx + 1)"
            let table = SpreadsheetTableData(sheetName: name, rows: rows, styles: styles)
            sheets.append(XLSXSheetModel(
                id: "xls-html-\(tIdx)",
                name: name,
                archivePath: "xls/sheet\(tIdx)",
                table: table
            ))
        }

        return sheets
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        // Entidades numéricas decimales (&#225;) y hexadecimales (&#xE1;)
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|\\d+);") {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let token = ns.substring(with: match.range(at: 1))
                let codePoint: UInt32? = token.lowercased().hasPrefix("x")
                    ? UInt32(token.dropFirst(), radix: 16)
                    : UInt32(token)
                if let cp = codePoint, let scalar = UnicodeScalar(cp) {
                    result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
                }
            }
        }
        return result
    }
}

// MARK: - Lector de Contenedor OLE2 Compound File Binary Format (MS-CFB)

private struct OLE2CompoundFileReader {
    private static let endOfChain: UInt32 = 0xFFFF_FFFE
    private static let freeSect: UInt32 = 0xFFFF_FFFF

    let bytes: [UInt8]
    let sectorSize: Int
    let miniSectorSize: Int
    let miniCutoff: Int
    let dirFirstSector: UInt32
    let miniFatFirstSector: UInt32
    let fat: [UInt32]
    let miniFat: [UInt32]

    struct DirectoryEntry {
        let name: String
        let objectType: UInt8   // 1=storage, 2=stream, 5=root
        let startSector: UInt32
        let streamSize: UInt64
    }

    init(bytes: [UInt8]) throws {
        guard bytes.count >= 512 else {
            throw XLSDocumentEngine.xlsError("Archivo OLE2 demasiado corto.")
        }
        self.bytes = bytes

        let sectorShift = Int(XLSDocumentEngine.readUInt16LE(bytes, at: 30))
        let miniSectorShift = Int(XLSDocumentEngine.readUInt16LE(bytes, at: 32))
        guard sectorShift >= 7 && sectorShift <= 16 else {
            throw XLSDocumentEngine.xlsError("Tamaño de sector OLE2 inválido (\(sectorShift)).")
        }
        self.sectorSize = 1 << sectorShift
        self.miniSectorSize = 1 << min(max(miniSectorShift, 4), 12)
        self.dirFirstSector = XLSDocumentEngine.readUInt32LE(bytes, at: 48)
        self.miniCutoff = Int(XLSDocumentEngine.readUInt32LE(bytes, at: 56))
        self.miniFatFirstSector = XLSDocumentEngine.readUInt32LE(bytes, at: 60)
        let numMiniFatSectors = Int(XLSDocumentEngine.readUInt32LE(bytes, at: 64))
        let difatFirstSector = XLSDocumentEngine.readUInt32LE(bytes, at: 68)
        let numDifatSectors = Int(XLSDocumentEngine.readUInt32LE(bytes, at: 72))

        // 1. Reunir todos los sectores FAT desde los 109 inline en header + cadena DIFAT
        var fatSectorIDs: [UInt32] = []
        fatSectorIDs.reserveCapacity(128)
        for i in 0..<109 {
            let sid = XLSDocumentEngine.readUInt32LE(bytes, at: 76 + i * 4)
            if sid < 0xFFFF_FFFC {
                fatSectorIDs.append(sid)
            }
        }

        var currentDifat = difatFirstSector
        var difatVisited = Set<UInt32>()
        var remainingDifat = numDifatSectors
        let entriesPerDifat = (sectorSize / 4) - 1
        while remainingDifat > 0 && currentDifat < 0xFFFF_FFFC && !difatVisited.contains(currentDifat) {
            difatVisited.insert(currentDifat)
            let base = (Int(currentDifat) + 1) * sectorSize
            guard base + sectorSize <= bytes.count else { break }
            for i in 0..<entriesPerDifat {
                let sid = XLSDocumentEngine.readUInt32LE(bytes, at: base + i * 4)
                if sid < 0xFFFF_FFFC {
                    fatSectorIDs.append(sid)
                }
            }
            currentDifat = XLSDocumentEngine.readUInt32LE(bytes, at: base + entriesPerDifat * 4)
            remainingDifat -= 1
        }

        // 2. Construir tabla FAT completa
        var fatTable: [UInt32] = []
        fatTable.reserveCapacity(fatSectorIDs.count * (sectorSize / 4))
        for fatSID in fatSectorIDs {
            let base = (Int(fatSID) + 1) * sectorSize
            guard base + sectorSize <= bytes.count else { continue }
            let count = sectorSize / 4
            for i in 0..<count {
                fatTable.append(XLSDocumentEngine.readUInt32LE(bytes, at: base + i * 4))
            }
        }
        self.fat = fatTable

        // 3. Construir tabla Mini-FAT si existe
        var miniFatTable: [UInt32] = []
        if miniFatFirstSector < 0xFFFF_FFFC && numMiniFatSectors > 0 {
            let miniFatBytes = Self.readSectorChain(
                start: miniFatFirstSector,
                fat: fatTable,
                bytes: bytes,
                sectorSize: sectorSize,
                maxBytes: numMiniFatSectors * sectorSize
            )
            let count = miniFatBytes.count / 4
            miniFatTable.reserveCapacity(count)
            for i in 0..<count {
                miniFatTable.append(XLSDocumentEngine.readUInt32LE(miniFatBytes, at: i * 4))
            }
        }
        self.miniFat = miniFatTable
    }

    func extractWorkbookStream() -> [UInt8]? {
        let dirBytes = Self.readSectorChain(
            start: dirFirstSector,
            fat: fat,
            bytes: bytes,
            sectorSize: sectorSize,
            maxBytes: nil
        )
        let entryCount = dirBytes.count / 128
        var entries: [DirectoryEntry] = []
        entries.reserveCapacity(entryCount)

        for i in 0..<entryCount {
            let base = i * 128
            let nameLen = Int(XLSDocumentEngine.readUInt16LE(dirBytes, at: base + 64))
            let objType = dirBytes[base + 66]
            guard objType != 0, nameLen >= 2, nameLen <= 64 else { continue }

            let charCount = (nameLen / 2) - 1
            var codeUnits: [UInt16] = []
            codeUnits.reserveCapacity(max(0, charCount))
            for c in 0..<max(0, charCount) {
                codeUnits.append(XLSDocumentEngine.readUInt16LE(dirBytes, at: base + c * 2))
            }
            let name = String(decoding: codeUnits, as: UTF16.self)
            let startSect = XLSDocumentEngine.readUInt32LE(dirBytes, at: base + 116)
            let sizeLo = UInt64(XLSDocumentEngine.readUInt32LE(dirBytes, at: base + 120))
            let sizeHi = sectorSize == 4096 ? UInt64(XLSDocumentEngine.readUInt32LE(dirBytes, at: base + 124)) : 0
            let size = sizeLo | (sizeHi << 32)
            entries.append(DirectoryEntry(name: name, objectType: objType, startSector: startSect, streamSize: size))
        }

        let rootEntry = entries.first(where: { $0.objectType == 5 })
        // Preferir "Workbook" (BIFF8) y si no existe, "Book" (BIFF5/7)
        let targetEntry = entries.first(where: { $0.objectType == 2 && $0.name.caseInsensitiveCompare("Workbook") == .orderedSame })
            ?? entries.first(where: { $0.objectType == 2 && $0.name.caseInsensitiveCompare("Book") == .orderedSame })

        guard let target = targetEntry else { return nil }
        let expectedSize = Int(min(target.streamSize, 128_000_000))

        if expectedSize < miniCutoff, let root = rootEntry, root.startSector < 0xFFFF_FFFC {
            let miniContainer = Self.readSectorChain(
                start: root.startSector,
                fat: fat,
                bytes: bytes,
                sectorSize: sectorSize,
                maxBytes: Int(min(root.streamSize, 64_000_000))
            )
            return readMiniStream(start: target.startSector, size: expectedSize, container: miniContainer)
        }

        return Self.readSectorChain(
            start: target.startSector,
            fat: fat,
            bytes: bytes,
            sectorSize: sectorSize,
            maxBytes: expectedSize
        )
    }

    private func readMiniStream(start: UInt32, size: Int, container: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(size)
        var current = start
        var visited = Set<UInt32>()

        while current < 0xFFFF_FFFC && !visited.contains(current) && result.count < size {
            visited.insert(current)
            let offset = Int(current) * miniSectorSize
            guard offset >= 0 && offset < container.count else { break }
            let end = min(offset + miniSectorSize, container.count)
            result.append(contentsOf: container[offset..<end])
            let idx = Int(current)
            guard idx >= 0 && idx < miniFat.count else { break }
            current = miniFat[idx]
        }

        if result.count > size {
            result.removeLast(result.count - size)
        }
        return result
    }

    private static func readSectorChain(
        start: UInt32,
        fat: [UInt32],
        bytes: [UInt8],
        sectorSize: Int,
        maxBytes: Int?
    ) -> [UInt8] {
        var result: [UInt8] = []
        if let maxBytes { result.reserveCapacity(min(maxBytes, bytes.count)) }
        var current = start
        var visited = Set<UInt32>()

        while current < 0xFFFF_FFFC && !visited.contains(current) {
            visited.insert(current)
            let offset = (Int(current) + 1) * sectorSize
            guard offset >= 0 && offset < bytes.count else { break }
            let end = min(offset + sectorSize, bytes.count)
            result.append(contentsOf: bytes[offset..<end])
            if let maxBytes, result.count >= maxBytes {
                if result.count > maxBytes {
                    result.removeLast(result.count - maxBytes)
                }
                break
            }
            let idx = Int(current)
            guard idx >= 0 && idx < fat.count else { break }
            current = fat[idx]
        }

        return result
    }
}

// MARK: - Parser de Registros BIFF8 / BIFF5 (Workbook + Worksheets + SST + Estilos + Fechas)

private final class BIFFWorkbookParser {
    private let bytes: [UInt8]

    private var isBIFF8: Bool = true
    private var stringEncoding: String.Encoding = .windowsCP1252
    private var is1904DateMode: Bool = false

    private struct BoundSheetInfo {
        let offset: Int
        let name: String
        let sheetType: UInt8
    }

    private struct FontInfo {
        let isBold: Bool
        let isItalic: Bool
        let colorIndex: Int
    }

    private struct XFInfo {
        let fontIndex: Int
        let formatIndex: Int
        let alignment: SpreadsheetCellAlignment
        let fillColorIndex: Int?
    }

    private var boundSheets: [BoundSheetInfo] = []
    private var sharedStrings: [String] = []
    private var customFormats: [Int: String] = [:]
    private var fonts: [FontInfo] = []
    private var xfs: [XFInfo] = []
    private var customPalette: [Int: String] = [:]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    func parse() throws -> [XLSXSheetModel] {
        // 1. Parsear Workbook Globals (desde byte 0 hasta primer EOF 0x000A)
        try parseWorkbookGlobals()

        // 2. Parsear cada hoja de cálculo declarada en BOUNDSHEET (solo hojas tipo 0x00 = Worksheet)
        let worksheetDefs = boundSheets.filter { $0.sheetType == 0x00 }
        var sheets: [XLSXSheetModel] = []

        if worksheetDefs.isEmpty {
            // Caso BIFF2/3/4 (hoja única en el mismo stream)
            let table = parseWorksheet(startingAt: 0, sheetName: "Sheet1")
            sheets.append(XLSXSheetModel(
                id: "xls-sheet-0",
                name: "Sheet1",
                archivePath: "xls/sheet0",
                table: table
            ))
            return sheets
        }

        for (idx, def) in worksheetDefs.enumerated() {
            let table = parseWorksheet(startingAt: def.offset, sheetName: def.name)
            sheets.append(XLSXSheetModel(
                id: "xls-sheet-\(idx)",
                name: def.name,
                archivePath: "xls/sheet\(idx)",
                table: table
            ))
        }

        if sheets.isEmpty {
            sheets.append(XLSXSheetModel(
                id: "xls-sheet-0",
                name: "Sheet1",
                archivePath: "xls/sheet0",
                table: SpreadsheetTableData(sheetName: "Sheet1", rows: [[""]])
            ))
        }
        return sheets
    }

    // MARK: - Substream Workbook Globals

    private func parseWorkbookGlobals() throws {
        var pos = 0
        while pos + 4 <= bytes.count {
            let recType = XLSDocumentEngine.readUInt16LE(bytes, at: pos)
            let recLen = Int(XLSDocumentEngine.readUInt16LE(bytes, at: pos + 2))
            let dataStart = pos + 4
            let dataEnd = min(dataStart + recLen, bytes.count)
            pos = dataEnd

            switch recType {
            case 0x0809: // BOF
                if recLen >= 4 {
                    let version = XLSDocumentEngine.readUInt16LE(bytes, at: dataStart)
                    let substreamType = XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2)
                    isBIFF8 = (version >= 0x0600)
                    if substreamType == 0x0010 {
                        // Archivo de una sola hoja sin bloque globals
                        return
                    }
                }

            case 0x002F: // FILEPASS (archivo cifrado con contraseña)
                throw XLSDocumentEngine.xlsError("Este archivo .xls está protegido con contraseña y no se puede descifrar directamente.")

            case 0x0042: // CODEPAGE
                if recLen >= 2 {
                    let cp = XLSDocumentEngine.readUInt16LE(bytes, at: dataStart)
                    stringEncoding = encoding(forCodepage: cp)
                }

            case 0x0022: // DATEMODE
                if recLen >= 2 {
                    is1904DateMode = (XLSDocumentEngine.readUInt16LE(bytes, at: dataStart) == 1)
                }

            case 0x041E: // FORMAT
                if recLen >= 5 {
                    let fmtIdx = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let fmtStr = decodeBIFF16String(from: bytes, at: dataStart + 2, limit: dataEnd).text
                    customFormats[fmtIdx] = fmtStr
                }

            case 0x0031: // FONT (recordar que Excel salta el índice 4)
                if fonts.count == 4 {
                    fonts.append(FontInfo(isBold: false, isItalic: false, colorIndex: 0x7FFF))
                }
                if recLen >= 10 {
                    let flags = XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2)
                    let colorIdx = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    let weight = XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 6)
                    let isBold = (weight >= 600) || ((flags & 0x0001) != 0)
                    let isItalic = (flags & 0x0002) != 0
                    fonts.append(FontInfo(isBold: isBold, isItalic: isItalic, colorIndex: colorIdx))
                } else {
                    fonts.append(FontInfo(isBold: false, isItalic: false, colorIndex: 0x7FFF))
                }

            case 0x0092: // PALETTE
                if recLen >= 2 {
                    let count = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    for i in 0..<count {
                        let base = dataStart + 2 + i * 4
                        guard base + 3 <= dataEnd else { break }
                        customPalette[8 + i] = String(format: "%02X%02X%02X", bytes[base], bytes[base + 1], bytes[base + 2])
                    }
                }

            case 0x00E0: // XF
                if recLen >= 16 {
                    let fontIdx = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let fmtIdx = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let alignByte = bytes[dataStart + 6] & 0x07
                    let alignment: SpreadsheetCellAlignment = {
                        switch alignByte {
                        case 2, 6: return .center
                        case 3: return .trailing
                        default: return .leading
                        }
                    }()
                    var fillColorIdx: Int? = nil
                    if isBIFF8 && recLen >= 20 {
                        let fillPattern = (XLSDocumentEngine.readUInt32LE(bytes, at: dataStart + 14) >> 26) & 0x3F
                        if fillPattern == 1 { // solid fill
                            let icvFore = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 18) & 0x007F)
                            if icvFore != 64 && icvFore != 65 {
                                fillColorIdx = icvFore
                            }
                        }
                    }
                    xfs.append(XFInfo(fontIndex: fontIdx, formatIndex: fmtIdx, alignment: alignment, fillColorIndex: fillColorIdx))
                }

            case 0x0085: // BOUNDSHEET
                if recLen >= 8 {
                    let offset = Int(XLSDocumentEngine.readUInt32LE(bytes, at: dataStart))
                    let sheetType = bytes[dataStart + 5]
                    let name = decodeBIFF8ShortString(from: bytes, at: dataStart + 6, limit: dataEnd)
                    boundSheets.append(BoundSheetInfo(offset: offset, name: name.isEmpty ? "Sheet\(boundSheets.count + 1)" : name, sheetType: sheetType))
                }

            case 0x00FC: // SST + CONTINUE (0x003C)
                var chunks: [ArraySlice<UInt8>] = [bytes[dataStart..<dataEnd]]
                while pos + 4 <= bytes.count {
                    let nextType = XLSDocumentEngine.readUInt16LE(bytes, at: pos)
                    guard nextType == 0x003C else { break }
                    let nextLen = Int(XLSDocumentEngine.readUInt16LE(bytes, at: pos + 2))
                    let nextStart = pos + 4
                    let nextEnd = min(nextStart + nextLen, bytes.count)
                    chunks.append(bytes[nextStart..<nextEnd])
                    pos = nextEnd
                }
                sharedStrings = parseSST(chunks: chunks)

            case 0x000A: // EOF de Workbook Globals
                return

            default:
                break
            }
        }
    }

    // MARK: - Substream de cada Worksheet

    private func parseWorksheet(startingAt startOffset: Int, sheetName: String) -> SpreadsheetTableData {
        guard startOffset >= 0 && startOffset + 4 <= bytes.count else {
            return SpreadsheetTableData(sheetName: sheetName, rows: [[""]])
        }

        var cellValues: [SpreadsheetCellCoord: String] = [:]
        var cellStyles: [SpreadsheetCellCoord: SpreadsheetCellStyle] = [:]
        var maxRow = 0
        var maxCol = 0

        var pos = startOffset
        var pendingFormulaCoord: SpreadsheetCellCoord? = nil
        var depth = 0

        func recordCell(row: Int, col: Int, value: String, xfIndex: Int) {
            guard row >= 0, col >= 0, row < 100_000, col < 256 else { return }
            let coord = SpreadsheetCellCoord(row: row, col: col)
            cellValues[coord] = value
            if let style = resolveStyle(forXF: xfIndex), !style.isDefault {
                cellStyles[coord] = style
            }
            if row > maxRow { maxRow = row }
            if col > maxCol { maxCol = col }
        }

        while pos + 4 <= bytes.count {
            let recType = XLSDocumentEngine.readUInt16LE(bytes, at: pos)
            let recLen = Int(XLSDocumentEngine.readUInt16LE(bytes, at: pos + 2))
            let dataStart = pos + 4
            let dataEnd = min(dataStart + recLen, bytes.count)
            pos = dataEnd

            // Si un FORMULA esperaba un registro STRING (0x0207), solo los inmediatamente siguientes (o SHRFMLA) aplican
            if recType != 0x0207 && recType != 0x04BC && recType != 0x0221 {
                pendingFormulaCoord = nil
            }

            switch recType {
            case 0x0809, 0x0409, 0x0209, 0x0009: // BOF (puede haber sub-BOFs embebidos como gráficos)
                depth += 1

            case 0x000A: // EOF
                depth -= 1
                if depth <= 0 {
                    return buildTableData(
                        sheetName: sheetName,
                        cellValues: cellValues,
                        cellStyles: cellStyles,
                        maxRow: maxRow,
                        maxCol: maxCol
                    )
                }

            case 0x0203 where depth <= 1: // NUMBER
                if recLen >= 14 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let col = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    let num = XLSDocumentEngine.readDoubleLE(bytes, at: dataStart + 6)
                    recordCell(row: row, col: col, value: formatNumericValue(num, xfIndex: xf), xfIndex: xf)
                }

            case 0x027E where depth <= 1: // RK
                if recLen >= 10 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let col = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    let rkRaw = XLSDocumentEngine.readUInt32LE(bytes, at: dataStart + 6)
                    let num = decodeRK(rkRaw)
                    recordCell(row: row, col: col, value: formatNumericValue(num, xfIndex: xf), xfIndex: xf)
                }

            case 0x00BD where depth <= 1: // MULRK
                if recLen >= 10 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let firstCol = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let lastCol = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataEnd - 2))
                    let count = min(lastCol - firstCol + 1, (recLen - 6) / 6)
                    for i in 0..<max(0, count) {
                        let entryBase = dataStart + 4 + i * 6
                        let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: entryBase))
                        let rkRaw = XLSDocumentEngine.readUInt32LE(bytes, at: entryBase + 2)
                        let num = decodeRK(rkRaw)
                        recordCell(row: row, col: firstCol + i, value: formatNumericValue(num, xfIndex: xf), xfIndex: xf)
                    }
                }

            case 0x00FD where depth <= 1: // LABELSST
                if recLen >= 10 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let col = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    let sstIdx = Int(XLSDocumentEngine.readUInt32LE(bytes, at: dataStart + 6))
                    let text = (sstIdx >= 0 && sstIdx < sharedStrings.count) ? sharedStrings[sstIdx] : ""
                    recordCell(row: row, col: col, value: text, xfIndex: xf)
                }

            case 0x0204 where depth <= 1, 0x00D6 where depth <= 1: // LABEL / RSTRING
                if recLen >= 8 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let col = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    let text = decodeBIFF16String(from: bytes, at: dataStart + 6, limit: dataEnd).text
                    recordCell(row: row, col: col, value: text, xfIndex: xf)
                }

            case 0x0205 where depth <= 1: // BOOLERR
                if recLen >= 8 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let col = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    let code = bytes[dataStart + 6]
                    let isError = bytes[dataStart + 7] != 0
                    let text = isError ? excelErrorString(code) : (code != 0 ? "TRUE" : "FALSE")
                    recordCell(row: row, col: col, value: text, xfIndex: xf)
                }

            case 0x0006 where depth <= 1: // FORMULA (valor cacheado)
                if recLen >= 14 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let col = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    // En BIFF8, si bytes[12..13] == 0xFFFF entonces bytes[6] indica tipo especial:
                    // 0 = string (en el siguiente registro 0x0207), 1 = bool, 2 = error, 3 = empty
                    if bytes[dataStart + 12] == 0xFF && bytes[dataStart + 13] == 0xFF {
                        let specialType = bytes[dataStart + 6]
                        switch specialType {
                        case 0:
                            recordCell(row: row, col: col, value: "", xfIndex: xf)
                            pendingFormulaCoord = SpreadsheetCellCoord(row: row, col: col)
                        case 1:
                            let flag = bytes[dataStart + 8] != 0
                            recordCell(row: row, col: col, value: flag ? "TRUE" : "FALSE", xfIndex: xf)
                        case 2:
                            recordCell(row: row, col: col, value: excelErrorString(bytes[dataStart + 8]), xfIndex: xf)
                        default:
                            recordCell(row: row, col: col, value: "", xfIndex: xf)
                        }
                    } else {
                        let num = XLSDocumentEngine.readDoubleLE(bytes, at: dataStart + 6)
                        recordCell(row: row, col: col, value: formatNumericValue(num, xfIndex: xf), xfIndex: xf)
                    }
                }

            case 0x0207 where depth <= 1: // STRING (resultado en texto del FORMULA anterior)
                if let coord = pendingFormulaCoord, recLen >= 2 {
                    let text = decodeBIFF16String(from: bytes, at: dataStart, limit: dataEnd).text
                    cellValues[coord] = text
                    pendingFormulaCoord = nil
                }

            case 0x0201 where depth <= 1: // BLANK
                if recLen >= 6 {
                    let row = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart))
                    let col = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 2))
                    let xf = Int(XLSDocumentEngine.readUInt16LE(bytes, at: dataStart + 4))
                    if let style = resolveStyle(forXF: xf), !style.isDefault {
                        cellStyles[SpreadsheetCellCoord(row: row, col: col)] = style
                    }
                }

            default:
                break
            }
        }

        return buildTableData(
            sheetName: sheetName,
            cellValues: cellValues,
            cellStyles: cellStyles,
            maxRow: maxRow,
            maxCol: maxCol
        )
    }

    private func buildTableData(
        sheetName: String,
        cellValues: [SpreadsheetCellCoord: String],
        cellStyles: [SpreadsheetCellCoord: SpreadsheetCellStyle],
        maxRow: Int,
        maxCol: Int
    ) -> SpreadsheetTableData {
        if cellValues.isEmpty {
            return SpreadsheetTableData(sheetName: sheetName, rows: [[""]])
        }
        let rowCount = min(maxRow + 1, 100_000)
        let colCount = min(maxCol + 1, 256)
        var grid = Array(repeating: Array(repeating: "", count: colCount), count: rowCount)
        for (coord, value) in cellValues where coord.row < rowCount && coord.col < colCount {
            grid[coord.row][coord.col] = value
        }
        return SpreadsheetTableData(
            sheetName: sheetName,
            rows: grid,
            styles: cellStyles
        )
    }

    // MARK: - Decodificador SST (Shared String Table) con Continuaciones BIFF8

    private func parseSST(chunks: [ArraySlice<UInt8>]) -> [String] {
        guard !chunks.isEmpty, chunks[0].count >= 8 else { return [] }
        var reader = BIFFContinueReader(chunks: chunks)
        _ = reader.readUInt32() // cstTotal
        let uniqueCount = Int(min(reader.readUInt32(), 500_000))

        var strings: [String] = []
        strings.reserveCapacity(uniqueCount)

        for _ in 0..<uniqueCount {
            guard reader.hasBytes else { break }
            let charCount = Int(reader.readUInt16())
            guard reader.hasBytes else {
                strings.append("")
                break
            }
            let flags = reader.readUInt8()
            var isUTF16 = (flags & 0x01) != 0
            let hasExtended = (flags & 0x04) != 0
            let hasRichText = (flags & 0x08) != 0

            let richRunCount = hasRichText ? Int(reader.readUInt16()) : 0
            let extByteCount = hasExtended ? Int(reader.readUInt32()) : 0

            var scalars: [UInt16] = []
            scalars.reserveCapacity(charCount)
            var remainingChars = charCount

            while remainingChars > 0 {
                if reader.remainingInCurrentChunk == 0 {
                    guard reader.advanceToNextChunk() else { break }
                    // En registros CONTINUE que dividen un string SST, el primer byte es el nuevo grbit (bit 0 = UTF-16LE)
                    let contFlags = reader.readUInt8()
                    isUTF16 = (contFlags & 0x01) != 0
                }
                let bytesPerChar = isUTF16 ? 2 : 1
                let availChars = reader.remainingInCurrentChunk / bytesPerChar
                let toRead = min(remainingChars, availChars)
                if toRead <= 0 {
                    guard reader.advanceToNextChunk() else { break }
                    let contFlags = reader.readUInt8()
                    isUTF16 = (contFlags & 0x01) != 0
                    continue
                }
                if isUTF16 {
                    for _ in 0..<toRead {
                        scalars.append(reader.readUInt16())
                    }
                } else {
                    for _ in 0..<toRead {
                        scalars.append(UInt16(reader.readUInt8()))
                    }
                }
                remainingChars -= toRead
            }

            strings.append(String(decoding: scalars, as: UTF16.self))

            // Saltar metadatos de formato enriquecido y fonéticos (pueden cruzar límites de CONTINUE sin byte grbit)
            if richRunCount > 0 {
                reader.skipRawBytes(richRunCount * 4)
            }
            if extByteCount > 0 {
                reader.skipRawBytes(extByteCount)
            }
        }

        return strings
    }

    private struct BIFFContinueReader {
        let chunks: [ArraySlice<UInt8>]
        var chunkIndex: Int = 0
        var offset: Int

        init(chunks: [ArraySlice<UInt8>]) {
            self.chunks = chunks
            self.offset = chunks.first?.startIndex ?? 0
        }

        var remainingInCurrentChunk: Int {
            guard chunkIndex < chunks.count else { return 0 }
            return max(0, chunks[chunkIndex].endIndex - offset)
        }

        var hasBytes: Bool {
            if remainingInCurrentChunk > 0 { return true }
            return (chunkIndex + 1) < chunks.count
        }

        mutating func advanceToNextChunk() -> Bool {
            chunkIndex += 1
            guard chunkIndex < chunks.count else { return false }
            offset = chunks[chunkIndex].startIndex
            return true
        }

        mutating func readUInt8() -> UInt8 {
            if remainingInCurrentChunk == 0 {
                guard advanceToNextChunk() else { return 0 }
            }
            let b = chunks[chunkIndex][offset]
            offset += 1
            return b
        }

        mutating func readUInt16() -> UInt16 {
            let lo = UInt16(readUInt8())
            let hi = UInt16(readUInt8())
            return lo | (hi << 8)
        }

        mutating func readUInt32() -> UInt32 {
            let lo = UInt32(readUInt16())
            let hi = UInt32(readUInt16())
            return lo | (hi << 16)
        }

        mutating func skipRawBytes(_ count: Int) {
            var remaining = count
            while remaining > 0 {
                let avail = remainingInCurrentChunk
                if avail == 0 {
                    guard advanceToNextChunk() else { return }
                    continue
                }
                let step = min(remaining, avail)
                offset += step
                remaining -= step
            }
        }
    }

    // MARK: - Strings, RK, Fechas, Errores y Estilos BIFF

    private func decodeBIFF8ShortString(from buf: [UInt8], at start: Int, limit: Int) -> String {
        guard start < limit else { return "" }
        let charCount = Int(buf[start])
        if !isBIFF8 {
            let end = min(start + 1 + charCount, limit)
            return decode8BitBytes(buf[(start + 1)..<end])
        }
        guard start + 1 < limit else { return "" }
        let flags = buf[start + 1]
        let isUTF16 = (flags & 0x01) != 0
        let strStart = start + 2
        if isUTF16 {
            let byteCount = min(charCount * 2, max(0, limit - strStart))
            var units: [UInt16] = []
            units.reserveCapacity(byteCount / 2)
            var i = 0
            while i + 1 < byteCount {
                units.append(XLSDocumentEngine.readUInt16LE(buf, at: strStart + i))
                i += 2
            }
            return String(decoding: units, as: UTF16.self)
        } else {
            let end = min(strStart + charCount, limit)
            return String(decoding: buf[strStart..<end].map { UInt16($0) }, as: UTF16.self)
        }
    }

    private func decodeBIFF16String(from buf: [UInt8], at start: Int, limit: Int) -> (text: String, bytesConsumed: Int) {
        guard start + 2 <= limit else { return ("", 0) }
        let charCount = Int(XLSDocumentEngine.readUInt16LE(buf, at: start))
        if !isBIFF8 {
            let strStart = start + 2
            let end = min(strStart + charCount, limit)
            return (decode8BitBytes(buf[strStart..<end]), end - start)
        }
        guard start + 3 <= limit else { return ("", 2) }
        let flags = buf[start + 2]
        let isUTF16 = (flags & 0x01) != 0
        let hasExt = (flags & 0x04) != 0
        let hasRich = (flags & 0x08) != 0
        var cursor = start + 3
        let richRuns = hasRich && cursor + 2 <= limit ? Int(XLSDocumentEngine.readUInt16LE(buf, at: cursor)) : 0
        if hasRich { cursor += 2 }
        let extSize = hasExt && cursor + 4 <= limit ? Int(XLSDocumentEngine.readUInt32LE(buf, at: cursor)) : 0
        if hasExt { cursor += 4 }

        let text: String
        if isUTF16 {
            let byteCount = min(charCount * 2, max(0, limit - cursor))
            var units: [UInt16] = []
            units.reserveCapacity(byteCount / 2)
            var i = 0
            while i + 1 < byteCount {
                units.append(XLSDocumentEngine.readUInt16LE(buf, at: cursor + i))
                i += 2
            }
            cursor += byteCount
            text = String(decoding: units, as: UTF16.self)
        } else {
            let end = min(cursor + charCount, limit)
            text = String(decoding: buf[cursor..<end].map { UInt16($0) }, as: UTF16.self)
            cursor = end
        }
        cursor = min(limit, cursor + richRuns * 4 + extSize)
        return (text, cursor - start)
    }

    private func decode8BitBytes(_ slice: ArraySlice<UInt8>) -> String {
        let data = Data(slice)
        return String(data: data, encoding: stringEncoding)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: slice.map { UInt16($0) }, as: UTF16.self)
    }

    private func decodeRK(_ rk: UInt32) -> Double {
        let isDiv100 = (rk & 0x01) != 0
        let isInt = (rk & 0x02) != 0
        let baseValue: Double
        if isInt {
            // 30-bit signed integer en bits 2..31
            let signed = Int32(bitPattern: rk) >> 2
            baseValue = Double(signed)
        } else {
            // IEEE-754 double con los 30 bits más significativos en rk & ~3
            let highBits = UInt64(rk & 0xFFFF_FFFC) << 32
            baseValue = Double(bitPattern: highBits)
        }
        return isDiv100 ? (baseValue / 100.0) : baseValue
    }

    private func formatNumericValue(_ value: Double, xfIndex: Int) -> String {
        guard value.isFinite else { return "" }

        if isDateFormat(forXF: xfIndex), value >= 0 && value < 2_958_466 {
            return formatExcelSerialDate(value, formatID: xfs.indices.contains(xfIndex) ? xfs[xfIndex].formatIndex : 14)
        }

        // Formatear enteros exactos sin ".0"
        if value == floor(value) && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        // Evitar ruido flotante tipo 19.990000000000002
        return String(format: "%.10g", value)
    }

    private func isDateFormat(forXF xfIndex: Int) -> Bool {
        guard xfs.indices.contains(xfIndex) else { return false }
        let fmtID = xfs[xfIndex].formatIndex
        if (14...22).contains(fmtID) || (45...47).contains(fmtID) {
            return true
        }
        guard let custom = customFormats[fmtID] else { return false }
        // Quitar literales entre comillas y corchetes ([Red], [$-409])
        var cleaned = ""
        var inQuotes = false
        var inBrackets = false
        for ch in custom.lowercased() {
            if ch == "\"" { inQuotes.toggle(); continue }
            if !inQuotes {
                if ch == "[" { inBrackets = true; continue }
                if ch == "]" { inBrackets = false; continue }
                if !inBrackets { cleaned.append(ch) }
            }
        }
        return cleaned.contains("y") || cleaned.contains("d") || cleaned.contains("h")
            || (cleaned.contains("m") && (cleaned.contains("/") || cleaned.contains("-") || cleaned.contains(":")))
    }

    private func formatExcelSerialDate(_ serial: Double, formatID: Int) -> String {
        // Epoch 1900 (con bug bisiesto de Excel: día 60 = 29/02/1900) o Epoch 1904 (Mac clásico)
        let daysOffset: Double
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let baseDate: Date
        if is1904DateMode {
            baseDate = cal.date(from: DateComponents(year: 1904, month: 1, day: 1))!
            daysOffset = serial
        } else {
            baseDate = cal.date(from: DateComponents(year: 1899, month: 12, day: 31))!
            daysOffset = serial >= 60 ? (serial - 1.0) : serial
        }

        let target = baseDate.addingTimeInterval(daysOffset * 86_400.0)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: target)
        let y = comps.year ?? 1900
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let hh = comps.hour ?? 0
        let mm = comps.minute ?? 0
        let ss = comps.second ?? 0

        let hasTimePart = (serial - floor(serial)) > 0.0001
        if (18...21).contains(formatID) || (45...47).contains(formatID) {
            return String(format: "%02d:%02d:%02d", hh, mm, ss)
        }
        if hasTimePart || formatID == 22 {
            return String(format: "%04d-%02d-%02d %02d:%02d", y, m, d, hh, mm)
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func excelErrorString(_ code: UInt8) -> String {
        switch code {
        case 0x00: return "#NULL!"
        case 0x07: return "#DIV/0!"
        case 0x0F: return "#VALUE!"
        case 0x17: return "#REF!"
        case 0x1D: return "#NAME?"
        case 0x24: return "#NUM!"
        case 0x2A: return "#N/A"
        default: return "#ERR!"
        }
    }

    private func resolveStyle(forXF xfIndex: Int) -> SpreadsheetCellStyle? {
        guard xfs.indices.contains(xfIndex) else { return nil }
        let xf = xfs[xfIndex]
        let font = fonts.indices.contains(xf.fontIndex) ? fonts[xf.fontIndex] : nil
        let textHex = font.flatMap { paletteHex(forIndex: $0.colorIndex, isForegroundText: true) }
        let fillHex = xf.fillColorIndex.flatMap { paletteHex(forIndex: $0, isForegroundText: false) }
        return SpreadsheetCellStyle(
            isBold: font?.isBold ?? false,
            isItalic: font?.isItalic ?? false,
            alignment: xf.alignment,
            textColorHex: textHex,
            fillColorHex: fillHex
        )
    }

    private func paletteHex(forIndex idx: Int, isForegroundText: Bool) -> String? {
        // Índices automáticos / por defecto de Excel (sin color forzado)
        if idx == 0x7FFF || idx == 64 || idx == 65 { return nil }
        if isForegroundText && (idx == 0 || idx == 8) { return nil } // negro estándar -> usar color adaptativo Light/Dark
        if !isForegroundText && (idx == 1 || idx == 9) { return nil } // blanco estándar -> fondo adaptativo

        if let custom = customPalette[idx] { return custom }
        return Self.defaultBIFF8Palette[idx]
    }

    private func encoding(forCodepage cp: UInt16) -> String.Encoding {
        switch cp {
        case 65001: return .utf8
        case 10000: return .macOSRoman
        case 1250: return .windowsCP1250
        case 1251: return .windowsCP1251
        case 1253: return .windowsCP1253
        case 1254: return .windowsCP1254
        default: return .windowsCP1252
        }
    }

    private static let defaultBIFF8Palette: [Int: String] = [
        8: "000000", 9: "FFFFFF", 10: "FF0000", 11: "00FF00", 12: "0000FF", 13: "FFFF00", 14: "FF00FF", 15: "00FFFF",
        16: "800000", 17: "008000", 18: "000080", 19: "808000", 20: "800080", 21: "008080", 22: "C0C0C0", 23: "808080",
        24: "9999FF", 25: "993366", 26: "FFFFCC", 27: "CCFFFF", 28: "660066", 29: "FF8080", 30: "0066CC", 31: "CCCCFF",
        40: "00CCFF", 41: "CCFFFF", 42: "CCFFCC", 43: "FFFF99", 44: "99CCFF", 45: "FF99CC", 46: "CC99FF", 47: "FFCC99",
        48: "3366FF", 49: "33CCCC", 50: "99CC00", 51: "FFCC00", 52: "FF9900", 53: "FF6600", 54: "666699", 55: "969696",
        56: "003366", 57: "339966", 58: "003300", 59: "333300", 60: "993300", 61: "993366", 62: "333399", 63: "333333"
    ]
}

// MARK: - Escritor Nativo BIFF8 + OLE2 CFBF (Guardado Real a .xls Binario)

private enum BIFF8WorkbookWriter {

    private struct StyleKey: Hashable {
        let isBold: Bool
        let isItalic: Bool
        let alignment: SpreadsheetCellAlignment
    }

    static func buildWorkbookStream(from workbook: XLSXWorkbookModel) -> [UInt8] {
        let sheets = workbook.sheets.isEmpty
            ? [XLSXSheetModel(name: "Sheet1", archivePath: "xls/sheet0", table: SpreadsheetTableData(rows: [[""]]))]
            : workbook.sheets

        // 1. Recolectar tabla SST (Shared String Table) y mapa de estilos XF
        var sstList: [String] = []
        var sstIndexByText: [String: UInt32] = [:]
        var totalStringRefs: UInt32 = 0

        func internString(_ text: String) -> UInt32 {
            totalStringRefs += 1
            if let existing = sstIndexByText[text] { return existing }
            let idx = UInt32(sstList.count)
            sstIndexByText[text] = idx
            sstList.append(text)
            return idx
        }

        // XF índices 0..14 son Style XFs; índice 15 es el Cell XF por defecto; 16+ son estilos personalizados
        var xfIndexByStyle: [StyleKey: UInt16] = [
            StyleKey(isBold: false, isItalic: false, alignment: .leading): 15
        ]
        var customStyleKeys: [StyleKey] = []

        func xfIndex(for style: SpreadsheetCellStyle?) -> UInt16 {
            guard let style else { return 15 }
            let key = StyleKey(isBold: style.isBold, isItalic: style.isItalic, alignment: style.alignment)
            if let existing = xfIndexByStyle[key] { return existing }
            let idx = UInt16(16 + customStyleKeys.count)
            xfIndexByStyle[key] = idx
            customStyleKeys.append(key)
            return idx
        }

        // Pre-construir substreams de cada hoja para conocer su contenido exacto y poblar SST + XFs
        var worksheetStreams: [[UInt8]] = []
        worksheetStreams.reserveCapacity(sheets.count)

        for sheet in sheets {
            var ws: [UInt8] = []
            // BOF Worksheet (0x0809): version 0x0600, type 0x0010 (Worksheet)
            appendRecord(type: 0x0809, payload: [
                0x00, 0x06, 0x10, 0x00, 0xAF, 0x18, 0xCD, 0x07,
                0xC1, 0x40, 0x00, 0x00, 0x06, 0x01, 0x00, 0x00
            ], to: &ws)

            let rowCount = min(sheet.table.rows.count, 65_535)
            let colCount = min(sheet.table.columnCount, 255)

            // DIMENSION (0x0200): firstRow(4), lastRow+1(4), firstCol(2), lastCol+1(2), reserved(2)
            var dimPayload: [UInt8] = []
            XLSDocumentEngine.appendUInt32LE(0, to: &dimPayload)
            XLSDocumentEngine.appendUInt32LE(UInt32(rowCount), to: &dimPayload)
            XLSDocumentEngine.appendUInt16LE(0, to: &dimPayload)
            XLSDocumentEngine.appendUInt16LE(UInt16(colCount), to: &dimPayload)
            XLSDocumentEngine.appendUInt16LE(0, to: &dimPayload)
            appendRecord(type: 0x0200, payload: dimPayload, to: &ws)

            for r in 0..<rowCount {
                let row = sheet.table.rows[r]
                for c in 0..<min(row.count, colCount) {
                    let rawVal = row[c]
                    let coord = SpreadsheetCellCoord(row: r, col: c)
                    let style = sheet.table.styles[coord]
                    if rawVal.isEmpty && (style == nil || style?.isDefault == true) {
                        continue
                    }
                    let xf = xfIndex(for: style)

                    if rawVal.isEmpty {
                        var blankPayload: [UInt8] = []
                        XLSDocumentEngine.appendUInt16LE(UInt16(r), to: &blankPayload)
                        XLSDocumentEngine.appendUInt16LE(UInt16(c), to: &blankPayload)
                        XLSDocumentEngine.appendUInt16LE(xf, to: &blankPayload)
                        appendRecord(type: 0x0201, payload: blankPayload, to: &ws)
                    } else if rawVal == "TRUE" || rawVal == "FALSE" {
                        var boolPayload: [UInt8] = []
                        XLSDocumentEngine.appendUInt16LE(UInt16(r), to: &boolPayload)
                        XLSDocumentEngine.appendUInt16LE(UInt16(c), to: &boolPayload)
                        XLSDocumentEngine.appendUInt16LE(xf, to: &boolPayload)
                        boolPayload.append(rawVal == "TRUE" ? 1 : 0)
                        boolPayload.append(0) // bool, not error
                        appendRecord(type: 0x0205, payload: boolPayload, to: &ws)
                    } else if let num = Double(rawVal.trimmingCharacters(in: .whitespaces)),
                              num.isFinite,
                              !rawVal.hasPrefix("0") || rawVal == "0" || rawVal.hasPrefix("0.") || rawVal.hasPrefix("-0.") {
                        var numPayload: [UInt8] = []
                        XLSDocumentEngine.appendUInt16LE(UInt16(r), to: &numPayload)
                        XLSDocumentEngine.appendUInt16LE(UInt16(c), to: &numPayload)
                        XLSDocumentEngine.appendUInt16LE(xf, to: &numPayload)
                        XLSDocumentEngine.appendDoubleLE(num, to: &numPayload)
                        appendRecord(type: 0x0203, payload: numPayload, to: &ws)
                    } else {
                        let sstIdx = internString(rawVal)
                        var lblPayload: [UInt8] = []
                        XLSDocumentEngine.appendUInt16LE(UInt16(r), to: &lblPayload)
                        XLSDocumentEngine.appendUInt16LE(UInt16(c), to: &lblPayload)
                        XLSDocumentEngine.appendUInt16LE(xf, to: &lblPayload)
                        XLSDocumentEngine.appendUInt32LE(sstIdx, to: &lblPayload)
                        appendRecord(type: 0x00FD, payload: lblPayload, to: &ws)
                    }
                }
            }

            // WINDOW2 (0x023E): muestra grilla, encabezados y valores cero
            appendRecord(type: 0x023E, payload: [
                0xB6, 0x06, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00
            ], to: &ws)

            // EOF Worksheet (0x000A)
            appendRecord(type: 0x000A, payload: [], to: &ws)
            worksheetStreams.append(ws)
        }

        // 2. Construir Workbook Globals substream
        var globals: [UInt8] = []

        // BOF Workbook Globals (0x0809): version 0x0600, type 0x0005
        appendRecord(type: 0x0809, payload: [
            0x00, 0x06, 0x05, 0x00, 0xAF, 0x18, 0xCD, 0x07,
            0xC1, 0x40, 0x00, 0x00, 0x06, 0x01, 0x00, 0x00
        ], to: &globals)

        // CODEPAGE (0x0042): 0x04B0 (1200 = UTF-16LE)
        appendRecord(type: 0x0042, payload: [0xB0, 0x04], to: &globals)

        // WINDOW1 (0x003D)
        appendRecord(type: 0x003D, payload: [
            0xE0, 0x01, 0x69, 0x00, 0x23, 0x2F, 0xC9, 0x1B,
            0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
            0x58, 0x02
        ], to: &globals)

        // DATEMODE (0x0022): 1900 system
        appendRecord(type: 0x0022, payload: [0x00, 0x00], to: &globals)

        // FONT (0x0031): índices 0..3 + 5..7 (recordar que Excel omite el índice 4)
        // 0 = Normal, 1 = Bold, 2 = Italic, 3 = Bold+Italic, (4 omitido por spec), 5 = Normal copia
        appendRecord(type: 0x0031, payload: makeFontPayload(isBold: false, isItalic: false), to: &globals) // idx 0
        appendRecord(type: 0x0031, payload: makeFontPayload(isBold: true, isItalic: false), to: &globals)  // idx 1
        appendRecord(type: 0x0031, payload: makeFontPayload(isBold: false, isItalic: true), to: &globals)  // idx 2
        appendRecord(type: 0x0031, payload: makeFontPayload(isBold: true, isItalic: true), to: &globals)   // idx 3
        appendRecord(type: 0x0031, payload: makeFontPayload(isBold: false, isItalic: false), to: &globals) // idx 5

        // XF (0x00E0): 15 Style XFs (0..14) + 1 Default Cell XF (15) + custom Cell XFs (16+)
        for _ in 0..<15 {
            appendRecord(type: 0x00E0, payload: makeStyleXFPayload(), to: &globals)
        }
        appendRecord(type: 0x00E0, payload: makeCellXFPayload(fontIndex: 0, alignment: .leading), to: &globals)
        for key in customStyleKeys {
            let fontIdx: UInt16 = {
                switch (key.isBold, key.isItalic) {
                case (false, false): return 0
                case (true, false): return 1
                case (false, true): return 2
                case (true, true): return 3
                }
            }()
            appendRecord(type: 0x00E0, payload: makeCellXFPayload(fontIndex: fontIdx, alignment: key.alignment), to: &globals)
        }

        // STYLE (0x0293): estilo "Normal" apuntando al XF 0
        appendRecord(type: 0x0293, payload: [0x00, 0x80, 0x00, 0xFF], to: &globals)

        // BOUNDSHEET (0x0085): guardar posiciones de los offsets de 4 bytes para parchearlos al finalizar Globals
        var boundSheetOffsetPatches: [Int] = []
        let invalidSheetChars = CharacterSet(charactersIn: ":\\/?*[]")
        for (sheetIdx, sheet) in sheets.enumerated() {
            let sanitized = sheet.name
                .components(separatedBy: invalidSheetChars)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanName = String((sanitized.isEmpty ? "Sheet\(sheetIdx + 1)" : sanitized).prefix(31))
            let utf16 = Array(cleanName.utf16)
            var payload: [UInt8] = []
            XLSDocumentEngine.appendUInt32LE(0, to: &payload) // placeholder offset
            payload.append(0x00) // visible
            payload.append(0x00) // worksheet
            payload.append(UInt8(utf16.count))
            payload.append(0x01) // UTF-16LE
            for unit in utf16 {
                XLSDocumentEngine.appendUInt16LE(unit, to: &payload)
            }
            let offsetFieldPos = globals.count + 4
            boundSheetOffsetPatches.append(offsetFieldPos)
            appendRecord(type: 0x0085, payload: payload, to: &globals)
        }

        // SST (0x00FC) + CONTINUE (0x003C) respetando límite BIFF8 de 8224 bytes por registro
        appendSSTRecords(strings: sstList, totalRefs: totalStringRefs, to: &globals)

        // EOF Workbook Globals (0x000A)
        appendRecord(type: 0x000A, payload: [], to: &globals)

        // 3. Parchear offsets reales de cada hoja y concatenar todo el stream
        var currentSheetOffset = globals.count
        for i in 0..<worksheetStreams.count {
            let patchPos = boundSheetOffsetPatches[i]
            let off = UInt32(currentSheetOffset)
            globals[patchPos] = UInt8(off & 0xFF)
            globals[patchPos + 1] = UInt8((off >> 8) & 0xFF)
            globals[patchPos + 2] = UInt8((off >> 16) & 0xFF)
            globals[patchPos + 3] = UInt8((off >> 24) & 0xFF)
            currentSheetOffset += worksheetStreams[i].count
        }

        var fullStream = globals
        for ws in worksheetStreams {
            fullStream.append(contentsOf: ws)
        }
        return fullStream
    }

    private static func appendRecord(type: UInt16, payload: [UInt8], to out: inout [UInt8]) {
        XLSDocumentEngine.appendUInt16LE(type, to: &out)
        XLSDocumentEngine.appendUInt16LE(UInt16(payload.count), to: &out)
        out.append(contentsOf: payload)
    }

    private static func makeFontPayload(isBold: Bool, isItalic: Bool) -> [UInt8] {
        var p: [UInt8] = []
        XLSDocumentEngine.appendUInt16LE(200, to: &p) // 10pt (200 twips)
        let grbit: UInt16 = (isBold ? 0x0001 : 0) | (isItalic ? 0x0002 : 0)
        XLSDocumentEngine.appendUInt16LE(grbit, to: &p)
        XLSDocumentEngine.appendUInt16LE(0x7FFF, to: &p) // automatic color
        XLSDocumentEngine.appendUInt16LE(isBold ? 700 : 400, to: &p)
        XLSDocumentEngine.appendUInt16LE(0, to: &p) // escapement
        p.append(0) // underline
        p.append(0) // family
        p.append(0) // charset
        p.append(0) // reserved
        let name = Array("Arial".utf16)
        p.append(UInt8(name.count))
        p.append(0x01) // UTF-16LE
        for u in name { XLSDocumentEngine.appendUInt16LE(u, to: &p) }
        return p
    }

    private static func makeStyleXFPayload() -> [UInt8] {
        var p: [UInt8] = []
        XLSDocumentEngine.appendUInt16LE(0, to: &p)       // font 0
        XLSDocumentEngine.appendUInt16LE(0, to: &p)       // format 0 (General)
        XLSDocumentEngine.appendUInt16LE(0xFFF5, to: &p)  // style XF (bit 2=1, parent=0xFFF)
        p.append(0x20)                                    // bottom vertical align
        p.append(0x00)
        p.append(0x00)
        p.append(0x00)
        XLSDocumentEngine.appendUInt32LE(0, to: &p)
        XLSDocumentEngine.appendUInt32LE(0, to: &p)
        XLSDocumentEngine.appendUInt16LE(0x20C0, to: &p)  // default colors (64/65)
        return p
    }

    private static func makeCellXFPayload(fontIndex: UInt16, alignment: SpreadsheetCellAlignment) -> [UInt8] {
        var p: [UInt8] = []
        XLSDocumentEngine.appendUInt16LE(fontIndex, to: &p)
        XLSDocumentEngine.appendUInt16LE(0, to: &p) // General format
        XLSDocumentEngine.appendUInt16LE(0x0001, to: &p) // cell XF, parent = 0
        let hAlign: UInt8 = {
            switch alignment {
            case .leading: return 0x01
            case .center: return 0x02
            case .trailing: return 0x03
            }
        }()
        p.append(0x20 | hAlign)
        p.append(0x00)
        p.append(0x00)
        // Marcar flags de atributos usados (font + alignment)
        p.append((fontIndex != 0 ? 0x08 : 0x00) | (alignment != .leading ? 0x10 : 0x00))
        XLSDocumentEngine.appendUInt32LE(0, to: &p)
        XLSDocumentEngine.appendUInt32LE(0, to: &p)
        XLSDocumentEngine.appendUInt16LE(0x20C0, to: &p)
        return p
    }

    private static func appendSSTRecords(strings: [String], totalRefs: UInt32, to out: inout [UInt8]) {
        let maxPayload = 8200
        var currentType: UInt16 = 0x00FC // SST
        var currentPayload: [UInt8] = []
        XLSDocumentEngine.appendUInt32LE(totalRefs, to: &currentPayload)
        XLSDocumentEngine.appendUInt32LE(UInt32(strings.count), to: &currentPayload)

        func flushCurrent() {
            appendRecord(type: currentType, payload: currentPayload, to: &out)
            currentType = 0x003C // CONTINUE
            currentPayload = []
        }

        for str in strings {
            let units = Array(str.prefix(32_767).utf16)
            let neededHeader = 3 // cch (2) + flags (1)
            // Si ni siquiera entra el encabezado + 1 carácter, abrir CONTINUE antes del string
            if currentPayload.count + neededHeader + (units.isEmpty ? 0 : 2) > maxPayload {
                flushCurrent()
            }

            XLSDocumentEngine.appendUInt16LE(UInt16(units.count), to: &currentPayload)
            currentPayload.append(0x01) // UTF-16LE

            var idx = 0
            while idx < units.count {
                let spaceBytes = maxPayload - currentPayload.count
                let charsFit = spaceBytes / 2
                if charsFit <= 0 {
                    flushCurrent()
                    // Primer byte de CONTINUE dentro de un string partido: grbit = 0x01 (UTF-16LE)
                    currentPayload.append(0x01)
                    continue
                }
                let take = min(charsFit, units.count - idx)
                for j in 0..<take {
                    XLSDocumentEngine.appendUInt16LE(units[idx + j], to: &currentPayload)
                }
                idx += take
            }
        }

        appendRecord(type: currentType, payload: currentPayload, to: &out)
    }
}

// MARK: - Empaquetador OLE2 Compound File Binary Format (MS-CFB v3, sectores de 512 bytes)

private enum OLE2CompoundFileWriter {
    private static let sectorSize = 512
    private static let freeSect: UInt32 = 0xFFFF_FFFF
    private static let endOfChain: UInt32 = 0xFFFF_FFFE
    private static let fatSect: UInt32 = 0xFFFF_FFFD
    private static let difSect: UInt32 = 0xFFFF_FFFC

    static func pack(workbookStream rawStream: [UInt8]) -> Data {
        // Garantizar tamaño >= 4096 bytes tanto en datos como en streamSize del directorio
        // para que lectores estrictos MS-CFB (Excel, OfficeImport) lean siempre desde FAT regular y no Mini-Stream.
        let reportedStreamSize = max(rawStream.count, 4096)
        var paddedStream = rawStream
        let minStreamBytes = ((reportedStreamSize + sectorSize - 1) / sectorSize) * sectorSize
        if paddedStream.count < minStreamBytes {
            paddedStream.append(contentsOf: repeatElement(0, count: minStreamBytes - paddedStream.count))
        }

        let wbSectorCount = paddedStream.count / sectorSize
        let dirSectorCount = 1

        // Calcular cantidad de sectores FAT (y DIFAT si el libro es enorme > 109*128 sectores ≈ 7 MB)
        var fatSectorCount = 1
        var difatSectorCount = 0
        while true {
            let totalSectors = wbSectorCount + dirSectorCount + fatSectorCount + difatSectorCount
            let neededFat = max(1, (totalSectors + 127) / 128)
            let neededDifat = neededFat > 109 ? ((neededFat - 109) + 126) / 127 : 0
            if neededFat == fatSectorCount && neededDifat == difatSectorCount {
                break
            }
            fatSectorCount = neededFat
            difatSectorCount = neededDifat
        }

        let dirStartSector = UInt32(wbSectorCount)
        let fatStartSector = dirStartSector + UInt32(dirSectorCount)
        let difatStartSector = fatStartSector + UInt32(fatSectorCount)

        // Construir entradas de tabla FAT
        let totalFatEntries = fatSectorCount * 128
        var fat = Array(repeating: freeSect, count: totalFatEntries)

        // Cadena del stream Workbook: 0 -> 1 -> ... -> wbSectorCount-1 -> ENDOFCHAIN
        for s in 0..<wbSectorCount {
            fat[s] = (s + 1 < wbSectorCount) ? UInt32(s + 1) : endOfChain
        }
        // Sector de Directorio
        fat[Int(dirStartSector)] = endOfChain
        // Sectores FAT
        for i in 0..<fatSectorCount {
            fat[Int(fatStartSector) + i] = fatSect
        }
        // Sectores DIFAT si existen
        for i in 0..<difatSectorCount {
            fat[Int(difatStartSector) + i] = difSect
        }

        // 1. Header OLE2 (512 bytes)
        var header = [UInt8](repeating: 0, count: sectorSize)
        let sig: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        for i in 0..<8 { header[i] = sig[i] }
        writeUInt16LE(0x003E, into: &header, at: 24) // minor version
        writeUInt16LE(0x0003, into: &header, at: 26) // major version 3
        writeUInt16LE(0xFFFE, into: &header, at: 28) // little-endian BOM
        writeUInt16LE(0x0009, into: &header, at: 30) // sector shift = 9 (512 bytes)
        writeUInt16LE(0x0006, into: &header, at: 32) // mini sector shift = 6 (64 bytes)
        writeUInt32LE(UInt32(fatSectorCount), into: &header, at: 44)
        writeUInt32LE(dirStartSector, into: &header, at: 48)
        writeUInt32LE(0x0000_1000, into: &header, at: 56) // mini cutoff 4096
        writeUInt32LE(endOfChain, into: &header, at: 60)  // no mini FAT
        writeUInt32LE(0, into: &header, at: 64)
        writeUInt32LE(difatSectorCount > 0 ? difatStartSector : endOfChain, into: &header, at: 68)
        writeUInt32LE(UInt32(difatSectorCount), into: &header, at: 72)

        for i in 0..<109 {
            let sid: UInt32 = (i < fatSectorCount) ? (fatStartSector + UInt32(i)) : freeSect
            writeUInt32LE(sid, into: &header, at: 76 + i * 4)
        }

        // 2. Sector de Directorio (512 bytes: Entry 0 = Root Entry, Entry 1 = Workbook)
        var dirSector = [UInt8](repeating: 0, count: sectorSize)
        writeDirectoryEntry(
            name: "Root Entry",
            objectType: 5,
            color: 1,
            leftSibling: freeSect,
            rightSibling: freeSect,
            childID: 1,
            startSector: endOfChain,
            streamSize: 0,
            into: &dirSector,
            at: 0
        )
        writeDirectoryEntry(
            name: "Workbook",
            objectType: 2,
            color: 1,
            leftSibling: freeSect,
            rightSibling: freeSect,
            childID: freeSect,
            startSector: 0,
            streamSize: UInt32(reportedStreamSize),
            into: &dirSector,
            at: 128
        )

        // 3. Sectores FAT
        var fatBytes: [UInt8] = []
        fatBytes.reserveCapacity(fatSectorCount * sectorSize)
        for entry in fat {
            XLSDocumentEngine.appendUInt32LE(entry, to: &fatBytes)
        }

        // 4. Sectores DIFAT adicionales (si fatSectorCount > 109)
        var difatBytes: [UInt8] = []
        if difatSectorCount > 0 {
            difatBytes.reserveCapacity(difatSectorCount * sectorSize)
            var nextFatIdx = 109
            for d in 0..<difatSectorCount {
                for _ in 0..<127 {
                    let sid: UInt32 = (nextFatIdx < fatSectorCount) ? (fatStartSector + UInt32(nextFatIdx)) : freeSect
                    XLSDocumentEngine.appendUInt32LE(sid, to: &difatBytes)
                    nextFatIdx += 1
                }
                let nextDifat: UInt32 = (d + 1 < difatSectorCount) ? (difatStartSector + UInt32(d + 1)) : endOfChain
                XLSDocumentEngine.appendUInt32LE(nextDifat, to: &difatBytes)
            }
        }

        var output = Data()
        output.reserveCapacity(header.count + paddedStream.count + dirSector.count + fatBytes.count + difatBytes.count)
        output.append(contentsOf: header)
        output.append(contentsOf: paddedStream)
        output.append(contentsOf: dirSector)
        output.append(contentsOf: fatBytes)
        output.append(contentsOf: difatBytes)
        return output
    }

    private static func writeDirectoryEntry(
        name: String,
        objectType: UInt8,
        color: UInt8,
        leftSibling: UInt32,
        rightSibling: UInt32,
        childID: UInt32,
        startSector: UInt32,
        streamSize: UInt32,
        into buf: inout [UInt8],
        at base: Int
    ) {
        let utf16 = Array(name.utf16) + [0]
        for (i, unit) in utf16.enumerated() where i < 32 {
            writeUInt16LE(unit, into: &buf, at: base + i * 2)
        }
        writeUInt16LE(UInt16(min(utf16.count, 32) * 2), into: &buf, at: base + 64)
        buf[base + 66] = objectType
        buf[base + 67] = color
        writeUInt32LE(leftSibling, into: &buf, at: base + 68)
        writeUInt32LE(rightSibling, into: &buf, at: base + 72)
        writeUInt32LE(childID, into: &buf, at: base + 76)
        writeUInt32LE(startSector, into: &buf, at: base + 116)
        writeUInt32LE(streamSize, into: &buf, at: base + 120)
    }

    private static func writeUInt16LE(_ value: UInt16, into buf: inout [UInt8], at offset: Int) {
        buf[offset] = UInt8(value & 0xFF)
        buf[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeUInt32LE(_ value: UInt32, into buf: inout [UInt8], at offset: Int) {
        buf[offset] = UInt8(value & 0xFF)
        buf[offset + 1] = UInt8((value >> 8) & 0xFF)
        buf[offset + 2] = UInt8((value >> 16) & 0xFF)
        buf[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
