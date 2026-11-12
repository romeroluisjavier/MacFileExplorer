import SwiftUI
import AppKit

/// Panel Lateral Izquierdo (Navigation Pane) estilo Windows 11 Explorer con estética macOS.
/// Incluye:
/// 1. Acceso rápido / Quick access
/// 2. Este equipo / This PC
/// 3. Cuentas de Google / Google Accounts (con sesiones aisladas por usuario y accesos directos a Gmail, Drive y Calendar).
public struct NavigationPaneView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Bindable var sidebarViewModel: SidebarViewModel
    @Bindable var googleManager: GoogleAccountsManager = .shared
    @Bindable var quickAccessPrefs: QuickAccessPreferences = .shared

    @ViewState private var isQuickAccessDropTargeted: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel, sidebarViewModel: SidebarViewModel) {
        self.viewModel = viewModel
        self.sidebarViewModel = sidebarViewModel
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                // 1. Sección "Acceso rápido" / "Quick access"
                VStack(alignment: .leading, spacing: 6) {
                    SidebarSectionHeader(
                        title: loc.text(es: "Acceso rápido", en: "Quick access"),
                        systemImage: "star.fill",
                        iconColor: .yellow,
                        isExpanded: $sidebarViewModel.isQuickAccessExpanded
                    )

                    if sidebarViewModel.isQuickAccessExpanded {
                        VStack(alignment: .leading, spacing: 2) {
                            if sidebarViewModel.quickAccessNodes.isEmpty {
                                Text(loc.text(
                                    es: "Ninguna carpeta visible",
                                    en: "No visible folders"
                                ))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                            } else {
                                ForEach(sidebarViewModel.quickAccessNodes) { node in
                                    SidebarTreeNodeView(
                                        node: node,
                                        depth: 0,
                                        viewModel: viewModel,
                                        sidebarViewModel: sidebarViewModel
                                    )
                                }
                            }
                        }
                        .padding(.leading, 12)
                    }

                    if isQuickAccessDropTargeted {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text(loc.text(
                                es: "Soltar aquí para fijar en Favoritos",
                                en: "Drop here to pin to Favorites"
                            ))
                            .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 18)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isQuickAccessDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isQuickAccessDropTargeted ? Color.accentColor.opacity(0.75) : Color.clear,
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                )
                .quickAccessFavoriteDropTarget(isTargeted: $isQuickAccessDropTargeted) { folderURLs in
                    let added = quickAccessPrefs.addCustomFolders(from: folderURLs)
                    if added > 0, !sidebarViewModel.isQuickAccessExpanded {
                        sidebarViewModel.isQuickAccessExpanded = true
                    }
                    sidebarViewModel.reloadQuickAccessNodes()
                }

                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)

                // 2. Sección "Este equipo" / "This PC"
                SidebarSectionHeader(
                    title: loc.text(es: "Este equipo", en: "This PC"),
                    systemImage: "desktopcomputer",
                    iconColor: .accentColor,
                    isExpanded: $sidebarViewModel.isVolumesExpanded
                )

                if sidebarViewModel.isVolumesExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(sidebarViewModel.volumeNodes) { node in
                            SidebarTreeNodeView(
                                node: node,
                                depth: 0,
                                viewModel: viewModel,
                                sidebarViewModel: sidebarViewModel
                            )
                        }
                    }
                    .padding(.leading, 12)
                }

                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)

                // 3. Sección "Google Workspace / Cuentas de Google" (Aisladas por usuario)
                HStack(spacing: 4) {
                    SidebarSectionHeader(
                        title: loc.text(es: "Cuentas de Google", en: "Google Accounts"),
                        systemImage: "globe",
                        iconColor: Color(red: 0.26, green: 0.52, blue: 0.96),
                        useGoogleLogo: true,
                        isExpanded: $googleManager.isGoogleSectionExpanded
                    )

                    Button {
                        googleManager.startAddGoogleAccount()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(
                        es: "Agregar una cuenta de Google en sesión aislada",
                        en: "Add a Google account in an isolated session"
                    ))
                }

                if googleManager.isGoogleSectionExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(googleManager.accounts) { account in
                            SidebarGoogleAccountNodeView(
                                account: account,
                                googleManager: googleManager
                            )
                        }
                    }
                    .padding(.leading, 12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        .task {
            await sidebarViewModel.loadInitialSections(includeHidden: viewModel.showHiddenFiles)
        }
        .onAppear {
            sidebarViewModel.reloadQuickAccessNodes()
        }
        .onChange(of: quickAccessPrefs.visibleFolders) { _, _ in
            sidebarViewModel.reloadQuickAccessNodes()
        }
        .onChange(of: quickAccessPrefs.customFolderPaths) { _, _ in
            sidebarViewModel.reloadQuickAccessNodes()
        }
    }
}

