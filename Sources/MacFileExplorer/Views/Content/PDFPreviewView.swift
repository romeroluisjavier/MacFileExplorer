import AppKit
import Foundation
import PDFKit
import SwiftUI

// MARK: - Herramienta Activa del Visor PDF Interactivo

public enum PDFPreviewToolMode: String, CaseIterable, Identifiable, Sendable {
    case selectText
    case captureImage

    public var id: String { rawValue }
}

// MARK: - Anotación de Imagen Pegada sobre una Página PDF

/// Anotación PDF nativa que dibuja una imagen (`NSImage`) pegada desde el portapapeles sobre la página
/// y se conserva al guardar el PDF.
private final class PDFPastedImageAnnotation: PDFAnnotation {
    let pastedImage: NSImage

    init(bounds: CGRect, image: NSImage) {
        self.pastedImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.shouldDisplay = true
        self.shouldPrint = true
    }

    required init?(coder: NSCoder) {
        self.pastedImage = NSImage()
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = pastedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            super.draw(with: box, in: context)
            return
        }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}

// MARK: - Subclase Interactiva de `PDFView` (Selección de Texto, Captura de Área, Copiar y Pegar)

@MainActor
private final class InteractiveExplorerPDFView: PDFView {
    var toolMode: PDFPreviewToolMode = .selectText {
        didSet {
            if toolMode != .captureImage {
                clearMarqueeSelection()
            }
            window?.invalidateCursorRects(for: self)
        }
    }

    var onCopySelectionTriggered: (() -> Void)?
    var onCopyPageImageTriggered: (() -> Void)?
    var onPasteTriggered: (() -> Void)?
    var onSaveTriggered: (() -> Void)?
    var onFindTriggered: (() -> Void)?
    var onImageRegionCaptured: ((NSImage, CGSize) -> Void)?

    private var dragStartPoint: NSPoint?
    private var marqueeRect: NSRect = .zero
    private let marqueeOverlayLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureMarqueeLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureMarqueeLayer() {
        marqueeOverlayLayer.strokeColor = NSColor.controlAccentColor.cgColor
        marqueeOverlayLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        marqueeOverlayLayer.lineWidth = 1.8
        marqueeOverlayLayer.lineDashPattern = [5, 4]
        marqueeOverlayLayer.isHidden = true
        marqueeOverlayLayer.zPosition = 999
        layer?.addSublayer(marqueeOverlayLayer)
    }

    private func ensureMarqueeLayerAttached() {
        if marqueeOverlayLayer.superlayer == nil {
            wantsLayer = true
            layer?.addSublayer(marqueeOverlayLayer)
        }
    }

    private func clearMarqueeSelection() {
        dragStartPoint = nil
        marqueeRect = .zero
        marqueeOverlayLayer.isHidden = true
        marqueeOverlayLayer.path = nil
    }

    override func resetCursorRects() {
        if toolMode == .captureImage {
            addCursorRect(bounds, cursor: .crosshair)
        } else {
            super.resetCursorRects()
        }
    }

    // MARK: - Atajos de Teclado Nativos (⌘C, ⌘V, ⌘A, ⌘F, ⌘S)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == .command {
            switch key {
            case "c":
                onCopySelectionTriggered?()
                return true
            case "v":
                onPasteTriggered?()
                return true
            case "a":
                selectAll(nil)
                return true
            case "f":
                onFindTriggered?()
                return true
            case "s":
                onSaveTriggered?()
                return true
            case "+", "=":
                zoomIn(nil)
                return true
            case "-":
                zoomOut(nil)
                return true
            case "0":
                autoScales = true
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Menú Contextual Enriquecido (Clic Derecho en el PDF)

    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = LocalizationManager.shared
        let menu = super.menu(for: event) ?? NSMenu()
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }

        let pasteItem = NSMenuItem(
            title: loc.text(es: "Pegar texto o imagen aquí (⌘V)", en: "Paste Text or Image Here (⌘V)"),
            action: #selector(handleContextPaste(_:)),
            keyEquivalent: ""
        )
        pasteItem.target = self
        menu.insertItem(pasteItem, at: 0)

        let copyPageImgItem = NSMenuItem(
            title: loc.text(es: "Copiar página actual como imagen", en: "Copy Current Page as Image"),
            action: #selector(handleContextCopyPageImage(_:)),
            keyEquivalent: ""
        )
        copyPageImgItem.target = self
        menu.insertItem(copyPageImgItem, at: 0)

