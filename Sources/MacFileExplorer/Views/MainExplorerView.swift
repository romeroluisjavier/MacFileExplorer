import SwiftUI

/// Vista raíz del Explorador de Archivos (layout Windows 11 Explorer + estética nativa macOS).
public struct MainExplorerView: View {
    @ViewState private var viewModel: ExplorerViewModel
    @Bindable private var slackPrefs: SlackPreferences = .shared
    @Bindable private var monthlySupportManager: MonthlySupportCheckManager = .shared
    @Bindable private var appShortcutPrefs: AppShortcutPreferences = .shared
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

            // 5. Aviso mensual flotante no invasivo (Comprobación automática de actualizaciones + propina opcional Ko-fi)
            if monthlySupportManager.isPopupVisible {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        MonthlySupportFloatingToastView()
                            .padding(.trailing, 16)
                            .padding(.bottom, 38)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: monthlySupportManager.isPopupVisible)
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
            monthlySupportManager.scheduleStartupEvaluationIfNeeded()
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
        .sheet(item: activeSheetBinding) { sheet in
            switch sheet {
            case .properties(let targetItem):
                ItemPropertiesModalView(item: targetItem)
            case .shareToSlack:
                ShareToSlackModalView(viewModel: viewModel)
            case .bulkRename:
                BulkRenameModalView(viewModel: viewModel)
            case .imageConvert(let urls):
                QuickActionImageConvertModalView(viewModel: viewModel, targetURLs: urls)
            case .videoConvert(let urls):
                QuickActionVideoConvertModalView(viewModel: viewModel, targetURLs: urls)
            case .videoTrim(let url):
                QuickActionVideoTrimModalView(viewModel: viewModel, targetURL: url)
            case .duplicateFinder:
                DuplicateFinderModalView(viewModel: viewModel)
            case .hiddenCacheManager:
                HiddenCacheManagerModalView(viewModel: viewModel)
            case .permanentDelete(let req):
                PermanentDeleteConfirmModalView(viewModel: viewModel, request: req)
            }
        }
        .focusedSceneValue(\.explorerViewModel, viewModel)
    }

    private enum ActiveExplorerSheet: Identifiable {
        case properties(FileItem)
        case shareToSlack
        case bulkRename
        case imageConvert([URL])
        case videoConvert([URL])
        case videoTrim(URL)
        case duplicateFinder
        case hiddenCacheManager
        case permanentDelete(ExplorerViewModel.PendingPermanentDeleteRequest)

        var id: String {
            switch self {
            case .properties(let item): return "properties-\(item.id.absoluteString)"
            case .shareToSlack: return "shareToSlack"
            case .bulkRename: return "bulkRename"
            case .imageConvert(let urls): return "imageConvert-\(urls.count)"
            case .videoConvert(let urls): return "videoConvert-\(urls.count)"
            case .videoTrim(let url): return "videoTrim-\(url.absoluteString)"
            case .duplicateFinder: return "duplicateFinder"
            case .hiddenCacheManager: return "hiddenCacheManager"
            case .permanentDelete(let req): return "permanentDelete-\(req.urls.count)"
            }
        }
    }

    private var activeSheetBinding: Binding<ActiveExplorerSheet?> {
        Binding(
            get: {
                if let item = viewModel.propertiesTargetItem { return .properties(item) }
                if viewModel.isShareToSlackPresented { return .shareToSlack }
                if viewModel.isBulkRenamePresented { return .bulkRename }
                if let urls = viewModel.quickActionImageConvertURLs { return .imageConvert(urls) }
                if let urls = viewModel.quickActionVideoConvertURLs { return .videoConvert(urls) }
                if let url = viewModel.quickActionVideoTrimURL { return .videoTrim(url) }
                if viewModel.isDuplicateFinderPresented { return .duplicateFinder }
                if viewModel.isHiddenCacheManagerPresented { return .hiddenCacheManager }
                if let req = viewModel.pendingPermanentDelete { return .permanentDelete(req) }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    viewModel.propertiesTargetItem = nil
                    viewModel.isShareToSlackPresented = false
                    viewModel.isBulkRenamePresented = false
                    viewModel.quickActionImageConvertURLs = nil
                    viewModel.quickActionVideoConvertURLs = nil
                    viewModel.quickActionVideoTrimURL = nil
                    viewModel.isDuplicateFinderPresented = false
                    viewModel.isHiddenCacheManagerPresented = false
                    viewModel.pendingPermanentDelete = nil
                }
            }
        )
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

    /// Botones invisibles para enlazar atajos estándar y personalizables (`Cmd+L`, `Cmd+X/C/V/A`, `Cmd+R`, `Cmd+Shift+.`, `Cmd+1/2`, `Cmd+I`).
    private var hiddenShortcutButtons: some View {
        Group {
            Button("") { viewModel.beginAddressBarEditing() }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .focusAddressBar))

            Button("") { viewModel.cutSelectedItems() }
                .keyboardShortcut("x", modifiers: [.command])

            Button("") { viewModel.copySelectedItems() }
                .keyboardShortcut("c", modifiers: [.command])

            Button("") { viewModel.pasteItems() }
                .keyboardShortcut("v", modifiers: [.command])

            Button("") { viewModel.selectAll() }
                .keyboardShortcut("a", modifiers: [.command])

            Button("") { viewModel.refresh(preservingSelection: true) }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .refreshFolder))

            Button("") { viewModel.showHiddenFiles.toggle() }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .toggleHiddenFiles))

            Button("") { viewModel.viewMode = .details }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .viewDetails))

            Button("") { viewModel.viewMode = .largeIcons }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .viewLargeIcons))

            Button("") { viewModel.showProperties() }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .showProperties))
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

private struct PermanentDeleteConfirmModalView: View {
    let viewModel: ExplorerViewModel
    let request: ExplorerViewModel.PendingPermanentDeleteRequest
    @Environment(\.dismiss) private var dismiss

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var titleText: String {
        if request.urls.count == 1, let singleName = request.displayNames.first ?? request.urls.first?.lastPathComponent {
            return loc.text(
                es: "¿Eliminar \"\(singleName)\" de forma permanente?",
                en: "Permanently delete \"\(singleName)\"?"
            )
        }
        return loc.text(
            es: "¿Eliminar \(request.urls.count) elementos de forma permanente?",
            en: "Permanently delete \(request.urls.count) items?"
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.slash.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

            VStack(spacing: 6) {
                Text(titleText)
                    .font(.system(size: 13.5, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(loc.text(
                    es: "Se borrará directamente del disco sin pasar por la Papelera. Esta acción no se puede deshacer.",
                    en: "Items will be deleted directly from disk without moving to the Trash. This action cannot be undone."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                Button {
                    let targets = request.urls
                    dismiss()
                    viewModel.executePermanentDelete(urls: targets)
                } label: {
                    Text(loc.text(es: "Eliminar permanentemente", en: "Delete Permanently"))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    dismiss()
                } label: {
                    Text(loc.text(es: "Cancelar", en: "Cancel"))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 280)
    }
}