// MARK: - Nodo de Cuenta de Google con Accesos Directos (Gmail, Drive, Calendar)

private struct SidebarGoogleAccountNodeView: View {
    let account: GoogleAccount
    @Bindable var googleManager: GoogleAccountsManager

    @ViewState private var isRowHovered: Bool = false
    @ViewState private var isChevronHovered: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var isExpanded: Bool {
        googleManager.isAccountExpanded(account)
    }

    private var isAccountActiveInCurrentTab: Bool {
        guard let activeTab = googleManager.activeTab else { return false }
        return activeTab.accountID == account.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Fila de la cuenta de Google
            HStack(spacing: 2) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        googleManager.toggleAccountExpansion(account)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isChevronHovered ? Color.primary.opacity(0.10) : Color.clear)
                            .frame(width: 18, height: 20)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isChevronHovered = hovering
                }

                Button {
                    if account.isAuthenticated {
                        withAnimation(.snappy(duration: 0.18)) {
                            googleManager.toggleAccountExpansion(account)
                        }
                    } else if let loginTab = googleManager.openTabs.first(where: { $0.accountID == account.id }) {
                        googleManager.activeTabID = loginTab.id
                    } else {
                        let langCode = loc.isSpanish ? "es" : "en"
                        let loginURL = URL(
                            string: "https://accounts.google.com/ServiceLogin?hl=\(langCode)&continue=https%3A%2F%2Fmyaccount.google.com%2F"
                        )!
                        googleManager.openURLInAccountTab(loginURL, for: account.id)
                    }
                } label: {
                    HStack(spacing: 7) {
                        GoogleAccountAvatarView(account: account, size: 16)

                        Text(account.displayLabel)
                            .font(.system(size: 12, weight: isAccountActiveInCurrentTab ? .semibold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 5)
                    .padding(.trailing, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isAccountActiveInCurrentTab
                        ? account.badgeColor.opacity(0.13)
                        : (isRowHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .onHover { hovering in
                isRowHovered = hovering
            }
            .contextMenu {
                ForEach(GoogleServiceShortcut.allCases) { service in
                    Button {
                        googleManager.openServiceTab(service, for: account, forceNewTab: true)
                    } label: {
                        Label(
                            loc.text(es: "Abrir \(service.title) en nueva pestaña", en: "Open \(service.title) in new tab"),
                            systemImage: service.systemImage
                        )
                    }
                }

                Divider()

                Button {
                    let url = URL(string: "https://myaccount.google.com/")!
                    googleManager.openURLInAccountTab(url, for: account.id)
                } label: {
                    Label(
                        loc.text(es: "Cuenta de Google (Mi Cuenta)", en: "Google Account Settings"),
                        systemImage: "person.text.rectangle"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    googleManager.removeAccount(account)
                } label: {
                    Label(
                        loc.text(es: "Cerrar sesión y quitar cuenta", en: "Sign out and remove account"),
                        systemImage: "trash"
                    )
                }
            }

            // Sub-ítems desplegables de la cuenta: Gmail, Google Drive y Google Calendar
            if isExpanded {
                if account.isAuthenticated || !account.email.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(GoogleServiceShortcut.allCases) { service in
                            GoogleServiceShortcutRowView(
                                service: service,
                                account: account,
                                googleManager: googleManager
                            )
                        }
                    }
                } else {
                    Button {
                        if let loginTab = googleManager.openTabs.first(where: { $0.accountID == account.id }) {
                            googleManager.activeTabID = loginTab.id
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Spacer()
                                .frame(width: 22)
                            Image(systemName: "key.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(account.badgeColor)
                            Text(loc.text(
                                es: "Completa el login en la pestaña para ver Gmail, Drive y Calendar",
                                en: "Complete sign-in in tab to unlock Gmail, Drive & Calendar"
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                        .padding(.trailing, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Fila de Acceso Directo (Gmail / Drive / Calendar) Bajo una Cuenta

private struct GoogleServiceShortcutRowView: View {
    let service: GoogleServiceShortcut
    let account: GoogleAccount
    @Bindable var googleManager: GoogleAccountsManager

    @ViewState private var isHovered: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var isSelected: Bool {
        guard let activeTab = googleManager.activeTab else { return false }
        return activeTab.accountID == account.id && activeTab.service == service
    }

    var body: some View {
        Button {
            googleManager.openServiceTab(service, for: account)
        } label: {
            HStack(spacing: 7) {
                Spacer()
                    .frame(width: 22)

                GoogleServiceIconView(service: service, size: 15)
                    .frame(width: 16, height: 16)

                Text(service.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1.0 : 0.0)
            }
            .padding(.vertical, 4.5)
            .padding(.trailing, 8)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected
                            ? account.badgeColor.opacity(0.15)
                            : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                        )

                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(service.iconColor)
                            .frame(width: 3, height: 14)
                            .padding(.leading, 18)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                googleManager.openServiceTab(service, for: account, forceNewTab: false)
            } label: {
                Label(
                    loc.text(es: "Abrir \(service.title)", en: "Open \(service.title)"),
                    systemImage: service.systemImage
                )
            }

            Button {
                googleManager.openServiceTab(service, for: account, forceNewTab: true)
            } label: {
                Label(
                    loc.text(es: "Abrir en una pestaña nueva", en: "Open in new tab"),
                    systemImage: "plus.square.on.square"
                )
            }
        }
        .help("\(service.title) — \(account.displayLabel)")
    }
}

// MARK: - Encabezado de Sección del Panel Lateral

private struct SidebarSectionHeader: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    var useGoogleLogo: Bool = false
    @Binding var isExpanded: Bool

    @ViewState private var isHovered: Bool = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 14)

                if useGoogleLogo {
                    GoogleGLogoView(size: 14.5)
                        .frame(width: 15, height: 15)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 15, height: 15)
                }

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.90))

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Nodo Recursivo del Árbol Jerárquico de Carpetas Locales

private struct SidebarTreeNodeView: View {
    let node: NavigationNode
    let depth: Int
    @Bindable var viewModel: ExplorerViewModel
    @Bindable var sidebarViewModel: SidebarViewModel

    @ViewState private var isRowHovered: Bool = false
    @ViewState private var isChevronHovered: Bool = false
    @ViewState private var isDropTargeted: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var isSelected: Bool {
        viewModel.currentDirectoryURL.standardizedFileURL == node.url.standardizedFileURL
    }

    private var canExpandNode: Bool {
        sidebarViewModel.canExpand(node)
    }

    private var isExpanded: Bool {
        sidebarViewModel.isExpanded(node)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                // Sangría jerárquica según profundidad
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 14)
                }

                // Botón Chevron Independiente: Solo se muestra si la carpeta realmente tiene subcarpetas
                if canExpandNode {
                    Button {
                        toggleNodeExpansion()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isChevronHovered ? Color.primary.opacity(0.10) : Color.clear)
                                .frame(width: 18, height: 20)

                            if sidebarViewModel.isLoading(node) {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isChevronHovered = hovering
                    }
                    .help(isExpanded
                        ? loc.text(es: "Contraer subcarpetas", en: "Collapse subfolders")
                        : loc.text(es: "Expandir subcarpetas sin abrir", en: "Expand subfolders without opening")
                    )
                } else {
                    Spacer()
                        .frame(width: 18, height: 20)
                }

                // Elemento de carpeta: clic para navegar/seleccionar, doble clic para expandir/contraer igual que la flecha
                HStack(spacing: 7) {
                    Image(systemName: node.systemImage)
                        .font(.system(size: 13))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(iconColor(for: node))
                        .frame(width: 16)

                    Text(loc.sidebarNodeTitle(for: node))
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)
                }
                .padding(.vertical, 5)
                .padding(.trailing, 6)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard canExpandNode else { return }
                        toggleNodeExpansion()
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 1).onEnded {
                        viewModel.selectSidebarFolder(node)
                    }
                )
            }
            .padding(.leading, 4)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(rowBackgroundColor)

                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 15)
                            .padding(.leading, 1)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .explorerFolderDropTarget(
                enabled: true,
                destinationURL: node.url,
                viewModel: viewModel,
                isTargeted: $isDropTargeted
            )
            .onHover { hovering in
                isRowHovered = hovering
            }
            .contextMenu {
                Button {
                    viewModel.selectSidebarFolder(node)
                } label: {
                    Label(loc.text(es: "Abrir", en: "Open"), systemImage: "folder")
                }

                if canExpandNode {
                    Button {
                        toggleNodeExpansion()
                    } label: {
                        Label(
                            isExpanded
                                ? loc.text(es: "Contraer árbol", en: "Collapse tree")
                                : loc.text(es: "Expandir árbol", en: "Expand tree"),
                            systemImage: isExpanded ? "chevron.down" : "chevron.right"
                        )
                    }
                }

                Divider()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                } label: {
                    Label(loc.text(es: "Mostrar en Finder", en: "Show in Finder"), systemImage: "macwindow")
                }

                Button {
                    viewModel.openTerminal(at: node.url)
                } label: {
                    Label(loc.text(es: "Abrir Terminal aquí...", en: "Open Terminal here..."), systemImage: "terminal")
                }

                if node.isCustomQuickAccessFavorite {
                    Divider()
                    Button {
                        QuickAccessPreferences.shared.removeCustomFolder(node.url)
                        sidebarViewModel.reloadQuickAccessNodes()
                    } label: {
                        Label(
                            loc.text(es: "Sacar de Favoritos", en: "Remove from Favorites"),
                            systemImage: "star.slash"
                        )
                    }
                }

                if viewModel.isDeletableSidebarFolder(node.url) {
                    Divider()

                    Button(role: .destructive) {
                        viewModel.moveSidebarNodeToTrash(node)
                    } label: {
                        Label(
                            loc.text(es: "Mover a la Papelera", en: "Move to Trash"),
                            systemImage: "trash"
                        )
                    }

                    Button(role: .destructive) {
                        viewModel.requestPermanentDeleteSidebarNode(node)
                    } label: {
                        Label(
                            loc.text(es: "Eliminar permanentemente (⇧⌫)", en: "Delete permanently (⇧⌫)"),
                            systemImage: "trash.slash"
                        )
                    }
                }

                Divider()
                Button {
                    viewModel.showPropertiesForURL(node.url)
                } label: {
                    Label(loc.text(es: "Propiedades", en: "Properties"), systemImage: "info.circle")
                }

                AddToGeminiMenuButton(viewModel: viewModel) {
                    [node.url]
                }
            }

            // Subcarpetas desplegadas recursivamente
            if isExpanded {
                let children = sidebarViewModel.children(for: node)
                ForEach(children) { child in
                    SidebarTreeNodeView(
                        node: child,
                        depth: depth + 1,
                        viewModel: viewModel,
                        sidebarViewModel: sidebarViewModel
                    )
                }
            }
        }
    }

    private func toggleNodeExpansion() {
        withAnimation(.snappy(duration: 0.18)) {
            sidebarViewModel.toggleExpansion(
                for: node,
                includeHidden: viewModel.showHiddenFiles
            )
        }
    }

    private var rowBackgroundColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.20)
        }
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }
        if isRowHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }

    private func iconColor(for node: NavigationNode) -> Color {
        switch node.systemImage {
        case "house.fill":
            return .teal
        case "menubar.dock.rectangle":
            return .blue
        case "arrow.down.circle.fill":
            return .green
        case "doc.text.fill":
            return .indigo
        case "app.badge.fill":
            return .purple
        case "photo.fill":
            return .pink
        case "music.note":
            return .red
        case "film":
            return .mint
        case "externaldrive.fill":
            return .orange
        case "internaldrive.fill":
            return .secondary
        default:
            return Color(red: 0.20, green: 0.62, blue: 0.96)
        }
    }
}
