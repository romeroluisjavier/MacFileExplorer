import AppKit
import SwiftUI

/// Vista principal del Historial del Portapapeles estilo Maccy integrada en el área central de `MacFileExplorer`.
/// Permite buscar cualquier texto, enlace, archivo o imagen copiada, configurar el tiempo y cantidad máxima de guardado,
/// personalizar todos los atajos de teclado (`⌃⌘V`, `⇧⌘C`, `⌥P`, `⌥⌫`, `⌥↵`, `⌥⌘⌫`) y previsualizar imágenes a tamaño completo.
public struct ClipboardHistoryMainView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Bindable var historyManager: ClipboardHistoryManager = .shared
    @Bindable var prefs: ClipboardHistoryPreferences = .shared

    @FocusState private var isSearchFieldFocused: Bool
    @ViewState private var keyMonitor: Any? = nil

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerToolbar
            Divider()
            filterAndSettingsBar
            Divider()

            if !prefs.isEnabled {
                disabledStateView
            } else if historyManager.filteredItems.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    entriesListPane
                        .frame(minWidth: 320, idealWidth: 400, maxWidth: 560, maxHeight: .infinity)

                    inspectorDetailPane
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if historyManager.selectedEntryID == nil {
                historyManager.selectedEntryID = historyManager.filteredItems.first?.id
            }
            installLocalKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeLocalKeyMonitor()
        }
    }

    // MARK: - Cabecera Superior con Buscador y Botón Volver

    private var headerToolbar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.isShowingClipboardHistory = false
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(loc.text(es: "Carpetas", en: "Folders"))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Volver al explorador de carpetas", en: "Back to folder explorer"))

            HStack(spacing: 7) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.purple)

                Text(loc.text(es: "Historial del Portapapeles", en: "Clipboard History"))
                    .font(.system(size: 14, weight: .semibold))

                Text("\(historyManager.items.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                    )
            }

            Spacer(minLength: 8)

            // Caja de búsqueda instantánea estilo Maccy
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(
                    loc.text(
                        es: "Buscar texto, imágenes, archivos o app…",
                        en: "Search text, images, files, or app…"
                    ),
                    text: $historyManager.searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isSearchFieldFocused)
                .onChange(of: historyManager.searchQuery) { _, _ in
                    historyManager.selectedEntryID = historyManager.filteredItems.first?.id
                }

                if !historyManager.searchQuery.isEmpty {
                    Button {
                        historyManager.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 220, idealWidth: 300, maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Barra de Filtros por Categoría y Configuración de Tiempo / Cantidad / Atajos

    private var filterAndSettingsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Píldoras de filtro por tipo (Todos, Texto, Imágenes, Archivos, Enlaces, Fijados)
                ForEach(ClipboardHistoryFilter.allCases) { filter in
                    let isSelected = historyManager.selectedFilter == filter
                    let count = countForFilter(filter)
                    Button {
                        historyManager.selectedFilter = filter
                        historyManager.selectedEntryID = historyManager.filteredItems.first?.id
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.systemImage)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            Text(filter.localizedTitle(using: loc))
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 4)

                // Configuración 1: Cantidad máxima a guardar
                Menu {
                    Picker(
                        loc.text(es: "Cantidad máxima a guardar", en: "Maximum items to keep"),
                        selection: $prefs.maxItemsOption
                    ) {
                        ForEach(ClipboardMaxItemsOption.allCases) { option in
                            Text(option.localizedTitle(using: loc))
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "number.circle")
                            .font(.system(size: 11))
                        Text(
                            prefs.maxItemsOption == .unlimited
                                ? loc.text(es: "Límite: Ilimitado", en: "Limit: Unlimited")
                                : loc.text(es: "Máx: \(prefs.maxItemsOption.rawValue)", en: "Max: \(prefs.maxItemsOption.rawValue)")
                        )
                        .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Configuración 2: Tiempo de retención
                Menu {
                    Picker(
                        loc.text(es: "Guardar historial durante", en: "Keep history for"),
                        selection: $prefs.retentionPeriod
                    ) {
                        ForEach(ClipboardRetentionPeriod.allCases) { period in
                            Text(period.localizedTitle(using: loc))
                                .tag(period)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(prefs.retentionPeriod.localizedTitle(using: loc))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Configuración 3: Abrir ventana de Configuración de Atajos
                Button {
                    ClipboardShortcutsWindowController.shared.show()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11))
                        Text(
                            loc.text(
                                es: "Atajos (\(prefs.quickPasteDropdownShortcut.displayString))…",
                                en: "Shortcuts (\(prefs.quickPasteDropdownShortcut.displayString))…"
                            )
                        )
                        .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
                .help(loc.text(
                    es: "Configurar todos los atajos del portapapeles (Pegar del menú: \(prefs.quickPasteDropdownShortcut.displayString))",
                    en: "Configure all clipboard shortcuts (Paste menu: \(prefs.quickPasteDropdownShortcut.displayString))"
                ))

                // Botón Limpiar no fijados
                Button {
                    historyManager.clearUnpinnedHistory()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text(loc.text(
                            es: "Limpiar (\(prefs.clearHistoryShortcut.displayString))",
                            en: "Clear (\(prefs.clearHistoryShortcut.displayString))"
                        ))
                        .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(historyManager.items.allSatisfy(\.isPinned))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Lista Izquierda de Entradas

    private var entriesListPane: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 3) {
                    ForEach(Array(historyManager.filteredItems.enumerated()), id: \.element.id) { index, entry in
                        ClipboardHistoryRowView(
                            entry: entry,
                            shortcutNumber: index < 9 ? (index + 1) : (index == 9 ? 0 : nil),
                            isSelected: historyManager.selectedEntry?.id == entry.id,
                            isCopiedFeedbackVisible: historyManager.recentlyCopiedFeedbackEntryID == entry.id,
                            onSelect: {
                                historyManager.selectedEntryID = entry.id
                            },
                            onCopy: {
                                historyManager.selectedEntryID = entry.id
                                historyManager.copyEntryToPasteboard(entry)
                            },
                            onTogglePin: {
                                historyManager.togglePin(entry.id)
                            },
                            onDelete: {
                                historyManager.deleteEntry(entry.id)
                            }
                        )
                        .id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: historyManager.selectedEntryID) { _, newID in
                if let newID {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Panel Derecho de Inspección y Previsualización (Texto / Imágenes / Archivos)

    @ViewBuilder
    private var inspectorDetailPane: some View {
        if let entry = historyManager.selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: entry.kind.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayTitle(using: loc))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        Text(entry.displaySubtitle(using: loc))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if historyManager.recentlyCopiedFeedbackEntryID == entry.id {
                        Label(loc.text(es: "¡Copiado!", en: "Copied!"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                    }

                    Button {
                        historyManager.copyEntryToPasteboard(entry)
                    } label: {
                        Label(loc.text(es: "Copiar (↵)", en: "Copy (↵)"), systemImage: "doc.on.doc")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        historyManager.togglePin(entry.id)
                    } label: {
                        Image(systemName: entry.isPinned ? "pin.slash.fill" : "pin")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(loc.text(
                        es: "Fijar / Desfijar (\(prefs.pinShortcut.displayString))",
                        en: "Pin / Unpin (\(prefs.pinShortcut.displayString))"
                    ))

                    Button(role: .destructive) {
                        historyManager.deleteEntry(entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(loc.text(
                        es: "Eliminar del historial (\(prefs.deleteShortcut.displayString))",
                        en: "Delete from history (\(prefs.deleteShortcut.displayString))"
                    ))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.02))

                Divider()

                Group {
                    if let previewImg = historyManager.image(for: entry) {
                        imagePreviewBody(entry: entry, image: previewImg)
                    } else if entry.kind == .files {
                        filesPreviewBody(entry: entry)
                    } else {
                        textPreviewBody(entry: entry)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack(spacing: 14) {
                    Label(
                        entry.lastCopiedAt.formatted(date: .abbreviated, time: .standard),
                        systemImage: "clock"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    if let app = entry.sourceAppName, !app.isEmpty {
                        Label(app, systemImage: "app.badge")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(loc.text(
                        es: "Menú rápido: \(prefs.quickPasteDropdownShortcut.displayString) • ↵ Copiar • \(prefs.plainTextShortcut.displayString) Texto plano • \(prefs.pinShortcut.displayString) Fijar • \(prefs.deleteShortcut.displayString) Borrar",
                        en: "Quick menu: \(prefs.quickPasteDropdownShortcut.displayString) • ↵ Copy • \(prefs.plainTextShortcut.displayString) Plain text • \(prefs.pinShortcut.displayString) Pin • \(prefs.deleteShortcut.displayString) Delete"
                    ))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.02))
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(loc.text(es: "Selecciona un elemento para previsualizarlo", en: "Select an item to preview"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func imagePreviewBody(entry: ClipboardHistoryEntry, image: NSImage) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.06))

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                if let w = entry.imagePixelWidth, let h = entry.imagePixelHeight {
                    Text("\(w) × \(h) px")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    historyManager.exportImageWithSavePanel(for: entry)
                } label: {
                    Label(loc.text(es: "Guardar imagen como PNG…", en: "Save Image as PNG…"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
    }

    private func filesPreviewBody(entry: ClipboardHistoryEntry) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.filePaths, id: \.self) { path in
                    let fileURL = URL(fileURLWithPath: path)
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileURL.lastPathComponent)
                                .font(.system(size: 12.5, weight: .medium))
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            let parent = fileURL.deletingLastPathComponent()
                            viewModel.navigate(to: parent)
                        } label: {
                            Label(loc.text(es: "Ir a carpeta", en: "Open Folder"), systemImage: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
            .padding(14)
        }
    }

    private func textPreviewBody(entry: ClipboardHistoryEntry) -> some View {
        let text = entry.textContent ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical) {
                Text(text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 12) {
                let charCount = text.count
                let lineCount = max(1, text.components(separatedBy: .newlines).count)
                Text(loc.text(
                    es: "\(charCount) caracteres • \(lineCount) líneas",
                    en: "\(charCount) characters • \(lineCount) lines"
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Spacer()

                if entry.kind == .link, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(loc.text(es: "Abrir enlace", en: "Open Link"), systemImage: "safari")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    historyManager.copyEntryToPasteboard(entry, plainTextOnly: true)
                } label: {
                    Label(
                        loc.text(
                            es: "Copiar sin formato (\(prefs.plainTextShortcut.displayString))",
                            en: "Copy Plain Text (\(prefs.plainTextShortcut.displayString))"
                        ),
                        systemImage: "text.alignleft"
                    )
                    .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: historyManager.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)

            Text(
                historyManager.searchQuery.isEmpty
                    ? loc.text(
                        es: "Aún no hay elementos en el historial del portapapeles",
                        en: "No items in clipboard history yet"
                    )
                    : loc.text(
                        es: "Ningún elemento del portapapeles coincide con \"\(historyManager.searchQuery)\"",
                        en: "No clipboard items match \"\(historyManager.searchQuery)\""
                    )
            )
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.secondary)

            Text(loc.text(
                es: "Cualquier texto, enlace, archivo o imagen que copies (⌘C) aparecerá automáticamente aquí.",
                en: "Any text, link, file, or image you copy (⌘C) will automatically appear here."
            ))
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)

            Text(loc.text(
                es: "El Historial del Portapapeles está desactivado",
                en: "Clipboard History is currently disabled"
            ))
            .font(.system(size: 14, weight: .semibold))

            Button {
                prefs.isEnabled = true
            } label: {
                Label(loc.text(es: "Activar Historial del Portapapeles", en: "Enable Clipboard History"), systemImage: "power")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countForFilter(_ filter: ClipboardHistoryFilter) -> Int {
        historyManager.items.filter { $0.matches(query: historyManager.searchQuery, filter: filter) }.count
    }

    // MARK: - Atajos de Teclado Internos Configurables

    private func installLocalKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let chars = event.charactersIgnoringModifiers?.lowercased()
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let handled = MainActor.assumeIsolated {
                handleMaccyKeyboardEvent(keyCode: keyCode, chars: chars, flags: flags)
            }
            return handled ? nil : event
        }
    }

    private func removeLocalKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleMaccyKeyboardEvent(
        keyCode: UInt16,
        chars: String?,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard viewModel.isShowingClipboardHistory else { return false }
        guard !ClipboardShortcutsWindowController.shared.isRecordingShortcut else { return false }
        let list = historyManager.filteredItems
        let cleanFlags = flags.intersection([.command, .shift, .option, .control])

        // ⌘1 .. ⌘9 y ⌘0 (ítem 10) -> Copia rápida por índice como en Maccy
        if cleanFlags == .command, let chars, let digit = Int(chars) {
            let idx = digit == 0 ? 9 : (digit - 1)
            if list.indices.contains(idx) {
                let target = list[idx]
                historyManager.selectedEntryID = target.id
                historyManager.copyEntryToPasteboard(target)
                return true
            }
        }

        // Atajo configurable: Fijar / Desfijar elemento seleccionado (por defecto ⌥P)
        if prefs.pinShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            if let current = historyManager.selectedEntry {
                historyManager.togglePin(current.id)
                return true
            }
        }

        // Atajo configurable: Eliminar elemento seleccionado (por defecto ⌥⌫)
        if prefs.deleteShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            if let current = historyManager.selectedEntry {
                historyManager.deleteEntry(current.id)
                return true
            }
        }

        // Atajo configurable: Limpiar todos los elementos no fijados (por defecto ⌥⌘⌫)
        if prefs.clearHistoryShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            historyManager.clearUnpinnedHistory()
            return true
        }

        // Atajo configurable: Copiar como texto plano sin formato (por defecto ⌥↵)
        if prefs.plainTextShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            if let current = historyManager.selectedEntry {
                historyManager.copyEntryToPasteboard(current, plainTextOnly: true)
                return true
            }
        }

        // Enter / Return (36 / 76) sin modificadores -> Copiar elemento seleccionado
        if (keyCode == 36 || keyCode == 76) && cleanFlags.isEmpty {
            if let current = historyManager.selectedEntry {
                historyManager.copyEntryToPasteboard(current, plainTextOnly: false)
                return true
            }
        }

        // Flecha Arriba (126) / Flecha Abajo (125)
        if (keyCode == 126 || keyCode == 125) && cleanFlags.isEmpty {
            guard !list.isEmpty else { return false }
            let currentID = historyManager.selectedEntry?.id
            let currentIndex = list.firstIndex(where: { $0.id == currentID }) ?? 0
            let nextIndex = keyCode == 126
                ? max(0, currentIndex - 1)
                : min(list.count - 1, currentIndex + 1)
            historyManager.selectedEntryID = list[nextIndex].id
            return true
        }

        return false
    }
}

// MARK: - Fila Individual del Historial del Portapapeles (Vista Completa)

struct ClipboardHistoryRowView: View {
    let entry: ClipboardHistoryEntry
    let shortcutNumber: Int?
    let isSelected: Bool
    let isCopiedFeedbackVisible: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @ViewState private var isHovered: Bool = false
    private var loc: LocalizationManager { LocalizationManager.shared }

    var body: some View {
        HStack(spacing: 10) {
            rowLeadingVisual

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    Text(entry.displayTitle(using: loc))
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(entry.displaySubtitle(using: loc))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isCopiedFeedbackVisible {
                Text(loc.text(es: "Copiado", en: "Copied"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            } else if isHovered || isSelected {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Copiar al portapapeles", en: "Copy to clipboard"))

                    Button(action: onTogglePin) {
                        Image(systemName: entry.isPinned ? "pin.slash.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(entry.isPinned ? .orange : .secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
            } else if let shortcutNumber {
                Text("⌘\(shortcutNumber)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onCopy()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var rowLeadingVisual: some View {
        if let thumb = ClipboardHistoryManager.shared.image(for: entry) {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 34, height: 34)

                Image(systemName: entry.kind.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

// MARK: - Panel Flotante Desplegable Estilo Maccy (`⌃⌘V` en cualquier lugar de la Mac)

@MainActor
private final class MaccyDropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class ClipboardQuickPopupController: NSObject {

    public static let shared = ClipboardQuickPopupController()

    private var popupPanel: MaccyDropdownPanel?
    private weak var previousActiveApp: NSRunningApplication?
    private var resignKeyObserver: NSObjectProtocol?
    private var popupKeyMonitor: Any?

    @Observable
    fileprivate final class PopupState {
        var query: String = ""
        var highlightedEntryID: UUID?
    }

    fileprivate let state = PopupState()

    private override init() {
        super.init()
    }

    public var isVisible: Bool {
        popupPanel?.isVisible == true
    }

    public func togglePopup() {
        if isVisible {
            closePopup(restorePreviousApp: true)
        } else {
            showPopup()
        }
    }

    /// Abre el menú desplegable estilo Maccy con los últimos 10 elementos cerca del puntero del ratón,
    /// sin importar en qué aplicación o escritorio esté parado el usuario.
    public func showPopup() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousActiveApp = front
        }

        state.query = ""
        let initialItems = ClipboardHistoryManager.shared.dropdownPopupItems(query: "")
        state.highlightedEntryID = initialItems.first?.id

        let panel = ensurePanel()
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        let panelWidth: CGFloat = 530
        let panelHeight: CGFloat = 430

        if let screen = targetScreen {
            let visible = screen.visibleFrame
            var originX = mouseLoc.x - 40
            var originY = mouseLoc.y - panelHeight - 8
            if originY < visible.minY + 12 {
                originY = min(mouseLoc.y + 18, visible.maxY - panelHeight - 12)
            }
            originX = min(max(originX, visible.minX + 12), visible.maxX - panelWidth - 12)
            originY = min(max(originY, visible.minY + 12), visible.maxY - panelHeight - 12)
            panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
        }

        installPopupKeyMonitorIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func closePopup(restorePreviousApp: Bool) {
        removePopupKeyMonitor()
        popupPanel?.orderOut(nil)
        if restorePreviousApp, let prev = previousActiveApp, !prev.isTerminated {
            prev.activate()
        }
        previousActiveApp = nil
    }

    fileprivate func selectAndPaste(_ entry: ClipboardHistoryEntry, plainTextOnly: Bool = false) {
        let targetApp = previousActiveApp
        ClipboardHistoryManager.shared.copyEntryToPasteboard(entry, plainTextOnly: plainTextOnly)
        removePopupKeyMonitor()
        popupPanel?.orderOut(nil)

        if let targetApp, !targetApp.isTerminated {
            targetApp.activate()
            previousActiveApp = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(75))
                ClipboardHistoryManager.shared.synthesizeCommandVInActiveApplication()
            }
        } else {
            previousActiveApp = nil
        }
    }

    public func openFullHistoryInMainWindow() {
        closePopup(restorePreviousApp: false)
        GoogleAccountsManager.shared.openOrFocusMainWindow()
        ExplorerWindowRegistry.shared.activeViewModel?.openClipboardHistorySection()
    }

    private func ensurePanel() -> MaccyDropdownPanel {
        if let existing = popupPanel {
            return existing
        }
        let panel = MaccyDropdownPanel(
            contentRect: NSRect(x: 200, y: 200, width: 530, height: 430),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let hc = NSHostingController(rootView: ClipboardQuickPopupView(controller: self, state: state))
        hc.sizingOptions = []
        panel.contentViewController = hc

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible else { return }
                self.closePopup(restorePreviousApp: false)
            }
        }

        self.popupPanel = panel
        return panel
    }

    private func installPopupKeyMonitorIfNeeded() {
        guard popupKeyMonitor == nil else { return }
        popupKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode
            let chars = event.charactersIgnoringModifiers?.lowercased()
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let handled = MainActor.assumeIsolated {
                self.handlePopupKeyDown(keyCode: keyCode, chars: chars, flags: flags)
            }
            return handled ? nil : event
        }
    }

    private func removePopupKeyMonitor() {
        if let monitor = popupKeyMonitor {
            NSEvent.removeMonitor(monitor)
            popupKeyMonitor = nil
        }
    }

    private func handlePopupKeyDown(
        keyCode: UInt16,
        chars: String?,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard isVisible else { return false }
        let prefs = ClipboardHistoryPreferences.shared
        let manager = ClipboardHistoryManager.shared
        let items = manager.dropdownPopupItems(query: state.query)
        let cleanFlags = flags.intersection([.command, .shift, .option, .control])

        // Escape (53) -> Cerrar menú desplegable y devolver foco
        if keyCode == 53 {
            closePopup(restorePreviousApp: true)
            return true
        }

        // ⌘1 .. ⌘9 y ⌘0 (ítem 10) -> Pegar inmediatamente ese elemento como en Maccy
        if cleanFlags == .command, let chars, let digit = Int(chars) {
            let idx = digit == 0 ? 9 : (digit - 1)
            if items.indices.contains(idx) {
                selectAndPaste(items[idx], plainTextOnly: false)
                return true
            }
        }

        // Atajo configurable: Pegar texto plano (por defecto ⌥↵)
        if prefs.plainTextShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            if let current = items.first(where: { $0.id == state.highlightedEntryID }) ?? items.first {
                selectAndPaste(current, plainTextOnly: true)
                return true
            }
        }

        // Enter / Return (36 / 76) -> Pegar elemento resaltado
        if (keyCode == 36 || keyCode == 76) && cleanFlags.isEmpty {
            if let current = items.first(where: { $0.id == state.highlightedEntryID }) ?? items.first {
                selectAndPaste(current, plainTextOnly: false)
                return true
            }
        }

        // Atajo configurable: Fijar / Desfijar (por defecto ⌥P)
        if prefs.pinShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            if let current = items.first(where: { $0.id == state.highlightedEntryID }) ?? items.first {
                manager.togglePin(current.id)
                return true
            }
        }

        // Atajo configurable: Eliminar elemento (por defecto ⌥⌫)
        if prefs.deleteShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            if let current = items.first(where: { $0.id == state.highlightedEntryID }) ?? items.first {
                manager.deleteEntry(current.id)
                let updated = manager.dropdownPopupItems(query: state.query)
                state.highlightedEntryID = updated.first?.id
                return true
            }
        }

        // Atajo configurable: Limpiar historial no fijado (por defecto ⌥⌘⌫)
        if prefs.clearHistoryShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: cleanFlags) {
            manager.clearUnpinnedHistory()
            let updated = manager.dropdownPopupItems(query: state.query)
            state.highlightedEntryID = updated.first?.id
            return true
        }

        // Flechas Arriba (126) / Abajo (125)
        if (keyCode == 126 || keyCode == 125) && cleanFlags.isEmpty {
            guard !items.isEmpty else { return true }
            let currentIdx = items.firstIndex(where: { $0.id == state.highlightedEntryID }) ?? 0
            let nextIdx = keyCode == 126
                ? (currentIdx > 0 ? currentIdx - 1 : items.count - 1)
                : (currentIdx + 1 < items.count ? currentIdx + 1 : 0)
            state.highlightedEntryID = items[nextIdx].id
            return true
        }

        return false
    }
}

/// Vista del menú desplegable rápido estilo Maccy (idéntica al diseño de la captura de referencia:
/// cabecera compacta con caja `type to search...`, listado de los últimos 10 ítems con imágenes en vivo y `⌘1`..`⌘9`).
private struct ClipboardQuickPopupView: View {
    let controller: ClipboardQuickPopupController
    @Bindable var state: ClipboardQuickPopupController.PopupState
    @Bindable var historyManager: ClipboardHistoryManager = .shared
    @FocusState private var isSearchFocused: Bool

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var displayedItems: [ClipboardHistoryEntry] {
        historyManager.dropdownPopupItems(query: state.query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cabecera idéntica a Maccy: título sutil a la izquierda + campo de búsqueda redondeado a la derecha
            HStack(spacing: 10) {
                Text("MacFileExplorer")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    TextField(
                        loc.text(es: "escribir para buscar...", en: "type to search..."),
                        text: $state.query
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onChange(of: state.query) { _, newValue in
                        let updated = historyManager.dropdownPopupItems(query: newValue)
                        state.highlightedEntryID = updated.first?.id
                    }

                    if !state.query.isEmpty {
                        Button {
                            state.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

            // Listado de los últimos 10 ítems copiados (con previsualización directa de imágenes como en Maccy)
            if displayedItems.isEmpty {
                VStack(spacing: 6) {
                    Text(loc.text(es: "Sin elementos coincidentes", en: "No matching items"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(displayedItems.enumerated()), id: \.element.id) { idx, entry in
                                MaccyDropdownRowView(
                                    entry: entry,
                                    shortcutBadge: idx < 9 ? "⌘\(idx + 1)" : (idx == 9 ? "⌘0" : nil),
                                    isHighlighted: state.highlightedEntryID == entry.id,
                                    onHoverRow: {
                                        state.highlightedEntryID = entry.id
                                    },
                                    onSelectRow: {
                                        controller.selectAndPaste(entry, plainTextOnly: false)
                                    }
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                    .onChange(of: state.highlightedEntryID) { _, newID in
                        if let newID {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }

            Divider()
                .padding(.horizontal, 10)

            // Pie compacto con acceso al buscador completo, configuración de atajos y limpiar
            HStack(spacing: 12) {
                Button {
                    controller.openFullHistoryInMainWindow()
                } label: {
                    Label(
                        loc.text(es: "Ver todo el historial…", en: "Search Full History…"),
                        systemImage: "magnifyingglass"
                    )
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    controller.closePopup(restorePreviousApp: false)
                    ClipboardShortcutsWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Atajos y ajustes…", en: "Shortcuts & Settings…"),
                        systemImage: "keyboard"
                    )
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    historyManager.clearUnpinnedHistory()
                } label: {
                    Text(loc.text(es: "Limpiar", en: "Clear"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
        }
    }
}

/// Fila individual del menú desplegable estilo Maccy:
/// - Si es una imagen, muestra directamente la imagen renderizada (igual que en Maccy).
/// - Si es texto/enlace/archivo, muestra el texto formateado en una línea con `⏎` para saltos de línea.
/// - A la derecha muestra `⌘1` … `⌘9`.
private struct MaccyDropdownRowView: View {
    let entry: ClipboardHistoryEntry
    let shortcutBadge: String?
    let isHighlighted: Bool
    let onHoverRow: () -> Void
    let onSelectRow: () -> Void

    private var loc: LocalizationManager { LocalizationManager.shared }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(isHighlighted ? .white : .orange)
            }

            if let image = ClipboardHistoryManager.shared.image(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 46, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Text(entry.maccyMenuTitle(using: loc))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let shortcutBadge {
                Text(shortcutBadge)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.9) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                onHoverRow()
            }
        }
        .onTapGesture {
            onSelectRow()
        }
    }
}

// MARK: - Ventana de Configuración de Todos los Atajos y Opciones del Portapapeles

@MainActor
public final class ClipboardShortcutsWindowController: NSObject {

    public static let shared = ClipboardShortcutsWindowController()

    private var window: NSWindow?
    public var isRecordingShortcut: Bool = false

    private override init() {
        super.init()
    }

    public func show() {
        let loc = LocalizationManager.shared
        if let existing = window {
            existing.title = loc.text(
                es: "Configuración y Atajos del Portapapeles",
                en: "Clipboard Settings & Keyboard Shortcuts"
            )
            NSApplication.shared.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.title = loc.text(
            es: "Configuración y Atajos del Portapapeles",
            en: "Clipboard Settings & Keyboard Shortcuts"
        )
        win.contentViewController = NSHostingController(rootView: ClipboardShortcutsSettingsView())
        win.center()
        self.window = win

        NSApplication.shared.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

public struct ClipboardShortcutsSettingsView: View {
    @Bindable private var prefs: ClipboardHistoryPreferences = .shared
    @ViewState private var recordingTarget: ShortcutActionKind? = nil
    @ViewState private var recordingMonitor: Any? = nil

    private var loc: LocalizationManager { LocalizationManager.shared }

    fileprivate enum ShortcutActionKind: String, CaseIterable, Identifiable {
        case quickPasteDropdown
        case fullHistorySearch
        case pinItem
        case deleteItem
        case plainTextCopy
        case clearHistory

        var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Cabecera
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(
                        es: "Configuración del Portapapeles y Atajos (Maccy)",
                        en: "Clipboard History & Shortcuts (Maccy)"
                    ))
                    .font(.system(size: 15, weight: .semibold))

                    Text(loc.text(
                        es: "El pegado estándar (⌘V) siempre pega lo último copiado. Usa el atajo desplegable (⌃⌘V) para elegir entre los últimos elementos copiados desde cualquier app.",
                        en: "Standard paste (⌘V) always pastes the latest item. Use the dropdown shortcut (⌃⌘V) to pick from recent items anywhere on your Mac."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Sección 1: Retención y Comportamiento General
            VStack(alignment: .leading, spacing: 10) {
                Text(loc.text(es: "Almacenamiento y Menú Desplegable", en: "Storage & Dropdown Menu"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Toggle(isOn: $prefs.isEnabled) {
                    Text(loc.text(
                        es: "Activar Historial del Portapapeles",
                        en: "Enable Clipboard History"
                    ))
                    .font(.system(size: 13, weight: .medium))
                }

                HStack {
                    Text(loc.text(es: "Tiempo de guardado:", en: "Keep history for:"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: $prefs.retentionPeriod) {
                        ForEach(ClipboardRetentionPeriod.allCases) { period in
                            Text(period.localizedTitle(using: loc)).tag(period)
                        }
                    }
                    .frame(width: 240)
                }

                HStack {
                    Text(loc.text(es: "Cantidad máxima en historial:", en: "Maximum items in history:"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: $prefs.maxItemsOption) {
                        ForEach(ClipboardMaxItemsOption.allCases) { option in
                            Text(option.localizedTitle(using: loc)).tag(option)
                        }
                    }
                    .frame(width: 240)
                }

                HStack {
                    Text(loc.text(es: "Elementos en el menú desplegable (⌃⌘V):", en: "Items in quick dropdown menu (⌃⌘V):"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: $prefs.dropdownCountOption) {
                        ForEach(ClipboardDropdownCountOption.allCases) { option in
                            Text(option.localizedTitle(using: loc)).tag(option)
                        }
                    }
                    .frame(width: 240)
                }

                Toggle(isOn: $prefs.autoPasteOnSelect) {
                    Text(loc.text(
                        es: "Pegar automáticamente en la aplicación activa al elegir del menú desplegable",
                        en: "Automatically paste into active application when selecting from dropdown"
                    ))
                    .font(.system(size: 12.5))
                }
            }

            Divider()

            // Sección 2: Todos los Atajos Configurables
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(loc.text(es: "Atajos de Teclado Configurables", en: "Configurable Keyboard Shortcuts"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        stopRecording()
                        prefs.resetShortcutsToDefaults()
                    } label: {
                        Label(
                            loc.text(es: "Restablecer predeterminados", en: "Reset to Defaults"),
                            systemImage: "arrow.counterclockwise"
                        )
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                shortcutRow(
                    kind: .quickPasteDropdown,
                    title: loc.text(
                        es: "Abrir menú desplegable para pegar (Global en la Mac)",
                        en: "Open quick paste dropdown menu (Global on Mac)"
                    ),
                    shortcut: $prefs.quickPasteDropdownShortcut
                )

                shortcutRow(
                    kind: .fullHistorySearch,
                    title: loc.text(
                        es: "Abrir buscador completo del Historial",
                        en: "Open full Clipboard History search"
                    ),
                    shortcut: $prefs.fullHistorySearchShortcut
                )

                shortcutRow(
                    kind: .pinItem,
                    title: loc.text(
                        es: "Fijar / Desfijar elemento en el menú",
                        en: "Pin / Unpin item in menu"
                    ),
                    shortcut: $prefs.pinShortcut
                )

                shortcutRow(
                    kind: .deleteItem,
                    title: loc.text(
                        es: "Eliminar elemento seleccionado del historial",
                        en: "Delete selected item from history"
                    ),
                    shortcut: $prefs.deleteShortcut
                )

                shortcutRow(
                    kind: .plainTextCopy,
                    title: loc.text(
                        es: "Pegar / Copiar sin formato (Texto plano)",
                        en: "Paste / Copy as plain text"
                    ),
                    shortcut: $prefs.plainTextShortcut
                )

                shortcutRow(
                    kind: .clearHistory,
                    title: loc.text(
                        es: "Limpiar todo el historial no fijado",
                        en: "Clear all unpinned history"
                    ),
                    shortcut: $prefs.clearHistoryShortcut
                )
            }

            Spacer(minLength: 4)
        }
        .padding(20)
        .frame(width: 560)
        .onDisappear {
            stopRecording()
        }
    }

    private func shortcutRow(
        kind: ShortcutActionKind,
        title: String,
        shortcut: Binding<ClipboardKeyShortcut>
    ) -> some View {
        let isRecordingThis = recordingTarget == kind
        return HStack(spacing: 10) {
            Toggle("", isOn: shortcut.isEnabled)
                .labelsHidden()
                .controlSize(.small)

            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(shortcut.wrappedValue.isEnabled ? .primary : .secondary)

            Spacer()

            Button {
                if isRecordingThis {
                    stopRecording()
                } else {
                    startRecording(for: kind)
                }
            } label: {
                Text(
                    isRecordingThis
                        ? loc.text(es: "Presiona las teclas…", en: "Press keys…")
                        : shortcut.wrappedValue.displayString
                )
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecordingThis ? Color.white : Color.primary)
                .frame(minWidth: 110)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecordingThis ? Color.accentColor : Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .help(loc.text(
                es: "Haz clic y presiona la nueva combinación de teclas en tu teclado",
                en: "Click and press the new key combination on your keyboard"
            ))
        }
        .padding(.vertical, 2)
    }

    private func startRecording(for kind: ShortcutActionKind) {
        stopRecording()
        recordingTarget = kind
        ClipboardShortcutsWindowController.shared.isRecordingShortcut = true

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let recorded = ClipboardKeyShortcut.from(event: event)
            let consumed = MainActor.assumeIsolated { () -> Bool in
                if keyCode == 53 { // Escape cancela la grabación
                    stopRecording()
                    return true
                }
                if let recorded {
                    applyRecordedShortcut(recorded, to: kind)
                    stopRecording()
                    return true
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        recordingTarget = nil
        ClipboardShortcutsWindowController.shared.isRecordingShortcut = false
    }

    private func applyRecordedShortcut(_ shortcut: ClipboardKeyShortcut, to kind: ShortcutActionKind) {
        switch kind {
        case .quickPasteDropdown:
            prefs.quickPasteDropdownShortcut = shortcut
        case .fullHistorySearch:
            prefs.fullHistorySearchShortcut = shortcut
        case .pinItem:
            prefs.pinShortcut = shortcut
        case .deleteItem:
            prefs.deleteShortcut = shortcut
        case .plainTextCopy:
            prefs.plainTextShortcut = shortcut
        case .clearHistory:
            prefs.clearHistoryShortcut = shortcut
        }
    }
}