        let hasSelection = !(currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let copyTextItem = NSMenuItem(
            title: hasSelection
                ? loc.text(es: "Copiar texto seleccionado (⌘C)", en: "Copy Selected Text (⌘C)")
                : loc.text(es: "Copiar texto de esta página (⌘C)", en: "Copy Current Page Text (⌘C)"),
            action: #selector(handleContextCopyText(_:)),
            keyEquivalent: ""
        )
        copyTextItem.target = self
        menu.insertItem(copyTextItem, at: 0)

        return menu
    }

    @objc private func handleContextCopyText(_ sender: Any?) {
        onCopySelectionTriggered?()
    }

    @objc private func handleContextCopyPageImage(_ sender: Any?) {
        onCopyPageImageTriggered?()
    }

    @objc private func handleContextPaste(_ sender: Any?) {
        onPasteTriggered?()
    }

    // MARK: - Selección Rectangular para Copiar Región como Imagen HD

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard toolMode == .captureImage else {
            super.mouseDown(with: event)
            return
        }
        ensureMarqueeLayerAttached()
        let pt = convert(event.locationInWindow, from: nil)
        dragStartPoint = pt
        marqueeRect = NSRect(origin: pt, size: .zero)
        marqueeOverlayLayer.isHidden = false
        marqueeOverlayLayer.path = CGPath(rect: marqueeRect, transform: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard toolMode == .captureImage, let start = dragStartPoint else {
            super.mouseDragged(with: event)
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).intersection(bounds)
        marqueeRect = rect
        marqueeOverlayLayer.path = CGPath(rect: rect, transform: nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard toolMode == .captureImage, dragStartPoint != nil else {
            super.mouseUp(with: event)
            return
        }
        let finalRect = marqueeRect
        clearMarqueeSelection()

        guard finalRect.width >= 10, finalRect.height >= 10 else {
            return
        }
        captureRegionAsImage(viewRect: finalRect)
    }

    private func captureRegionAsImage(viewRect: NSRect) {
        let centerPt = NSPoint(x: viewRect.midX, y: viewRect.midY)
        guard let page = page(for: centerPt, nearest: true) else { return }

        let pageRect = convert(viewRect, to: page)
        let pageBounds = page.bounds(for: .cropBox)
        let clipped = pageRect.intersection(pageBounds)
        guard clipped.width >= 4, clipped.height >= 4 else { return }

        // Renderizar recorte en alta resolución (2.5x Retina para máxima nitidez)
        let scale: CGFloat = 2.5
        let pixelW = max(1, Int((clipped.width * scale).rounded()))
        let pixelH = max(1, Int((clipped.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        rep.size = NSSize(width: clipped.width, height: clipped.height)
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            let cg = ctx.cgContext
            cg.setFillColor(NSColor.white.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: clipped.width, height: clipped.height))
            cg.translateBy(x: -clipped.origin.x, y: -clipped.origin.y)
            page.draw(with: .cropBox, to: cg)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: clipped.width, height: clipped.height))
        image.addRepresentation(rep)
        onImageRegionCaptured?(image, CGSize(width: pixelW, height: pixelH))
    }
}

// MARK: - Controlador Observable del Visor PDF

@MainActor
@Observable
private final class PDFPreviewController: NSObject {
    var document: PDFDocument?
    var currentPageIndex: Int = 0
    var pageCount: Int = 0
    var zoomPercent: Int = 100
    var hasTextSelection: Bool = false
    var toolMode: PDFPreviewToolMode = .selectText
    var showThumbnails: Bool = false
    var isSearchVisible: Bool = false
    var searchQuery: String = ""
    var searchMatches: [PDFSelection] = []
    var activeMatchIndex: Int = 0
    var hasUnsavedEdits: Bool = false
    var addedAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
    var feedbackBanner: (text: String, isError: Bool)? = nil
    var loadError: String? = nil

    weak var pdfView: InteractiveExplorerPDFView?
    weak var thumbnailView: PDFThumbnailView?

    private var fileURL: URL?
    private var feedbackClearTask: Task<Void, Never>?

    func load(url: URL) {
        fileURL = url
        loadError = nil
        hasUnsavedEdits = false
        addedAnnotations.removeAll()
        searchMatches.removeAll()
        activeMatchIndex = 0

        guard let doc = PDFDocument(url: url) else {
            document = nil
            pageCount = 0
            currentPageIndex = 0
            loadError = LocalizationManager.shared.text(
                es: "No se pudo abrir este archivo PDF.",
                en: "Could not open this PDF file."
            )
            return
        }

        document = doc
        pageCount = doc.pageCount
        currentPageIndex = 0
        applyDocumentToViews()
    }

