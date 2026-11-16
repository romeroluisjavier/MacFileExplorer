import SwiftUI

/// Vista raíz del Explorador de Archivos (layout Windows 11 Explorer + estética nativa macOS).
public struct MainExplorerView: View {
    @ViewState private var viewModel: ExplorerViewModel
    @Bindable private var slackPrefs: SlackPreferences = .shared
    @Environment(\.colorScheme) private var colorScheme

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel = ExplorerViewModel()) {
        _viewModel = ViewState(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 1. Barra Superior Nivel 1: Command Bar (Nuevo, Cortar, Copiar, Pegar, Renombrar, Eliminar, Ordenar, Vista)
                CommandBarView(viewModel: viewModel)

                Divider()

                // 2. Barra Superior Nivel 2: Navegación + Breadcrumb (Cmd+L) + Búsqueda Rápida
                NavigationBarView(viewModel: viewModel)

                Divider()

                // Banner de error no intrusivo si ocurre algún fallo de permisos/I/O
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(message: errorMessage)
                    Divider()
                }

                if let archiveMsg = viewModel.archiveProgressMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(archiveMsg)
                            .font(.system(size: 12, weight: .medium))
                        ProgressView(value: viewModel.archiveProgressValue ?? 0.35, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 240)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.08))
                    Divider()
                }

                // 3. Cuerpo Central Dividido: Panel Lateral Izquierdo + Área Principal
                HSplitView {
                    NavigationPaneView(
                        viewModel: viewModel,
                        sidebarViewModel: viewModel.sidebarViewModel
                    )
                    .frame(minWidth: 215, idealWidth: 245, maxWidth: 360)

                    mainContentArea
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // 4. Barra de Estado Inferior (Conteo total, seleccionados, suma de tamaños y conmutador de vista)
                StatusBarView(viewModel: viewModel)
            }
        }
        .navigationTitle(viewModel.currentFolderTitle)
        .explorerKeyboardShortcuts(viewModel: viewModel)
        .background {
            WindowFrameAutosaveView(folderTitle: viewModel.currentFolderTitle, viewModel: viewModel)
            QuickLookPanelHostBridge(viewModel: viewModel)
            hiddenShortcutButtons
        }
        .task {
            FileIconProvider.shared.syncApplicationDockIcon(for: colorScheme)
            viewModel.refresh(preservingSelection: false)
        }
        .onChange(of: colorScheme) { _, newScheme in
            FileIconProvider.shared.syncApplicationDockIcon(for: newScheme)
        }
        .onAppear {
            MouseNavigationManager.shared.installIfNeeded()
            ClipboardHistoryManager.shared.installIfNeeded()
            ExplorerWindowRegistry.shared.lastActiveViewModel = viewModel
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkCurrentDirectoryForExternalChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            if let win = notif.object as? NSWindow,
               let registered = ExplorerWindowRegistry.shared.viewModel(for: win) {
                if registered === viewModel {
                    viewModel.checkCurrentDirectoryForExternalChanges()
                }
            } else {
                viewModel.checkCurrentDirectoryForExternalChanges()
            }
        }
        .sheet(item: $viewModel.propertiesTargetItem) { targetItem in
            ItemPropertiesModalView(item: targetItem)
        }
        .sheet(isPresented: $viewModel.isShareToSlackPresented) {
            ShareToSlackModalView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isBulkRenamePresented) {
            BulkRenameModalView(viewModel: viewModel)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.quickActionImageConvertURLs != nil },
                set: { if !$0 { viewModel.quickActionImageConvertURLs = nil } }
            )
        ) {
            if let urls = viewModel.quickActionImageConvertURLs {
                QuickActionImageConvertModalView(viewModel: viewModel, targetURLs: urls)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.quickActionVideoConvertURLs != nil },
                set: { if !$0 { viewModel.quickActionVideoConvertURLs = nil } }
            )
        ) {
            if let urls = viewModel.quickActionVideoConvertURLs {
                QuickActionVideoConvertModalView(viewModel: viewModel, targetURLs: urls)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.quickActionVideoTrimURL != nil },
                set: { if !$0 { viewModel.quickActionVideoTrimURL = nil } }
            )
        ) {
            if let url = viewModel.quickActionVideoTrimURL {
                QuickActionVideoTrimModalView(viewModel: viewModel, targetURL: url)
            }
        }
        .focusedSceneValue(\.explorerViewModel, viewModel)
    }

    // MARK: - Área Principal de Contenidos

    @ViewBuilder
    private var mainContentArea: some View {
        if viewModel.isShowingClipboardHistory {
            ClipboardHistoryMainView(viewModel: viewModel)
        } else {
            folderExplorerContentArea
        }
    }

    @ViewBuilder
    private var folderExplorerContentArea: some View {
        ZStack {
            switch viewModel.viewMode {
            case .details:
                FileDetailsTableView(viewModel: viewModel)
            case .largeIcons:
                FileGridView(viewModel: viewModel)
            }

            if viewModel.isSlowLoadingOverlayVisible {
                slowLoadingOverlay
            } else if viewModel.displayedItems.isEmpty && !viewModel.isLoading {
                emptyFolderOverlay
            }
        }
        .contextMenu {
            Button {
                viewModel.createNewFolder()
            } label: {
                Label(loc.text(es: "Nueva carpeta", en: "New folder"), systemImage: "folder.badge.plus")
            }

            Button {
                viewModel.createNewTextFile()
            } label: {
                Label(loc.text(es: "Nuevo documento de texto", en: "New Text Document"), systemImage: "doc.badge.plus")
            }

            Divider()

            Button {
                viewModel.pasteItems()
            } label: {
                Label(loc.text(es: "Pegar", en: "Paste"), systemImage: "doc.on.clipboard")
            }
            .disabled(!viewModel.canPaste)

            Button {
                viewModel.selectAll()
            } label: {
                Label(loc.text(es: "Seleccionar todo", en: "Select all"), systemImage: "checkmark.rectangle.stack")
            }

            Button {
                viewModel.refresh(preservingSelection: true)
            } label: {
                Label(loc.text(es: "Actualizar", en: "Refresh"), systemImage: "arrow.clockwise")
            }

            Divider()

            Toggle(isOn: $viewModel.showHiddenFiles) {
                Label(loc.text(es: "Mostrar archivos ocultos", en: "Show hidden files"), systemImage: "eye")
            }

            Divider()

            Button {
                viewModel.openTerminal(at: viewModel.currentDirectoryURL)
            } label: {
                Label(loc.text(es: "Abrir Terminal aquí...", en: "Open Terminal here..."), systemImage: "terminal")
            }

            Button {
                viewModel.showPropertiesForURL(viewModel.currentDirectoryURL)
            } label: {
                Label(loc.text(es: "Propiedades", en: "Properties"), systemImage: "info.circle")
            }

            AddToGeminiMenuButton(viewModel: viewModel) {
                [viewModel.currentDirectoryURL]
            }

            if slackPrefs.isShareToSlackEnabled {
                AddToSlackMenuButton(viewModel: viewModel) {
                    [viewModel.currentDirectoryURL]
                }
            }
        }
    }

    private var slowLoadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            VStack(spacing: 3) {
                Text(loc.text(es: "Cargando carpeta...", en: "Loading folder..."))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(viewModel.currentFolderTitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .allowsHitTesting(false)
    }

    private var emptyFolderOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.searchQuery.isEmpty ? "folder" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)

            Text(
                viewModel.searchQuery.isEmpty
                    ? loc.text(es: "Esta carpeta está vacía", en: "This folder is empty")
                    : loc.text(
                        es: "Ningún elemento coincide con \"\(viewModel.searchQuery)\"",
                        en: "No items match \"\(viewModel.searchQuery)\""
                    )
            )
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.secondary)

            if !viewModel.searchQuery.isEmpty {
                Button(loc.text(es: "Limpiar filtro de búsqueda", en: "Clear search filter")) {
                    viewModel.searchQuery = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .allowsHitTesting(!viewModel.searchQuery.isEmpty)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    /// Botones invisibles para enlazar atajos estándar con modificadores `Cmd` (`Cmd+L`, `Cmd+X`, `Cmd+C`, `Cmd+V`, `Cmd+A`, `Cmd+R`, `Cmd+Shift+.`).
    private var hiddenShortcutButtons: some View {
        Group {
            Button("") { viewModel.beginAddressBarEditing() }
                .keyboardShortcut("l", modifiers: [.command])

            Button("") { viewModel.cutSelectedItems() }
                .keyboardShortcut("x", modifiers: [.command])

            Button("") { viewModel.copySelectedItems() }
                .keyboardShortcut("c", modifiers: [.command])

            Button("") { viewModel.pasteItems() }
                .keyboardShortcut("v", modifiers: [.command])

            Button("") { viewModel.selectAll() }
                .keyboardShortcut("a", modifiers: [.command])

            Button("") { viewModel.refresh(preservingSelection: true) }
                .keyboardShortcut("r", modifiers: [.command])

            Button("") { viewModel.showHiddenFiles.toggle() }
                .keyboardShortcut(".", modifiers: [.command, .shift])

            Button("") { viewModel.viewMode = .details }
                .keyboardShortcut("1", modifiers: [.command])

            Button("") { viewModel.viewMode = .largeIcons }
                .keyboardShortcut("2", modifiers: [.command])

            Button("") { viewModel.showProperties() }
                .keyboardShortcut("i", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}

private struct ExplorerViewModelFocusedValueKey: FocusedValueKey {
    typealias Value = ExplorerViewModel
}

public extension FocusedValues {
    var explorerViewModel: ExplorerViewModel? {
        get { self[ExplorerViewModelFocusedValueKey.self] }
        set { self[ExplorerViewModelFocusedValueKey.self] = newValue }
    }
}
