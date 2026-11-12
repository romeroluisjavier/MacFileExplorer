import AppKit
import SwiftUI

/// Vista principal de "Detalles" estilo tabla Windows 11 Explorer con estética nativa de macOS.
/// Incluye encabezados de columna interactivos (Nombre, Fecha de modificación, Tipo, Tamaño),
/// selección múltiple (`Shift+Clic`, `Cmd+Clic`, cuadro de arrastre), edición en línea (`F2`) y atenuación por corte (`Cmd+X`).
public struct FileDetailsTableView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Bindable private var columnPrefs: DetailsColumnPreferences = .shared
    @Bindable private var listIconPrefs: ListIconPreferences = .shared

    @ViewState private var itemFrames: [FileItem.ID: CGRect] = [:]
    @ViewState private var dragStartPoint: CGPoint? = nil
    @ViewState private var dragCurrentPoint: CGPoint? = nil
    @ViewState private var ignoredRubberBandStart: CGPoint? = nil
    @ViewState private var initialSelectionBeforeDrag: Set<FileItem.ID> = []
    @ViewState private var isContainerDropTargeted: Bool = false
    @ViewState private var headerWidth: CGFloat = 0
    @ViewState private var dragStartWidths: DetailsColumnWidths? = nil

    private let coordinateSpaceName = "DetailsCanvasCoordinateSpace"

    private var dateColumnWidth: CGFloat { columnPrefs.widths.dateWidth }
    private var kindColumnWidth: CGFloat { columnPrefs.widths.kindWidth }
    private var sizeColumnWidth: CGFloat { columnPrefs.widths.sizeWidth }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Barra de Encabezados de Columna Ordenables
            headerBar

            Divider()

            // 2. Cuerpo de la Tabla con Virtualización, Arrastre Nativo y Selección por Arrastre
            GeometryReader { outerGeo in
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        ZStack(alignment: .topLeading) {
                            // Fondo clicable para limpiar selección o iniciar arrastre en espacio vacío
                            Color.clear
                                .frame(
                                    minWidth: outerGeo.size.width,
                                    minHeight: max(outerGeo.size.height, CGFloat(viewModel.displayedItems.count) * 30 + 60)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.clearSelection()
                                }

                            LazyVStack(spacing: 1) {
                                ForEach(viewModel.displayedItems) { item in
                                    FileDetailsRowView(
                                        item: item,
                                        viewModel: viewModel,
                                        dateColumnWidth: dateColumnWidth,
                                        kindColumnWidth: kindColumnWidth,
                                        sizeColumnWidth: sizeColumnWidth,
                                        listIconMode: listIconPrefs.mode
                                    )
                                    .id(item.id)
                                    .background(
                                        GeometryReader { rowGeo in
                                            Color.clear.preference(
                                                key: ItemFramePreferenceKey.self,
                                                value: [item.id: rowGeo.frame(in: .named(coordinateSpaceName))]
                                            )
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)

                            // Cuadro de selección por arrastre (Rubber-band)
                            RubberBandSelectionOverlay(rect: currentDragRect)
                        }
                        .background(
                            NativeFileDragCanvas(viewModel: viewModel, itemFrames: itemFrames)
                        )
                        .coordinateSpace(name: coordinateSpaceName)
                        .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                            itemFrames = frames
                        }
                        .gesture(rubberBandDragGesture)
                    }
                    .onChange(of: viewModel.keyboardScrollToken) { _, _ in
                        if let targetID = viewModel.keyboardScrollTargetID {
                            scrollProxy.scrollTo(targetID)
                        }
                    }
                }
            }
            .explorerFolderDropTarget(
                enabled: true,
                destinationURL: viewModel.currentDirectoryURL,
                viewModel: viewModel,
                isTargeted: $isContainerDropTargeted
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                    .padding(3)
                    .opacity(isContainerDropTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            )
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Encabezado de Columnas

    private var headerBar: some View {
        HStack(spacing: 0) {
            DetailsColumnHeaderButton(
                field: .name,
                activeField: viewModel.sortField,
                ascending: viewModel.sortAscending,
                alignment: .leading
            ) {
                viewModel.toggleSort(by: .name)
            }
            .frame(minWidth: DetailsColumnWidths.minNameWidth, maxWidth: .infinity, alignment: .leading)

            DetailsColumnResizeDivider(
                onDragChanged: { deltaX in
                    let base = captureDragStartWidths()
                    let availableContentWidth = max(headerWidth - 16 - 3, 400)
                    columnPrefs.widths = base.resizingNameAndDate(
                        deltaX: deltaX,
                        availableContentWidth: availableContentWidth
                    )
                },
                onDragEnded: { dragStartWidths = nil },
                onDoubleClickReset: { columnPrefs.resetToDefaults() }
            )
            .zIndex(10)

            DetailsColumnHeaderButton(
                field: .modificationDate,
                activeField: viewModel.sortField,
                ascending: viewModel.sortAscending,
                alignment: .leading
            ) {
                viewModel.toggleSort(
                    by: viewModel.sortField == .modificationDateMix ? .modificationDateMix : .modificationDate
                )
            }
            .frame(width: dateColumnWidth, alignment: .leading)

            DetailsColumnResizeDivider(
                onDragChanged: { deltaX in
                    let base = captureDragStartWidths()
                    columnPrefs.widths = base.resizingDateAndKind(deltaX: deltaX)
                },
                onDragEnded: { dragStartWidths = nil },
                onDoubleClickReset: { columnPrefs.resetToDefaults() }
            )
            .zIndex(10)

            DetailsColumnHeaderButton(
                field: .kind,
                activeField: viewModel.sortField,
                ascending: viewModel.sortAscending,
                alignment: .leading
            ) {
                viewModel.toggleSort(by: .kind)
            }
            .frame(width: kindColumnWidth, alignment: .leading)

            DetailsColumnResizeDivider(
                onDragChanged: { deltaX in
                    let base = captureDragStartWidths()
                    columnPrefs.widths = base.resizingKindAndSize(deltaX: deltaX)
                },
                onDragEnded: { dragStartWidths = nil },
                onDoubleClickReset: { columnPrefs.resetToDefaults() }
            )
            .zIndex(10)

            DetailsColumnHeaderButton(
                field: .size,
                activeField: viewModel.sortField,
                ascending: viewModel.sortAscending,
                alignment: .trailing
            ) {
                viewModel.toggleSort(by: .size)
            }
            .frame(width: sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 29)
        .background(
            GeometryReader { geo in
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.85)
                    .onAppear { headerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        headerWidth = newWidth
                    }
            }
        )
    }

    private func captureDragStartWidths() -> DetailsColumnWidths {
        if let dragStartWidths {
            return dragStartWidths
        }
        let current = columnPrefs.widths
        dragStartWidths = current
        return current
    }

    // MARK: - Lógica del Cuadro de Selección por Arrastre

    private var currentDragRect: CGRect? {
        guard let start = dragStartPoint, let current = dragCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private var rubberBandDragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if dragStartPoint == nil {
                    if ignoredRubberBandStart == value.startLocation {
                        return
                    }
                    if DragDropOperationHelper.isPoint(value.startLocation, insideAny: itemFrames) {
                        ignoredRubberBandStart = value.startLocation
                        return
                    }
                    ignoredRubberBandStart = nil
                    dragStartPoint = value.startLocation
                    let modifiers = KeyboardShortcuts.currentEventModifiers
                    if modifiers.contains(.command) || modifiers.contains(.shift) {
                        initialSelectionBeforeDrag = viewModel.selectedItemIDs
                    } else {
                        initialSelectionBeforeDrag = []
                    }
                }
                dragCurrentPoint = value.location

                guard let rect = currentDragRect else { return }
                var matchingIDs = initialSelectionBeforeDrag
                for (id, frame) in itemFrames where rect.intersects(frame) {
                    matchingIDs.insert(id)
                }
                viewModel.selectedItemIDs = matchingIDs
            }
            .onEnded { _ in
                ignoredRubberBandStart = nil
                dragStartPoint = nil
                dragCurrentPoint = nil
                initialSelectionBeforeDrag = []
            }
    }
}