    func attach(pdfView: InteractiveExplorerPDFView, thumbnailView: PDFThumbnailView) {
        self.pdfView = pdfView
        self.thumbnailView = thumbnailView
        thumbnailView.pdfView = pdfView

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        pdfView.toolMode = toolMode
        pdfView.onCopySelectionTriggered = { [weak self] in
            self?.copySelectedOrPageText()
        }
        pdfView.onCopyPageImageTriggered = { [weak self] in
            self?.copyCurrentPageAsImage()
        }
        pdfView.onPasteTriggered = { [weak self] in
            self?.pasteFromClipboardIntoCurrentPage()
        }
        pdfView.onSaveTriggered = { [weak self] in
            self?.saveDocumentChanges()
        }
        pdfView.onFindTriggered = { [weak self] in
            self?.isSearchVisible = true
        }
        pdfView.onImageRegionCaptured = { [weak self] image, pixelSize in
            self?.writeImageToPasteboard(image)
            let loc = LocalizationManager.shared
            self?.showFeedback(
                loc.text(
                    es: "Recorte copiado como imagen (\(Int(pixelSize.width))×\(Int(pixelSize.height)) px)",
                    en: "Region copied as image (\(Int(pixelSize.width))×\(Int(pixelSize.height)) px)"
                )
            )
            self?.setToolMode(.selectText)
        }

        applyDocumentToViews()
    }

    private func applyDocumentToViews() {
        guard let pdfView, let doc = document else { return }
        if pdfView.document !== doc {
            pdfView.document = doc
            pdfView.autoScales = true
            pdfView.displayMode = .singlePageContinuous
            pdfView.displaysPageBreaks = true
            pdfView.displayDirection = .vertical
            pdfView.backgroundColor = NSColor.underPageBackgroundColor
        }
        thumbnailView?.pdfView = pdfView
        syncStateFromPDFView()
    }

    func setToolMode(_ mode: PDFPreviewToolMode) {
        toolMode = mode
        pdfView?.toolMode = mode
        if mode == .captureImage {
            let loc = LocalizationManager.shared
            showFeedback(
                loc.text(
                    es: "Arrastrá un rectángulo sobre el PDF para copiarlo como imagen",
                    en: "Drag a rectangle over the PDF to copy it as an image"
                )
            )
        }
    }

    // MARK: - Navegación y Zoom

    func goToPreviousPage() {
        pdfView?.goToPreviousPage(nil)
        syncStateFromPDFView()
    }

    func goToNextPage() {
        pdfView?.goToNextPage(nil)
        syncStateFromPDFView()
    }

    func zoomIn() {
        pdfView?.autoScales = false
        pdfView?.zoomIn(nil)
        syncStateFromPDFView()
    }

    func zoomOut() {
        pdfView?.autoScales = false
        pdfView?.zoomOut(nil)
        syncStateFromPDFView()
    }

    func resetZoomFit() {
        pdfView?.autoScales = true
        syncStateFromPDFView()
    }

    func rotateCurrentPageRight() {
        guard let page = pdfView?.currentPage else { return }
        page.rotation = (page.rotation + 90) % 360
        hasUnsavedEdits = true
        pdfView?.layoutDocumentView()
        let loc = LocalizationManager.shared
        showFeedback(loc.text(es: "Página rotada 90° (guardá con ⌘S)", en: "Page rotated 90° (save with ⌘S)"))
    }

    // MARK: - Copiar Texto e Imágenes

    func copySelectedOrPageText() {
        let loc = LocalizationManager.shared
        if let selected = pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selected.isEmpty {
            writeTextToPasteboard(selected)
            showFeedback(loc.text(es: "Texto seleccionado copiado", en: "Selected text copied"))
            return
        }

        if let pageText = pdfView?.currentPage?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pageText.isEmpty {
            writeTextToPasteboard(pageText)
            showFeedback(
                loc.text(
                    es: "Texto de la página \(currentPageIndex + 1) copiado",
                    en: "Page \(currentPageIndex + 1) text copied"
                )
            )
            return
        }

        // Si la página es una imagen escaneada sin capa de texto, copiarla como imagen HD automáticamente
        copyCurrentPageAsImage()
    }

