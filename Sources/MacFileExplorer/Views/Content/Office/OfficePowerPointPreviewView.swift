import AppKit
import SwiftUI

// MARK: - Visor / Editor Estilo LibreOffice Impress para Microsoft PowerPoint (.pptx / .ppt)

public struct OfficePowerPointPreviewView: View {
    public let fileURL: URL

    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var officePrefs = OfficePreferences.shared
    @ViewState private var presentation: PPTXPresentationModel? = nil
    @ViewState private var activeSlideIndex: Int = 0
    @ViewState private var selectedBoxID: String? = nil
    @ViewState private var showOriginalQuickLook: Bool = true
    @ViewState private var showSpeakerNotes: Bool = false
    @ViewState private var searchQuery: String = ""
    @ViewState private var isLoading: Bool = true
    @ViewState private var loadError: String? = nil
    @ViewState private var hasUnsavedChanges: Bool = false
    @ViewState private var statusToast: String? = nil
    @ViewState private var undoStack: [PPTXPresentationModel] = []
    @ViewState private var redoStack: [PPTXPresentationModel] = []

    @FocusState private var isSearchFocused: Bool

    public init(fileURL: URL) {
        self.fileURL = fileURL
        _showOriginalQuickLook = ViewState(initialValue: OfficePreferences.shared.shouldOpenInOriginalView)
    }

    private var isLegacyBinaryFormat: Bool {
        !OfficePreviewSupport.editablePowerPointExtensions.contains(fileURL.pathExtension.lowercased())
    }

    private var safeSlideIndex: Int {
        guard let pres = presentation, !pres.slides.isEmpty else { return 0 }
        return min(max(0, activeSlideIndex), pres.slides.count - 1)
    }

    private var activeSlide: PPTXSlideModel? {
        guard let pres = presentation, !pres.slides.isEmpty else { return nil }
        return pres.slides[safeSlideIndex]
    }

    private var selectedBoxIndex: Int? {
        guard let slide = activeSlide, let selectedBoxID else { return nil }
        return slide.textBoxes.firstIndex(where: { $0.id == selectedBoxID })
    }

    private var selectedBox: PPTXTextBox? {
        guard let slide = activeSlide, let idx = selectedBoxIndex else { return nil }
        return slide.textBoxes[idx]
    }

