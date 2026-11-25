import AppKit
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Panel HUD Reutilizable Pre-Asignado (< 16 ms al abrir)

@MainActor
private final class AltTabSwitcherNSPanel: NSPanel {
    var allowsKeyFocus: Bool = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class AltTabSwitcherPanelController {

    public static let shared = AltTabSwitcherPanelController()

    private var panel: AltTabSwitcherNSPanel?
    private var globalClickMonitor: Any?
    private var lastShownMouseLocation: NSPoint = .zero
    public private(set) var hasMouseMovedSinceOpen: Bool = false

    private init() {}

    public var panelWindowNumber: Int? {
        panel?.windowNumber
    }

    public func prewarmPanel() {
        _ = ensurePanel()
    }

    public func show(
        metrics: AltTabLayoutMetrics,
        targetScreenFrameCocoa: NSRect,
        activateForSearch: Bool
    ) {
        let targetPanel = ensurePanel()
        applyAppearance(AltTabPreferences.shared.themeMode, to: targetPanel)
        targetPanel.allowsKeyFocus = activateForSearch

        lastShownMouseLocation = NSEvent.mouseLocation
        hasMouseMovedSinceOpen = false

        updateFrame(metrics: metrics, targetScreenFrameCocoa: targetScreenFrameCocoa)
        installGlobalClickOutsideMonitor()

        if activateForSearch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            targetPanel.makeKeyAndOrderFront(nil)
        } else {
            targetPanel.orderFrontRegardless()
        }
    }

    public func makeKeyForSearch() {
        guard let panel, panel.isVisible else { return }
        panel.allowsKeyFocus = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func updateFrame(metrics: AltTabLayoutMetrics, targetScreenFrameCocoa: NSRect) {
        guard let panel else { return }
        let x = targetScreenFrameCocoa.midX - (metrics.panelWidth / 2)
        let y = targetScreenFrameCocoa.midY - (metrics.panelHeight / 2)
        let rect = NSRect(
            x: round(x),
            y: round(y),
            width: round(metrics.panelWidth),
            height: round(metrics.panelHeight)
        )
        if panel.frame != rect {
            panel.setFrame(rect, display: true)
        }
    }

    public func hide() {
        removeGlobalClickOutsideMonitor()
        panel?.allowsKeyFocus = false
        panel?.orderOut(nil)
    }

    /// Verifica si el cursor realmente se movió > 5 pt desde que se abrió el HUD para no pisar la selección por teclado.
    public func checkMouseMovementFromOpen() -> Bool {
        if hasMouseMovedSinceOpen { return true }
        let current = NSEvent.mouseLocation
        if hypot(current.x - lastShownMouseLocation.x, current.y - lastShownMouseLocation.y) > 5 {
            hasMouseMovedSinceOpen = true
            return true
        }
        return false
    }

    private func ensurePanel() -> AltTabSwitcherNSPanel {
        if let existing = panel {
            return existing
        }
        let created = AltTabSwitcherNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.acceptsMouseMovedEvents = true
        created.level = .popUpMenu
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        created.contentView = NSHostingView(rootView: AltTabSwitcherHUDView())
        panel = created
        return created
    }

    private func applyAppearance(_ themeMode: TaskbarThemeMode, to panel: NSPanel) {
        switch themeMode {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func installGlobalClickOutsideMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let mouseLoc = NSEvent.mouseLocation
                if !panel.frame.contains(mouseLoc) {
                    AltTabManager.shared.cancelSwitcher()
                }
            }
        }
    }

    private func removeGlobalClickOutsideMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}

// MARK: - Vista Principal del Selector HUD (3 Estilos + Auto-Size + Búsqueda + Badges de Space/Estado)

private struct AltTabSwitcherHUDView: View {
    @Bindable private var manager = AltTabManager.shared
    @Bindable private var prefs = AltTabPreferences.shared
    @Bindable private var thumbs = TaskbarThumbnailService.shared
    @Bindable private var loc = LocalizationManager.shared
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = thumbs.cacheRevision // Observar actualizaciones de caché en vivo