    func copyAllDocumentText() {
        let loc = LocalizationManager.shared
        guard let fullText = document?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fullText.isEmpty else {
            showFeedback(
                loc.text(
                    es: "Este PDF no contiene texto seleccionable (podés copiarlo como imagen).",
                    en: "This PDF has no selectable text (you can copy it as an image)."
                ),
                isError: true
            )
            return
        }
        writeTextToPasteboard(fullText)
        showFeedback(
            loc.text(
                es: "Todo el texto del PDF copiado (\(pageCount) págs.)",
                en: "All PDF text copied (\(pageCount) pages)"
            )
        )
    }

    func copyCurrentPageAsImage() {
        let loc = LocalizationManager.shared
        guard let page = pdfView?.currentPage ?? document?.page(at: currentPageIndex) else { return }
        let pageBounds = page.bounds(for: .cropBox)
        let scale: CGFloat = 2.0
        let targetSize = NSSize(width: max(1, pageBounds.width * scale), height: max(1, pageBounds.height * scale))
        let rendered = page.thumbnail(of: targetSize, for: .cropBox)
        writeImageToPasteboard(rendered)
        showFeedback(
            loc.text(
                es: "Página \(currentPageIndex + 1) copiada como imagen",
                en: "Page \(currentPageIndex + 1) copied as image"
            )
        )
    }

    // MARK: - Pegar Texto o Imagen sobre la Página Actual (y Guardar / Deshacer)

    func pasteFromClipboardIntoCurrentPage() {
        let loc = LocalizationManager.shared
        guard let page = pdfView?.currentPage ?? document?.page(at: currentPageIndex) else { return }
        let pb = NSPasteboard.general
        let pageBounds = page.bounds(for: .cropBox)

        // 1. Si hay una imagen en el portapapeles, pegarla como sello de imagen nítido en la página
        if let image = NSImage(pasteboard: pb), image.size.width > 1, image.size.height > 1 {
            let maxW = pageBounds.width * 0.48
            let maxH = pageBounds.height * 0.42
            let ratio = min(maxW / image.size.width, maxH / image.size.height, 1.0)
            let drawW = max(48, image.size.width * ratio)
            let drawH = max(48, image.size.height * ratio)
            let offset = CGFloat(addedAnnotations.count % 5) * 16.0
            let rect = CGRect(
                x: pageBounds.midX - drawW * 0.5 + offset,
                y: pageBounds.midY - drawH * 0.5 - offset,
                width: drawW,
                height: drawH
            )
            let annotation = PDFPastedImageAnnotation(bounds: rect, image: image)
            page.addAnnotation(annotation)
            addedAnnotations.append((page: page, annotation: annotation))
            hasUnsavedEdits = true
            pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
            showFeedback(
                loc.text(
                    es: "Imagen pegada en pág. \(currentPageIndex + 1) (guardá con ⌘S)",
                    en: "Image pasted on page \(currentPageIndex + 1) (save with ⌘S)"
                )
            )
            return
        }

        // 2. Si hay texto en el portapapeles, pegarlo como anotación de texto legible sobre la página
        if let rawText = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawText.isEmpty {
            let clippedText = rawText.count > 420 ? String(rawText.prefix(420)) + "…" : rawText
            let boxWidth = min(pageBounds.width * 0.58, 300)
            let estimatedLines = max(2, min(8, Int(ceil(Double(clippedText.count) / 38.0))))
            let boxHeight = CGFloat(estimatedLines) * 18.0 + 18.0
            let offset = CGFloat(addedAnnotations.count % 5) * 18.0
            let rect = CGRect(
                x: pageBounds.minX + 36 + offset,
                y: max(pageBounds.minY + 36, pageBounds.maxY - boxHeight - 48 - offset),
                width: boxWidth,
                height: boxHeight
            )
            let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            annotation.contents = clippedText
            annotation.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
            annotation.fontColor = NSColor.black
            annotation.color = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.72, alpha: 0.95)
            let border = PDFBorder()
            border.lineWidth = 1.0
            annotation.border = border
            page.addAnnotation(annotation)
            addedAnnotations.append((page: page, annotation: annotation))
            hasUnsavedEdits = true
            pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
            showFeedback(
                loc.text(
                    es: "Texto pegado en pág. \(currentPageIndex + 1) (guardá con ⌘S)",
                    en: "Text pasted on page \(currentPageIndex + 1) (save with ⌘S)"
                )
            )
            return
        }

