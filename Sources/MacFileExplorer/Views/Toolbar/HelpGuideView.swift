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
                subtitleES: "Podés personalizar vistas, idioma, carpetas visibles en Acceso rápido, portapapeles Maccy, ratón, marcadores, Slack y caché oculta.",
                subtitleEN: "Customize view modes, language, visible Quick Access folders, Maccy clipboard, mouse buttons, bookmarks, Slack, and hidden cache."
            )
            ForEach(Self.settingsTopics) { card in
                topicCardView(card)
            }

        case .releases:
            introBanner(
                icon: "sparkles",
                titleES: "Novedades por versión (Release Notes)",
                titleEN: "Release Notes by Version",
                subtitleES: "Historial completo generado directamente desde el catálogo oficial de versiones de MacFileExplorer.",
                subtitleEN: "Full chronological changelog synced directly from MacFileExplorer's official release catalog."
            )
            ForEach(ReleaseNotesCatalog.sections) { section in
                releaseSectionCard(section)
            }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        let q = trimmedSearch
        let matchingCards = (Self.highlightedTopics + Self.sidebarTopics + Self.searchTopics + Self.allFeatureTopics + Self.settingsTopics)
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
}

// MARK: - Catálogo Estructurado de Contenidos de la Ayuda

extension HelpGuideView {

