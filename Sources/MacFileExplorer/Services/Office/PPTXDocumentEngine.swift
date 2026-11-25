import CoreGraphics
import Foundation

// MARK: - Modelo de Presentación PowerPoint (.pptx)

public enum PPTXTextAlignment: String, Codable, Sendable, Equatable {
    case leading
    case center
    case trailing

    public var ooxmlValue: String {
        switch self {
        case .leading: return "l"
        case .center: return "ctr"
        case .trailing: return "r"
        }
    }
}

public struct PPTXTextBox: Identifiable, Sendable, Equatable {
    public let id: String
    /// Índice de forma `<p:sp>` dentro de `<p:spTree>` (o `nil` si fue agregado por el usuario).
    public var shapeIndex: Int?
    public var isTitle: Bool
    /// Coordenadas normalizadas `0...1` dentro del lienzo de la diapositiva.
    public var normRect: CGRect
    public var text: String
    public var fontSizePt: Double
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool
    public var textColorHex: String?
    public var alignment: PPTXTextAlignment
    public var isBulleted: Bool

    public init(
        id: String = UUID().uuidString,
        shapeIndex: Int? = nil,
        isTitle: Bool = false,
        normRect: CGRect = CGRect(x: 0.08, y: 0.25, width: 0.84, height: 0.28),
        text: String = "",
        fontSizePt: Double = 20,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        textColorHex: String? = nil,
        alignment: PPTXTextAlignment = .leading,
        isBulleted: Bool = false
    ) {
        self.id = id
        self.shapeIndex = shapeIndex
        self.isTitle = isTitle
        self.normRect = normRect
        self.text = text
        self.fontSizePt = fontSizePt
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.textColorHex = textColorHex
        self.alignment = alignment
        self.isBulleted = isBulleted
    }
}

public struct PPTXEmbeddedImage: Identifiable, Sendable, Equatable {
    public let id: String
    public var normRect: CGRect
    public var imageData: Data

    public init(id: String = UUID().uuidString, normRect: CGRect, imageData: Data) {
        self.id = id
        self.normRect = normRect
        self.imageData = imageData
    }
}

public struct PPTXSlideModel: Identifiable, Sendable, Equatable {
    public let id: String
    /// Ruta original en el ZIP (ej. `"ppt/slides/slide1.xml"`), o `nil` para una diapositiva nueva.
    public var archivePath: String?
    /// Ruta de notas del orador si existían en el ZIP.
    public var notesArchivePath: String?
    public var textBoxes: [PPTXTextBox]
    public var images: [PPTXEmbeddedImage]
    public var speakerNotes: String
    public var isModified: Bool

    public init(
        id: String = UUID().uuidString,
        archivePath: String? = nil,
        notesArchivePath: String? = nil,
        textBoxes: [PPTXTextBox] = [],
        images: [PPTXEmbeddedImage] = [],
        speakerNotes: String = "",
        isModified: Bool = false
    ) {
        self.id = id
        self.archivePath = archivePath
        self.notesArchivePath = notesArchivePath
        self.textBoxes = textBoxes
        self.images = images
        self.speakerNotes = speakerNotes
        self.isModified = isModified
    }

    public var summaryTitle: String {
        if let titleBox = textBoxes.first(where: { $0.isTitle && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return titleBox.text.components(separatedBy: .newlines).first ?? ""
        }
        if let firstNonEmpty = textBoxes.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return firstNonEmpty.text.components(separatedBy: .newlines).first ?? ""
        }
        return ""
    }

