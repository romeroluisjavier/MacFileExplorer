import SwiftUI

/// Vista de "Iconos grandes / Mosaicos" estilo Windows 11 Explorer con estética de macOS.
/// Soporta selección múltiple (`Shift+Clic`, `Cmd+Clic`, casilla superior y cuadro de arrastre),
/// renombrado en línea (`F2`) y atenuación visual de elementos cortados (`Cmd+X`).
public struct FileGridView: View {
    @Bindable var viewModel: ExplorerViewModel

    @ViewState private var itemFrames: [FileItem.ID: CGRect] = [:]
    @ViewState private var dragStartPoint: CGPoint? = nil
    @ViewState private var dragCurrentPoint: CGPoint? = nil
    @ViewState private var ignoredRubberBandStart: CGPoint? = nil
    @ViewState private var initialSelectionBeforeDrag: Set<FileItem.ID> = []
    @ViewState private var isContainerDropTargeted: Bool = false

    private let coordinateSpaceName = "GridCanvasCoordinateSpace"

    private let columns = [
        GridItem(.adaptive(minimum: 114, maximum: 138), spacing: 12, alignment: .top)
    ]

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        // Superficie de fondo clicable para limpiar selección o iniciar arrastre
                        Color.clear
                            .frame(
                                minWidth: outerGeo.size.width,
                                minHeight: outerGeo.size.height
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.clearSelection()
                            }

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(viewModel.displayedItems) { item in
                                FileGridTileView(item: item, viewModel: viewModel)
                                    .id(item.id)
                                    .background(
                                        GeometryReader { tileGeo in
                                            Color.clear.preference(
                                                key: ItemFramePreferenceKey.self,
                                                value: [item.id: tileGeo.frame(in: .named(coordinateSpaceName))]
                                            )
                                        }
                                    )
                            }
                        }
                        .padding(16)

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
        .background(Color(nsColor: .controlBackgroundColor))
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

// MARK: - Tarjeta Individual de Icono Grande / Mosaico

private struct FileGridTileView: View {
    let item: FileItem
    @Bindable var viewModel: ExplorerViewModel

    @ViewState private var isHovered: Bool = false
    @ViewState private var isDropTargeted: Bool = false
    @ViewState private var loadedThumbnail: NSImage? = nil

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
        loadedThumbnail ?? ThumbnailCacheService.shared.memoryCachedThumbnail(for: item)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                // Contenedor de miniatura (64x64 para fotos/multimedia) o icono grande (56x56)
                ZStack(alignment: .bottomTrailing) {
                    if let thumb = effectiveThumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: 68, maxHeight: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6)
                            )
                            .frame(width: 68, height: 64)
                            .opacity(isCut ? 0.42 : (item.isHidden ? 0.55 : 1.0))
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
                    } else {
                        Image(nsImage: FileIconProvider.shared.icon(for: item, size: 56))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 56, height: 56)
                            .frame(width: 68, height: 64)
                            .opacity(isCut ? 0.42 : (item.isHidden ? 0.55 : 1.0))
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }

                    if isCut {
                        Image(systemName: "scissors")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3.5)
                            .background(Circle().fill(Color.orange))
                            .offset(x: 4, y: 4)
                    } else if item.isSymbolicLink {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                            .offset(x: 3, y: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                // Casilla de selección rápida en la esquina superior izquierda (Estilo Windows 11 Explorer)
                if isSelected || isHovered {
                    Button {
                        if isSelected {
                            viewModel.selectedItemIDs.remove(item.id)
                        } else {
                            viewModel.selectedItemIDs.insert(item.id)
                            viewModel.selectionAnchorID = item.id
                        }
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.65))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(isSelected
                        ? LocalizationManager.shared.text(es: "Quitar de la selección", en: "Remove from selection")
                        : LocalizationManager.shared.text(es: "Añadir a la selección", en: "Add to selection")
                    )
                }
            }

            // Nombre o campo de renombrado en línea (F2)
            if isRenaming {
                InlineRenameTextField(viewModel: viewModel, alignment: .center)
                    .frame(maxWidth: 112)
            } else {
                Text(item.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isCut || item.isHidden ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(height: 30, alignment: .top)
            }

            // Subtítulo compacto (Tamaño o Tipo)
            Text(item.isNavigableFolder
                ? LocalizationManager.shared.text(es: "Carpeta", en: "Folder")
                : item.formattedSize
            )
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(minWidth: 110, maxWidth: 136)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tileBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    tileBorderColor,
                    style: StrokeStyle(lineWidth: (isDropTargeted || isSelected || isCut) ? 1.4 : 0.6, dash: (isCut && !isDropTargeted) ? [4, 3] : [])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .task(id: item.id) {
            guard ThumbnailCacheService.shared.supportsThumbnail(for: item) else {
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

    private var tileBackgroundColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.22)
        }
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovered {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private var tileBorderColor: Color {
        if isDropTargeted {
            return Color.accentColor
        }
        if isCut {
            return Color.orange.opacity(0.6)
        }
        if isSelected {
            return Color.accentColor.opacity(0.65)
        }
        if isHovered {
            return Color.primary.opacity(0.12)
        }
        return Color.clear
    }
}