        showFeedback(
            loc.text(
                es: "El portapapeles no tiene texto ni imagen para pegar.",
                en: "Clipboard has no text or image to paste."
            ),
            isError: true
        )
    }

    func undoLastPastedAnnotation() {
        let loc = LocalizationManager.shared
        guard let last = addedAnnotations.popLast() else { return }
        last.page.removeAnnotation(last.annotation)
        pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
        showFeedback(loc.text(es: "Último pegado deshecho", en: "Undid last paste"))
    }

    func saveDocumentChanges() {
        let loc = LocalizationManager.shared
        guard let document, let fileURL else { return }

        bakePastedImageAnnotations(in: document)

        if document.write(to: fileURL) {
            hasUnsavedEdits = false
            showFeedback(loc.text(es: "PDF guardado correctamente", en: "PDF saved successfully"))
        } else {
            showFeedback(
                loc.text(es: "No se pudo guardar el PDF (puede ser de solo lectura).", en: "Could not save PDF (file may be read-only)."),
                isError: true
            )
        }
    }

    /// Consolida las anotaciones `PDFPastedImageAnnotation` dentro del contenido vectorial real de cada página
    /// mediante `CGPDFContext` antes de llamar a `PDFDocument.write(to:)`, garantizando que las imágenes pegadas
    /// se conserven nítidas al reabrir el PDF sin perder texto seleccionable ni el resto de anotaciones.
    private func bakePastedImageAnnotations(in document: PDFDocument) {
        let activePageIndex = currentPageIndex
        var didBakeAny = false

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pastedImages = page.annotations.compactMap { $0 as? PDFPastedImageAnnotation }
            guard !pastedImages.isEmpty else { continue }

            var mediaBox = page.bounds(for: .mediaBox)
            let cropBox = page.bounds(for: .cropBox)
            guard mediaBox.width > 0, mediaBox.height > 0 else { continue }

            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                continue
            }

            var pageInfo: [CFString: Any] = [
                kCGPDFContextMediaBox: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
            ]
            if cropBox != mediaBox {
                var cropBoxCopy = cropBox
                pageInfo[kCGPDFContextCropBox] = Data(bytes: &cropBoxCopy, count: MemoryLayout<CGRect>.size)
            }