    public var body: some View {
        VStack(spacing: 0) {
            modeHeaderBar
            Divider()

            if isLegacyBinaryFormat || !officePrefs.isOfficeEditingEnabled || showOriginalQuickLook {
                if isLegacyBinaryFormat {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                        Text(loc.text(
                            es: "Formato antiguo (.\(fileURL.pathExtension.lowercased())) en solo lectura. Usá «Enviar a Drive» arriba para editarlo en Google Slides.",
                            en: "Legacy format (.\(fileURL.pathExtension.lowercased())) shown read-only. Click \"Send to Drive\" above to edit it live in Google Slides."
                        ))
                        .font(.system(size: 11.5))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.10))
                }
                NativeQLPreviewRepresentable(fileURL: fileURL)
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
            } else if let pres = presentation {
                impressToolbarRow1
                Divider()
                impressToolbarRow2
                Divider()

                HStack(spacing: 0) {
                    slideThumbnailsSidebar(presentation: pres)
                    Divider()

                    VStack(spacing: 0) {
                        slideCanvasStage(presentation: pres)
                        if showSpeakerNotes {
                            Divider()
                            speakerNotesDrawer
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()
                statusBar(presentation: pres)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: fileURL) {
            if isLegacyBinaryFormat {
                isLoading = false
                return
            }
            await loadPresentation()
        }
        .background {
            Group {
                Button("") { savePresentation(to: fileURL) }.keyboardShortcut("s", modifiers: [.command])
                Button("") { savePresentationCopy() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("") { isSearchFocused = true }.keyboardShortcut("f", modifiers: [.command])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Encabezado & Barras Estilo LibreOffice Impress

    private var modeHeaderBar: some View {
        HStack(spacing: 10) {
            Label(
                loc.text(es: "Microsoft PowerPoint · Editor rápido", en: "Microsoft PowerPoint · Quick Editor"),
                systemImage: OfficeDocumentKind.powerpoint.symbolName
            )
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(OfficeDocumentKind.powerpoint.accentColor)

            if hasUnsavedChanges {
                Text(loc.text(es: "Sin guardar", en: "Unsaved"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }

            Spacer()

            if !isLegacyBinaryFormat && officePrefs.isOfficeEditingEnabled {
                Picker("", selection: $showOriginalQuickLook) {
                    Text(loc.text(es: "Vista original", en: "Original View")).tag(true)
                    Text(loc.text(es: "Editor", en: "Editor")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            } else if !isLegacyBinaryFormat {
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

    private var impressToolbarRow1: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    savePresentation(to: fileURL)
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
                .help(loc.text(es: "Guardar presentación (⌘S)", en: "Save presentation (⌘S)"))

                Button {
                    savePresentationCopy()
                } label: {
                    HStack(spacing: 6) {
                        FloppyDiskCopyIconView(size: PreviewToolbarMetrics.iconSize)
                        Text(loc.text(es: "Guardar copia…", en: "Save Copy…"))
                            .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                }
                .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
                .help(loc.text(es: "Guardar una copia nueva (⇧⌘S)", en: "Save a new copy (⇧⌘S)"))

                Divider().frame(height: 16)

                iconBtn("arrow.uturn.backward", help: loc.text(es: "Deshacer", en: "Undo"), disabled: undoStack.isEmpty) { performUndo() }
                iconBtn("arrow.uturn.forward", help: loc.text(es: "Rehacer", en: "Redo"), disabled: redoStack.isEmpty) { performRedo() }

                Divider().frame(height: 16)

                iconBtn("scissors", help: loc.text(es: "Cortar texto del cuadro seleccionado", en: "Cut selected box text"), disabled: selectedBox == nil) { cutSelectedBoxText() }
                iconBtn("doc.on.doc", help: loc.text(es: "Copiar texto del cuadro seleccionado", en: "Copy selected box text"), disabled: selectedBox == nil) { copySelectedBoxText() }
                iconBtn("doc.on.clipboard", help: loc.text(es: "Pegar texto en la diapositiva", en: "Paste text into slide")) { pasteTextIntoSlide() }
                iconBtn("text.document", help: loc.text(es: "Copiar todo el texto de esta diapositiva", en: "Copy all text from this slide")) { copyAllSlideText() }

                Divider().frame(height: 16)

                iconBtn("plus.rectangle.on.rectangle", help: loc.text(es: "Nueva diapositiva", en: "New slide")) { addNewSlide() }
                iconBtn("square.on.square", help: loc.text(es: "Duplicar diapositiva actual", en: "Duplicate current slide"), disabled: activeSlide == nil) { duplicateCurrentSlide() }
                iconBtn("trash", help: loc.text(es: "Eliminar diapositiva actual", en: "Delete current slide"), disabled: (presentation?.slides.count ?? 0) <= 1) { deleteCurrentSlide() }
                iconBtn("textbox", help: loc.text(es: "Agregar cuadro de texto", en: "Add text box"), disabled: activeSlide == nil) { addTextBoxToCurrentSlide() }

                Divider().frame(height: 16)

                iconBtn("note.text", active: showSpeakerNotes, help: loc.text(es: "Mostrar / ocultar notas del orador", en: "Show / hide speaker notes")) {
                    showSpeakerNotes.toggle()
                }

                // Buscador en presentación (altura unificada 26 pt)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: PreviewToolbarMetrics.iconSize - 0.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(loc.text(es: "Buscar (⌘F)…", en: "Find (⌘F)…"), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: PreviewToolbarMetrics.labelFontSize))
                        .frame(width: 115)
                        .focused($isSearchFocused)
                        .onSubmit { jumpToNextSearchMatch() }
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
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
            .padding(.vertical, 5)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var impressToolbarRow2: some View {
        let box = selectedBox
        let isDisabled = (box == nil)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text(loc.text(es: "Formato de caja:", en: "Text box format:"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                iconBtn("textformat.size.smaller", help: loc.text(es: "Reducir tamaño (A-)", en: "Decrease size (A-)"), disabled: isDisabled) {
                    mutateSelectedBox { $0.fontSizePt = max(10, $0.fontSizePt - 2) }
                }
                Text("\(Int(box?.fontSizePt ?? 18)) pt")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 38)
                iconBtn("textformat.size.larger", help: loc.text(es: "Aumentar tamaño (A+)", en: "Increase size (A+)"), disabled: isDisabled) {
                    mutateSelectedBox { $0.fontSizePt = min(72, $0.fontSizePt + 2) }
                }

                Divider().frame(height: 15)

                toggleCharBtn("B", bold: true, active: box?.isBold ?? false, disabled: isDisabled, help: loc.text(es: "Negrita", en: "Bold")) {
                    mutateSelectedBox { $0.isBold.toggle() }
                }
                toggleCharBtn("I", italic: true, active: box?.isItalic ?? false, disabled: isDisabled, help: loc.text(es: "Cursiva", en: "Italic")) {
                    mutateSelectedBox { $0.isItalic.toggle() }
                }
                toggleCharBtn("U", underline: true, active: box?.isUnderline ?? false, disabled: isDisabled, help: loc.text(es: "Subrayado", en: "Underline")) {
                    mutateSelectedBox { $0.isUnderline.toggle() }
                }

                Divider().frame(height: 15)

                Menu {
                    Button(loc.text(es: "Negro", en: "Black")) { mutateSelectedBox { $0.textColorHex = "18181B" } }
                    Button(loc.text(es: "Azul", en: "Blue")) { mutateSelectedBox { $0.textColorHex = "1D4ED8" } }
                    Button(loc.text(es: "Rojo / Coral", en: "Red / Coral")) { mutateSelectedBox { $0.textColorHex = "DC2626" } }
                    Button(loc.text(es: "Verde", en: "Green")) { mutateSelectedBox { $0.textColorHex = "15803D" } }
                    Button(loc.text(es: "Naranja", en: "Orange")) { mutateSelectedBox { $0.textColorHex = "EA580C" } }
                    Button(loc.text(es: "Violeta", en: "Purple")) { mutateSelectedBox { $0.textColorHex = "7E22CE" } }
                    Button(loc.text(es: "Gris oscuro", en: "Dark Gray")) { mutateSelectedBox { $0.textColorHex = "52525B" } }
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
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.42 : 1.0)
                .help(loc.text(es: "Color de texto", en: "Text color"))

                Divider().frame(height: 15)

                iconBtn("text.alignleft", active: box?.alignment == .leading, help: loc.text(es: "Izquierda", en: "Left"), disabled: isDisabled) {
                    mutateSelectedBox { $0.alignment = .leading }
                }
                iconBtn("text.aligncenter", active: box?.alignment == .center, help: loc.text(es: "Centrar", en: "Center"), disabled: isDisabled) {
                    mutateSelectedBox { $0.alignment = .center }
                }
                iconBtn("text.alignright", active: box?.alignment == .trailing, help: loc.text(es: "Derecha", en: "Right"), disabled: isDisabled) {
                    mutateSelectedBox { $0.alignment = .trailing }
                }
                iconBtn("list.bullet", active: box?.isBulleted ?? false, help: loc.text(es: "Viñetas", en: "Bullets"), disabled: isDisabled) {
                    mutateSelectedBox { $0.isBulleted.toggle() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(Color.primary.opacity(0.018))
    }

    // MARK: - Panel Lateral de Miniaturas de Diapositivas

    private func slideThumbnailsSidebar(presentation: PPTXPresentationModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(presentation.slides.enumerated()), id: \.element.id) { idx, slide in
                    let isSelected = (idx == safeSlideIndex)
                    let matchesSearch = !searchQuery.isEmpty && slide.plainTextSummary.localizedCaseInsensitiveContains(searchQuery)

                    Button {
                        activeSlideIndex = idx
                        selectedBoxID = slide.textBoxes.first?.id
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                .frame(width: 18, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(slide.summaryTitle.isEmpty ? loc.text(es: "Diapositiva \(idx + 1)", en: "Slide \(idx + 1)") : slide.summaryTitle)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Color(white: 0.14))
                                    .lineLimit(2)
                                if let bodyBox = slide.textBoxes.first(where: { !$0.isTitle && !$0.text.isEmpty }) {
                                    Text(bodyBox.text)
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color(white: 0.42))
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(6)
                            .frame(width: 118, height: 68, alignment: .topLeading)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? Color.accentColor
                                            : (matchesSearch ? Color.orange : Color.black.opacity(0.14)),
                                        lineWidth: isSelected ? 2 : (matchesSearch ? 1.5 : 0.8)
                                    )
                            )
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(width: 158)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Lienzo Central Interactivo de la Diapositiva

    private func slideCanvasStage(presentation: PPTXPresentationModel) -> some View {
        GeometryReader { geo in
            let pad: CGFloat = 24
            let availW = max(240, geo.size.width - pad * 2)
            let availH = max(160, geo.size.height - pad * 2)
            let aspect = presentation.aspectRatio
            let slideW = min(availW, availH * aspect)
            let slideH = slideW / aspect

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let slide = activeSlide {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)

                        // Imágenes incrustadas de la diapositiva
                        ForEach(slide.images) { img in
                            if let nsImg = NSImage(data: img.imageData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(
                                        width: max(36, img.normRect.width * slideW),
                                        height: max(36, img.normRect.height * slideH)
                                    )
                                    .offset(
                                        x: img.normRect.minX * slideW,
                                        y: img.normRect.minY * slideH
                                    )
                            }
                        }

                        // Cuadros de texto interactivos y editables
                        ForEach(Array(slide.textBoxes.enumerated()), id: \.element.id) { boxIdx, box in
                            let isSelected = (selectedBoxID == box.id)
                            let scaledFont = max(10, min(42, CGFloat(box.fontSizePt) * (slideW / 760.0)))
                            let boxColor = OfficeColorCodec.swiftUIColor(fromHex: box.textColorHex) ?? Color(white: 0.12)
                            let boxBinding = Binding<String>(
                                get: { self.presentation?.slides[safeSlideIndex].textBoxes[boxIdx].text ?? "" },
                                set: { newText in
                                    self.pushUndoIfNeeded()
                                    self.presentation?.slides[safeSlideIndex].textBoxes[boxIdx].text = newText
                                    self.presentation?.slides[safeSlideIndex].isModified = true
                                    self.hasUnsavedChanges = true
                                }
                            )

                            TextEditor(text: boxBinding)
                                .font(.system(size: scaledFont, weight: box.isBold ? .bold : .regular))
                                .italic(box.isItalic)
                                .underline(box.isUnderline)
                                .multilineTextAlignment(swiftUIAlignment(box.alignment))
                                .foregroundStyle(boxColor)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .frame(
                                    width: max(80, box.normRect.width * slideW),
                                    height: max(34, box.normRect.height * slideH),
                                    alignment: .topLeading
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(
                                            isSelected ? Color.accentColor : Color.black.opacity(0.08),
                                            style: StrokeStyle(lineWidth: isSelected ? 1.5 : 0.75, dash: isSelected ? [] : [4, 3])
                                        )
                                )
                                .offset(
                                    x: box.normRect.minX * slideW,
                                    y: box.normRect.minY * slideH
                                )
                                .onTapGesture {
                                    selectedBoxID = box.id
                                }
                        }
                    }
                    .frame(width: slideW, height: slideH)
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var speakerNotesDrawer: some View {
        let notesBinding = Binding<String>(
            get: { presentation?.slides[safeSlideIndex].speakerNotes ?? "" },
            set: { newNotes in
                pushUndoIfNeeded()
                presentation?.slides[safeSlideIndex].speakerNotes = newNotes
                presentation?.slides[safeSlideIndex].isModified = true
                hasUnsavedChanges = true
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(loc.text(es: "Notas del orador", en: "Speaker Notes"), systemImage: "note.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            TextEditor(text: notesBinding)
                .font(.system(size: 12))
                .frame(height: 68)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private func statusBar(presentation: PPTXPresentationModel) -> some View {
        HStack(spacing: 10) {
            Button {
                activeSlideIndex = max(0, safeSlideIndex - 1)
                selectedBoxID = activeSlide?.textBoxes.first?.id
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(safeSlideIndex <= 0)

            Text(loc.text(
                es: "Diapositiva \(safeSlideIndex + 1) de \(presentation.slides.count)",
                en: "Slide \(safeSlideIndex + 1) of \(presentation.slides.count)"
            ))
            .monospacedDigit()

            Button {
                activeSlideIndex = min(presentation.slides.count - 1, safeSlideIndex + 1)
                selectedBoxID = activeSlide?.textBoxes.first?.id
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(safeSlideIndex >= presentation.slides.count - 1)

            if let toast = statusToast {
                Text("· \(toast)")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.medium)
            }

            Spacer()

            Text("PPTX")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Acciones de Edición, Diapositivas, Portapapeles y Guardado

    private func loadPresentation() async {
        isLoading = true
        loadError = nil
        let targetURL = fileURL
        let result = await Task.detached(priority: .userInitiated) {
            Result { try PPTXDocumentEngine.load(from: targetURL) }
        }.value

        switch result {
        case .success(let model):
            presentation = model
            activeSlideIndex = 0
            selectedBoxID = model.slides.first?.textBoxes.first?.id
            hasUnsavedChanges = false
        case .failure(let err):
            InternalErrorLogger.shared.logNonFatalError(
                category: "OFFICE_PPTX_LOAD",
                error: err,
                context: ["ext": fileURL.pathExtension.lowercased()]
            )
            loadError = err.localizedDescription
        }
        isLoading = false
    }

    private func pushUndoIfNeeded() {
        guard let pres = presentation else { return }
        if undoStack.last != pres {
            undoStack.append(pres)
            if undoStack.count > 30 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
    }

    private func performUndo() {
        guard let prev = undoStack.popLast(), let cur = presentation else { return }
        redoStack.append(cur)
        presentation = prev
        hasUnsavedChanges = true
    }

    private func performRedo() {
        guard let next = redoStack.popLast(), let cur = presentation else { return }
        undoStack.append(cur)
        presentation = next
        hasUnsavedChanges = true
    }

    private func mutateSelectedBox(_ mutate: (inout PPTXTextBox) -> Void) {
        guard let boxIdx = selectedBoxIndex, presentation != nil else { return }
        pushUndoIfNeeded()
        mutate(&presentation!.slides[safeSlideIndex].textBoxes[boxIdx])
        presentation!.slides[safeSlideIndex].isModified = true
        hasUnsavedChanges = true
    }

    private func copySelectedBoxText() {
        guard let box = selectedBox else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(box.text, forType: .string)
        showToast(loc.text(es: "Texto copiado", en: "Text copied"))
    }

    private func cutSelectedBoxText() {
        copySelectedBoxText()
        mutateSelectedBox { $0.text = "" }
    }

    private func pasteTextIntoSlide() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        if selectedBoxIndex != nil {
            mutateSelectedBox { box in
                box.text = box.text.isEmpty ? text : (box.text + "\n" + text)
            }
        } else {
            addTextBoxToCurrentSlide(initialText: text)
        }
    }

    private func copyAllSlideText() {
        guard let slide = activeSlide else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(slide.plainTextSummary, forType: .string)
        showToast(loc.text(es: "Texto de diapositiva copiado", en: "Slide text copied"))
    }

    private func addTextBoxToCurrentSlide(initialText: String = "") {
        guard presentation != nil else { return }
        pushUndoIfNeeded()
        let count = presentation!.slides[safeSlideIndex].textBoxes.count
        let y = min(0.72, 0.22 + Double(count % 4) * 0.16)
        let newBox = PPTXTextBox(
            shapeIndex: nil,
            isTitle: false,
            normRect: CGRect(x: 0.08, y: y, width: 0.84, height: 0.22),
            text: initialText.isEmpty ? loc.text(es: "Nuevo texto…", en: "New text…") : initialText,
            fontSizePt: 20
        )
        presentation!.slides[safeSlideIndex].textBoxes.append(newBox)
        presentation!.slides[safeSlideIndex].isModified = true
        selectedBoxID = newBox.id
        hasUnsavedChanges = true
    }

    private func addNewSlide() {
        guard presentation != nil else { return }
        pushUndoIfNeeded()
        let titleBox = PPTXTextBox(
            isTitle: true,
            normRect: CGRect(x: 0.07, y: 0.08, width: 0.86, height: 0.18),
            text: loc.text(es: "Título de la diapositiva", en: "Slide Title"),
            fontSizePt: 30,
            isBold: true
        )
        let bodyBox = PPTXTextBox(
            isTitle: false,
            normRect: CGRect(x: 0.07, y: 0.30, width: 0.86, height: 0.52),
            text: loc.text(es: "Escribí contenido aquí…", en: "Type slide content here…"),
            fontSizePt: 18
        )
        let newSlide = PPTXSlideModel(archivePath: nil, textBoxes: [titleBox, bodyBox], isModified: true)
        presentation!.slides.append(newSlide)
        activeSlideIndex = presentation!.slides.count - 1
        selectedBoxID = titleBox.id
        hasUnsavedChanges = true
    }

    private func duplicateCurrentSlide() {
        guard let current = activeSlide, presentation != nil else { return }
        pushUndoIfNeeded()
        let clonedBoxes = current.textBoxes.map { b in
            PPTXTextBox(
                shapeIndex: nil,
                isTitle: b.isTitle,
                normRect: b.normRect,
                text: b.text,
                fontSizePt: b.fontSizePt,
                isBold: b.isBold,
                isItalic: b.isItalic,
                isUnderline: b.isUnderline,
                textColorHex: b.textColorHex,
                alignment: b.alignment,
                isBulleted: b.isBulleted
            )
        }
        let copy = PPTXSlideModel(archivePath: nil, textBoxes: clonedBoxes, speakerNotes: current.speakerNotes, isModified: true)
        presentation!.slides.insert(copy, at: safeSlideIndex + 1)
        activeSlideIndex = safeSlideIndex + 1
        selectedBoxID = copy.textBoxes.first?.id
        hasUnsavedChanges = true
    }

    private func deleteCurrentSlide() {
        guard let pres = presentation, pres.slides.count > 1 else { return }
        pushUndoIfNeeded()
        let removed = presentation!.slides.remove(at: safeSlideIndex)
        if let archivePath = removed.archivePath {
            presentation!.deletedSlideArchivePaths.insert(archivePath)
        }
        activeSlideIndex = min(safeSlideIndex, presentation!.slides.count - 1)
        selectedBoxID = activeSlide?.textBoxes.first?.id
        hasUnsavedChanges = true
    }

    private func jumpToNextSearchMatch() {
        guard let pres = presentation, !searchQuery.isEmpty else { return }
        let count = pres.slides.count
        for offset in 1...count {
            let idx = (safeSlideIndex + offset) % count
            if pres.slides[idx].plainTextSummary.localizedCaseInsensitiveContains(searchQuery) {
                activeSlideIndex = idx
                selectedBoxID = pres.slides[idx].textBoxes.first(where: { $0.text.localizedCaseInsensitiveContains(searchQuery) })?.id
                return
            }
        }
    }

    private func savePresentation(to destinationURL: URL) {
        guard var pres = presentation else { return }
        do {
            try PPTXDocumentEngine.save(presentation: pres, to: destinationURL)
            if destinationURL == fileURL {
                for i in pres.slides.indices { pres.slides[i].isModified = false }
                pres.deletedSlideArchivePaths.removeAll()
                presentation = pres
                hasUnsavedChanges = false
            }
            showToast(loc.text(es: "Presentación guardada", en: "Presentation saved"))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func savePresentationCopy() {
        guard let dest = OfficeSavePanelHelper.chooseCopyDestination(
            originalURL: fileURL,
            preferredExtension: "pptx",
            title: loc.text(es: "Guardar copia de PowerPoint (.pptx)", en: "Save PowerPoint Copy (.pptx)")
        ) else { return }
        savePresentation(to: dest)
    }

    private func showToast(_ message: String) {
        statusToast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            if statusToast == message { statusToast = nil }
        }
    }

    private func swiftUIAlignment(_ align: PPTXTextAlignment) -> TextAlignment {
        switch align {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func iconBtn(_ symbol: String, active: Bool = false, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        PreviewToolbarIconButton(symbol, active: active, help: help, disabled: disabled, action: action)
    }

    private func toggleCharBtn(
        _ text: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        active: Bool,
        disabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        PreviewToolbarToggleCharButton(
            text,
            bold: bold,
            italic: italic,
            underline: underline,
            active: active,
            disabled: disabled,
            help: help,
            action: action
        )
    }
}