    public var plainTextSummary: String {
        textBoxes
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

public struct PPTXPresentationModel: Sendable, Equatable {
    public var sourceURL: URL
    /// Relación de aspecto del lienzo (por defecto 16:9).
    public var aspectRatio: CGFloat
    public var slides: [PPTXSlideModel]
    public var deletedSlideArchivePaths: Set<String>

    public init(
        sourceURL: URL,
        aspectRatio: CGFloat = 16.0 / 9.0,
        slides: [PPTXSlideModel] = [],
        deletedSlideArchivePaths: Set<String> = []
    ) {
        self.sourceURL = sourceURL
        self.aspectRatio = aspectRatio
        self.slides = slides
        self.deletedSlideArchivePaths = deletedSlideArchivePaths
    }
}

// MARK: - Motor OOXML Nativo para Microsoft PowerPoint (.pptx)

public enum PPTXDocumentEngine {

    private static let defaultSlideWidthEMU: Double = 9_144_000   // 10 in
    private static let defaultSlideHeightEMU: Double = 5_143_500  // 5.625 in (16:9)

    /// Parsea diapositivas, cuadros de texto, imágenes incrustadas y notas del orador desde un `.pptx`.
    public static func load(from url: URL) throws -> PPTXPresentationModel {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfe_pptx_read_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try OOXMLArchiveUtility.unzip(archiveURL: url, to: tempDir)

        let (slideWidth, slideHeight, slidePaths) = parsePresentationStructure(in: tempDir)
        let aspect = slideHeight > 0 ? CGFloat(slideWidth / slideHeight) : (16.0 / 9.0)

        var slides: [PPTXSlideModel] = []
        for path in slidePaths {
            let slideURL = tempDir.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: slideURL.path(percentEncoded: false)) else { continue }
            let slide = parseSlide(
                at: slideURL,
                archivePath: path,
                rootDir: tempDir,
                slideWidthEMU: slideWidth,
                slideHeightEMU: slideHeight
            )
            slides.append(slide)
        }

        return PPTXPresentationModel(
            sourceURL: url,
            aspectRatio: min(max(aspect, 1.15), 2.2),
            slides: slides
        )
    }

    /// Re-escribe los cuadros de texto modificados, cuadros nuevos, notas y diapositivas duplicadas/borradas dentro del `.pptx`.
    public static func save(presentation: PPTXPresentationModel, to destinationURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfe_pptx_write_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try OOXMLArchiveUtility.unzip(archiveURL: presentation.sourceURL, to: tempDir)
        let (slideWidthEMU, slideHeightEMU, _) = parsePresentationStructure(in: tempDir)

        // 1. Aplicar ediciones a diapositivas existentes
        for slide in presentation.slides where slide.isModified {
            if let archivePath = slide.archivePath {
                let slideURL = tempDir.appendingPathComponent(archivePath)
                if FileManager.default.fileExists(atPath: slideURL.path(percentEncoded: false)) {
                    try rewriteSlideXML(
                        at: slideURL,
                        with: slide,
                        slideWidthEMU: slideWidthEMU,
                        slideHeightEMU: slideHeightEMU
                    )
                }
                if let notesPath = slide.notesArchivePath {
                    let notesURL = tempDir.appendingPathComponent(notesPath)
                    if FileManager.default.fileExists(atPath: notesURL.path(percentEncoded: false)) {
                        try rewriteNotesXML(at: notesURL, notesText: slide.speakerNotes)
                    }
                }
            }
        }

        // 2. Manejar diapositivas agregadas o eliminadas en `presentation.xml`, `_rels` y `[Content_Types].xml`
        let hasStructuralChanges = !presentation.deletedSlideArchivePaths.isEmpty
            || presentation.slides.contains(where: { $0.archivePath == nil })

        if hasStructuralChanges {
            try applySlideStructuralChanges(
                presentation: presentation,
                rootDir: tempDir,
                slideWidthEMU: slideWidthEMU,
                slideHeightEMU: slideHeightEMU
            )
        }

        try OOXMLArchiveUtility.zip(directory: tempDir, to: destinationURL)
    }

    // MARK: - Parseo de Estructura de Presentación

    private static func parsePresentationStructure(in rootDir: URL) -> (Double, Double, [String]) {
        let presURL = rootDir.appendingPathComponent("ppt/presentation.xml")
        let relsURL = rootDir.appendingPathComponent("ppt/_rels/presentation.xml.rels")

        var targetByRelID: [String: String] = [:]
        if let relsDoc = try? XMLDocument(contentsOf: relsURL, options: []),
           let root = relsDoc.rootElement() {
            for rel in OOXMLArchiveUtility.childElements(of: root, localName: "Relationship") {
                if let id = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Id"),
                   let target = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Target") {
                    let clean = target.hasPrefix("/")
                        ? String(target.dropFirst())
                        : (target.hasPrefix("ppt/") ? target : "ppt/\(target)")
                    targetByRelID[id] = clean
                }
            }
        }

        var widthEMU = defaultSlideWidthEMU
        var heightEMU = defaultSlideHeightEMU
        var slidePaths: [String] = []

        if let doc = try? XMLDocument(contentsOf: presURL, options: []),
           let root = doc.rootElement() {
            if let sldSz = OOXMLArchiveUtility.firstChild(of: root, localName: "sldSz") {
                if let cx = OOXMLArchiveUtility.attributeValue(of: sldSz, localName: "cx").flatMap(Double.init), cx > 0 {
                    widthEMU = cx
                }
                if let cy = OOXMLArchiveUtility.attributeValue(of: sldSz, localName: "cy").flatMap(Double.init), cy > 0 {
                    heightEMU = cy
                }
            }
            if let sldIdLst = OOXMLArchiveUtility.firstChild(of: root, localName: "sldIdLst") {
                for sldId in OOXMLArchiveUtility.childElements(of: sldIdLst, localName: "sldId") {
                    if let rid = OOXMLArchiveUtility.relationshipID(of: sldId),
                       let path = targetByRelID[rid] {
                        slidePaths.append(path)
                    }
                }
            }
        }

        // Fallback si el orden no vino en `sldIdLst`
        if slidePaths.isEmpty {
            let slidesDir = rootDir.appendingPathComponent("ppt/slides")
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: slidesDir.path(percentEncoded: false)) {
                slidePaths = entries
                    .filter { $0.hasPrefix("slide") && $0.hasSuffix(".xml") }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    .map { "ppt/slides/\($0)" }
            }
        }