            pdfContext.beginPDFPage(pageInfo as CFDictionary)
            if let cgPage = page.pageRef {
                // Dibuja el contenido vectorial y de texto original de la página en su espacio de coordenadas PDF
                pdfContext.drawPDFPage(cgPage)
                for imgAnn in pastedImages {
                    if let cgImage = imgAnn.pastedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        pdfContext.saveGState()
                        pdfContext.interpolationQuality = .high
                        pdfContext.draw(cgImage, in: imgAnn.bounds)
                        pdfContext.restoreGState()
                    }
                }
            } else {
                // Respaldo para páginas sintéticas sin CGPDFPage (dibuja la página junto con sus anotaciones)
                page.draw(with: .mediaBox, to: pdfContext)
            }
            pdfContext.endPDFPage()
            pdfContext.closePDF()

            guard let bakedDoc = PDFDocument(data: pdfData as Data),
                  let bakedPage = bakedDoc.page(at: 0) else {
                continue
            }

            bakedPage.rotation = page.rotation
            // Preservar el resto de anotaciones nativas (enlaces, texto pegado .freeText, comentarios, etc.)
            for otherAnn in page.annotations where !(otherAnn is PDFPastedImageAnnotation) {
                bakedPage.addAnnotation(otherAnn)
            }

            document.insert(bakedPage, at: pageIndex)
            document.removePage(at: pageIndex + 1)

            // Actualizar referencias pendientes en addedAnnotations
            addedAnnotations.removeAll { entry in
                entry.page === page && (entry.annotation is PDFPastedImageAnnotation)
            }
            for i in addedAnnotations.indices where addedAnnotations[i].page === page {
                addedAnnotations[i] = (page: bakedPage, annotation: addedAnnotations[i].annotation)
            }
            didBakeAny = true
        }

        if didBakeAny, let targetPage = document.page(at: min(activePageIndex, max(0, document.pageCount - 1))) {
            pdfView?.go(to: targetPage)
            pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
        }
    }

    // MARK: - Búsqueda de Texto en Vivo (⌘F)

    func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let document else {
            searchMatches = []
            activeMatchIndex = 0
            pdfView?.highlightedSelections = nil
            return
        }

        let results = document.findString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive])
        searchMatches = results
        activeMatchIndex = 0
        for sel in results {
            sel.color = NSColor.systemYellow.withAlphaComponent(0.45)
        }
        pdfView?.highlightedSelections = results
        if let first = results.first {
            pdfView?.setCurrentSelection(first, animate: true)
            pdfView?.go(to: first)
            syncStateFromPDFView()
        }
    }

    func selectNextSearchMatch(offset: Int) {
        guard !searchMatches.isEmpty else { return }
        let count = searchMatches.count
        activeMatchIndex = ((activeMatchIndex + offset) % count + count) % count
        let match = searchMatches[activeMatchIndex]
        pdfView?.setCurrentSelection(match, animate: true)
        pdfView?.go(to: match)
        syncStateFromPDFView()
    }

    func clearSearch() {
        searchQuery = ""
        searchMatches = []
        activeMatchIndex = 0
        pdfView?.highlightedSelections = nil
        isSearchVisible = false
    }

    // MARK: - Helpers Privados

    private func writeTextToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func writeImageToPasteboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
            pb.setData(tiff, forType: .tiff)
        } else {
            pb.writeObjects([image])
        }
    }

    private func showFeedback(_ text: String, isError: Bool = false) {
        feedbackClearTask?.cancel()
        feedbackBanner = (text: text, isError: isError)
        feedbackClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.feedbackBanner = nil
        }
    }

    private func syncStateFromPDFView() {
        guard let pdfView, let doc = document else { return }
        pageCount = doc.pageCount
        if let page = pdfView.currentPage {
            currentPageIndex = doc.index(for: page)
        }
        zoomPercent = max(10, Int((pdfView.scaleFactor * 100.0).rounded()))
        let selected = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasTextSelection = !selected.isEmpty
    }

    @objc private func handlePageChanged(_ notification: Notification) {
        syncStateFromPDFView()
    }

    @objc private func handleScaleChanged(_ notification: Notification) {
        syncStateFromPDFView()
    }

    @objc private func handleSelectionChanged(_ notification: Notification) {
        syncStateFromPDFView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Puente `NSViewRepresentable` (PDFView + Barra Lateral de Miniaturas)

private struct InteractivePDFCanvasRepresentable: NSViewRepresentable {
    let controller: PDFPreviewController
    let showThumbnails: Bool
    let toolMode: PDFPreviewToolMode

    func makeNSView(context: Context) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        let thumbView = PDFThumbnailView()
        thumbView.thumbnailSize = NSSize(width: 92, height: 120)
        thumbView.backgroundColor = NSColor.windowBackgroundColor
        thumbView.translatesAutoresizingMaskIntoConstraints = true
        thumbView.frame = NSRect(x: 0, y: 0, width: 124, height: 500)

        let pdfView = InteractiveExplorerPDFView(frame: NSRect(x: 0, y: 0, width: 760, height: 500))
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true

        split.addArrangedSubview(thumbView)
        split.addArrangedSubview(pdfView)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        thumbView.isHidden = !showThumbnails

        controller.attach(pdfView: pdfView, thumbnailView: thumbView)
        return split
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        guard nsView.arrangedSubviews.count == 2,
              let thumbView = nsView.arrangedSubviews[0] as? PDFThumbnailView,
              let pdfView = nsView.arrangedSubviews[1] as? InteractiveExplorerPDFView else {
            return
        }
        if thumbView.isHidden == showThumbnails {
            thumbView.isHidden = !showThumbnails
            if showThumbnails {
                nsView.setPosition(128, ofDividerAt: 0)
            }
        }
        if pdfView.toolMode != toolMode {
            pdfView.toolMode = toolMode
        }
    }
}

// MARK: - Vista Principal del Visor PDF Interactivo para Quick Look

/// Visor PDF nativo interactivo (`PDFKit`) para Quick Look (`Espacio`):
/// - Selección de texto con copia directa (`⌘C`), copia de página completa o documento entero.
/// - Herramienta de recorte rectangular para copiar cualquier gráfico/imagen del PDF en HD (`2.5×`).
/// - Pegado directo (`⌘V`) de texto o imágenes sobre la página con Deshacer y Guardar (`⌘S`).
/// - Búsqueda de texto (`⌘F`) con resaltado en vivo, miniaturas de páginas, zoom y rotación.
public struct PDFPreviewView: View {
    public let fileURL: URL