// MARK: - Divisor Redimensionable de Columnas

private struct DetailsColumnResizeDivider: View {
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onDoubleClickReset: () -> Void

    @ViewState private var isHovered: Bool = false
    @ViewState private var isDragging: Bool = false
    @ViewState private var didPushCursor: Bool = false

    private var isActive: Bool { isHovered || isDragging }

    var body: some View {
        Rectangle()
            .fill(isActive ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.14))
            .frame(width: isActive ? 2 : 1, height: isActive ? 18 : 16)
            .frame(width: 1, height: 29)
            .overlay(alignment: .center) {
                Color.clear
                    .frame(width: 12, height: 29)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHovered = hovering
                        updateCursor(active: hovering || isDragging)
                    }
                    .onTapGesture(count: 2) {
                        onDoubleClickReset()
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    updateCursor(active: true)
                                }
                                onDragChanged(value.translation.width)
                            }
                            .onEnded { _ in
                                isDragging = false
                                updateCursor(active: isHovered)
                                onDragEnded()
                            }
                    )
            }
            .onDisappear {
                updateCursor(active: false)
            }
    }

    @MainActor
    private func updateCursor(active: Bool) {
        if active && !didPushCursor {
            NSCursor.resizeLeftRight.push()
            didPushCursor = true
        } else if !active && didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
    }
}

// MARK: - Botón de Encabezado de Columna

private struct DetailsColumnHeaderButton: View {
    let field: FileItem.SortField
    let activeField: FileItem.SortField
    let ascending: Bool
    let alignment: Alignment
    let action: () -> Void