        VStack(spacing: 0) {
            if manager.isSearchActive || prefs.showSearchBar {
                searchBarHeader
                Divider().opacity(0.5)
            }

            if manager.displayedWindows.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: manager.displayedWindows.count > 12) {
                        Group {
                            switch prefs.displayStyle {
                            case .thumbnails:
                                thumbnailsGridView
                            case .appIcons:
                                appIconsGridView
                            case .titlesList:
                                titlesListView
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: manager.selectedIndex) { _, newIdx in
                        if newIdx >= 0, newIdx < manager.displayedWindows.count {
                            withAnimation(.easeOut(duration: 0.08)) {
                                proxy.scrollTo(manager.displayedWindows[newIdx].id, anchor: .center)
                            }
                        }
                    }
                }
            }

            if prefs.displayStyle == .appIcons, let selected = manager.selectedWindow {
                selectedTitleBanner(for: selected)
            }

            Divider().opacity(0.4)
            footerHintsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14), lineWidth: 1)
        )
        .onChange(of: manager.isSearchActive) { _, active in
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    isSearchFocused = true
                }
            }
        }
    }

    // MARK: - Buscador Superior Opcional

    private var searchBarHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                loc.text(es: "Buscar ventana o aplicación…", en: "Search window or app…"),
                text: $manager.searchQuery
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .focused($isSearchFocused)

            if !manager.searchQuery.isEmpty {
                Button {
                    manager.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let profile = manager.activeProfile {
                Text(profile.displayString)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(loc.text(es: "No hay ventanas que coincidan", en: "No matching windows"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Estilo 1: Miniaturas (`thumbnails`)

    private var thumbnailsGridView: some View {
        let cols = Array(
            repeating: GridItem(.fixed(manager.layoutMetrics.cellWidth), spacing: 12),
            count: max(1, manager.layoutMetrics.columns)
        )
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(Array(manager.displayedWindows.enumerated()), id: \.element.id) { index, item in
                AltTabThumbnailCardView(
                    item: item,
                    width: manager.layoutMetrics.cellWidth,
                    height: manager.layoutMetrics.cellHeight,
                    isSelected: index == manager.selectedIndex,
                    thumbnail: thumbs.cachedThumbnail(for: item.windowID),
                    showSpaceBadges: prefs.showSpaceBadges,
                    showStateBadges: prefs.showWindowStateBadges,
                    showHoverQuickActions: prefs.showHoverQuickActions,
                    onHoverSelect: {
                        if AltTabSwitcherPanelController.shared.checkMouseMovementFromOpen() {
                            manager.selectWindow(at: index, confirmImmediately: false)
                        }
                    },
                    onConfirm: {
                        manager.selectWindow(at: index, confirmImmediately: true)
                    }
                )
                .id(item.id)
            }
        }
    }

    // MARK: - Estilo 2: Íconos de Aplicación (`appIcons`)

    private var appIconsGridView: some View {
        let cols = Array(
            repeating: GridItem(.fixed(manager.layoutMetrics.cellWidth), spacing: 12),
            count: max(1, manager.layoutMetrics.columns)
        )
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(Array(manager.displayedWindows.enumerated()), id: \.element.id) { index, item in
                AltTabAppIconCardView(
                    item: item,
                    width: manager.layoutMetrics.cellWidth,
                    height: manager.layoutMetrics.cellHeight,
                    isSelected: index == manager.selectedIndex,
                    showSpaceBadges: prefs.showSpaceBadges,
                    showStateBadges: prefs.showWindowStateBadges,
                    onHoverSelect: {
                        if AltTabSwitcherPanelController.shared.checkMouseMovementFromOpen() {
                            manager.selectWindow(at: index, confirmImmediately: false)
                        }
                    },
                    onConfirm: {
                        manager.selectWindow(at: index, confirmImmediately: true)
                    }
                )
                .id(item.id)
            }
        }
    }

    private func selectedTitleBanner(for item: TaskbarWindowItem) -> some View {
        HStack(spacing: 8) {
            Text(item.appName)
                .font(.system(size: 12.5, weight: .bold))
            Text("—")
                .foregroundStyle(.tertiary)
            Text(item.displayTitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            AltTabStatusBadgesRow(
                item: item,
                showSpaceBadges: prefs.showSpaceBadges,
                showStateBadges: prefs.showWindowStateBadges
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - Estilo 3: Lista Compacta de Títulos (`titlesList`)

    private var titlesListView: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(manager.displayedWindows.enumerated()), id: \.element.id) { index, item in
                AltTabTitleListRowView(
                    item: item,
                    rowHeight: manager.layoutMetrics.cellHeight,
                    isSelected: index == manager.selectedIndex,
                    showSpaceBadges: prefs.showSpaceBadges,
                    showStateBadges: prefs.showWindowStateBadges,
                    showHoverQuickActions: prefs.showHoverQuickActions,
                    onHoverSelect: {
                        if AltTabSwitcherPanelController.shared.checkMouseMovementFromOpen() {
                            manager.selectWindow(at: index, confirmImmediately: false)
                        }
                    },
                    onConfirm: {
                        manager.selectWindow(at: index, confirmImmediately: true)
                    }
                )
                .id(item.id)
            }
        }
    }

    // MARK: - Pie con Ayudas Rápidas y Selector de Estilo en Vivo

    private var footerHintsBar: some View {
        HStack(spacing: 12) {
            Text(loc.text(
                es: "W Cerrar · M Minimizar · H Ocultar · F Pantalla completa · / Buscar · Esc Cancelar",
                en: "W Close · M Minimize · H Hide · F Fullscreen · / Search · Esc Cancel"
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 4)

            // Cambio rápido de estilo en 1 clic
            HStack(spacing: 4) {
                ForEach(AltTabDisplayStyle.allCases) { style in
                    Button {
                        prefs.displayStyle = style
                        manager.refilterCurrentSession(preserveSelectionID: manager.selectedWindow?.id)
                    } label: {
                        Image(systemName: style.systemImage)
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 22, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(prefs.displayStyle == style ? Color.accentColor.opacity(0.22) : Color.clear)
                            )
                            .foregroundStyle(prefs.displayStyle == style ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(style.localizedTitle(using: loc))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
    }
}

// MARK: - Tarjeta de Miniatura

private struct AltTabThumbnailCardView: View {
    let item: TaskbarWindowItem
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let thumbnail: NSImage?
    let showSpaceBadges: Bool
    let showStateBadges: Bool
    let showHoverQuickActions: Bool
    let onHoverSelect: () -> Void
    let onConfirm: () -> Void

    @ViewState private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Cabecera: ícono + título + badges
            HStack(spacing: 6) {
                Image(nsImage: TaskbarAppCatalogService.shared.icon(
                    forBundleIdentifier: item.bundleIdentifier,
                    fallbackURL: item.appBundleURL
                ))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)

                Text(item.displayTitle)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                AltTabStatusBadgesRow(
                    item: item,
                    showSpaceBadges: showSpaceBadges,
                    showStateBadges: showStateBadges,
                    compact: true
                )
            }
            .padding(.horizontal, 8)
            .frame(height: 28)

            // Cuerpo: miniatura en vivo o ícono grande elegante
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity((item.isMinimized || item.isAppHidden) ? 0.68 : 1.0)
                    } else {
                        VStack(spacing: 6) {
                            Image(nsImage: TaskbarAppCatalogService.shared.icon(
                                forBundleIdentifier: item.bundleIdentifier,
                                fallbackURL: item.appBundleURL
                            ))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 44, height: 44)
                            .opacity((item.isMinimized || item.isAppHidden) ? 0.65 : 1.0)
                            Text(item.appName)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)

                if showHoverQuickActions && (isHovered || isSelected) {
                    AltTabHoverQuickActions(item: item)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16)
                        : Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2.2 : 0.75
                )
        )
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
            if inside {
                onHoverSelect()
            }
        }
        .onTapGesture {
            onConfirm()
        }
    }
}

// MARK: - Tarjeta de Ícono de Aplicación

private struct AltTabAppIconCardView: View {
    let item: TaskbarWindowItem
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let showSpaceBadges: Bool
    let showStateBadges: Bool
    let onHoverSelect: () -> Void
    let onConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: TaskbarAppCatalogService.shared.icon(
                    forBundleIdentifier: item.bundleIdentifier,
                    fallbackURL: item.appBundleURL
                ))
                .resizable()
                .interpolation(.high)
                .frame(width: min(64, width * 0.56), height: min(64, width * 0.56))
                .opacity((item.isMinimized || item.isAppHidden) ? 0.58 : 1.0)

                AltTabStatusBadgesRow(
                    item: item,
                    showSpaceBadges: showSpaceBadges,
                    showStateBadges: showStateBadges,
                    compact: true
                )
                .offset(x: 6, y: -4)
            }

            Text(item.displayTitle)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { onHoverSelect() }
        }
        .onTapGesture {
            onConfirm()
        }
    }
}