    private static let highlightedTopics: [HelpTopicCard] = [
        HelpTopicCard(
            id: "hl-alttab-switcher",
            icon: "rectangle.stack.fill",
            badgeES: "Nuevo",
            badgeEN: "New",
            titleES: "Selector de ventanas AltTab (Menú superior «AltTab»)",
            titleEN: "AltTab Window Switcher («AltTab» Top Menu)",
            bodyES: "Alterna al instante entre cada ventana abierta individualmente (incluso varias ventanas de una misma app), mostrando ventanas minimizadas, ocultas y de otros Spaces con su etiqueta (Space 2, Minimizada, Oculta), vista previa a tamaño completo encima del resto, 3 estilos (Miniaturas, Íconos, Lista de títulos) con tamaño automático, buscador y hasta 5 atajos personalizables (⌥⇥ y ⌥` por defecto). Comparte el motor de ventanas y miniaturas con la Barra de tareas para máxima performance.",
            bodyEN: "Switch instantly between individual windows (including multiple windows of the same app), showing minimized, hidden, and other-Space windows with clear badges (Space 2, Minimized, Hidden), full-size preview above other windows, 3 display styles (Thumbnails, App Icons, Compact Titles List) with auto-sizing, live search, and up to 5 custom shortcuts (⌥⇥ and ⌥` by default). Shares the window & thumbnail engine with Taskbar for peak performance."
        ),
        HelpTopicCard(
            id: "hl-windows-taskbar",
            icon: "dock.rectangle",
            badgeES: "Nuevo",
            badgeEN: "New",
            titleES: "Barra de tareas estilo Windows (Menú superior «Barra de tareas»)",
            titleEN: "Windows-Style Taskbar («Taskbar» Top Menu)",
            bodyES: "Activable y desactivable desde el menú superior Barra de tareas (apagada por defecto y sin tocar el Dock original de macOS). Muestra un botón por cada ventana abierta, miniaturas en vivo al pasar el cursor, apps fijadas, Menú Inicio alfabético con buscador, soporte multimonitor (hasta 5 pantallas), sincronización con Spaces, drag-and-drop y restauración de emergencia del Dock.",
            bodyEN: "Toggle on or off from the top Taskbar menu (off by default without touching your original macOS Dock). Shows one button per open window, live hover thumbnails, pinned apps, a searchable alphabetical Start Menu, multi-monitor support (up to 5 displays), Spaces sync, drag-and-drop reordering, and emergency Dock restore."
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
            titleES: "Vistas Detalles, Iconos Grandes y Lista con 3 modos de icono",
            titleEN: "Details, Large Icons & List Views with 3 Icon Modes",
            bodyES: "En Detalles podés redimensionar columnas arrastrando los divisores (con cursor horizontal nativo y doble clic para restablecer). En Lista elegís entre icono Básico, Icono de app predeterminada o Miniatura visual. En Iconos Grandes disponés de deslizador inferior estilo Finder de 40 px a 192 px.",
            bodyEN: "In Details view resize columns by dragging dividers (with native horizontal resize cursor and double-click reset). In List view pick Basic, App Icon, or Thumbnail mode. In Large Icons adjust icon sizes smoothly from 40 px to 192 px via the bottom slider."
        ),
        HelpTopicCard(
            id: "af-quicklook-properties",
            icon: "eye.fill",
            titleES: "Vista Rápida enriquecida (Espacio) y Propiedades con EXIF (⌘I)",
            titleEN: "Enhanced Quick Look (Space) & EXIF Properties (⌘I)",
            bodyES: "La ventana de Vista Rápida es flotante, movible, redimensionable y maximizable con doble clic. Renderiza Markdown completo (tablas/frontmatter), JSON en árbol colapsable o texto plano, código fuente con números de línea, fotos/videos/PDF y resumen de carpetas. Propiedades (⌘I) muestra metadatos técnicos EXIF y multimedia.",
            bodyEN: "The Quick Look preview is a movable, resizable floating window (double-click title bar to maximize). Renders rich Markdown, collapsible JSON tree or plain text, line-numbered code, media/PDFs, and folder statistics. Properties (⌘I) displays full EXIF camera and video/audio specs."
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
            id: "af-taskbar-full",
            icon: "dock.rectangle",
            titleES: "Barra de tareas estilo Windows, Menú Inicio y Multimonitor",
            titleEN: "Windows-Style Taskbar, Start Menu & Multi-Monitor",
            bodyES: "Desde el menú Barra de tareas podés encender una barra inferior con un botón por ventana, vistas previas al pasar el mouse, apps fijadas, Menú Inicio con buscador/recientes/A–Z, hasta 5 monitores independientes o unificados, sincronización con Spaces, clic en ventana activa para minimizar, clic central para cerrar y auto-redimensionamiento de ventanas superpuestas.",
            bodyEN: "Enable a bottom bar from the Taskbar menu with one button per window, live hover previews, pinned apps, searchable Start Menu with recent & A–Z apps, up to 5 independent or unified displays, Spaces sync, click active window to minimize, middle-click to close, and automatic overlap resizing."
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
        HelpShortcutRow(id: "sc-quicklook", categoryES: "Previsualización e Info", categoryEN: "Preview & Info", keys: "Espacio / Space", actionES: "Abrir o cerrar Vista Rápida (Quick Look / Propiedades de carpeta)", actionEN: "Toggle Quick Look (or folder properties)"),
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
            id: "cfg-alttab",
            icon: "rectangle.stack.fill",
            titleES: "Selector AltTab, estilos, vista previa y atajos (Menú AltTab)",
            titleEN: "AltTab Switcher, Styles, Preview & Shortcuts (AltTab Menu)",
            bodyES: "Arranca desactivado por defecto. Desde AltTab → Configuración podés encenderlo, elegir si arranca activo al abrir la app, grabar hasta 5 perfiles de atajos con filtros propios (app actual, Space actual, monitor, minimizadas/ocultas), elegir entre Miniaturas, Íconos o Lista con tamaño automático, activar la vista previa a tamaño completo y excluir apps específicas.",
            bodyEN: "Starts disabled by default. Under AltTab → Settings you can enable it, choose launch-on-startup behavior, record up to 5 shortcut profiles with custom filters, choose Thumbnails, App Icons, or Titles List with auto-sizing, toggle full-size window previews, and exclude specific apps."
        ),
        HelpTopicCard(
            id: "cfg-taskbar",
            icon: "dock.rectangle",
            titleES: "Barra de tareas, apariencia, monitores y Dock (Menú Barra de tareas)",
            titleEN: "Taskbar, Appearance, Displays & Dock (Taskbar Menu)",
            bodyES: "Arranca desactivada por defecto con el Dock original de macOS intacto. En Barra de tareas → Configuración podés elegir si se activa por defecto al abrir la app, ajustar altura, fuente, transparencia, tema claro/oscuro, solo íconos, apps fijadas/excluidas, comportamiento multimonitor y gestión opcional del Dock con botón de emergencia para restaurar el Dock original en un clic.",
            bodyEN: "Starts disabled by default with your original macOS Dock untouched. Under Taskbar → Settings you can choose whether to launch enabled by default, customize height, font, opacity, light/dark theme, icon-only mode, pinned/excluded apps, multi-monitor rules, and optional Dock placement with a one-click emergency restore."
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
            bodyES: "Activá o desactivá el guardado automático, configurá Tiempo de retención (1 día, 7 días, 30 días o Sin límite), Cantidad máxima (50 a 1000 ítems), Cantidad visible en el desplegable rápido (5 a 20), Pegar automáticamente tras seleccionar, y personalizá todos los atajos de teclado desde el Panel de atajos y ajustes.",
            bodyEN: "Enable/disable history recording, set Retention Time (1 day, 7 days, 30 days, or Unlimited), Maximum Items (50–1000), Quick Dropdown count (5–20), Auto-paste on selection, and customize every shortcut in the Shortcuts & Settings panel."
        ),
        HelpTopicCard(
            id: "cfg-cache-updates",
            icon: "internaldrive",
            titleES: "Mantenimiento de caché oculta (.macfileexplorer) y Actualizaciones",
            titleEN: "Hidden Cache (.macfileexplorer) Maintenance & GitHub Updates",
            bodyES: "Desde Archivo → Caché oculta (.macfileexplorer)… inspeccioná cuántos archivos .macfileexplorer_dir.cache, .macfileexplorer_thumbs.cache y .macfileexplorer_ocr.cache hay y cuánto ocupan, o borralos para regenerarlos. Desde MacFileExplorer → Buscar actualizaciones… comprobá y descargá nuevas versiones desde GitHub.",
            bodyEN: "Under File → Hidden Cache (.macfileexplorer)… inspect total file count and disk usage of .macfileexplorer_*.cache files and wipe them to regenerate cleanly. Under MacFileExplorer → Check for Updates… check GitHub and download newer versions."
        )
    ]
}
