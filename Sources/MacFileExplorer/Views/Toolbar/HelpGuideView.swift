import AppKit
import SwiftUI

/// Secciones navegables de la Guía / Ayuda de MacFileExplorer.
public enum HelpGuideSection: String, CaseIterable, Identifiable, Sendable {
    case highlights
    case sidebar
    case search
    case features
    case shortcuts
    case settings
    case permissions
    case releases

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .highlights: return "star.leadinghalf.filled"
        case .sidebar: return "sidebar.left"
        case .search: return "magnifyingglass.circle.fill"
        case .features: return "square.grid.2x2.fill"
        case .shortcuts: return "keyboard"
        case .settings: return "slider.horizontal.3"
        case .permissions: return "lock.shield.fill"
        case .releases: return "sparkles"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .highlights: return loc.text(es: "Destacadas", en: "Highlights")
        case .sidebar: return loc.text(es: "Menú lateral", en: "Sidebar Menu")
        case .search: return loc.text(es: "Menú de búsqueda", en: "Search & OCR")
        case .features: return loc.text(es: "Todas las funciones", en: "All Features")
        case .shortcuts: return loc.text(es: "Atajos de teclado", en: "Keyboard Shortcuts")
        case .settings: return loc.text(es: "Configuraciones", en: "Settings")
        case .permissions: return loc.text(es: "Permisos de macOS", en: "macOS Permissions")
        case .releases: return loc.text(es: "Historial de releases", en: "Release History")
        }
    }
}

/// Controlador singleton para presentar la ventana nativa de Ayuda completa desde el menú Help.
@MainActor
public final class HelpWindowController {
    public static let shared = HelpWindowController()

    private var window: NSWindow?
    private var selectedSectionStorage: HelpGuideSection = .highlights

    private init() {}

    public func show(section: HelpGuideSection = .highlights) {
        selectedSectionStorage = section
        let loc = LocalizationManager.shared
        let title = loc.text(es: "Ayuda de MacFileExplorer", en: "MacFileExplorer Help")

        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = window {
            existingWindow.title = title
            existingWindow.contentView = NSHostingView(
                rootView: HelpGuideView(initialSection: section, onClose: { [weak self] in
                    self?.close()
                })
            )
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let createdWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        createdWindow.title = title
        createdWindow.minSize = NSSize(width: 720, height: 500)
        createdWindow.titlebarAppearsTransparent = true
        createdWindow.isMovableByWindowBackground = true
        createdWindow.isReleasedWhenClosed = false
        createdWindow.contentView = NSHostingView(
            rootView: HelpGuideView(initialSection: section, onClose: { [weak self] in
                self?.close()
            })
        )
        createdWindow.center()
        createdWindow.makeKeyAndOrderFront(nil)
        self.window = createdWindow
    }

    public func refreshLocalizedTitle() {
        window?.title = LocalizationManager.shared.text(es: "Ayuda de MacFileExplorer", en: "MacFileExplorer Help")
    }

    public func close() {
        window?.close()
    }
}

// MARK: - Modelo de Tarjeta / Atajo para Búsqueda Interna de Ayuda

private struct HelpTopicCard: Identifiable {
    let id: String
    let icon: String
    let badgeES: String?
    let badgeEN: String?
    let titleES: String
    let titleEN: String
    let bodyES: String
    let bodyEN: String

    init(
        id: String,
        icon: String,
        badgeES: String? = nil,
        badgeEN: String? = nil,
        titleES: String,
        titleEN: String,
        bodyES: String,
        bodyEN: String
    ) {
        self.id = id
        self.icon = icon
        self.badgeES = badgeES
        self.badgeEN = badgeEN
        self.titleES = titleES
        self.titleEN = titleEN
        self.bodyES = bodyES
        self.bodyEN = bodyEN
    }
}

private struct HelpShortcutRow: Identifiable {
    let id: String
    let categoryES: String
    let categoryEN: String
    let keys: String
    let actionES: String
    let actionEN: String
}

/// Ventana interactiva de Ayuda con navegación por secciones, buscador en vivo y catálogo basado en los releases.
public struct HelpGuideView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var windowTracker = TaskbarWindowTracker.shared
    @Bindable private var thumbnailService = TaskbarThumbnailService.shared

    @ViewState private var selectedSection: HelpGuideSection
    @ViewState private var searchText: String = ""

    private let onClose: (() -> Void)?

    public init(initialSection: HelpGuideSection = .highlights, onClose: (() -> Void)? = nil) {
        _selectedSection = ViewState(initialValue: initialSection)
        self.onClose = onClose
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
                .frame(width: 225)
                .background(.bar)

            Divider()

            VStack(spacing: 0) {
                topSearchHeader
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !trimmedSearch.isEmpty {
                            searchResultsContent
                        } else {
                            sectionContent(for: selectedSection)
                        }
                    }
                    .padding(20)
                }

                Divider()

                footerBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            if !searchText.isEmpty {
                searchText = ""
            } else {
                onClose?()
            }
        }
    }

    // MARK: - Columna Lateral de la Ayuda

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let appIcon = FileIconProvider.shared.appIcon(for: colorScheme) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("MacFileExplorer")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("v\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 32)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(HelpGuideSection.allCases) { section in
                        let isSelected = trimmedSearch.isEmpty && selectedSection == section
                        Button {
                            searchText = ""
                            selectedSection = section
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)

                                Text(section.localizedTitle(using: loc))
                                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    AboutWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Acerca de / Release Notes", en: "About / Release Notes"),
                        systemImage: "info.circle"
                    )
                    .font(.system(size: 11.5))
                }
                .buttonStyle(.link)

                Button {
                    UpdateWindowController.shared.showAndCheck()
                } label: {
                    Label(
                        loc.text(es: "Buscar actualizaciones…", en: "Check for Updates…"),
                        systemImage: "arrow.down.circle"
                    )
                    .font(.system(size: 11.5))
                }
                .buttonStyle(.link)
            }
            .padding(14)
        }
    }

    // MARK: - Encabezado con Buscador Interno

    private var topSearchHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    trimmedSearch.isEmpty
                        ? selectedSection.localizedTitle(using: loc)
                        : loc.text(es: "Resultados en la Ayuda", en: "Help Search Results")
                )
                .font(.system(size: 16, weight: .bold))

                Text(loc.text(
                    es: "Guía completa basada en las funcionalidades y releases de MacFileExplorer",
                    en: "Complete guide built from MacFileExplorer features & releases"
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField(
                    loc.text(es: "Buscar en la ayuda…", en: "Search help…"),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .frame(width: 190)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
            )
        }
    }

    private var footerBar: some View {
        HStack {
            Text(loc.text(
                es: "Consejo: usá el buscador de arriba para encontrar cualquier atajo, opción o función.",
                en: "Tip: use the search box above to find any shortcut, setting, or feature."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button(loc.text(es: "Cerrar", en: "Close")) {
                onClose?()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Contenido por Sección

    @ViewBuilder
    private func sectionContent(for section: HelpGuideSection) -> some View {
        switch section {
        case .highlights:
            introBanner(
                icon: "star.leadinghalf.filled",
                titleES: "Funciones destacadas de MacFileExplorer",
                titleEN: "Highlighted MacFileExplorer Features",
                subtitleES: "Lo más potente de la aplicación para navegar, editar archivos multimedia, buscar con OCR y trabajar con múltiples cuentas sin perder fluidez.",
                subtitleEN: "The most powerful tools in the app for navigating, editing media, OCR searching, and multi-account workflows."
            )
            ForEach(Self.highlightedTopics) { card in
                topicCardView(card)
            }

        case .sidebar:
            introBanner(
                icon: "sidebar.left",
                titleES: "Cómo usar el Menú Lateral Izquierdo",
                titleEN: "How the Left Sidebar Menu Works",
                subtitleES: "El panel lateral organiza tus ubicaciones en cuatro bloques colapsables: Acceso rápido, Este equipo, Cuentas de Google e Historial del Portapapeles.",
                subtitleEN: "The left sidebar organizes your workspace into four collapsible sections: Quick Access, This PC, Google Accounts, and Clipboard History."
            )
            ForEach(Self.sidebarTopics) { card in
                topicCardView(card)
            }

        case .search:
            introBanner(
                icon: "magnifyingglass.circle.fill",
                titleES: "Menú de Búsqueda Rápida y Buscador Avanzado (OCR)",
                titleEN: "Quick Search Box & Advanced Search (OCR)",
                subtitleES: "Ubicado arriba a la derecha. Filtrá instantáneamente por nombre o abrí el botón de filtros avanzado para buscar por tipo, tamaño, subcarpetas y contenido interno.",
                subtitleEN: "Located at the top-right. Filter instantly by name or click the filter icon to search by file type, size, subfolders, and inside file contents."
            )
            ForEach(Self.searchTopics) { card in
                topicCardView(card)
            }

        case .features:
            introBanner(
                icon: "square.grid.2x2.fill",
                titleES: "Catálogo completo de funcionalidades",
                titleEN: "Complete Feature Catalog",
                subtitleES: "Todas las herramientas integradas en menús contextuales, barra superior, barra de comandos y barra de estado.",
                subtitleEN: "Every built-in tool across context menus, top menu bar, command bar, and bottom status bar."
            )
            ForEach(Self.allFeatureTopics) { card in
                topicCardView(card)
            }

        case .shortcuts:
            introBanner(
                icon: "keyboard",
                titleES: "Todos los atajos de teclado y ratón",
                titleEN: "All Keyboard & Mouse Shortcuts",
                subtitleES: "Compatibles con teclados en Español / Latinoamericano y US ANSI, además de botones laterales Logitech MX Master 3 y gestos del trackpad.",
                subtitleEN: "Supports Spanish/Latin American & US ANSI layouts, plus Logitech MX Master 3 side buttons and trackpad horizontal swipes."
            )
            shortcutsTable(Self.allShortcuts)

        case .settings:
            introBanner(
                icon: "slider.horizontal.3",
                titleES: "Todas las configuraciones posibles",
                titleEN: "All Available Settings & Preferences",
                subtitleES: "Podés personalizar vistas, idioma, carpetas visibles en Acceso rápido, portapapeles Maccy, ratón, marcadores, Slack, atajos y herramientas.",
                subtitleEN: "Customize view modes, language, visible Quick Access folders, Maccy clipboard, mouse buttons, bookmarks, Slack, shortcuts, and tools."
            )
            ForEach(Self.settingsTopics) { card in
                topicCardView(card)
            }

        case .permissions:
            introBanner(
                icon: "lock.shield.fill",
                titleES: "Permisos de macOS: pedimos solo lo mínimo y necesario",
                titleEN: "macOS Permissions: Strictly Minimum & Necessary",
                subtitleES: "MacFileExplorer respeta tu privacidad. Solo solicita permisos del sistema cuando activás o usás una función específica que los requiere. Ningún permiso es obligatorio para usar el Explorador básico, y todo se procesa 100% localmente en tu Mac sin telemetría ni envío de capturas o archivos a servidores externos.",
                subtitleEN: "MacFileExplorer respects your privacy. It requests system permissions only when you enable or use a specific feature that needs them. No special permission is required for basic file browsing, and everything runs 100% locally on your Mac with zero telemetry or external data sharing."
            )
            permissionsLiveStatusCard
            ForEach(Self.permissionTopics) { card in
                topicCardView(card)
            }
            permissionsSystemShortcutsCard

        case .releases:
            introBanner(
                icon: "sparkles",
                titleES: "Novedades por versión (Release Notes)",
                titleEN: "Release Notes by Version",
                subtitleES: "Historial completo generado directamente desde el catálogo oficial de versiones de MacFileExplorer.",
                subtitleEN: "Full chronological changelog synced directly from MacFileExplorer's official release catalog."
            )
            KoFiSupportCardView(compact: false)
            ForEach(ReleaseNotesCatalog.sections) { section in
                releaseSectionCard(section)
            }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        let q = trimmedSearch
        let matchingCards = (Self.highlightedTopics + Self.sidebarTopics + Self.searchTopics + Self.allFeatureTopics + Self.settingsTopics + Self.permissionTopics)
            .filter { card in
                matches(card.titleES, query: q) || matches(card.titleEN, query: q)
                    || matches(card.bodyES, query: q) || matches(card.bodyEN, query: q)
                    || (card.badgeES.map { matches($0, query: q) } ?? false)
                    || (card.badgeEN.map { matches($0, query: q) } ?? false)
            }
        let matchingShortcuts = Self.allShortcuts.filter { row in
            matches(row.keys, query: q)
                || matches(row.actionES, query: q) || matches(row.actionEN, query: q)
                || matches(row.categoryES, query: q) || matches(row.categoryEN, query: q)
        }
        let matchingReleaseItems = ReleaseNotesCatalog.sections.flatMap { sec in
            sec.items.compactMap { item -> (ReleaseNoteSection, ReleaseNoteItem)? in
                if matches(item.titleES, query: q) || matches(item.titleEN, query: q)
                    || matches(item.summaryES, query: q) || matches(item.summaryEN, query: q) {
                    return (sec, item)
                }
                return nil
            }
        }

        if matchingCards.isEmpty && matchingShortcuts.isEmpty && matchingReleaseItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(loc.text(
                    es: "No se encontraron resultados en la ayuda para «\(q)».",
                    en: "No help results found for «\(q)»."
                ))
                .font(.system(size: 13.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            if !matchingShortcuts.isEmpty {
                Text(loc.text(es: "Atajos de teclado", en: "Keyboard Shortcuts"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                shortcutsTable(matchingShortcuts)
            }

            if !matchingCards.isEmpty {
                Text(loc.text(es: "Guía, funciones y configuraciones", en: "Guide, Features & Settings"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(matchingCards) { card in
                    topicCardView(card)
                }
            }

            if !matchingReleaseItems.isEmpty {
                Text(loc.text(es: "En notas de versiones", en: "In Release Notes"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(matchingReleaseItems, id: \.1.id) { sec, item in
                    topicCardView(HelpTopicCard(
                        id: "rel-\(item.id)",
                        icon: item.icon,
                        badgeES: sec.versionLabelES,
                        badgeEN: sec.versionLabelEN,
                        titleES: item.titleES,
                        titleEN: item.titleEN,
                        bodyES: item.summaryES,
                        bodyEN: item.summaryEN
                    ))
                }
            }
        }
    }

    // MARK: - Subcomponentes Visuales

    private func introBanner(
        icon: String,
        titleES: String,
        titleEN: String,
        subtitleES: String,
        subtitleEN: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(loc.text(es: titleES, en: titleEN))
                    .font(.system(size: 14, weight: .bold))
                Text(loc.text(es: subtitleES, en: subtitleEN))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.8)
        )
    }

    private func topicCardView(_ card: HelpTopicCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(loc.text(es: card.titleES, en: card.titleEN))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let badgeES = card.badgeES, let badgeEN = card.badgeEN {
                        Text(loc.text(es: badgeES, en: badgeEN))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }

                Text(loc.text(es: card.bodyES, en: card.bodyEN))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
    }

    private func shortcutsTable(_ rows: [HelpShortcutRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Text(row.keys)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .frame(minWidth: 138, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.11))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(loc.text(es: row.actionES, en: row.actionEN))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(loc.text(es: row.categoryES, en: row.categoryEN))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func releaseSectionCard(_ section: ReleaseNoteSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.localizedVersionLabel(using: loc))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(section.localizedDateLabel(using: loc))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(section.items) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18, height: 18)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.localizedTitle(using: loc))
                                .font(.system(size: 12, weight: .semibold))
                            Text(item.localizedSummary(using: loc))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            )
        }
    }

    private func matches(_ text: String, query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Panel en Vivo y Accesos Rápidos de Permisos de macOS

    private var permissionsLiveStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(loc.text(
                    es: "Estado actual de permisos opcionales en esta Mac",
                    en: "Live Status of Optional Permissions on This Mac"
                ))
                .font(.system(size: 12.5, weight: .bold))

                Spacer()

                Button {
                    refreshPermissionStatuses()
                } label: {
                    Label(
                        loc.text(es: "Actualizar estado", en: "Refresh Status"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                livePermissionPill(
                    title: loc.text(es: "Accesibilidad", en: "Accessibility"),
                    subtitle: loc.text(es: "Barra de tareas, AltTab, auto-pegado", en: "Taskbar, AltTab, Auto-paste"),
                    isGranted: windowTracker.isAccessibilityGranted,
                    openAction: {
                        windowTracker.openAccessibilitySettings()
                    }
                )

                livePermissionPill(
                    title: loc.text(es: "Grabación de pantalla", en: "Screen Recording"),
                    subtitle: loc.text(es: "Solo miniaturas de ventanas", en: "Window thumbnails only"),
                    isGranted: thumbnailService.hasScreenRecordingPermission,
                    openAction: {
                        thumbnailService.openScreenRecordingSettings()
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .onAppear {
            refreshPermissionStatuses()
        }
    }

    private func livePermissionPill(
        title: String,
        subtitle: String,
        isGranted: Bool,
        openAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isGranted ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(isGranted
                        ? loc.text(es: "Activo", en: "Enabled")
                        : loc.text(es: "No habilitado", en: "Not enabled"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(isGranted ? Color.green : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(isGranted ? Color.green.opacity(0.14) : Color.primary.opacity(0.08))
                        )
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(loc.text(es: "Abrir", en: "Open")) {
                openAction()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isGranted ? Color.green.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    private var permissionsSystemShortcutsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.text(
                es: "Accesos directos a Ajustes del Sistema (Privacidad y Seguridad)",
                en: "Quick Links to macOS System Settings (Privacy & Security)"
            ))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    openPrivacyPane("Privacy_FilesAndFolders")
                } label: {
                    Label(loc.text(es: "Archivos y carpetas", en: "Files & Folders"), systemImage: "folder")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    windowTracker.openAccessibilitySettings()
                } label: {
                    Label(loc.text(es: "Accesibilidad", en: "Accessibility"), systemImage: "figure.walk.circle")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    thumbnailService.openScreenRecordingSettings()
                } label: {
                    Label(loc.text(es: "Grabación de pantalla", en: "Screen Recording"), systemImage: "rectangle.dashed.badge.record")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openPrivacyPane("Privacy_Automation")
                } label: {
                    Label(loc.text(es: "Automatización", en: "Automation"), systemImage: "gearshape.2")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
    }

    private func refreshPermissionStatuses() {
        _ = windowTracker.checkAccessibilityPermission(prompt: false)
        _ = thumbnailService.refreshPermissionStatus()
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Catálogo Estructurado de Contenidos de la Ayuda

extension HelpGuideView {

    private static let highlightedTopics: [HelpTopicCard] = [
        HelpTopicCard(
            id: "hl-notch-music-player",
            icon: "waveform",
            badgeES: "Nuevo · v2.5.1",
            badgeEN: "New · v2.5.1",
            titleES: "Reproductor de música Notch (Menú superior «Notch»)",
            titleEN: "Notch Music Player («Notch» Top Menu)",
            bodyES: "Integrado directamente alrededor del Notch de tu MacBook (o en el borde superior de cualquier pantalla), muestra lo que estás escuchando en YouTube Music, Spotify, Apple Music o el navegador sin tapar tu trabajo ni robar foco. En modo compacto muestra la carátula con anillo de progreso y un ecualizador animado a los lados del Notch; al pasar el puntero o hacer clic se despliega con animaciones fluidas, brillo ambiental del color del álbum, barra de progreso interactiva, controles de reproducción, selector rápido de salida de audio y letras sincronizadas estilo karaoke. Activá, probá con una canción demo o personalizá cada detalle desde el menú superior «Notch».",
            bodyEN: "Seamlessly integrated around your MacBook's notch (or the top center of any display), showing what's playing in YouTube Music, Spotify, Apple Music, or your browser without interrupting your work or stealing focus. While collapsed, it displays album artwork with a progress ring and animated equalizer bars on either side of the notch; hover or click to smoothly expand into a rich player with ambient album-art glow, interactive progress scrubber, playback controls, quick audio output switcher, and synced karaoke lyrics. Enable it, try the built-in Demo track, or customize every detail from the top «Notch» menu."
        ),
        HelpTopicCard(
            id: "hl-quicklook-media-actions-free-move",
            icon: "wand.and.stars",
            badgeES: "Nuevo · v2.5",
            badgeEN: "New · v2.5",
            titleES: "Vista Rápida libre con Acciones rápidas, Copiar (⌘C) e ícono rojo para PDF",
            titleEN: "Free-Moving Quick Look with Media Quick Actions, Copy (⌘C) & Red PDF Icon",
            bodyES: "Al abrir cualquier imagen o video con Espacio, tenés una barra directa con Copiar (⌘C) y todas las Acciones rápidas del clic derecho: copiar imagen y archivo en un clic (o solo imagen / solo archivo), eliminar fondo a PNG transparente, convertir a JPG/PNG, rotar 90° izquierda/derecha o 180° viendo el cambio en vivo, convertir videos a MP4, recortar (Trim), silenciar audio y limpiar metadatos privados. Además, podés arrastrar libremente la ventana de Vista Rápida fuera de MacFileExplorer o hacia otro monitor sin que se frene, y los archivos PDF ahora se distinguen de un vistazo con un ícono rojo estilo Acrobat.",
            bodyEN: "When previewing any image or video with Space, you get an action bar with Copy (⌘C) and every right-click Quick Action: copy both image and file in one click (or image-only / file-only), remove backgrounds into transparent PNGs, convert to JPG/PNG, rotate 90° left/right or 180° with instant live refresh, convert videos to MP4, trim clips, mute audio, and strip private metadata. You can also drag the Quick Look window freely outside MacFileExplorer or across displays without getting stuck, and PDF files stand out immediately with a crisp red Acrobat-style icon."
        ),
        HelpTopicCard(
            id: "hl-office-quicklook-drive",
            icon: "doc.richtext.fill",
            badgeES: "Nuevo · v2.5",
            badgeEN: "New · v2.5",
            titleES: "Editor Office en Vista Rápida (.docx, .xlsx, .xls, .pptx, .csv) y «Enviar a Drive»",
            titleEN: "Quick Look Office Editor (.docx, .xlsx, .xls, .pptx, .csv) & «Send to Drive»",
            bodyES: "Tocá Espacio sobre documentos de Word, planillas de Excel (tanto .xlsx modernos como .xls clásicos), presentaciones de PowerPoint o archivos CSV/TSV para verlos en Vista original y pasar en un clic a un editor práctico tipo LibreOffice con Guardar (⌘S), Guardar copia (⇧⌘S), Copiar/Pegar y conversión .xls → .xlsx. En CSV y Excel podés arrastrar con el mouse sobre celdas, números de fila (#) o encabezados de columna para seleccionar múltiples filas y columnas con Conteo/Suma/Promedio en vivo, encabezados fijos, filtro rápido (⌘F) y ordenamiento. Además, con «Enviar a Drive» subís cualquier archivo a tu carpeta elegida en Google Drive y se abre automático en Sheets, Docs o Slides (en MacFileExplorer o en Chrome externo).",
            bodyEN: "Press Space on Word documents, Excel spreadsheets (both modern .xlsx and classic .xls), PowerPoint decks, or CSV/TSV files to view them in Original View and switch in one click to a handy LibreOffice-style editor with Save (⌘S), Save Copy (⇧⌘S), Copy/Paste, and .xls → .xlsx conversion. In CSV and Excel you can click and drag across cells, row numbers (#), or column headers to select multiple rows and columns with live Count/Sum/Avg stats, frozen headers, live filtering (⌘F), and sorting. Plus, «Send to Drive» uploads any file straight to your chosen Google Drive folder and automatically opens it in Sheets, Docs, or Slides (in-app or external Chrome)."
        ),
        HelpTopicCard(
            id: "hl-windows-taskbar",
            icon: "dock.rectangle",
            badgeES: "Nuevo · v2.6",
            badgeEN: "New · v2.6",
            titleES: "Barra de tareas estilo Windows: Sin scroll, Apps fijadas primero, Sin fantasma de Preview y Ajuste instantáneo",
            titleEN: "Windows-Style Taskbar: Auto-Shrink No-Scroll, Pinned Apps First, Auto-Hide Preview & Instant Maximize",
            bodyES: "Activable desde el menú superior Barra de tareas (apagada por defecto y sin tocar el Dock original). Muestra un botón por ventana con miniaturas en vivo, apps fijadas, Menú Inicio con 8 animaciones (o 0 ms instantáneo) sin robar foco a tu app actual y soporte hasta 5 monitores:\n• Ajuste automático sin scroll (configurable): al abrir muchas ventanas reduce el ancho suavemente (o compacta a íconos) para verlas todas sin cortes ni scroll horizontal.\n• Apps fijadas primero en su mismo orden: muestra primero las ventanas de tus apps fijadas respetando su orden (con un pin sutil y divisor) y avisa al intentar arrastrarlas.\n• Sin botones fantasma de Preview: oculta automáticamente Preview, QuickTime, TextEdit, Pages, Numbers y Keynote cuando cerrás su última ventana (configurable con clic derecho), y ajusta al instante las ventanas maximizadas como Chrome para que nunca queden detrás de la barra.\n• Arrastrar archivos sobre la barra (1 s), Agrupación lado a lado y modos «Solo íconos» o «Solo ícono en minimizadas».",
            bodyEN: "Toggle on or off from the top Taskbar menu (off by default without touching your macOS Dock). Shows one button per window with live hover thumbnails, pinned apps, a non-activating searchable Start Menu with 8 animations (or 0 ms instant), and up to 5 displays:\n• Auto-shrink buttons without horizontal scroll (configurable): smoothly narrows buttons (and compacts to icons when crowded) so every window stays visible without clipping.\n• Pinned apps' windows first (in pinned order): places open windows of pinned apps first in their exact pinned order with a subtle pin indicator and divider.\n• No windowless Preview ghosts & instant maximize fit: automatically hides Preview, QuickTime, TextEdit, Pages, Numbers, and Keynote once their last window closes (customizable via right-click), and snaps maximized windows like Chrome cleanly above the bar almost instantaneously.\n• 1 s drag-hover to raise apps while dragging files, side-by-side grouping, and Icons-Only / Compact Minimized modes."
        ),
        HelpTopicCard(
            id: "hl-alttab-switcher",
            icon: "rectangle.stack.fill",
            badgeES: "v1.8 – v2.0",
            badgeEN: "v1.8 – v2.0",
            titleES: "Selector de ventanas AltTab (Menú superior «AltTab»)",
            titleEN: "AltTab Window Switcher («AltTab» Top Menu)",
            bodyES: "Alterna al instante entre cada ventana abierta individualmente (incluso varias ventanas de una misma app), mostrando ventanas minimizadas, ocultas y de otros Spaces con su etiqueta (Space 2, Minimizada, Oculta), vista previa a tamaño completo encima del resto, 3 estilos (Miniaturas, Íconos, Lista de títulos) con tamaño automático, buscador y hasta 5 atajos personalizables (⌥⇥ y ⌥` por defecto). Comparte el motor de ventanas y miniaturas con la Barra de tareas para máxima performance.",
            bodyEN: "Switch instantly between individual windows (including multiple windows of the same app), showing minimized, hidden, and other-Space windows with clear badges (Space 2, Minimized, Hidden), full-size preview above other windows, 3 display styles (Thumbnails, App Icons, Compact Titles List) with auto-sizing, live search, and up to 5 custom shortcuts (⌥⇥ and ⌥` by default). Shares the window & thumbnail engine with Taskbar for peak performance."
        ),
        HelpTopicCard(
            id: "hl-address-bar",
            icon: "chevron.right.2",
            badgeES: "v1.6",
            badgeEN: "v1.6",
            titleES: "Barra de direcciones editable estilo Windows Explorer",
            titleEN: "Windows Explorer-style Editable Address Bar",
            bodyES: "Hacé clic en el último segmento de la ruta, en el icono izquierdo, en cualquier zona vacía de la barra o presioná ⌘L para escribir o pegar rutas como ~/Documents/Proyectos. Selecciona toda la ruta automáticamente, sugiere subcarpetas con Tab y ofrece menús rápidos en cada ›.",
            bodyEN: "Click the current path segment, left icon, empty bar space, or press ⌘L to type or paste paths like ~/Documents/Projects. Auto-selects the full path, completes folders with Tab, and shows quick subfolder menus on each › chevron."
        ),
        HelpTopicCard(
            id: "hl-quick-actions",
            icon: "wand.and.stars",
            badgeES: "v1.4 – v1.6",
            badgeEN: "v1.4 – v1.6",
            titleES: "Quick Actions: Eliminar fondo (PNG transparente), Privacy Stripper y Media",
            titleEN: "Quick Actions: Remove Background (Transparent PNG), Privacy Stripper & Media",
            bodyES: "Desde clic derecho → Acciones rápidas podés quitar el fondo de imágenes creando un PNG transparente sin pisar el original, limpiar metadatos privados (GPS, cámara, autor) en fotos/videos/PDF, convertir JPG/PNG con calidad/DPI/peso máximo, rotar 90°/180°, convertir MOV→MP4, recortar (Trim) o silenciar video.",
            bodyEN: "From right-click → Quick Actions you can remove image backgrounds into a new transparent PNG, strip private metadata (GPS, camera, author) from photos/videos/PDFs, convert JPG/PNG with quality/DPI/max MB targets, rotate 90°/180°, convert MOV→MP4, trim, or mute videos."
        ),
        HelpTopicCard(
            id: "hl-search-ocr",
            icon: "text.viewfinder",
            badgeES: "v1.5 – v1.6",
            badgeEN: "v1.5 – v1.6",
            titleES: "Buscador avanzado con OCR en imágenes en segundo plano",
            titleEN: "Advanced Search with Background Image OCR",
            bodyES: "Hacé clic en el icono de filtros de la barra de búsqueda para buscar por tipo, extensión, tamaño, subcarpetas y contenido dentro de texto plano, PDFs e imágenes (OCR preciso insensible a mayúsculas/tildes). Cada carpeta indexa sus imágenes en background (máx. 5 MB en .macfileexplorer_ocr.cache) para responder al instante.",
            bodyEN: "Click the filter icon in the search bar to search by type, extension, size, subfolders, and inside text files, PDFs, and images (accurate case/accent-insensitive OCR). Folders quietly index images in the background (max 5 MB in .macfileexplorer_ocr.cache) for instant matching."
        ),
        HelpTopicCard(
            id: "hl-clipboard-tray",
            icon: "doc.on.clipboard.fill",
            badgeES: "v1.3",
            badgeEN: "v1.3",
            titleES: "Portapapeles estilo Maccy (⌃⌘V) y Tray Icon en barra de menús",
            titleEN: "Maccy-style Clipboard History (⌃⌘V) & Menu Bar Tray Icon",
            bodyES: "Guarda automáticamente textos, enlaces, archivos e imágenes copiados. Presioná ⌃⌘V desde cualquier app de tu Mac para abrir el desplegable rápido (accesos ⌘1..9) con pegado automático opcional, y accedé al explorador o carpetas favoritas desde el icono en la barra superior de macOS.",
            bodyEN: "Automatically saves copied text, links, files, and images. Press ⌃⌘V anywhere on your Mac for the quick dropdown (⌘1..9 shortcuts) with optional auto-paste, and jump to windows, tabs, or favorites from the macOS menu bar tray icon."
        ),
        HelpTopicCard(
            id: "hl-duplicates-queue",
            icon: "arrow.up.arrow.down.circle.fill",
            badgeES: "v1.5",
            badgeEN: "v1.5",
            titleES: "Buscador de duplicados y Cola de transferencias (> 1 GB)",
            titleEN: "Duplicate File Finder & Transfer Queue (> 1 GB)",
            bodyES: "Desde Archivo → Buscar archivos duplicados… detectá copias repetidas pre-marcadas para mover a Papelera, borrar o seleccionar. Al copiar/mover más de 1 GB, la barra inferior muestra una cola centrada clicable para pausar, reanudar o cancelar.",
            bodyEN: "From File → Find Duplicate Files… scan and pre-check duplicates to trash, delete permanently, or select. When copying/moving over 1 GB, the bottom bar shows a centered clickable transfer queue to pause, resume, or cancel."
        ),
        HelpTopicCard(
            id: "hl-tabs-google-updates",
            icon: "arrow.down.circle.fill",
            badgeES: "v1.0 – v1.5.1",
            badgeEN: "v1.0 – v1.5.1",
            titleES: "Pestañas nativas, Google Workspace aislado y actualizaciones desde GitHub",
            titleEN: "Native Tabs, Isolated Google Accounts & GitHub Updates",
            bodyES: "Abrí múltiples pestañas de carpetas (⌘T) y cuentas independientes de Gmail, Drive y Calendar sin mezclar cookies. Además, desde Acerca de / menú de la app podés verificar y descargar nuevas versiones directamente desde GitHub.",
            bodyEN: "Open multiple folder tabs (⌘T) alongside isolated Gmail, Drive, and Calendar accounts. Plus, check GitHub and automatically download new installer versions from About or the App menu."
        )
    ]

    private static let sidebarTopics: [HelpTopicCard] = [
        HelpTopicCard(
            id: "sb-quick-access",
            icon: "star.fill",
            titleES: "1. Acceso rápido (Quick Access y Favoritos)",
            titleEN: "1. Quick Access & Pinned Favorites",
            bodyES: "Incluye la carpeta virtual «Modificados hoy (24h)» (escaneo paralelo de archivos recientes en todo tu árbol) junto con Escritorio, Descargas, Documentos, Aplicaciones, Música, Películas, Imágenes y Papelera. Podés arrastrar y soltar cualquier carpeta sobre Acceso rápido para fijarla como favorita, o elegir cuáles mostrar desde Ver → Carpetas en Acceso rápido.",
            bodyEN: "Includes the «Modified Today (24h)» virtual folder (accelerated scan of recent changes across your folder tree) plus Desktop, Downloads, Documents, Applications, Music, Movies, Pictures, and Trash. Drag and drop any folder onto Quick Access to pin it, or customize visible folders under View → Quick Access Folders."
        ),
        HelpTopicCard(
            id: "sb-this-pc",
            icon: "desktopcomputer",
            titleES: "2. Este equipo (Discos, Volúmenes externos y Árbol de carpetas)",
            titleEN: "2. This PC (Drives, External Volumes & Folder Tree)",
            bodyES: "Muestra Macintosh HD, discos USB externos y unidades montadas. Cada ítem tiene flecha de expansión (›) para desplegar subcarpetas en árbol sin cambiar tu vista principal hasta que hagas clic, y botón de expulsión segura en unidades extraíbles.",
            bodyEN: "Lists Macintosh HD, external USB drives, and mounted volumes. Expand any node via the › disclosure triangle to browse subfolders as a tree, and safely eject removable volumes directly from the sidebar."
        ),
        HelpTopicCard(
            id: "sb-google",
            icon: "person.2.circle.fill",
            titleES: "3. Cuentas de Google aisladas (Gmail, Drive, Calendar)",
            titleEN: "3. Isolated Google Accounts (Gmail, Drive, Calendar)",
            bodyES: "Agregá tus cuentas personales o laborales con contenedores web separados para que nunca se mezclen sesiones ni cookies. Al hacer clic en Gmail, Google Drive o Google Calendar se abre en una pestaña integrada dentro de MacFileExplorer (o recordando tu sesión al reabrir la app).",
            bodyEN: "Add multiple personal or work accounts using isolated web containers so sessions never collide. Clicking Gmail, Google Drive, or Google Calendar opens them right inside tabs in MacFileExplorer and preserves your sessions across launches."
        ),
        HelpTopicCard(
            id: "sb-clipboard",
            icon: "doc.on.clipboard",
            titleES: "4. Historial del Portapapeles (Maccy) en el panel lateral",
            titleEN: "4. Clipboard History (Maccy) in the Sidebar",
            bodyES: "Muestra tus elementos recientes copiados (texto, URLs, archivos e imágenes) con acceso rápido para copiar o abrir la vista completa de búsqueda y fijar elementos con pin para que nunca expiren.",
            bodyEN: "Displays recently copied items (text, links, files, and images) for one-click reuse, plus access to the full searchable history panel where you can pin important clips."
        )
    ]

    private static let searchTopics: [HelpTopicCard] = [
        HelpTopicCard(
            id: "sr-quick",
            icon: "magnifyingglass",
            titleES: "Búsqueda rápida instantánea por nombre",
            titleEN: "Instant Quick Name Filter",
            bodyES: "Escribí directamente en la caja «Buscar en <carpeta>» arriba a la derecha para filtrar al instante los archivos y carpetas visibles por nombre. En la barra de estado inferior aparece la etiqueta del filtro activo y podés limpiarlo con la ✕ o Esc.",
            bodyEN: "Type directly in the top-right «Search <folder>» box to filter visible items by name in real time. The active filter appears in the bottom status bar and can be cleared with ✕ or Esc."
        ),
        HelpTopicCard(
            id: "sr-popover",
            icon: "line.3.horizontal.decrease.circle.fill",
            titleES: "Botón de filtros (Buscador avanzado)",
            titleEN: "Advanced Search Filters Popover",
            bodyES: "Hacé clic en el icono de filtros a la derecha de la caja de búsqueda para abrir el panel avanzado con: Texto (nombre o contenido), Tipo de archivo (Imágenes, Videos, Documentos, PDF, Código/Texto, Audio, Comprimidos, Carpetas), Extensión personalizada (ej. pdf, jpg, swift), Tamaño (> o < en KB/MB/GB), Incluir subcarpetas y Buscar dentro de archivos. Al tocar Buscar, presionar Enter o cerrar el popover tras cambiar filtros se ejecuta la búsqueda; Limpiar restaura la carpeta.",
            bodyEN: "Click the filter icon on the right side of the search box to filter by Query (name or content), File Type, custom Extension (e.g. pdf, jpg, swift), File Size (> or < in KB/MB/GB), Include subfolders, and Search inside files. Clicking Search, pressing Enter, or closing the popover after changing filters runs the scan; Reset restores the folder."
        ),
        HelpTopicCard(
            id: "sr-ocr-content",
            icon: "doc.text.magnifyingglass",
            titleES: "Cómo funciona «Buscar dentro de archivos (Texto, PDF e Imágenes OCR)»",
            titleEN: "How «Search inside files (Text, PDF & Image OCR)» Works",
            bodyES: "Lee archivos de texto/código (hasta 8 MB), páginas de documentos PDF (hasta 120 páginas) y texto dentro de imágenes (JPG, PNG, HEIC, WebP, etc.) usando Vision OCR preciso en español e inglés (insensible a mayúsculas, tildes y con soporte multi-palabra). Mientras escanea va mostrando coincidencias en vivo y progreso en la barra inferior.",
            bodyEN: "Scans plain text/code files (up to 8 MB), PDF documents (up to 120 pages), and text inside images (JPG, PNG, HEIC, WebP, etc.) using accurate Spanish/English Vision OCR (case- and accent-insensitive, multi-word aware). Matching files stream live into the list with bottom status bar progress."
        ),
        HelpTopicCard(
            id: "sr-ocr-cache",
            icon: "internaldrive",
            titleES: "Índice OCR automático en segundo plano (máx. 5 MB por carpeta)",
            titleEN: "Background OCR Index Cache (max 5 MB per folder)",
            bodyES: "Al abrir cualquier carpeta, MacFileExplorer analiza silenciosamente sus imágenes nuevas o modificadas y guarda el texto comprimido en el archivo oculto .macfileexplorer_ocr.cache (con tope estricto de 5 MB por carpeta mediante LRU). Así las próximas búsquedas OCR responden en milisegundos. Podés ver su peso o borrarlos para regenerar desde Archivo → Caché oculta (.macfileexplorer)…",
            bodyEN: "When you open a folder, MacFileExplorer quietly indexes new or updated images in the background into a hidden compressed .macfileexplorer_ocr.cache file (strictly capped at 5 MB per folder via LRU). Subsequent OCR searches return in milliseconds. Inspect disk usage or delete caches to regenerate anytime via File → Hidden Cache (.macfileexplorer)…"
        )
    ]

    private static let allFeatureTopics: [HelpTopicCard] = [
        HelpTopicCard(
            id: "af-views-columns",
            icon: "tablecells",
            titleES: "Vistas Detalles, Iconos Grandes, Lista con 3 modos e ícono rojo para PDF",
            titleEN: "Details, Large Icons, List View (3 Icon Modes) & Red Acrobat-Style PDF Icon",
            bodyES: "En Detalles podés redimensionar columnas arrastrando los divisores (con cursor horizontal nativo y doble clic para restablecer). En Lista elegís entre icono Básico, Icono de app predeterminada o Miniatura visual, y los archivos PDF siempre muestran un ícono rojo nítido estilo Acrobat para diferenciarlos al instante de las imágenes. En Iconos Grandes disponés de deslizador inferior estilo Finder de 40 px a 192 px.",
            bodyEN: "In Details view resize columns by dragging dividers (with native horizontal resize cursor and double-click reset). In List view pick Basic, App Icon, or Thumbnail mode, and PDF files always display a crisp red Acrobat-style icon to stand out instantly from images. In Large Icons adjust icon sizes smoothly from 40 px to 192 px via the bottom slider."
        ),
        HelpTopicCard(
            id: "af-quicklook-properties",
            icon: "eye.fill",
            titleES: "Vista Rápida independiente (Espacio), Acciones rápidas multimedia y Propiedades EXIF (⌘I)",
            titleEN: "Independent Quick Look (Space), Media Quick Actions & EXIF Properties (⌘I)",
            bodyES: "La ventana de Vista Rápida es completamente independiente: podés moverla con libertad fuera de MacFileExplorer o hacia otro monitor, redimensionarla y maximizarla con doble clic. En imágenes y videos incluye barra con Copiar (⌘C), Eliminar fondo, Convertir, Rotar 90°/180° en vivo, Convertir a MP4, Recortar (Trim), Silenciar y Limpiar metadatos. También renderiza Office/CSV editables, Markdown, JSON colapsable, XML/código, PDF y carpetas. Propiedades (⌘I) muestra metadatos técnicos EXIF y multimedia.",
            bodyEN: "The Quick Look window is completely independent: drag it freely outside MacFileExplorer or onto another display, resize it, or double-click its bar to maximize. Image and video previews include a built-in toolbar with Copy (⌘C), Remove Background, Convert, live 90°/180° Rotate, Convert to MP4, Trim, Mute, and Strip Metadata. It also renders editable Office/CSV files, Markdown, collapsible JSON, XML/code, PDFs, and folders. Properties (⌘I) displays full EXIF camera and video/audio specs."
        ),
        HelpTopicCard(
            id: "af-context-menu-integrations",
            icon: "cursorarrow.click.2",
            titleES: "Menú contextual: Gemini, Slack, Terminal, Compresor y Renombrado masivo",
            titleEN: "Context Menu: Gemini, Slack, Terminal, Archives & Bulk Rename",
            bodyES: "Al hacer clic derecho sobre archivos o carpetas contás con Abrir Terminal aquí, Comprimir / Extraer (.zip, .7z, .tar.gz, .rar), Quick Actions (Eliminar fondo PNG, Privacy Stripper, Convertir/Rotar/Trim/Silenciar), Añadir a Slack (canales # y personas @), Añadir a Gemini (siempre anteúltimo) y Propiedades (siempre último). Seleccionando varios elementos al renombrar se abre Renombrado masivo (Regex, numeración y fechas EXIF).",
            bodyEN: "Right-clicking items gives access to Open Terminal Here, Compress / Extract (.zip, .7z, .tar.gz, .rar), Quick Actions, Add to Slack, Add to Gemini (always second-to-last), and Properties (always last). Renaming multiple selected items opens Bulk Rename with Regex, sequential numbering, and EXIF dates."
        ),
        HelpTopicCard(
            id: "af-undo-drag-bookmarks",
            icon: "arrow.uturn.backward.circle",
            titleES: "Deshacer/Rehacer, Drag & Drop, Marcadores web y Cache Manager",
            titleEN: "Undo/Redo, Drag & Drop, Bookmarks Bar & Cache Manager",
            bodyES: "Soporte completo de Deshacer (⌘Z) y Rehacer (⇧⌘Z) para renombrado, mover, pegar y Papelera. Barra de marcadores web estilo Chrome (⇧⌘B) con favicons, cola de transferencias pausable (> 1 GB), gestor de caché oculta .macfileexplorer en el menú Archivo y comprobador de actualizaciones desde GitHub.",
            bodyEN: "Full Undo (⌘Z) / Redo (⇧⌘Z) for rename, move, paste, and Trash actions. Chrome-style web bookmarks bar (⇧⌘B) with favicons, pausable >1 GB transfer queue, hidden cache manager in the File menu, and GitHub upgrade checker."
        ),
        HelpTopicCard(
            id: "af-office-csv-drive",
            icon: "doc.richtext",
            titleES: "Edición de Word, Excel (.xlsx y .xls), PowerPoint, CSV con selección por arrastre y «Enviar a Drive»",
            titleEN: "Word, Excel (.xlsx & .xls), PowerPoint, Drag-Select CSV Editing & «Send to Drive»",
            bodyES: "Al abrir archivos de Office con Espacio se muestran en Vista original fiel y permiten pasar en un clic al Editor rápido (formato de texto, tablas, hojas, diapositivas, notas del orador, Copiar/Pegar, Guardar ⌘S, Guardar copia ⇧⌘S y convertir .xls a .xlsx). En CSV, TSV y Excel podés hacer clic y arrastrar con el mouse sobre celdas, números de fila (#) o encabezados de columna para seleccionar bloques de filas y columnas con auto-desplazamiento, encabezados fijos, filtro en vivo (⌘F), ordenamiento, barra de valor, Suma/Promedio en vivo y copiado directo a Excel/Sheets. El botón con logo de Google Drive sube el archivo a tu carpeta destino y lo abre automáticamente en Sheets, Docs o Slides.",
            bodyEN: "Pressing Space on Office files opens crisp Original View and lets you switch in one click to the Quick Editor (formatting, tables, sheets, slides, speaker notes, Copy/Paste, Save ⌘S, Save Copy ⇧⌘S, and .xls → .xlsx export). In CSV, TSV, and Excel you can click and drag with your mouse across cells, row numbers (#), or column headers to select multi-row/column blocks with edge auto-scroll, frozen headers, live filter (⌘F), sorting, formula bar, live Sum/Avg stats, and Excel/Sheets copy-paste. The Google Drive button uploads to your target folder and auto-opens in Sheets, Docs, or Slides."
        ),
        HelpTopicCard(
            id: "af-taskbar-full",
            icon: "dock.rectangle",
            titleES: "Barra de tareas: Sin scroll, Apps fijadas primero, Sin fantasma de Preview, Arrastrar (1 s) e Isla flotante",
            titleEN: "Taskbar: No-Scroll Auto-Shrink, Pinned Apps First, Auto-Hide Preview, Drag-to-Open (1 s) & Floating Island",
            bodyES: "Desde el menú Barra de tareas encendé una barra inferior estilo Windows (borde a borde o Isla flotante) con un botón por ventana, vistas previas emergentes, apps fijadas, Menú Inicio sin robar foco (8 animaciones), hasta 5 monitores y Spaces. Incluye ajuste automático de ancho sin scroll horizontal, orden «Apps fijadas primero en su mismo orden», ocultamiento automático de Preview y apps de documentos sin ventanas, ajuste instantáneo al maximizar ventanas (como Chrome), arrastrar archivos 1 s sobre un botón para abrir esa app, agrupación lado a lado y modos «Solo íconos» o «Solo ícono en minimizadas».",
            bodyEN: "Enable a Windows-style bottom bar (Edge-to-Edge or Floating Island) from the Taskbar menu with one button per window, hover previews, pinned apps, non-activating Start Menu (8 animations), up to 5 displays, and Spaces sync. Includes auto-shrinking buttons without horizontal scroll, «Pinned Apps' Windows First (in Pinned Order)», automatic hiding of windowless Preview & document apps, instant maximize fit above the bar (for Chrome & all apps), 1 s drag-hover to raise apps, same-app grouping, and Icons Only / Compact Minimized modes."
        ),
        HelpTopicCard(
            id: "af-alttab-full",
            icon: "rectangle.stack.fill",
            titleES: "AltTab: Selector de ventanas con Vista Previa Completa y Atajos Múltiples",
            titleEN: "AltTab: Window Switcher with Full-Size Preview & Multiple Shortcuts",
            bodyES: "Desde el menú individual AltTab podés activar el selector ultrarrápido de ventanas individuales (⌥⇥ por defecto, o ⌘⇥ si preferís), ver ventanas minimizadas, ocultas o de otros Spaces con su etiqueta, previsualizar en tamaño completo antes de soltar, cerrar/minimizar/ocultar con teclado (W/M/H/Q/F) o botones hover, buscar con / y alternar entre Miniaturas, Íconos o Lista compacta con auto-tamaño.",
            bodyEN: "From the dedicated AltTab menu enable the ultra-fast individual window switcher (⌥⇥ by default, or ⌘⇥ if preferred), view minimized, hidden, and other-Space windows with badges, preview full-size before switching, close/minimize/hide via keyboard (W/M/H/Q/F) or hover buttons, search with /, and switch between Thumbnails, App Icons, or Titles List with auto-sizing."
        )
    ]

    private static let allShortcuts: [HelpShortcutRow] = [
        HelpShortcutRow(id: "sc-view-desktop", categoryES: "Herramientas (Global)", categoryEN: "Tools (Global)", keys: "⌘ D", actionES: "Mostrar y poner en foco el Escritorio de la Mac desde cualquier app (personalizable en Archivo → Herramientas)", actionEN: "Reveal and focus your Mac Desktop from any app (customizable under File → Tools)"),
        HelpShortcutRow(id: "sc-tab-new", categoryES: "Pestañas y Ventanas", categoryEN: "Tabs & Windows", keys: "⌘ T", actionES: "Abrir nueva pestaña de carpetas en la ruta actual", actionEN: "Open new folder tab at current location"),
        HelpShortcutRow(id: "sc-tab-close", categoryES: "Pestañas y Ventanas", categoryEN: "Tabs & Windows", keys: "⇧ ⌘ T", actionES: "Cerrar pestaña actual", actionEN: "Close current tab"),
        HelpShortcutRow(id: "sc-address", categoryES: "Navegación", categoryEN: "Navigation", keys: "⌘ L", actionES: "Editar barra de direcciones (escribir o pegar ruta)", actionEN: "Edit address bar (type or paste path)"),
        HelpShortcutRow(id: "sc-back", categoryES: "Navegación", categoryEN: "Navigation", keys: "⌘ [  /  ⌥ ←  /  ⌘ ←", actionES: "Ir atrás en el historial (también botones laterales del ratón)", actionEN: "Go back in history (also mouse side button)"),
        HelpShortcutRow(id: "sc-fwd", categoryES: "Navegación", categoryEN: "Navigation", keys: "⌘ ]  /  ⌥ →  /  ⌘ →", actionES: "Ir adelante en el historial (también botones laterales del ratón)", actionEN: "Go forward in history (also mouse side button)"),
        HelpShortcutRow(id: "sc-up", categoryES: "Navegación", categoryEN: "Navigation", keys: "⌘ ↑  /  ⌥ ↑", actionES: "Subir a la carpeta superior", actionEN: "Go to enclosing folder"),
        HelpShortcutRow(id: "sc-open", categoryES: "Navegación", categoryEN: "Navigation", keys: "⌘ ↓", actionES: "Abrir carpeta o archivo seleccionado", actionEN: "Open selected folder or file"),
        HelpShortcutRow(id: "sc-home", categoryES: "Navegación", categoryEN: "Navigation", keys: "⇧ ⌘ H", actionES: "Ir a carpeta Inicio (~)", actionEN: "Go to Home folder (~)"),
        HelpShortcutRow(id: "sc-refresh", categoryES: "Navegación", categoryEN: "Navigation", keys: "⌘ R", actionES: "Actualizar contenido de la carpeta actual", actionEN: "Refresh current folder"),
        HelpShortcutRow(id: "sc-view1", categoryES: "Vistas e Interfaz", categoryEN: "Views & UI", keys: "⌘ 1  /  ⌘ 2", actionES: "Cambiar a vista Detalles (⌘1) o Iconos Grandes (⌘2)", actionEN: "Switch to Details (⌘1) or Large Icons (⌘2) view"),
        HelpShortcutRow(id: "sc-hidden", categoryES: "Vistas e Interfaz", categoryEN: "Views & UI", keys: "⇧ ⌘ .", actionES: "Mostrar u ocultar archivos ocultos", actionEN: "Show or hide hidden files"),
        HelpShortcutRow(id: "sc-bookmarks", categoryES: "Vistas e Interfaz", categoryEN: "Views & UI", keys: "⇧ ⌘ B", actionES: "Mostrar u ocultar barra de marcadores web", actionEN: "Show or hide bookmarks bar"),
        HelpShortcutRow(id: "sc-quicklook", categoryES: "Previsualización e Info", categoryEN: "Preview & Info", keys: "Espacio / Space", actionES: "Abrir o cerrar Vista Rápida (arrastrable libremente fuera de la app y entre monitores)", actionEN: "Toggle Quick Look (freely draggable outside the app and across displays)"),
        HelpShortcutRow(id: "sc-quicklook-copy-media", categoryES: "Previsualización e Info", categoryEN: "Preview & Info", keys: "⌘ C  (en Preview)", actionES: "Copiar imagen + archivo (o archivo de video) directamente desde la Vista Rápida", actionEN: "Copy image & file (or video file) directly from inside Quick Look Preview"),
        HelpShortcutRow(id: "sc-office-drag-select", categoryES: "Editor Office y CSV", categoryEN: "Office & CSV Editor", keys: "Clic y arrastrar", actionES: "Seleccionar múltiples filas y columnas arrastrando en celdas, números (#) o encabezados (A, B, C) en CSV/Excel", actionEN: "Drag-select multiple rows & columns across cells, row numbers (#), or column headers (A, B, C) in CSV/Excel"),
        HelpShortcutRow(id: "sc-office-save", categoryES: "Editor Office y CSV", categoryEN: "Office & CSV Editor", keys: "⌘ S  /  ⇧ ⌘ S", actionES: "Guardar cambios o Guardar copia dentro del Editor Office y CSV", actionEN: "Save changes or Save Copy inside the Quick Look Office & CSV editor"),
        HelpShortcutRow(id: "sc-office-find", categoryES: "Editor Office y CSV", categoryEN: "Office & CSV Editor", keys: "⌘ F", actionES: "Filtrar filas en CSV o buscar texto dentro del Editor Office", actionEN: "Filter rows in CSV or find text inside the Office editor"),
        HelpShortcutRow(id: "sc-taskbar-drag", categoryES: "Barra de tareas", categoryEN: "Taskbar", keys: "Arrastrar + 1 s", actionES: "Mantener un archivo quieto 1 s sobre un botón de la barra para abrir esa app y soltarlo adentro", actionEN: "Hold a dragged file still for 1 s over any Taskbar button to raise that app and drop inside"),
        HelpShortcutRow(id: "sc-info", categoryES: "Previsualización e Info", categoryEN: "Preview & Info", keys: "⌘ I", actionES: "Abrir ventana de Propiedades y metadatos EXIF / multimedia", actionEN: "Open Properties & EXIF / media metadata"),
        HelpShortcutRow(id: "sc-newfolder", categoryES: "Edición y Archivos", categoryEN: "Edit & Files", keys: "⇧ ⌘ N", actionES: "Crear nueva carpeta", actionEN: "Create new folder"),
        HelpShortcutRow(id: "sc-rename", categoryES: "Edición y Archivos", categoryEN: "Edit & Files", keys: "F2  o  Enter", actionES: "Renombrar (1 elemento en línea, varios con Renombrado masivo)", actionEN: "Rename (inline for 1 item, Bulk Rename for multiple)"),
        HelpShortcutRow(id: "sc-clipboard", categoryES: "Edición y Archivos", categoryEN: "Edit & Files", keys: "⌘ X  /  ⌘ C  /  ⌘ V", actionES: "Cortar, Copiar y Pegar archivos o carpetas", actionEN: "Cut, Copy, and Paste files or folders"),
        HelpShortcutRow(id: "sc-selectall", categoryES: "Edición y Archivos", categoryEN: "Edit & Files", keys: "⌘ A", actionES: "Seleccionar todo en la carpeta actual", actionEN: "Select All in current folder"),
        HelpShortcutRow(id: "sc-undoredo", categoryES: "Edición y Archivos", categoryEN: "Edit & Files", keys: "⌘ Z  /  ⇧ ⌘ Z", actionES: "Deshacer / Rehacer última operación de archivo", actionEN: "Undo / Redo last file operation"),
        HelpShortcutRow(id: "sc-trash", categoryES: "Edición y Archivos", categoryEN: "Edit & Files", keys: "⌘ ⌫  o  ⌫", actionES: "Mover seleccionados a la Papelera", actionEN: "Move selected items to Trash"),
        HelpShortcutRow(id: "sc-permdelete", categoryES: "Edición y Archivos", categoryEN: "Edit & Files", keys: "⇧ ⌫", actionES: "Eliminar permanentemente (con confirmación centrada)", actionEN: "Delete permanently (with confirmation modal)"),
        HelpShortcutRow(id: "sc-maccy", categoryES: "Portapapeles Maccy", categoryEN: "Maccy Clipboard", keys: "⌃ ⌘ V  (+ ⌘1..9)", actionES: "Abrir menú rápido global del Portapapeles (personalizable)", actionEN: "Open global Clipboard Quick Dropdown (customizable)"),
        HelpShortcutRow(id: "sc-webzoom", categoryES: "Pestañas Web", categoryEN: "Web Tabs", keys: "⌘ +  /  ⌘ -  /  ⌘ 0", actionES: "Acercar, alejar o restablecer zoom web (100%)", actionEN: "Zoom In, Zoom Out, or Reset Web Zoom (100%)"),
        HelpShortcutRow(id: "sc-alttab-all", categoryES: "AltTab (Selector)", categoryEN: "AltTab Switcher", keys: "⌥ ⇥  /  ⇧ ⌥ ⇥", actionES: "Alternar entre todas las ventanas abiertas (personalizable a ⌘⇥ o ⌃⇥)", actionEN: "Switch across all open windows (customizable to ⌘⇥ or ⌃⇥)"),
        HelpShortcutRow(id: "sc-alttab-app", categoryES: "AltTab (Selector)", categoryEN: "AltTab Switcher", keys: "⌥ `", actionES: "Alternar entre ventanas de la aplicación activa actual", actionEN: "Switch between windows of the active application"),
        HelpShortcutRow(id: "sc-alttab-actions", categoryES: "AltTab (Selector)", categoryEN: "AltTab Switcher", keys: "W / M / H / Q / F / /", actionES: "Dentro de AltTab: Cerrar, Minimizar, Ocultar, Salir, Pantalla completa o Buscar", actionEN: "Inside AltTab: Close, Minimize, Hide, Quit, Full Screen, or Search"),
        HelpShortcutRow(id: "sc-help", categoryES: "Ayuda", categoryEN: "Help", keys: "⌘ ?", actionES: "Abrir esta ventana de Ayuda de MacFileExplorer", actionEN: "Open this MacFileExplorer Help window")
    ]

    private static let settingsTopics: [HelpTopicCard] = [
        HelpTopicCard(
            id: "cfg-notch",
            icon: "waveform",
            titleES: "Reproductor Notch, carátula, letras y pantallas (Menú Notch)",
            titleEN: "Notch Music Player, Artwork, Lyrics & Displays (Notch Menu)",
            bodyES: "Arranca desactivado por defecto y se controla desde el menú superior «Notch» o «Configuración de Notch…». Detecta canción, artista, progreso y carátula exacta de YouTube Music (app o navegador), Spotify y Apple Music; ofrece accesos rápidos para volver a abrir tu último reproductor cuando no suena música, y el botón «✕» cierra y oculta el Notch por completo. Podés configurar inicio automático, letras sincronizadas, anuncios al cambiar de tema, brillo ambiental, estilo de carátula, tamaño, pantallas, apertura por puntero o clic, swipe horizontal y ocultamiento en pantalla completa o en pausa.",
            bodyEN: "Starts disabled by default and is managed from the top «Notch» menu or «Notch Settings…». Reads exact song, artist, progress, and cover art from YouTube Music (app or browser), Spotify, and Apple Music; shows quick buttons to reopen your last music app when idle, and the «✕» button closes and hides the Notch completely. Configure launch-on-startup, synced lyrics, track-change announcements, ambient glow, artwork style, sizing, displays, hover vs click expansion, horizontal swipe, and full-screen or paused auto-hide."
        ),
        HelpTopicCard(
            id: "cfg-shortcuts-and-tools",
            icon: "wrench.and.screwdriver.fill",
            titleES: "Administrador de todos los atajos y submenú «Herramientas» (Menú Archivo)",
            titleEN: "All Keyboard Shortcuts Manager & «Tools» Submenu (File Menu)",
            bodyES: "Desde Archivo → Administrar todos los atajos de teclado… podés buscar, activar, cambiar y restablecer en un solo lugar los atajos de Herramientas, Explorador, Portapapeles Maccy y AltTab con detección de conflictos. En Archivo → Herramientas (Tools) encontrás configuraciones modulares como «View Desktop Shortcut» (⌘D por defecto para mostrar y enfocar el Escritorio, con presets rápidos y elección entre Mission Control o estilo Win+D).",
            bodyEN: "Under File → Manage All Keyboard Shortcuts… you can search, toggle, customize, and reset shortcuts across Tools, File Explorer, Maccy Clipboard, and AltTab with automatic conflict detection. Under File → Tools you'll find extensible tool settings starting with «View Desktop Shortcut» (⌘D by default to show and focus your Mac Desktop, with quick presets and choice between Mission Control or Win+D mode)."
        ),
        HelpTopicCard(
            id: "cfg-alttab",
            icon: "rectangle.stack.fill",
            titleES: "Selector AltTab, estilos, vista previa y atajos (Menú AltTab)",
            titleEN: "AltTab Switcher, Styles, Preview & Shortcuts (AltTab Menu)",
            bodyES: "Arranca desactivado por defecto. Desde AltTab → Configuración podés encenderlo, elegir si arranca activo al abrir la app, grabar hasta 5 perfiles de atajos con filtros propios (app actual, Space actual, monitor, minimizadas/ocultas), elegir entre Miniaturas, Íconos o Lista con tamaño automático, activar la vista previa a tamaño completo y excluir apps específicas.",
            bodyEN: "Starts disabled by default. Under AltTab → Settings you can enable it, choose launch-on-startup behavior, record up to 5 shortcut profiles with custom filters, choose Thumbnails, App Icons, or Titles List with auto-sizing, toggle full-size window previews, and exclude specific apps."
        ),
        HelpTopicCard(
            id: "cfg-office",
            icon: "menubar.dock.rectangle",
            titleES: "Menú superior «Office»: Edición en Vista Rápida y «Enviar a Drive»",
            titleEN: "Top «Office» Menu: Quick Look Editing & «Send to Drive» Settings",
            bodyES: "Desde el menú superior Office controlás todo en un clic: activar o desactivar el modo edición en Vista Rápida, elegir si los documentos abren en Vista original o directo en Editor, habilitar o deshabilitar Word, Excel (.xlsx/.xls), PowerPoint y CSV por separado, configurar encabezados fijos y ajuste de texto en planillas, y ajustar «Enviar a Drive» (activar/desactivar, cuenta de Google por defecto, carpeta destino en Drive y abrir Sheets/Docs/Slides en pestaña interna o en Google Chrome externo).",
            bodyEN: "Manage everything in one click from the top Office menu: toggle Quick Look editing on or off, choose Original View or Quick Editor as default, enable or disable Word, Excel (.xlsx/.xls), PowerPoint, and CSV individually, configure frozen headers and text wrapping, and set up «Send to Drive» (enable/disable, default Google account, target Drive folder, and opening Sheets/Docs/Slides inside MacFileExplorer or in external Google Chrome)."
        ),
        HelpTopicCard(
            id: "cfg-taskbar",
            icon: "dock.rectangle",
            titleES: "Barra de tareas, sin scroll, apps fijadas primero, Preview, apariencia y Dock (Configuración de la Barra de tareas)",
            titleEN: "Taskbar Settings: Auto-Shrink, Pinned Apps First, Preview Auto-Hide, Appearance & Dock",
            bodyES: "Arranca desactivada por defecto con el Dock original de macOS intacto. Desde «Configuración de la Barra de tareas…» (o clic derecho sobre la barra) podés elegir inicio automático, «Ajustar ancho sin scroll horizontal» vs scroll horizontal, «Apps fijadas primero en la barra (en su mismo orden)», ocultar automáticamente apps de documentos sin ventanas como Preview (y clic medio para cerrarlas), Isla flotante o barra acoplada, línea divisoria, material de fondo, estilo de botones, indicador en 6 colores, «Solo íconos», agrupación lado a lado, 8 animaciones del Menú Inicio (incluyendo 0 ms), 5 íconos de app, multimonitor y restauración de emergencia del Dock.",
            bodyEN: "Starts disabled by default with your original macOS Dock untouched. Under «Taskbar Settings…» (or right-clicking the bar) configure launch-on-startup, «Auto-Shrink Buttons (No Scroll)» vs horizontal scroll, «Pinned Apps' Windows First (in Pinned Order)», auto-hiding windowless document apps like Preview (plus middle-click quit), Floating Island vs Edge-to-Edge, top divider, background material, button shapes, active indicator in 6 colors, «Icons Only», side-by-side grouping, 8 Start Menu animations (including 0 ms), 5 app icons, multi-monitor rules, and one-click emergency Dock restore."
        ),
        HelpTopicCard(
            id: "cfg-language",
            icon: "globe",
            titleES: "Idioma de la aplicación y menús (Menú Idioma / MacFileExplorer)",
            titleEN: "App & Menu Language (Language Menu)",
            bodyES: "Elegí Español, English o Automático del sistema. Cambia en tiempo real tanto toda la interfaz SwiftUI/AppKit como los textos e íconos del menú superior de macOS.",
            bodyEN: "Switch between Español, English, or System Default. Dynamically updates the entire UI and macOS top menu bar titles and SF Symbol icons in real time."
        ),
        HelpTopicCard(
            id: "cfg-view-toolbar",
            icon: "menubar.rectangle",
            titleES: "Apariencia, barra de herramientas, iconos y columnas (Menú Ver)",
            titleEN: "Layout, Toolbar, Icons & Columns (View Menu)",
            bodyES: "Configurá: Mostrar barra de marcadores (⇧⌘B), Abrir marcadores web en navegador del sistema o pestaña interna, Mostrar u ocultar botón «+ Nuevo», Mostrar archivos ocultos (⇧⌘.), Modo de iconos en vista Lista (Básico / Icono de app / Miniatura) y Tamaño de iconos en Cuadrícula (48 / 64 / 96 / 144 / 192 px o slider continuo). El ancho de las columnas en Detalles se guarda automáticamente.",
            bodyEN: "Configure: Show Bookmarks Bar (⇧⌘B), Open web bookmarks in system browser vs internal tab, Show «+ New» button, Show hidden files (⇧⌘.), List View Icons (Basic / App Icon / Thumbnail), and Grid Icon Size (48–192 px presets or slider). Details column widths persist automatically."
        ),
        HelpTopicCard(
            id: "cfg-quick-access",
            icon: "star.circle",
            titleES: "Carpetas visibles en Acceso rápido (Ver → Carpetas en Acceso rápido)",
            titleEN: "Quick Access Visible Folders (View → Quick Access Folders)",
            bodyES: "Activá o desactivá «Modificados hoy (24h)» y elegí individualmente cuáles carpetas mostrar en la barra lateral (Escritorio, Descargas, Documentos, Aplicaciones, Música, Películas, Imágenes, Papelera) o restablecé las predeterminadas. También podés arrastrar carpetas propias para fijarlas.",
            bodyEN: "Toggle «Modified Today (24h)» and show or hide Desktop, Downloads, Documents, Applications, Music, Movies, Pictures, and Trash individually, reset to defaults, or drag custom folders to pin them."
        ),
        HelpTopicCard(
            id: "cfg-behavior",
            icon: "gearshape.2",
            titleES: "Sesiones, Tray Icon, Slack y Botones del Ratón (Menú Ver)",
            titleEN: "Sessions, Tray Icon, Slack & Mouse Settings (View Menu)",
            bodyES: "• Recordar carpetas, pestañas y sesiones de Google al iniciar.\n• Mostrar icono de acceso rápido en la barra de menús de macOS (Tray Icon).\n• Mostrar u ocultar «Añadir a Slack» en menús contextuales (y gestionar canales/contactos recientes).\n• Invertir botones laterales del ratón (Atrás/Adelante) según tu comodidad.",
            bodyEN: "• Remember open folders, tabs, and Google sessions on launch.\n• Show quick access icon in the macOS menu bar (Tray Icon).\n• Show or hide «Add to Slack» in context menus (with recent channels/teammates).\n• Swap mouse side buttons (Back/Forward)."
        ),
        HelpTopicCard(
            id: "cfg-clipboard",
            icon: "doc.on.clipboard",
            titleES: "Historial del Portapapeles Maccy (Menú Portapapeles)",
            titleEN: "Maccy Clipboard History Settings (Clipboard Menu)",
            bodyES: "Activá o desactivá el guardado automático, configurá Tiempo de retención (1 día, 7 días, 30 días o Sin límite), Cantidad máxima (50 a 1000 ítems), Cantidad visible en el desplegable rápido (5 a 20), Pegar automáticamente tras seleccionar, y personalizá todos los atajos de teclado desde Configuración del Portapapeles.",
            bodyEN: "Enable/disable history recording, set Retention Time (1 day, 7 days, 30 days, or Unlimited), Maximum Items (50–1000), Quick Dropdown count (5–20), Auto-paste on selection, and customize every shortcut in Clipboard Settings."
        ),
        HelpTopicCard(
            id: "cfg-cache-updates",
            icon: "internaldrive",
            titleES: "Caché oculta (.macfileexplorer), Actualizaciones mensuales, Ícono Mono Oscuro y Ko-fi",
            titleEN: "Hidden Cache (.macfileexplorer), Monthly Update Check-In, Dark Mono Icon & Optional Ko-fi Tip",
            bodyES: "Desde Archivo → Caché oculta (.macfileexplorer)… inspeccioná cuántos archivos .macfileexplorer_dir.cache, .macfileexplorer_thumbs.cache y .macfileexplorer_ocr.cache hay y cuánto ocupan, o borralos para regenerarlos. Desde el menú MacFileExplorer podés buscar actualizaciones manualmente, cambiar entre los 5 íconos (Mono Oscuro por defecto) o abrir «Apoyar proyecto (Propina Ko-fi)…». Además, una vez cada 30 días aparece un aviso flotante discreto en la esquina inferior derecha que comprueba automáticamente si hay una nueva versión sin interrumpir tu trabajo (posponible o desactivable en un clic).",
            bodyEN: "Under File → Hidden Cache (.macfileexplorer)… inspect total file count and disk usage of .macfileexplorer_*.cache files and wipe them to regenerate cleanly. From the MacFileExplorer menu check for updates manually, switch among the 5 app icons (Dark Mono by default), or open «Support Project (Ko-fi Tip)…». Once every 30 days a non-invasive floating corner card also checks automatically for new updates without interrupting your workflow (snoozable or permanently dismissible in one click)."
        )
    ]

    private static let permissionTopics: [HelpTopicCard] = [
        HelpTopicCard(
            id: "perm-files-folders",
            icon: "folder.fill.badge.person.crop",
            badgeES: "Básico · Solo por carpeta",
            badgeEN: "Core · Per-folder only",
            titleES: "1. Archivos y Carpetas (Escritorio, Documentos, Descargas y Volúmenes externos)",
            titleEN: "1. Files & Folders (Desktop, Documents, Downloads & Removable Volumes)",
            bodyES: "• Para qué funciones se precisa: navegar, buscar, copiar, mover, renombrar, comprimir y previsualizar tus archivos dentro de Escritorio, Documentos, Descargas y discos USB/externos en «Acceso rápido» y «Este equipo».\n• Por qué es lo mínimo y necesario: macOS te pide autorización individual solo la primera vez que entrás a cada carpeta específica. MacFileExplorer NO solicita «Acceso total al disco» (Full Disk Access) ni accede a carpetas privadas del sistema.",
            bodyEN: "• Which features need it: browsing, searching, copying, moving, renaming, archiving, and previewing your files inside Desktop, Documents, Downloads, and external/USB drives in «Quick Access» and «This PC».\n• Why it's the strict minimum: macOS asks per individual folder only the first time you open it. MacFileExplorer NEVER asks for «Full Disk Access» or touches private system folders."
        ),
        HelpTopicCard(
            id: "perm-accessibility",
            icon: "figure.walk.circle.fill",
            badgeES: "Opcional · Ventanas y auto-pegado",
            badgeEN: "Optional · Windows & Auto-paste",
            titleES: "2. Accesibilidad (Accessibility)",
            titleEN: "2. Accessibility",
            bodyES: "• Para qué funciones se precisa:\n  – Barra de tareas (Taskbar): listar las ventanas abiertas de tus apps, cambiar a una ventana al hacer clic, minimizar/cerrar/reordenar ventanas, leer badges de notificaciones y redimensionar ventanas superpuestas.\n  – Selector AltTab: detectar los atajos globales de cambio de ventana (⌥⇥ / ⌘⇥ / ⌥`) y enfocar, cerrar o minimizar la ventana que elijas.\n  – Portapapeles Maccy (solo si activás «Pegar automáticamente»): simular ⌘V en la app activa cuando elegís un elemento del menú desplegable (⌃⌘V). Si desactivás el pegado automático, el portapapeles copia el texto/archivo sin necesitar Accesibilidad.\n• Por qué es lo mínimo y necesario: no se usa si solo utilizás el Explorador de archivos. Nunca registra contraseñas ni lo que escribís; solo se activa cuando encendés la Barra de tareas, AltTab o el pegado automático.",
            bodyEN: "• Which features need it:\n  – Taskbar: listing open windows from your apps, focusing a window on click, minimizing/closing/arranging windows, detecting notification badges, and auto-resizing overlapping windows.\n  – AltTab Switcher: listening for global window-switching shortcuts (⌥⇥ / ⌘⇥ / ⌥`) and focusing, closing, or minimizing the selected window.\n  – Maccy Clipboard (only if «Auto-paste on selection» is on): sending ⌘V to the active app when you pick an item from the quick dropdown (⌃⌘V). If auto-paste is turned off, Clipboard History works without Accessibility.\n• Why it's the strict minimum: not needed at all if you only use the File Explorer. It never logs keystrokes or passwords — it is only used when you enable Taskbar, AltTab, or auto-paste."
        ),
        HelpTopicCard(
            id: "perm-screen-recording",
            icon: "rectangle.dashed.badge.record",
            badgeES: "100% Opcional · Solo miniaturas",
            badgeEN: "100% Optional · Thumbnails only",
            titleES: "3. Grabación de pantalla (Screen Recording)",
            titleEN: "3. Screen Recording",
            bodyES: "• Para qué funciones se precisa:\n  – Barra de tareas: mostrar la vista previa (miniatura en vivo) de cada ventana al pasar el cursor por encima.\n  – Selector AltTab: mostrar miniaturas visuales y la vista previa a tamaño completo de las ventanas abiertas.\n• Aclaración importante de privacidad: MacFileExplorer NO graba tu pantalla, NO guarda videos ni capturas en disco y NO envía imágenes a internet. Apple agrupa bajo «Grabación de pantalla» el permiso técnico de macOS necesario para dibujar miniaturas locales de ventanas en memoria RAM.\n• Si preferís no habilitarlo: tanto la Barra de tareas como AltTab siguen funcionando sin problemas mostrando el ícono y título de cada ventana.",
            bodyEN: "• Which features need it:\n  – Taskbar: showing live window thumbnail previews when hovering over taskbar buttons.\n  – AltTab Switcher: displaying visual window thumbnails and full-size window previews.\n• Important privacy note: MacFileExplorer does NOT record your screen, does NOT save screenshots or videos to disk, and NEVER uploads anything. macOS uses the label «Screen Recording» for the system API required to render local in-memory window thumbnails.\n• If you prefer not to grant it: both Taskbar and AltTab keep working smoothly using app icons and window titles instead."
        ),
        HelpTopicCard(
            id: "perm-automation",
            icon: "gearshape.2.fill",
            badgeES: "Opcional · Solo 2 acciones puntuales",
            badgeEN: "Optional · 2 specific actions only",
            titleES: "4. Automatización (Finder y System Events)",
            titleEN: "4. Automation (Finder & System Events)",
            bodyES: "• Para qué funciones se precisa (únicamente si usás estas 2 opciones):\n  – «Vaciar Papelera» desde el menú lateral: solicita autorización puntual para pedirle a Finder que vacíe la Papelera con el diálogo nativo de macOS.\n  – «Añadir a Slack» desde el menú contextual: si activás la integración con Slack, solicita autorización puntual para traer Slack al frente y pegar el archivo con System Events.\n• Por qué es lo mínimo y necesario: si no hacés clic en ninguna de esas dos acciones, macOS nunca te pedirá permiso de Automatización.",
            bodyEN: "• Which features need it (only if you trigger these 2 actions):\n  – «Empty Trash» from the sidebar: asks once to let Finder empty Trash with macOS's native confirmation.\n  – «Add to Slack» from the context menu: if you enable Slack sharing, asks once to bring Slack forward and paste the file via System Events.\n• Why it's the strict minimum: if you never use those two actions, macOS will never ask you for Automation permission."
        ),
        HelpTopicCard(
            id: "perm-none-needed-and-never-asked",
            icon: "hand.raised.fill",
            badgeES: "Privacidad total",
            badgeEN: "Privacy First",
            titleES: "Funciones sin permisos especiales — y permisos que NUNCA pedimos",
            titleEN: "Zero-Permission Features — & Permissions We NEVER Request",
            bodyES: "• Funcionan de fábrica sin permisos especiales: Vista Rápida (Quick Look), Editor de Word/Excel/PowerPoint/CSV, Acciones rápidas de imágenes y videos (quitar fondo, rotar, convertir, recortar, limpiar metadatos), Buscador Avanzado y OCR local (Apple Vision), Buscador de duplicados, Compresión ZIP/TAR y atajos globales como «View Desktop Shortcut» (⌘D) o abrir el menú del Portapapeles (⌃⌘V).\n• Permisos que MacFileExplorer NUNCA solicita: Cámara, Micrófono, Contactos, Fotos, Calendario, Ubicación, Bluetooth ni Acceso total al disco (Full Disk Access).",
            bodyEN: "• Work out of the box with zero special permissions: Quick Look previews, Word/Excel/PowerPoint/CSV Editor, image & video Quick Actions (remove background, rotate, convert, trim, strip metadata), Advanced Search & local Vision OCR, Duplicate Finder, ZIP/TAR archiving, and global shortcuts like «View Desktop Shortcut» (⌘D) or opening the Clipboard dropdown (⌃⌘V).\n• Permissions MacFileExplorer NEVER requests: Camera, Microphone, Contacts, Photos, Calendar, Location, Bluetooth, or Full Disk Access."
        )
    ]
}