        return (widthEMU, heightEMU, slidePaths)
    }

    private static func parseSlide(
        at slideURL: URL,
        archivePath: String,
        rootDir: URL,
        slideWidthEMU: Double,
        slideHeightEMU: Double
    ) -> PPTXSlideModel {
        // Leer relaciones de la diapositiva para imágenes incrustadas y notas del orador
        let slideFileName = slideURL.lastPathComponent
        let relsURL = slideURL
            .deletingLastPathComponent()
            .appendingPathComponent("_rels/\(slideFileName).rels")

        var relTargetByID: [String: String] = [:]
        var notesArchivePath: String? = nil
        if let relsDoc = try? XMLDocument(contentsOf: relsURL, options: []),
           let root = relsDoc.rootElement() {
            for rel in OOXMLArchiveUtility.childElements(of: root, localName: "Relationship") {
                if let id = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Id"),
                   let target = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Target") {
                    let resolved = resolveRelativeOOXMLPath(from: archivePath, target: target)
                    relTargetByID[id] = resolved
                    let type = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Type") ?? ""
                    if type.lowercased().contains("notesslide") {
                        notesArchivePath = resolved
                    }
                }
            }
        }

        var textBoxes: [PPTXTextBox] = []
        var images: [PPTXEmbeddedImage] = []

        if let doc = try? XMLDocument(contentsOf: slideURL, options: []),
           let root = doc.rootElement(),
           let cSld = OOXMLArchiveUtility.firstChild(of: root, localName: "cSld"),
           let spTree = OOXMLArchiveUtility.firstChild(of: cSld, localName: "spTree") {

            let spElements = OOXMLArchiveUtility.childElements(of: spTree, localName: "sp")
            for (shapeIdx, sp) in spElements.enumerated() {
                guard let txBody = OOXMLArchiveUtility.firstChild(of: sp, localName: "txBody") else { continue }
                let paragraphs = OOXMLArchiveUtility.childElements(of: txBody, localName: "p")

                var lines: [String] = []
                var detectedSize: Double? = nil
                var detectedBold = false
                var detectedItalic = false
                var detectedUnderline = false
                var detectedColor: String? = nil
                var detectedAlign: PPTXTextAlignment = .leading
                var detectedBullet = false

                for pEl in paragraphs {
                    if let pPr = OOXMLArchiveUtility.firstChild(of: pEl, localName: "pPr") {
                        if let algn = OOXMLArchiveUtility.attributeValue(of: pPr, localName: "algn") {
                            switch algn {
                            case "ctr": detectedAlign = .center
                            case "r": detectedAlign = .trailing
                            default: detectedAlign = .leading
                            }
                        }
                        if OOXMLArchiveUtility.firstChild(of: pPr, localName: "buChar") != nil
                            || OOXMLArchiveUtility.firstChild(of: pPr, localName: "buAutoNum") != nil {
                            detectedBullet = true
                        }
                    }

                    var lineText = ""
                    for child in pEl.children ?? [] {
                        guard let el = child as? XMLElement else { continue }
                        let local = el.localName ?? el.name ?? ""
                        if local == "r" || local == "fld" {
                            if let rPr = OOXMLArchiveUtility.firstChild(of: el, localName: "rPr") {
                                if detectedSize == nil,
                                   let szStr = OOXMLArchiveUtility.attributeValue(of: rPr, localName: "sz"),
                                   let szHundredths = Double(szStr), szHundredths > 0 {
                                    detectedSize = szHundredths / 100.0
                                }
                                if OOXMLArchiveUtility.attributeValue(of: rPr, localName: "b") == "1" {
                                    detectedBold = true
                                }
                                if OOXMLArchiveUtility.attributeValue(of: rPr, localName: "i") == "1" {
                                    detectedItalic = true
                                }
                                if let u = OOXMLArchiveUtility.attributeValue(of: rPr, localName: "u"), u != "none" {
                                    detectedUnderline = true
                                }
                                if detectedColor == nil,
                                   let solidFill = OOXMLArchiveUtility.firstChild(of: rPr, localName: "solidFill"),
                                   let srgb = OOXMLArchiveUtility.firstChild(of: solidFill, localName: "srgbClr"),
                                   let hex = OOXMLArchiveUtility.attributeValue(of: srgb, localName: "val") {
                                    detectedColor = hex
                                }
                            }
                            if let t = OOXMLArchiveUtility.firstChild(of: el, localName: "t")?.stringValue {
                                lineText += t
                            }
                        } else if local == "br" {
                            lineText += "\n"
                        }
                    }
                    lines.append(lineText)
                }

                let fullText = lines.joined(separator: "\n")
                let isTitle = detectIsTitlePlaceholder(sp)
                let rect = parseNormalizedFrame(sp, slideWidthEMU: slideWidthEMU, slideHeightEMU: slideHeightEMU)
                    ?? (isTitle
                        ? CGRect(x: 0.07, y: 0.08, width: 0.86, height: 0.18)
                        : CGRect(x: 0.07, y: min(0.72, 0.28 + Double(textBoxes.count) * 0.20), width: 0.86, height: 0.24))

                if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTitle {
                    textBoxes.append(PPTXTextBox(
                        id: "\(archivePath)-sp-\(shapeIdx)",
                        shapeIndex: shapeIdx,
                        isTitle: isTitle,
                        normRect: rect,
                        text: fullText,
                        fontSizePt: detectedSize ?? (isTitle ? 32 : 18),
                        isBold: detectedBold || isTitle,
                        isItalic: detectedItalic,
                        isUnderline: detectedUnderline,
                        textColorHex: detectedColor,
                        alignment: detectedAlign,
                        isBulleted: detectedBullet
                    ))
                }
            }

            // Imágenes incrustadas `<p:pic>`
            let picElements = OOXMLArchiveUtility.childElements(of: spTree, localName: "pic")
            for (picIdx, pic) in picElements.enumerated() {
                guard let blipFill = OOXMLArchiveUtility.firstChild(of: pic, localName: "blipFill"),
                      let blip = OOXMLArchiveUtility.firstChild(of: blipFill, localName: "blip"),
                      let embedID = OOXMLArchiveUtility.attributeValue(of: blip, localName: "embed"),
                      let mediaRelPath = relTargetByID[embedID] else { continue }
                let mediaURL = rootDir.appendingPathComponent(mediaRelPath)
                if let imgData = try? Data(contentsOf: mediaURL) {
                    let rect = parseNormalizedFrame(pic, slideWidthEMU: slideWidthEMU, slideHeightEMU: slideHeightEMU)
                        ?? CGRect(x: 0.55, y: 0.24, width: 0.36, height: 0.50)
                    images.append(PPTXEmbeddedImage(
                        id: "\(archivePath)-pic-\(picIdx)",
                        normRect: rect,
                        imageData: imgData
                    ))
                }
            }
        }

        let speakerNotes: String
        if let notesArchivePath {
            speakerNotes = parseNotesText(at: rootDir.appendingPathComponent(notesArchivePath))
        } else {
            speakerNotes = ""
        }

        return PPTXSlideModel(
            id: archivePath,
            archivePath: archivePath,
            notesArchivePath: notesArchivePath,
            textBoxes: textBoxes,
            images: images,
            speakerNotes: speakerNotes,
            isModified: false
        )
    }

    private static func detectIsTitlePlaceholder(_ sp: XMLElement) -> Bool {
        guard let nvSpPr = OOXMLArchiveUtility.firstChild(of: sp, localName: "nvSpPr"),
              let nvPr = OOXMLArchiveUtility.firstChild(of: nvSpPr, localName: "nvPr"),
              let ph = OOXMLArchiveUtility.firstChild(of: nvPr, localName: "ph") else {
            return false
        }
        let type = (OOXMLArchiveUtility.attributeValue(of: ph, localName: "type") ?? "").lowercased()
        return type == "title" || type == "ctrtitle" || type == "subtitle"
    }

    private static func parseNormalizedFrame(_ shape: XMLElement, slideWidthEMU: Double, slideHeightEMU: Double) -> CGRect? {
        guard let spPr = OOXMLArchiveUtility.firstChild(of: shape, localName: "spPr"),
              let xfrm = OOXMLArchiveUtility.firstChild(of: spPr, localName: "xfrm"),
              let off = OOXMLArchiveUtility.firstChild(of: xfrm, localName: "off"),
              let ext = OOXMLArchiveUtility.firstChild(of: xfrm, localName: "ext"),
              let x = OOXMLArchiveUtility.attributeValue(of: off, localName: "x").flatMap(Double.init),
              let y = OOXMLArchiveUtility.attributeValue(of: off, localName: "y").flatMap(Double.init),
              let cx = OOXMLArchiveUtility.attributeValue(of: ext, localName: "cx").flatMap(Double.init),
              let cy = OOXMLArchiveUtility.attributeValue(of: ext, localName: "cy").flatMap(Double.init),
              cx > 0, cy > 0 else {
            return nil
        }
        return CGRect(
            x: max(0.0, min(0.92, x / slideWidthEMU)),
            y: max(0.0, min(0.92, y / slideHeightEMU)),
            width: max(0.08, min(1.0, cx / slideWidthEMU)),
            height: max(0.06, min(1.0, cy / slideHeightEMU))
        )
    }

    private static func resolveRelativeOOXMLPath(from basePath: String, target: String) -> String {
        if target.hasPrefix("/") {
            return String(target.dropFirst())
        }
        let baseURL = URL(fileURLWithPath: "/\(basePath)").deletingLastPathComponent()
        let resolved = baseURL.appendingPathComponent(target).standardized.path
        return resolved.hasPrefix("/") ? String(resolved.dropFirst()) : resolved
    }

    private static func parseNotesText(at notesURL: URL) -> String {
        guard let doc = try? XMLDocument(contentsOf: notesURL, options: []),
              let root = doc.rootElement(),
              let cSld = OOXMLArchiveUtility.firstChild(of: root, localName: "cSld"),
              let spTree = OOXMLArchiveUtility.firstChild(of: cSld, localName: "spTree") else {
            return ""
        }
        var chunks: [String] = []
        for sp in OOXMLArchiveUtility.childElements(of: spTree, localName: "sp") {
            // Saltar el marcador de número de diapositiva
            if let nvSpPr = OOXMLArchiveUtility.firstChild(of: sp, localName: "nvSpPr"),
               let nvPr = OOXMLArchiveUtility.firstChild(of: nvSpPr, localName: "nvPr"),
               let ph = OOXMLArchiveUtility.firstChild(of: nvPr, localName: "ph"),
               OOXMLArchiveUtility.attributeValue(of: ph, localName: "type")?.lowercased() == "sldnum" {
                continue
            }
            guard let txBody = OOXMLArchiveUtility.firstChild(of: sp, localName: "txBody") else { continue }
            for p in OOXMLArchiveUtility.childElements(of: txBody, localName: "p") {
                let line = OOXMLArchiveUtility.childElements(of: p, localName: "r")
                    .compactMap { OOXMLArchiveUtility.firstChild(of: $0, localName: "t")?.stringValue }
                    .joined()
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chunks.append(line)
                }
            }
        }
        return chunks.joined(separator: "\n")
    }

    // MARK: - Re-escritura Segura de Diapositivas y Notas (.pptx)

    private static func buildTxBodyXML(for box: PPTXTextBox) -> String {
        let lines = box.text.components(separatedBy: .newlines)
        let szHundredths = Int(round(max(8, min(96, box.fontSizePt)) * 100.0))
        let bAttr = box.isBold ? " b=\"1\"" : " b=\"0\""
        let iAttr = box.isItalic ? " i=\"1\"" : " i=\"0\""
        let uAttr = box.isUnderline ? " u=\"sng\"" : ""
        let colorXML: String
        if let hex = box.textColorHex?.replacingOccurrences(of: "#", with: ""), hex.count == 6 {
            colorXML = "<a:solidFill><a:srgbClr val=\"\(hex.uppercased())\"/></a:solidFill>"
        } else {
            colorXML = ""
        }
        let bulletXML = box.isBulleted ? "<a:buChar char=\"•\"/>" : "<a:buNone/>"

        let pXML = lines.map { line in
            let escaped = OOXMLArchiveUtility.xmlEscape(line)
            return """
            <a:p>
              <a:pPr algn="\(box.alignment.ooxmlValue)">\(bulletXML)</a:pPr>
              <a:r>
                <a:rPr lang="en-US" sz="\(szHundredths)"\(bAttr)\(iAttr)\(uAttr) dirty="0">\(colorXML)</a:rPr>
                <a:t>\(escaped)</a:t>
              </a:r>
            </a:p>
            """
        }.joined(separator: "\n")

        return """
        <p:txBody xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <a:bodyPr wrap="square"/>
          <a:lstStyle/>
          \(pXML)
        </p:txBody>
        """
    }

    private static func buildNewShapeXML(
        for box: PPTXTextBox,
        shapeID: Int,
        slideWidthEMU: Double,
        slideHeightEMU: Double
    ) -> String {
        let x = Int(round(box.normRect.origin.x * slideWidthEMU))
        let y = Int(round(box.normRect.origin.y * slideHeightEMU))
        let cx = Int(round(box.normRect.size.width * slideWidthEMU))
        let cy = Int(round(box.normRect.size.height * slideHeightEMU))
        let txBody = buildTxBodyXML(for: box)
        return """
        <p:sp xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <p:nvSpPr>
            <p:cNvPr id="\(shapeID)" name="TextBox \(shapeID)"/>
            <p:cNvSpPr txBox="1"/>
            <p:nvPr/>
          </p:nvSpPr>
          <p:spPr>
            <a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
            <a:noFill/>
          </p:spPr>
          \(txBody)
        </p:sp>
        """
    }

    private static func rewriteSlideXML(
        at slideURL: URL,
        with slide: PPTXSlideModel,
        slideWidthEMU: Double,
        slideHeightEMU: Double
    ) throws {
        let doc = try XMLDocument(contentsOf: slideURL, options: [.nodePreserveAll])
        guard let root = doc.rootElement(),
              let cSld = OOXMLArchiveUtility.firstChild(of: root, localName: "cSld"),
              let spTree = OOXMLArchiveUtility.firstChild(of: cSld, localName: "spTree") else {
            return
        }

        let spElements = OOXMLArchiveUtility.childElements(of: spTree, localName: "sp")

        for box in slide.textBoxes {
            if let shapeIdx = box.shapeIndex, shapeIdx >= 0, shapeIdx < spElements.count {
                let targetSp = spElements[shapeIdx]
                let txDoc = try XMLDocument(xmlString: buildTxBodyXML(for: box), options: [])
                guard let newTxBody = txDoc.rootElement()?.copy() as? XMLElement else { continue }
                if let oldTxBody = OOXMLArchiveUtility.firstChild(of: targetSp, localName: "txBody"),
                   let childIndex = targetSp.children?.firstIndex(of: oldTxBody) {
                    targetSp.replaceChild(at: childIndex, with: newTxBody)
                } else {
                    targetSp.addChild(newTxBody)
                }
            } else {
                // Cuadro de texto nuevo agregado por el usuario
                let nextID = 500 + (spTree.children?.count ?? 1)
                let spDoc = try XMLDocument(
                    xmlString: buildNewShapeXML(for: box, shapeID: nextID, slideWidthEMU: slideWidthEMU, slideHeightEMU: slideHeightEMU),
                    options: []
                )
                if let newSp = spDoc.rootElement()?.copy() as? XMLElement {
                    spTree.addChild(newSp)
                }
            }
        }

        try doc.xmlData(options: [.nodePreserveAll]).write(to: slideURL, options: .atomic)
    }

    private static func rewriteNotesXML(at notesURL: URL, notesText: String) throws {
        let doc = try XMLDocument(contentsOf: notesURL, options: [.nodePreserveAll])
        guard let root = doc.rootElement(),
              let cSld = OOXMLArchiveUtility.firstChild(of: root, localName: "cSld"),
              let spTree = OOXMLArchiveUtility.firstChild(of: cSld, localName: "spTree") else {
            return
        }
        for sp in OOXMLArchiveUtility.childElements(of: spTree, localName: "sp") {
            if let nvSpPr = OOXMLArchiveUtility.firstChild(of: sp, localName: "nvSpPr"),
               let nvPr = OOXMLArchiveUtility.firstChild(of: nvSpPr, localName: "nvPr"),
               let ph = OOXMLArchiveUtility.firstChild(of: nvPr, localName: "ph"),
               OOXMLArchiveUtility.attributeValue(of: ph, localName: "type")?.lowercased() == "body" {
                let box = PPTXTextBox(text: notesText, fontSizePt: 14)
                let txDoc = try XMLDocument(xmlString: buildTxBodyXML(for: box), options: [])
                if let newTx = txDoc.rootElement()?.copy() as? XMLElement,
                   let oldTx = OOXMLArchiveUtility.firstChild(of: sp, localName: "txBody"),
                   let idx = sp.children?.firstIndex(of: oldTx) {
                    sp.replaceChild(at: idx, with: newTx)
                }
                break
            }
        }
        try doc.xmlData(options: [.nodePreserveAll]).write(to: notesURL, options: .atomic)
    }

    /// Crea archivos XML para diapositivas nuevas/duplicadas y actualiza el orden/bajas en `presentation.xml`.
    private static func applySlideStructuralChanges(
        presentation: PPTXPresentationModel,
        rootDir: URL,
        slideWidthEMU: Double,
        slideHeightEMU: Double
    ) throws {
        let presURL = rootDir.appendingPathComponent("ppt/presentation.xml")
        let relsURL = rootDir.appendingPathComponent("ppt/_rels/presentation.xml.rels")
        let contentTypesURL = rootDir.appendingPathComponent("[Content_Types].xml")

        guard let presDoc = try? XMLDocument(contentsOf: presURL, options: [.nodePreserveAll]),
              let presRoot = presDoc.rootElement(),
              let sldIdLst = OOXMLArchiveUtility.firstChild(of: presRoot, localName: "sldIdLst"),
              let relsDoc = try? XMLDocument(contentsOf: relsURL, options: [.nodePreserveAll]),
              let relsRoot = relsDoc.rootElement() else {
            return
        }

        // Mapear `archivePath -> rId` existente
        var relIDByPath: [String: String] = [:]
        var maxRelNum = 100
        for rel in OOXMLArchiveUtility.childElements(of: relsRoot, localName: "Relationship") {
            if let id = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Id"),
               let target = OOXMLArchiveUtility.attributeValue(of: rel, localName: "Target") {
                let clean = target.hasPrefix("/") ? String(target.dropFirst()) : (target.hasPrefix("ppt/") ? target : "ppt/\(target)")
                relIDByPath[clean] = id
                if id.hasPrefix("rId"), let num = Int(id.dropFirst(3)) {
                    maxRelNum = max(maxRelNum, num)
                }
            }
        }

        // Determinar el mayor número de `slideN.xml` y `sldId`
        let slidesDir = rootDir.appendingPathComponent("ppt/slides")
        var maxSlideFileNum = 1
        if let files = try? FileManager.default.contentsOfDirectory(atPath: slidesDir.path(percentEncoded: false)) {
            for f in files where f.hasPrefix("slide") && f.hasSuffix(".xml") {
                let mid = f.dropFirst(5).dropLast(4)
                if let n = Int(mid) { maxSlideFileNum = max(maxSlideFileNum, n) }
            }
        }
        var maxSlideID: UInt32 = 256
        for sldId in OOXMLArchiveUtility.childElements(of: sldIdLst, localName: "sldId") {
            if let idStr = OOXMLArchiveUtility.attributeValue(of: sldId, localName: "id"),
               let n = UInt32(idStr) {
                maxSlideID = max(maxSlideID, n)
            }
        }

        // Eliminar referencias de diapositivas borradas en `sldIdLst`
        let deletedSet = presentation.deletedSlideArchivePaths
        if !deletedSet.isEmpty {
            let deletedRelIDs = Set(deletedSet.compactMap { relIDByPath[$0] })
            for child in (sldIdLst.children ?? []).reversed() {
                if let el = child as? XMLElement,
                   let rid = OOXMLArchiveUtility.relationshipID(of: el),
                   deletedRelIDs.contains(rid) {
                    el.detach()
                }
            }
        }

        // Agregar nuevas diapositivas
        let ctDoc = try? XMLDocument(contentsOf: contentTypesURL, options: [.nodePreserveAll])
        for slide in presentation.slides where slide.archivePath == nil {
            maxSlideFileNum += 1
            maxRelNum += 1
            maxSlideID += 1

            let fileName = "slide\(maxSlideFileNum).xml"
            let newRelID = "rId\(maxRelNum)"
            let newSlideURL = slidesDir.appendingPathComponent(fileName)

            let shapesXML = slide.textBoxes.enumerated().map { idx, box in
                buildNewShapeXML(for: box, shapeID: 10 + idx, slideWidthEMU: slideWidthEMU, slideHeightEMU: slideHeightEMU)
            }.joined(separator: "\n")

            let minimalSlideXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
              <p:cSld>
                <p:spTree>
                  <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
                  <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
                  \(shapesXML)
                </p:spTree>
              </p:cSld>
            </p:sld>
            """
            try minimalSlideXML.write(to: newSlideURL, atomically: true, encoding: .utf8)

            // Registrar relación en `ppt/_rels/presentation.xml.rels`
            let relEl = XMLElement(name: "Relationship")
            relEl.setAttributesWith([
                "Id": newRelID,
                "Type": "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide",
                "Target": "slides/\(fileName)"
            ])
            relsRoot.addChild(relEl)

            // Registrar en `<p:sldIdLst>`
            let sldIdEl = XMLElement(name: "p:sldId")
            sldIdEl.setAttributesWith(["id": "\(maxSlideID)", "r:id": newRelID])
            sldIdLst.addChild(sldIdEl)

            // Registrar en `[Content_Types].xml`
            if let ctRoot = ctDoc?.rootElement() {
                let ov = XMLElement(name: "Override")
                ov.setAttributesWith([
                    "PartName": "/ppt/slides/\(fileName)",
                    "ContentType": "application/vnd.openxmlformats-officedocument.presentationml.slide+xml"
                ])
                ctRoot.addChild(ov)
            }
        }

        try presDoc.xmlData(options: [.nodePreserveAll]).write(to: presURL, options: .atomic)
        try relsDoc.xmlData(options: [.nodePreserveAll]).write(to: relsURL, options: .atomic)
        if let ctDoc {
            try ctDoc.xmlData(options: [.nodePreserveAll]).write(to: contentTypesURL, options: .atomic)
        }
    }
}