    @Bindable private var loc = LocalizationManager.shared
    @ViewState private var controller = PDFPreviewController()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            pdfToolbar
            Divider()

            if controller.isSearchVisible {
                pdfSearchBar
                Divider()
            }

            if let error = controller.loadError {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
            } else {
                ZStack(alignment: .bottom) {
                    InteractivePDFCanvasRepresentable(
                        controller: controller,
                        showThumbnails: controller.showThumbnails,
                        toolMode: controller.toolMode
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let feedback = controller.feedbackBanner {
                        HStack(spacing: 6) {
                            Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(feedback.isError ? Color.orange : Color.green)
                            Text(feedback.text)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.84))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                                )
                        )
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: controller.feedbackBanner?.text)
            }
        }
        .onAppear {
            controller.load(url: fileURL)
        }
        .onChange(of: fileURL) { _, newURL in
            controller.load(url: newURL)
        }
    }

    // MARK: - Barra de Herramientas Interactiva del PDF

    private var pdfToolbar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // 1. Miniaturas + Navegación de páginas
                    PreviewToolbarIconButton(
                        "sidebar.left",
                        active: controller.showThumbnails,
                        help: loc.text(es: "Mostrar u ocultar miniaturas de páginas", en: "Toggle page thumbnails")
                    ) {
                        controller.showThumbnails.toggle()
                    }

                    HStack(spacing: 3) {
                        PreviewToolbarIconButton(
                            "chevron.up",
                            help: loc.text(es: "Página anterior", en: "Previous page"),
                            disabled: controller.currentPageIndex <= 0
                        ) {
                            controller.goToPreviousPage()
                        }

                        Text("\(min(controller.currentPageIndex + 1, max(controller.pageCount, 1))) / \(max(controller.pageCount, 1))")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 42)
                            .multilineTextAlignment(.center)

                        PreviewToolbarIconButton(
                            "chevron.down",
                            help: loc.text(es: "Página siguiente", en: "Next page"),
                            disabled: controller.currentPageIndex >= max(controller.pageCount - 1, 0)
                        ) {
                            controller.goToNextPage()
                        }
                    }

                    Divider().frame(height: 16)

                    // 2. Modo de cursor: Seleccionar texto vs Recortar imagen
                    Button {
                        controller.setToolMode(.selectText)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.cursor")
                                .font(.system(size: 12, weight: .medium))
                            Text(loc.text(es: "Texto", en: "Text"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(PreviewToolbarButtonStyle(variant: controller.toolMode == .selectText ? .prominent : .standard))
                    .help(loc.text(es: "Seleccionar texto del PDF para copiar (⌘C)", en: "Select PDF text to copy (⌘C)"))

                    Button {
                        controller.setToolMode(controller.toolMode == .captureImage ? .selectText : .captureImage)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "crop")
                                .font(.system(size: 12, weight: .medium))
                            Text(loc.text(es: "Copiar imagen", en: "Copy Image"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(PreviewToolbarButtonStyle(variant: controller.toolMode == .captureImage ? .prominent : .standard))
                    .help(loc.text(es: "Arrastrá sobre cualquier zona del PDF para copiarla como imagen", en: "Drag over any PDF region to copy it as an image"))

                    Divider().frame(height: 16)

                    // 3. Copiar (Texto seleccionado / página / todo / página como imagen)
                    Menu {
                        Button {
                            controller.copySelectedOrPageText()
                        } label: {
                            Label(
                                controller.hasTextSelection
                                    ? loc.text(es: "Copiar texto seleccionado (⌘C)", en: "Copy Selected Text (⌘C)")
                                    : loc.text(es: "Copiar texto de esta página (⌘C)", en: "Copy Current Page Text (⌘C)"),
                                systemImage: "doc.on.doc"
                            )
                        }

                        Button {
                            controller.copyAllDocumentText()
                        } label: {
                            Label(
                                loc.text(es: "Copiar todo el texto del PDF", en: "Copy All PDF Text"),
                                systemImage: "doc.plaintext"
                            )
                        }

                        Divider()

                        Button {
                            controller.copyCurrentPageAsImage()
                        } label: {
                            Label(
                                loc.text(es: "Copiar página actual como imagen (HD)", en: "Copy Current Page as Image (HD)"),
                                systemImage: "photo.on.rectangle"
                            )
                        }

                        Button {
                            controller.setToolMode(.captureImage)
                        } label: {
                            Label(
                                loc.text(es: "Recortar un área como imagen…", en: "Capture Area as Image…"),
                                systemImage: "crop"
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                            Text(loc.text(es: "Copiar", en: "Copy"))
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .frame(height: PreviewToolbarMetrics.controlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .help(loc.text(es: "Copiar texto o imagen del PDF", en: "Copy text or image from PDF"))

                    // 4. Pegar (texto o imagen del portapapeles sobre la página)
                    Button {
                        controller.pasteFromClipboardIntoCurrentPage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .medium))
                            Text(loc.text(es: "Pegar", en: "Paste"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
                    .help(loc.text(es: "Pegar texto o imagen del portapapeles en esta página (⌘V)", en: "Paste text or image from clipboard onto this page (⌘V)"))

                    if !controller.addedAnnotations.isEmpty {
                        PreviewToolbarIconButton(
                            "arrow.uturn.backward",
                            help: loc.text(es: "Deshacer último pegado", en: "Undo last paste")
                        ) {
                            controller.undoLastPastedAnnotation()
                        }
                    }

                    if controller.hasUnsavedEdits {
                        Button {
                            controller.saveDocumentChanges()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(loc.text(es: "Guardar", en: "Save"))
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(PreviewToolbarButtonStyle(variant: .prominent))
                        .help(loc.text(es: "Guardar cambios en el archivo PDF (⌘S)", en: "Save changes to the PDF file (⌘S)"))
                    }

                    Divider().frame(height: 16)

                    // 5. Zoom + Rotar + Buscar
                    HStack(spacing: 3) {
                        PreviewToolbarIconButton(
                            "minus.magnifyingglass",
                            help: loc.text(es: "Alejar (⌘-)", en: "Zoom Out (⌘-)")
                        ) {
                            controller.zoomOut()
                        }

                        Button {
                            controller.resetZoomFit()
                        } label: {
                            Text("\(controller.zoomPercent)%")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .frame(minWidth: 38)
                        }
                        .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
                        .help(loc.text(es: "Ajustar a la ventana (⌘0)", en: "Fit to Window (⌘0)"))

                        PreviewToolbarIconButton(
                            "plus.magnifyingglass",
                            help: loc.text(es: "Acercar (⌘+)", en: "Zoom In (⌘+)")
                        ) {
                            controller.zoomIn()
                        }
                    }

                    PreviewToolbarIconButton(
                        "rotate.right",
                        help: loc.text(es: "Rotar página 90°", en: "Rotate page 90°")
                    ) {
                        controller.rotateCurrentPageRight()
                    }

                    PreviewToolbarIconButton(
                        "magnifyingglass",
                        active: controller.isSearchVisible,
                        help: loc.text(es: "Buscar texto en el PDF (⌘F)", en: "Search text in PDF (⌘F)")
                    ) {
                        if controller.isSearchVisible {
                            controller.clearSearch()
                        } else {
                            controller.isSearchVisible = true
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }

    // MARK: - Barra de Búsqueda en el PDF (⌘F)

    private var pdfSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField(
                loc.text(es: "Buscar texto dentro del PDF…", en: "Search text inside PDF…"),
                text: $controller.searchQuery
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .onSubmit {
                if controller.searchMatches.isEmpty {
                    controller.performSearch()
                } else {
                    controller.selectNextSearchMatch(offset: 1)
                }
            }
            .onChange(of: controller.searchQuery) { _, _ in
                controller.performSearch()
            }

            if !controller.searchQuery.isEmpty {
                Text(
                    controller.searchMatches.isEmpty
                        ? loc.text(es: "0 resultados", en: "0 matches")
                        : "\(controller.activeMatchIndex + 1) / \(controller.searchMatches.count)"
                )
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)

                PreviewToolbarIconButton(
                    "chevron.up",
                    help: loc.text(es: "Coincidencia anterior", en: "Previous match"),
                    disabled: controller.searchMatches.isEmpty
                ) {
                    controller.selectNextSearchMatch(offset: -1)
                }

                PreviewToolbarIconButton(
                    "chevron.down",
                    help: loc.text(es: "Siguiente coincidencia", en: "Next match"),
                    disabled: controller.searchMatches.isEmpty
                ) {
                    controller.selectNextSearchMatch(offset: 1)
                }
            }

            Button {
                controller.clearSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Cerrar búsqueda", en: "Close search"))
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.primary.opacity(0.035))
    }
}