// MARK: - Fila de Lista Compacta de Títulos

private struct AltTabTitleListRowView: View {
    let item: TaskbarWindowItem
    let rowHeight: CGFloat
    let isSelected: Bool
    let showSpaceBadges: Bool
    let showStateBadges: Bool
    let showHoverQuickActions: Bool
    let onHoverSelect: () -> Void
    let onConfirm: () -> Void

    @ViewState private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: TaskbarAppCatalogService.shared.icon(
                forBundleIdentifier: item.bundleIdentifier,
                fallbackURL: item.appBundleURL
            ))
            .resizable()
            .interpolation(.high)
            .frame(width: 22, height: 22)
            .opacity((item.isMinimized || item.isAppHidden) ? 0.58 : 1.0)

            Text(item.appName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if item.displayTitle != item.appName {
                Text(item.displayTitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            AltTabStatusBadgesRow(
                item: item,
                showSpaceBadges: showSpaceBadges,
                showStateBadges: showStateBadges,
                compact: false
            )

            if showHoverQuickActions && (isHovered || isSelected) {
                AltTabHoverQuickActions(item: item)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.85) : Color.clear, lineWidth: 1.4)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
            if inside { onHoverSelect() }
        }
        .onTapGesture {
            onConfirm()
        }
    }
}

