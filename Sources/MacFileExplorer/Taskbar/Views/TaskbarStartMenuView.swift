import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - Panel Flotante del Menú Inicio

@MainActor
private final class TaskbarStartMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
public final class TaskbarStartMenuController: NSObject, NSWindowDelegate {

    public static let shared = TaskbarStartMenuController()

    public var searchQuery: String = ""
    public var selectedAppID: String?

    private var panel: TaskbarStartMenuPanel?
    private var keyMonitor: Any?
    private var currentDisplayID: String?

    private override init() {
        super.init()
    }

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public var panelWindowNumber: Int? {
        panel?.windowNumber
    }

    public func toggle(displayID: String, anchorButtonRect: NSRect) {
        if isVisible && currentDisplayID == displayID {
            close()
        } else {
            show(displayID: displayID, anchorButtonRect: anchorButtonRect)
        }
    }

    public func show(displayID: String, anchorButtonRect: NSRect) {
        TaskbarPreviewPanelController.shared.hideImmediately()
        TaskbarAppCatalogService.shared.refreshCatalogIfNeeded()

        searchQuery = ""
        selectedAppID = nil
        currentDisplayID = displayID
        TaskbarManager.shared.openStartMenuDisplayID = displayID

        let targetPanel = ensurePanel()
        applyAppearance(TaskbarPreferences.shared.themeMode, to: targetPanel)

        let screenFrame = TaskbarWindowTracker.shared.connectedScreens
            .first(where: { $0.id == displayID })?.frameCocoa
            ?? NSScreen.screens.first(where: { $0.frame.contains(anchorButtonRect.origin) })?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let panelSize = NSSize(width: 580, height: min(560, max(420, screenFrame.height - 96)))
        let margin: CGFloat = 8
        let originX = min(max(anchorButtonRect.minX, screenFrame.minX + margin), screenFrame.maxX - panelSize.width - margin)
        let originY = min(anchorButtonRect.maxY + 8, screenFrame.maxY - panelSize.height - margin)

        targetPanel.setFrame(NSRect(x: round(originX), y: round(originY), width: round(panelSize.width), height: round(panelSize.height)), display: true)
        installKeyMonitorIfNeeded()
        NSApplication.shared.activate(ignoringOtherApps: true)
        targetPanel.makeKeyAndOrderFront(nil)
    }

    public func close() {
        removeKeyMonitor()
        panel?.orderOut(nil)
        currentDisplayID = nil
        TaskbarManager.shared.openStartMenuDisplayID = nil
    }

    public func windowDidResignKey(_ notification: Notification) {
        close()
    }

    public func launchApp(_ app: TaskbarInstalledApp) {
        close()
        TaskbarWindowTracker.shared.launchOrFocusApplication(
            bundleIdentifier: app.bundleIdentifier,
            bundleURL: app.bundleURL
        )
    }

    public func launchPinned(_ pinned: TaskbarPinnedApp) {
        close()
        TaskbarWindowTracker.shared.launchOrFocusApplication(
            bundleIdentifier: pinned.bundleIdentifier,
            bundleURL: pinned.bundleURL
        )
    }

