import SwiftUI
import AppKit

/// Sección de Marcadores / Favoritos estilo Google Chrome ubicada en el extremo superior derecho de la barra de comandos.
/// Permite agregar, editar y eliminar accesos directos web, y elegir si se abren dentro de `MacFileExplorer`
/// o en una nueva ventana de `Google Chrome`.
public struct ChromeBookmarksBarView: View {
    @Bindable var bookmarksManager: BookmarksManager = .shared

    @ViewState private var isShowingAddPopover: Bool = false
    @ViewState private var editingBookmark: ChromeBookmarkItem? = nil

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init() {}

    private var bookmarksRowContent: some View {
        HStack(spacing: 4) {
            ForEach(bookmarksManager.bookmarks) { item in
                ChromeBookmarkChipView(
                    item: item,
                    bookmarksManager: bookmarksManager,
                    onEdit: {
                        editingBookmark = item
                    }
                )
            }
        }
        .padding(.vertical, 1)
    }

    public var body: some View {
        HStack(spacing: 5) {
            // Barra separadora única justo donde arrancan los bookmarks
            Divider()
                .frame(height: 18)
                .padding(.trailing, 2)

            if !bookmarksManager.bookmarks.isEmpty {
                // Lista horizontal de marcadores alineada a la derecha (sin hueco vacío a la izquierda)
                ViewThatFits(in: .horizontal) {
                    bookmarksRowContent
                        .fixedSize(horizontal: true, vertical: false)

                    ScrollView(.horizontal, showsIndicators: false) {
                        bookmarksRowContent
                    }
                    .frame(maxWidth: 380)
                }
            }

            // Botón "+" para agregar un nuevo acceso directo / favorito
            Button {
                isShowingAddPopover = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Agregar acceso directo web", en: "Add web bookmark shortcut"))
            .popover(isPresented: $isShowingAddPopover, arrowEdge: .bottom) {
                BookmarkEditorPopoverView(
                    mode: .add,
                    initialTitle: "",
                    initialURL: "https://"
                ) { title, url in
                    bookmarksManager.addBookmark(title: title, urlString: url)
                }
            }
        }
        .padding(.vertical, 2)
        .sheet(item: $editingBookmark) { itemToEdit in
            BookmarkEditorPopoverView(
                mode: .edit,
                initialTitle: itemToEdit.title,
                initialURL: itemToEdit.urlString
            ) { newTitle, newURL in
                bookmarksManager.updateBookmark(itemToEdit.id, title: newTitle, urlString: newURL)
            }
        }
    }
}

// MARK: - Chip Individual de Favorito de Chrome

private struct ChromeBookmarkChipView: View {
    let item: ChromeBookmarkItem
    @Bindable var bookmarksManager: BookmarksManager
    let onEdit: () -> Void

    @ViewState private var isHovered: Bool = false
    @ViewState private var favicon: NSImage? = nil

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var effectiveFavicon: NSImage? {
        bookmarksManager.cachedFavicon(for: item) ?? favicon
    }

    private struct FaviconTaskKey: Equatable {
        let id: UUID
        let urlString: String
        let faviconData: Data?
    }

    var body: some View {
        Button {
            bookmarksManager.openBookmark(item)
        } label: {
            HStack(spacing: 5) {
                if let icon = effectiveFavicon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.09) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: item.urlString) { _, _ in
            favicon = nil
        }
        .task(id: FaviconTaskKey(id: item.id, urlString: item.urlString, faviconData: item.faviconData)) {
            if let cached = bookmarksManager.cachedFavicon(for: item) {
                favicon = cached
            } else if let fetched = await bookmarksManager.fetchFavicon(for: item) {
                favicon = fetched
            } else {
                favicon = nil
            }
        }
        .contextMenu {
            Button {
                bookmarksManager.openBookmark(item, behaviorOverride: .inMacFileExplorer)
            } label: {
                Label(
                    loc.text(es: "Abrir en el mismo MacFileExplorer (Pestaña)", en: "Open inside MacFileExplorer (Tab)"),
                    systemImage: "macwindow.badge.plus"
                )
            }

            Button {
                bookmarksManager.openBookmark(item, behaviorOverride: .inNewChromeWindow)
            } label: {
                Label(
                    loc.text(es: "Abrir en nueva ventana de Google Chrome", en: "Open in new Google Chrome window"),
                    systemImage: "arrow.up.right.square"
                )
            }

            Divider()

            Button {
                onEdit()
            } label: {
                Label(
                    loc.text(es: "Editar marcador...", en: "Edit bookmark..."),
                    systemImage: "pencil"
                )
            }

            Button(role: .destructive) {
                bookmarksManager.removeBookmark(item)
            } label: {
                Label(
                    loc.text(es: "Eliminar marcador", en: "Delete bookmark"),
                    systemImage: "trash"
                )
            }
        }
        .help("\(item.title) — \(item.urlString) (\(bookmarksManager.openBehavior.shortTitle))")
    }
}

// MARK: - Popover / Modal para Agregar o Editar un Marcador

private struct BookmarkEditorPopoverView: View {
    enum Mode {
        case add
        case edit
    }

    let mode: Mode
    @ViewState private var title: String
    @ViewState private var urlString: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    private var loc: LocalizationManager { LocalizationManager.shared }

    init(
        mode: Mode,
        initialTitle: String,
        initialURL: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.mode = mode
        _title = ViewState(initialValue: initialTitle)
        _urlString = ViewState(initialValue: initialURL)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: mode == .add ? "bookmark.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)

                Text(mode == .add
                    ? loc.text(es: "Nuevo acceso directo de Chrome", en: "New Chrome Bookmark Shortcut")
                    : loc.text(es: "Editar marcador", en: "Edit Bookmark")
                )
                .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(loc.text(es: "Nombre", en: "Name"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(loc.text(es: "Ej. GitHub, Jira, YouTube...", en: "e.g. GitHub, Jira, YouTube..."), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("https://...", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        commitSave()
                    }
            }

            HStack {
                Spacer()

                Button(loc.text(es: "Cancelar", en: "Cancel")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(loc.text(es: "Guardar", en: "Save")) {
                    commitSave()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 310)
    }

    private func commitSave() {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        onSave(title, trimmedURL)
        dismiss()
    }
}
