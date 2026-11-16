import AppKit
import SwiftUI

/// Vista principal del Historial del Portapapeles estilo Maccy integrada en el área central de `MacFileExplorer`.
/// Permite buscar cualquier texto, enlace, archivo o imagen copiada, configurar el tiempo y cantidad máxima de guardado,
/// fijar elementos favoritos (`⌥P`), eliminar (`⌥⌫`), copiar con `Enter` o `⌘1`..`⌘9` y previsualizar imágenes a tamaño completo.
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

    // MARK: - Barra de Filtros por Categoría y Configuración de Tiempo / Cantidad

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
                .help(loc.text(
                    es: "Configurar cuántos elementos guardar en el historial del portapapeles",
                    en: "Configure how many items to keep in clipboard history"
                ))

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
                .help(loc.text(
                    es: "Configurar cuánto tiempo conservar los elementos copiados",
                    en: "Configure how long to keep copied items"
                ))

                // Configuración 3: Atajo estilo Maccy
                Menu {
                    Picker(
                        loc.text(es: "Atajo rápido estilo Maccy", en: "Maccy-style quick shortcut"),
                        selection: $prefs.popupShortcutPreset
                    ) {
                        ForEach(ClipboardPopupShortcutPreset.allCases) { preset in
                            Text(preset.localizedTitle(using: loc))
                                .tag(preset)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "command")
                            .font(.system(size: 11))
                        Text(
                            prefs.popupShortcutPreset == .disabled
                                ? loc.text(es: "Atajo: Off", en: "Shortcut: Off")
                                : loc.text(es: "Atajo: \(prefs.popupShortcutPreset.badgeText)", en: "Shortcut: \(prefs.popupShortcutPreset.badgeText)")
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
                .help(loc.text(
                    es: "Atajo para abrir el buscador rápido del portapapeles (como Maccy)",
                    en: "Shortcut to open the quick clipboard search popup (like Maccy)"
                ))

                // Botón Limpiar no fijados (⌥⌘⌫)
                Button {
                    historyManager.clearUnpinnedHistory()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text(loc.text(es: "Limpiar (⌥⌘⌫)", en: "Clear (⌥⌘⌫)"))
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
                .help(loc.text(
                    es: "Borrar todos los elementos no fijados del historial (⌥⌘⌫)",
                    en: "Clear all unpinned items from history (⌥⌘⌫)"
                ))
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
                            shortcutNumber: index < 9 ? (index + 1) : nil,
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
                // Cabecera del elemento seleccionado
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
                    .help(loc.text(es: "Fijar / Desfijar (⌥P)", en: "Pin / Unpin (⌥P)"))

                    Button(role: .destructive) {
                        historyManager.deleteEntry(entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(loc.text(es: "Eliminar del historial (⌥⌫)", en: "Delete from history (⌥⌫)"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.02))

                Divider()

                // Cuerpo de previsualización según el tipo de contenido
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

                // Pie de metadatos y atajos de Maccy
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
                        es: "Atajos Maccy: ↵ Copiar • ⌥↵ Texto plano • ⌥P Fijar • ⌥⌫ Borrar • ⌘1..9 Copia rápida",
                        en: "Maccy shortcuts: ↵ Copy • ⌥↵ Plain text • ⌥P Pin • ⌥⌫ Delete • ⌘1..9 Quick copy"
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
                    Label(loc.text(es: "Copiar sin formato (⌥↵)", en: "Copy Plain Text (⌥↵)"), systemImage: "text.alignleft")
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

    // MARK: - Atajos de Teclado Internos estilo Maccy (↑/↓, Enter, ⌥Enter, ⌥P, ⌥⌫, ⌘1..9)

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
        let list = historyManager.filteredItems
        let cleanFlags = flags.intersection([.command, .shift, .option, .control])

        // ⌘1 .. ⌘9 -> Copia rápida por índice como en Maccy
        if cleanFlags == .command, let chars, let digit = Int(chars), (1...9).contains(digit) {
            let idx = digit - 1
            if list.indices.contains(idx) {
                let target = list[idx]
                historyManager.selectedEntryID = target.id
                historyManager.copyEntryToPasteboard(target)
                return true
            }
        }

        // ⌥P -> Fijar / Desfijar elemento seleccionado
        if cleanFlags == .option && (keyCode == 35 || chars == "p") {
            if let current = historyManager.selectedEntry {
                historyManager.togglePin(current.id)
                return true
            }
        }

        // ⌥⌫ (Option + Backspace/Delete) -> Eliminar elemento seleccionado
        if cleanFlags == .option && (keyCode == 51 || keyCode == 117) {
            if let current = historyManager.selectedEntry {
                historyManager.deleteEntry(current.id)
                return true
            }
        }

        // ⌥⌘⌫ (Option + Cmd + Backspace) -> Limpiar todos los elementos no fijados
        if cleanFlags == [.command, .option] && (keyCode == 51 || keyCode == 117) {
            historyManager.clearUnpinnedHistory()
            return true
        }

        // Enter / Return (36 / 76): Copiar elemento seleccionado (con ⌥ copia texto plano)
        if keyCode == 36 || keyCode == 76 {
            if cleanFlags.isEmpty || cleanFlags == .option {
                if let current = historyManager.selectedEntry {
                    historyManager.copyEntryToPasteboard(current, plainTextOnly: cleanFlags == .option)
                    return true
                }
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

// MARK: - Fila Individual del Historial del Portapapeles

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
            // Miniatura si es imagen o icono representativo del tipo
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
                    .help(loc.text(es: "Fijar / Desfijar (⌥P)", en: "Pin / Unpin (⌥P)"))

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Eliminar (⌥⌫)", en: "Delete (⌥⌫)"))
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

// MARK: - Ventana Flotante Rápida Estilo Maccy (`⇧⌘C`)

@MainActor
public final class ClipboardQuickPopupController: NSObject {

    public static let shared = ClipboardQuickPopupController()

    private var popupPanel: NSPanel?
    private weak var previousActiveApp: NSRunningApplication?

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

    public func showPopup() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousActiveApp = front
        }

        let panel = ensurePanel()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let w: CGFloat = 580
            let h: CGFloat = 440
            let rect = NSRect(
                x: visible.midX - w / 2,
                y: visible.midY - h / 2 + 60,
                width: w,
                height: h
            )
            panel.setFrame(rect, display: true)
        }

        ClipboardHistoryManager.shared.searchQuery = ""
        ClipboardHistoryManager.shared.selectedFilter = .all
        ClipboardHistoryManager.shared.selectedEntryID = ClipboardHistoryManager.shared.filteredItems.first?.id

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func closePopup(restorePreviousApp: Bool) {
        popupPanel?.orderOut(nil)
        if restorePreviousApp, let prev = previousActiveApp, !prev.isTerminated {
            prev.activate()
        }
        previousActiveApp = nil
    }

    public func openFullHistoryInMainWindow() {
        closePopup(restorePreviousApp: false)
        GoogleAccountsManager.shared.openOrFocusMainWindow()
        ExplorerWindowRegistry.shared.activeViewModel?.openClipboardHistorySection()
    }

    private func ensurePanel() -> NSPanel {
        if let existing = popupPanel {
            return existing
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 580, height: 440),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.minSize = NSSize(width: 440, height: 320)

        let hc = NSHostingController(rootView: ClipboardQuickPopupView())
        hc.sizingOptions = []
        panel.contentViewController = hc
        self.popupPanel = panel
        return panel
    }
}

private struct ClipboardQuickPopupView: View {
    @Bindable var historyManager: ClipboardHistoryManager = .shared
    @FocusState private var isSearchFocused: Bool

    private var loc: LocalizationManager { LocalizationManager.shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(Color.purple)
                TextField(
                    loc.text(es: "Buscar en el portapapeles (Maccy)…", en: "Search clipboard (Maccy)…"),
                    text: $historyManager.searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($isSearchFocused)

                Button {
                    ClipboardQuickPopupController.shared.openFullHistoryInMainWindow()
                } label: {
                    Label(loc.text(es: "Abrir completo", en: "Open Full View"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    ClipboardQuickPopupController.shared.closePopup(restorePreviousApp: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView(.vertical) {
                LazyVStack(spacing: 3) {
                    ForEach(Array(historyManager.filteredItems.enumerated()), id: \.element.id) { idx, entry in
                        ClipboardHistoryRowView(
                            entry: entry,
                            shortcutNumber: idx < 9 ? (idx + 1) : nil,
                            isSelected: historyManager.selectedEntry?.id == entry.id,
                            isCopiedFeedbackVisible: historyManager.recentlyCopiedFeedbackEntryID == entry.id,
                            onSelect: {
                                historyManager.selectedEntryID = entry.id
                                historyManager.copyEntryToPasteboard(entry)
                                ClipboardQuickPopupController.shared.closePopup(restorePreviousApp: true)
                            },
                            onCopy: {
                                historyManager.copyEntryToPasteboard(entry)
                                ClipboardQuickPopupController.shared.closePopup(restorePreviousApp: true)
                            },
                            onTogglePin: {
                                historyManager.togglePin(entry.id)
                            },
                            onDelete: {
                                historyManager.deleteEntry(entry.id)
                            }
                        )
                    }
                }
                .padding(8)
            }
        }
        .background(.regularMaterial)
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            ClipboardQuickPopupController.shared.closePopup(restorePreviousApp: true)
        }
    }
}