    private func ensurePanel() -> TaskbarStartMenuPanel {
        if let existing = panel {
            return existing
        }
        let created = TaskbarStartMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.delegate = self
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.level = .popUpMenu
        created.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        created.contentView = NSHostingView(rootView: TaskbarStartMenuView())
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

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated {
                guard self.isVisible, event.window === self.panel else { return false }
                switch event.keyCode {
                case 53: // Escape
                    self.close()
                    return true
                case 125: // Down arrow
                    self.moveSelection(delta: 1)
                    return true
                case 126: // Up arrow
                    self.moveSelection(delta: -1)
                    return true
                case 36, 76: // Return / Enter
                    return self.launchSelectedSearchMatch()
                default:
                    return false
                }
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func moveSelection(delta: Int) {
        let filtered = TaskbarStartMenuFilter.filter(
            apps: TaskbarAppCatalogService.shared.installedApps,
            query: searchQuery
        )
        guard !filtered.isEmpty else { return }
        if let current = selectedAppID,
           let idx = filtered.firstIndex(where: { $0.id == current }) {
            let nextIdx = min(max(idx + delta, 0), filtered.count - 1)
            selectedAppID = filtered[nextIdx].id
        } else {
            selectedAppID = delta >= 0 ? filtered.first?.id : filtered.last?.id
        }
    }

    private func launchSelectedSearchMatch() -> Bool {
        let filtered = TaskbarStartMenuFilter.filter(
            apps: TaskbarAppCatalogService.shared.installedApps,
            query: searchQuery
        )
        guard !filtered.isEmpty else { return false }
        if let selectedAppID, let found = filtered.first(where: { $0.id == selectedAppID }) {
            launchApp(found)
            return true
        }
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = filtered.first {
            launchApp(first)
            return true
        }
        return false
    }
}

// MARK: - Vista del Menú Inicio Integrado (Buscador + Fijadas + Recientes + Lista Alfabética A–Z)

private struct TaskbarStartMenuView: View {
    @Bindable private var controller = TaskbarStartMenuController.shared
    @Bindable private var catalog = TaskbarAppCatalogService.shared
    @Bindable private var prefs = TaskbarPreferences.shared
    @Bindable private var loc = LocalizationManager.shared
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var trimmedQuery: String {
        controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredApps: [TaskbarInstalledApp] {
        TaskbarStartMenuFilter.filter(apps: catalog.installedApps, query: controller.searchQuery)
    }

    private var groupedAlphabeticalSections: [(letter: String, apps: [TaskbarInstalledApp])] {
        let dict = Dictionary(grouping: catalog.installedApps, by: \.sectionLetter)
        let sortedLetters = dict.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }
        return sortedLetters.map { letter in
            (letter, dict[letter] ?? [])
        }
    }

    private var recentApps: [TaskbarInstalledApp] {
        catalog.recentApps(limit: 6)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Buscador superior
            searchHeader

            Divider()

            // Cuerpo principal
            if !trimmedQuery.isEmpty {
                searchResultsList
            } else {
                HStack(spacing: 0) {
                    leftPinnedAndRecentColumn
                        .frame(width: 220)

                    Divider()

                    rightAlphabeticalAllAppsColumn
                        .frame(maxWidth: .infinity)
                }
            }

            Divider()

            // Pie con accesos rápidos
            footerBar
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: controller.searchQuery) { _, newValue in
            let matches = TaskbarStartMenuFilter.filter(apps: catalog.installedApps, query: newValue)
            controller.selectedAppID = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : matches.first?.id
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(
                loc.text(es: "Buscar aplicaciones instaladas…", en: "Search installed apps…"),
                text: $controller.searchQuery
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .focused($isSearchFocused)

            if !controller.searchQuery.isEmpty {
                Button {
                    controller.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(12)
    }

    private var searchResultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if filteredApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text(loc.text(es: "No se encontraron aplicaciones", en: "No applications found"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
                } else {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredApps) { app in
                            startMenuAppRow(app: app, isHighlighted: controller.selectedAppID == app.id)
                                .id(app.id)
                        }
                    }
                    .padding(10)
                }
            }
            .onChange(of: controller.selectedAppID) { _, newID in
                if let newID {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private var leftPinnedAndRecentColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                // Fijadas
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.text(es: "FIJADAS", en: "PINNED"))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    if prefs.pinnedApps.isEmpty {
                        Text(loc.text(
                            es: "Haz clic derecho en cualquier app para fijarla aquí.",
                            en: "Right-click any app to pin it here."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], spacing: 8) {
                            ForEach(prefs.pinnedApps) { pinned in
                                Button {
                                    controller.launchPinned(pinned)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(nsImage: catalog.icon(forAppAt: pinned.bundleURL))
                                            .resizable()
                                            .interpolation(.high)
                                            .frame(width: 30, height: 30)
                                        Text(pinned.displayName)
                                            .font(.system(size: 10.5))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 4)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(loc.text(es: "Abrir", en: "Open")) {
                                        controller.launchPinned(pinned)
                                    }
                                    Button(loc.text(es: "Desfijar de la barra", en: "Unpin from Taskbar")) {
                                        prefs.unpinApp(bundleIdentifier: pinned.bundleIdentifier, bundlePath: pinned.bundlePath)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                // Recientes
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text(es: "RECIENTES", en: "RECENTLY USED"))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    if recentApps.isEmpty {
                        Text(loc.text(
                            es: "Las apps que abras aparecerán aquí.",
                            en: "Apps you open will appear here."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(recentApps) { app in
                                startMenuAppRow(app: app, isHighlighted: false, compact: true)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var rightAlphabeticalAllAppsColumn: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loc.text(
                                es: "TODAS LAS APLICACIONES (\(catalog.installedApps.count))",
                                en: "ALL APPS (\(catalog.installedApps.count))"
                            ))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)

                            Spacer()

                            if catalog.isScanning {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Button {
                                    catalog.refreshCatalogIfNeeded(force: true)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(loc.text(es: "Actualizar lista de apps", en: "Refresh App List"))
                            }
                        }
                        .padding(.horizontal, 6)

                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(groupedAlphabeticalSections, id: \.letter) { section in
                                Text(section.letter)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 4)
                                    .id("letter-\(section.letter)")

                                ForEach(section.apps) { app in
                                    startMenuAppRow(app: app, isHighlighted: controller.selectedAppID == app.id)
                                }
                            }
                        }
                    }
                    .padding(10)
                }

                // Índice alfabético vertical compacto
                VStack(spacing: 1) {
                    ForEach(groupedAlphabeticalSections, id: \.letter) { section in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("letter-\(section.letter)", anchor: .top)
                            }
                        } label: {
                            Text(section.letter)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 13)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 4)
                .padding(.vertical, 8)
            }
        }
    }

    private func startMenuAppRow(
        app: TaskbarInstalledApp,
        isHighlighted: Bool,
        compact: Bool = false
    ) -> some View {
        let isPinned = prefs.isPinned(bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundleURL.path(percentEncoded: false))

        return Button {
            controller.launchApp(app)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: catalog.icon(forAppAt: app.bundleURL))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)

                Text(app.name)
                    .font(.system(size: compact ? 12 : 12.5))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(loc.text(es: "Abrir", en: "Open")) {
                controller.launchApp(app)
            }
            Divider()
            Button(isPinned
                   ? loc.text(es: "Desfijar de la barra de tareas", en: "Unpin from Taskbar")
                   : loc.text(es: "Fijar en la barra de tareas", en: "Pin to Taskbar")) {
                if isPinned {
                    prefs.unpinApp(bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundleURL.path(percentEncoded: false))
                } else {
                    prefs.pinApp(bundleIdentifier: app.bundleIdentifier, bundleURL: app.bundleURL, displayName: app.name)
                }
            }
            Divider()
            Button(loc.text(es: "Abrir carpeta contenedora en MacFileExplorer", en: "Reveal in MacFileExplorer")) {
                controller.close()
                GoogleAccountsManager.shared.openOrFocusMainWindow(at: app.bundleURL.deletingLastPathComponent())
            }
            Button(loc.text(es: "Mostrar en Finder", en: "Reveal in Finder")) {
                controller.close()
                NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Button {
                controller.close()
                GoogleAccountsManager.shared.openOrFocusMainWindow(at: FileManager.default.homeDirectoryForCurrentUser)
            } label: {
                Label(loc.text(es: "Archivos", en: "Files"), systemImage: "folder")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)

            Button {
                controller.close()
                if let url = URL(string: "x-apple.systempreferences:") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(loc.text(es: "Ajustes de macOS", en: "System Settings"), systemImage: "gearshape")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                controller.close()
                TaskbarSettingsWindowController.shared.show()
            } label: {
                Label(loc.text(es: "Configurar barra…", en: "Taskbar Settings…"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.03))
    }
}