    @ViewState private var isHovered: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var isSortedByThisColumn: Bool {
        field == activeField || (field == .modificationDate && activeField == .modificationDateMix)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if alignment == .trailing {
                    Spacer(minLength: 4)
                }

                Text(loc.sortFieldTitle(field))
                    .font(.system(size: 11.5, weight: isSortedByThisColumn ? .semibold : .medium))
                    .foregroundStyle(isSortedByThisColumn ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isSortedByThisColumn {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                if alignment == .leading {
                    Spacer(minLength: 4)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipped()
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Fila Individual de la Vista Detalles

private struct ListRowThumbnailTaskKey: Equatable {
    let itemID: FileItem.ID
    let mode: ListIconDisplayMode
}

private struct FileDetailsRowView: View {
    let item: FileItem
    @Bindable var viewModel: ExplorerViewModel
    let dateColumnWidth: CGFloat
    let kindColumnWidth: CGFloat
    let sizeColumnWidth: CGFloat
    let listIconMode: ListIconDisplayMode

    @ViewState private var isHovered: Bool = false
    @ViewState private var isDropTargeted: Bool = false
    @ViewState private var loadedThumbnail: NSImage? = nil

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var isSelected: Bool {
        viewModel.selectedItemIDs.contains(item.id)
    }

    private var isRenaming: Bool {
        viewModel.renamingItemID == item.id
    }

    private var isCut: Bool {
        viewModel.clipboardManager.isCut(item)
    }

    private var effectiveThumbnail: NSImage? {
        guard listIconMode == .thumbnail else { return nil }
        return loadedThumbnail ?? ThumbnailCacheService.shared.memoryCachedThumbnail(for: item)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Columna 1: Icono / Miniatura + Nombre (o campo de renombrado en línea F2)
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let thumb = effectiveThumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
                            )
                            .opacity(isCut ? 0.42 : (item.isHidden ? 0.55 : 1.0))
                    } else {
                        Image(nsImage: FileIconProvider.shared.listIcon(for: item, mode: listIconMode, size: 20))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 20, height: 20)
                            .opacity(isCut ? 0.42 : (item.isHidden ? 0.55 : 1.0))
                    }

                    if isCut {
                        Image(systemName: "scissors")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(Color.orange))
                            .offset(x: 3, y: 3)
                    } else if item.isSymbolicLink {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                            .offset(x: 2, y: 2)
                    }
                }

                if isRenaming {
                    InlineRenameTextField(viewModel: viewModel, alignment: .leading)
                        .frame(maxWidth: 340)
                } else {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(textForegroundColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)
            }
            .padding(.leading, 10)
            .frame(minWidth: DetailsColumnWidths.minNameWidth, maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: 1, height: 1)

            // Columna 2: Fecha de modificación
            Text(item.formattedModificationDate)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(width: dateColumnWidth, alignment: .leading)
                .opacity(isCut ? 0.5 : 1.0)

            Color.clear.frame(width: 1, height: 1)

            // Columna 3: Tipo
            Text(loc.localizedKindDescription(for: item))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(width: kindColumnWidth, alignment: .leading)
                .opacity(isCut ? 0.5 : 1.0)

            Color.clear.frame(width: 1, height: 1)

            // Columna 4: Tamaño (alineado a la derecha, vacío para carpetas)
            Text(item.formattedSize)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(width: sizeColumnWidth, alignment: .trailing)
                .opacity(isCut ? 0.5 : 1.0)
        }
        .frame(height: 28)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(rowBackgroundColor)

                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 1)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    isDropTargeted
                        ? Color.accentColor
                        : (isCut ? Color.orange.opacity(0.45) : (isSelected ? Color.accentColor.opacity(0.25) : Color.clear)),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 0.8, dash: (isCut && !isDropTargeted) ? [4, 3] : [])
                )
        )
        .contentShape(Rectangle())
        .explorerFolderDropTarget(
            enabled: item.isNavigableFolder,
            destinationURL: item.url,
            viewModel: viewModel,
            isTargeted: $isDropTargeted
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !isRenaming else { return }
                viewModel.openItem(item)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                guard !isRenaming else { return }
                let modifiers = KeyboardShortcuts.currentEventModifiers
                viewModel.handleSelection(of: item, modifiers: modifiers)
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            ExplorerItemContextMenu(item: item, viewModel: viewModel)
        }
        .task(id: ListRowThumbnailTaskKey(itemID: item.id, mode: listIconMode)) {
            guard listIconMode == .thumbnail,
                  ThumbnailCacheService.shared.supportsThumbnail(for: item) else {
                loadedThumbnail = nil
                return
            }
            if let memCached = ThumbnailCacheService.shared.memoryCachedThumbnail(for: item) {
                loadedThumbnail = memCached
                return
            }
            if let generated = await ThumbnailCacheService.shared.thumbnail(for: item, maxPixelSize: 160) {
                loadedThumbnail = generated
            }
        }
    }

    private var textForegroundColor: Color {
        if isCut {
            return .secondary
        }
        if item.isHidden {
            return .secondary
        }
        return .primary
    }

    private var rowBackgroundColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.22)
        }
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        if isHovered {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }
}