// MARK: - Badges de Estado y Space + Acciones Rápidas Hover

struct AltTabStatusBadgesRow: View {
    let item: TaskbarWindowItem
    let showSpaceBadges: Bool
    let showStateBadges: Bool
    var compact: Bool = false

    @Bindable private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 4) {
            if showSpaceBadges {
                if let spaceNum = item.spaceIndex, !item.isOnActiveSpace {
                    badgePill(
                        text: compact ? "S\(spaceNum)" : "Space \(spaceNum)",
                        icon: "squares.leading.rectangle",
                        color: .blue
                    )
                } else if !item.isOnActiveSpace && !item.isMinimized && !item.isAppHidden {
                    badgePill(
                        text: compact ? "S+" : loc.text(es: "Otro Space", en: "Other Space"),
                        icon: "squares.leading.rectangle",
                        color: .blue
                    )
                }
            }

            if showStateBadges {
                if item.isMinimized {
                    badgePill(
                        text: compact ? "Min" : loc.text(es: "Minimizada", en: "Minimized"),
                        icon: "minus.circle.fill",
                        color: .orange
                    )
                } else if item.isAppHidden {
                    badgePill(
                        text: compact ? "Hid" : loc.text(es: "Oculta", en: "Hidden"),
                        icon: "eye.slash.fill",
                        color: .purple
                    )
                } else if item.isFullScreen {
                    badgePill(
                        text: compact ? "FS" : loc.text(es: "Completa", en: "Full Screen"),
                        icon: "arrow.up.left.and.arrow.down.right",
                        color: .green
                    )
                }
            }
        }
    }

    private func badgePill(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 2.5) {
            if !compact {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(color.opacity(0.16), in: Capsule())
    }
}

private struct AltTabHoverQuickActions: View {
    let item: TaskbarWindowItem
    @Bindable private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 4) {
            quickDot(color: Color(red: 1.0, green: 0.37, blue: 0.34), symbol: "xmark") {
                AltTabManager.shared.closeWindowFromSwitcher(item)
            }
            .help(loc.text(es: "Cerrar ventana (W)", en: "Close Window (W)"))

            quickDot(color: Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus") {
                AltTabManager.shared.minimizeWindowFromSwitcher(item)
            }
            .help(loc.text(es: "Minimizar / Restaurar (M)", en: "Minimize / Restore (M)"))

            quickDot(color: Color(red: 0.16, green: 0.79, blue: 0.25), symbol: "arrow.up.left.and.arrow.down.right") {
                AltTabManager.shared.toggleFullScreenFromSwitcher(item)
            }
            .help(loc.text(es: "Alternar pantalla completa (F)", en: "Toggle Full Screen (F)"))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func quickDot(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Image(systemName: symbol)
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}
