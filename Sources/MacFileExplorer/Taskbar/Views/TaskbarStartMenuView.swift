import AppKit
import Foundation
import Observation
import QuartzCore
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

    /// Márgenes transparentes alrededor de la tarjeta del Menú Inicio para que las sombras suaves,
    /// el rebote tipo gelatina, el giro 3D y el genio giratorio jamás se recorten contra el borde del `NSPanel`.
    public static let panelHorizontalInset: CGFloat = 26
    public static let panelTopInset: CGFloat = 28
    public static let panelBottomInset: CGFloat = 20

    public var searchQuery: String = ""
    public var selectedAppID: String?
    public private(set) var activeAnimationStyle: TaskbarStartMenuAnimation = .riseFromBar
    public private(set) var animationProgress: Double = 1.0
    public private(set) var menuContentSize: NSSize = NSSize(width: 580, height: 540)
    public private(set) var presentationToken: UInt64 = 0

    private var panel: TaskbarStartMenuPanel?
    private var keyMonitor: Any?
    private var currentDisplayID: String?
    private var animationTask: Task<Void, Never>?
    private var isClosingWithAnimation: Bool = false

    private override init() {
        super.init()
    }

    public var isVisible: Bool {
        panel?.isVisible == true && !isClosingWithAnimation
    }

    public var panelWindowNumber: Int? {
        panel?.windowNumber
    }

    public func toggle(displayID: String, anchorButtonRect: NSRect) {
        if isVisible && currentDisplayID == displayID {
            close(animated: true)
        } else {
            show(displayID: displayID, anchorButtonRect: anchorButtonRect)
        }
    }

    /// Permite probar en vivo la animación y velocidad actuales desde la ventana de Configuración.
    public func showLivePreviewFromSettings() {
        let screens = TaskbarWindowTracker.shared.connectedScreens
        let targetScreen = screens.first(where: \.isMain) ?? screens.first
        let displayID = targetScreen?.id ?? "main"
        let screenFrame = targetScreen?.frameCocoa ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let barHeight = CGFloat(TaskbarPreferences.shared.barHeight)
        let anchorRect = NSRect(x: screenFrame.minX + 10, y: screenFrame.minY, width: 38, height: barHeight)
        if isVisible {
            close(animated: false)
        }
        show(displayID: displayID, anchorButtonRect: anchorRect)
    }

    public func show(displayID: String, anchorButtonRect: NSRect) {
        TaskbarPreviewPanelController.shared.hideImmediately()
        TaskbarAppCatalogService.shared.refreshCatalogIfNeeded()

        animationTask?.cancel()
        animationTask = nil
        isClosingWithAnimation = false

        let prefs = TaskbarPreferences.shared
        let style = prefs.startMenuAnimation
        let duration = prefs.startMenuAnimationDuration

        searchQuery = ""
        selectedAppID = nil
        currentDisplayID = displayID
        activeAnimationStyle = style
        TaskbarManager.shared.openStartMenuDisplayID = displayID

        let targetPanel = ensurePanel()
        applyAppearance(prefs.themeMode, to: targetPanel)

        let screenFrame = TaskbarWindowTracker.shared.connectedScreens
            .first(where: { $0.id == displayID })?.frameCocoa
            ?? NSScreen.screens.first(where: { $0.frame.contains(anchorButtonRect.origin) })?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let contentSize = NSSize(width: 580, height: min(560, max(420, screenFrame.height - 96)))
        menuContentSize = contentSize

        let margin: CGFloat = 8
        let desiredMenuX = min(max(anchorButtonRect.minX, screenFrame.minX + margin), screenFrame.maxX - contentSize.width - margin)
        let desiredMenuY = min(anchorButtonRect.maxY + 8, screenFrame.maxY - contentSize.height - margin)

        let totalW = contentSize.width + (Self.panelHorizontalInset * 2)
        let totalH = contentSize.height + Self.panelTopInset + Self.panelBottomInset
        let panelOriginX = desiredMenuX - Self.panelHorizontalInset
        let panelOriginY = desiredMenuY - Self.panelBottomInset

        if duration <= 0.001 {
            // Modo 0 ms: apertura 100% instantánea sin animación ni tareas de frame
            animationProgress = 1.0
        } else {
            animationProgress = 0.0
        }

        targetPanel.setFrame(
            NSRect(x: round(panelOriginX), y: round(panelOriginY), width: round(totalW), height: round(totalH)),
            display: true
        )
        targetPanel.contentView?.layoutSubtreeIfNeeded()
        presentationToken &+= 1
        installKeyMonitorIfNeeded()
        NSApplication.shared.activate(ignoringOtherApps: true)
        targetPanel.makeKeyAndOrderFront(nil)

        if duration > 0.001 {
            startOneShotAnimation(from: 0.0, to: 1.0, duration: duration, orderOutOnFinish: false)
        }
    }

    public func close(animated: Bool = false) {
        removeKeyMonitor()
        currentDisplayID = nil
        TaskbarManager.shared.openStartMenuDisplayID = nil

        let duration = TaskbarPreferences.shared.startMenuAnimationDuration
        guard animated,
              panel?.isVisible == true,
              duration > 0.001,
              !isClosingWithAnimation else {
            animationTask?.cancel()
            animationTask = nil
            isClosingWithAnimation = false
            animationProgress = 1.0
            panel?.orderOut(nil)
            return
        }

        isClosingWithAnimation = true
        let closeDuration = min(max(duration * 0.55, 0.08), 0.18)
        startOneShotAnimation(from: animationProgress, to: 0.0, duration: closeDuration, orderOutOnFinish: true)
    }

    private func startOneShotAnimation(from startValue: Double, to endValue: Double, duration: Double, orderOutOnFinish: Bool) {
        animationTask?.cancel()
        let safeDuration = max(0.016, duration)
        let startTime = CACurrentMediaTime()

        animationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = CACurrentMediaTime() - startTime
                let rawT = min(1.0, max(0.0, elapsed / safeDuration))
                self.animationProgress = startValue + (endValue - startValue) * rawT

                if rawT >= 1.0 {
                    self.animationProgress = endValue
                    self.animationTask = nil
                    if orderOutOnFinish {
                        self.isClosingWithAnimation = false
                        self.panel?.orderOut(nil)
                    }
                    return
                }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    public func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        close(animated: true)
    }

    public func launchApp(_ app: TaskbarInstalledApp) {
        close(animated: false)
        TaskbarWindowTracker.shared.launchOrFocusApplication(
            bundleIdentifier: app.bundleIdentifier,
            bundleURL: app.bundleURL
        )
    }

    public func launchPinned(_ pinned: TaskbarPinnedApp) {
        close(animated: false)
        TaskbarWindowTracker.shared.launchOrFocusApplication(
            bundleIdentifier: pinned.bundleIdentifier,
            bundleURL: pinned.bundleURL
        )
    }

    private func ensurePanel() -> TaskbarStartMenuPanel {
        if let existing = panel {
            return existing
        }
        let initialW = 580 + (Self.panelHorizontalInset * 2)
        let initialH = 540 + Self.panelTopInset + Self.panelBottomInset
        let created = TaskbarStartMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialW, height: initialH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.delegate = self
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        // La sombra se dibuja sobre la tarjeta animada para que acompañe la escala, giro 3D y rebote sin ghosting
        created.hasShadow = false
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
                    self.close(animated: true)
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

    private var animationAnchor: UnitPoint {
        switch controller.activeAnimationStyle {
        case .springPop, .jellyBounce, .twirlGenie:
            return .bottomLeading
        case .spotlightFocus:
            return .center
        case .fadeLift, .riseFromBar, .flipReveal, .executiveCurtain:
            return .bottom
        }
    }

    var body: some View {
        let motion = controller.activeAnimationStyle.evaluate(
            progress: controller.animationProgress,
            motionScale: 1.0
        )
        let contentSize = controller.menuContentSize
        let totalW = contentSize.width + (TaskbarStartMenuController.panelHorizontalInset * 2)
        let totalH = contentSize.height + TaskbarStartMenuController.panelTopInset + TaskbarStartMenuController.panelBottomInset

        ZStack(alignment: .bottom) {
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
            .frame(width: contentSize.width, height: contentSize.height)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .clipShape(
                StartMenuCurtainClipShape(
                    hiddenTopFraction: motion.clipTopFraction,
                    cornerRadius: 14
                )
            )
            .overlay(
                StartMenuCurtainClipShape(
                    hiddenTopFraction: motion.clipTopFraction,
                    cornerRadius: 14
                )
                .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.50 : 0.22),
                radius: 14,
                x: 0,
                y: 6
            )
            .blur(radius: motion.blurRadius > 0.05 ? motion.blurRadius : 0)
            .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: animationAnchor)
            .rotationEffect(.degrees(motion.rotationZ), anchor: animationAnchor)
            .rotation3DEffect(
                .degrees(motion.rotationX),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                perspective: 0.48
            )
            .offset(x: motion.offsetX, y: motion.offsetY)
            .opacity(motion.opacity)
            .padding(.bottom, TaskbarStartMenuController.panelBottomInset)
        }
        .frame(width: totalW, height: totalH, alignment: .bottom)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: controller.presentationToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
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

// MARK: - Forma de Cortina para Animación "Cortina Ejecutiva"

private struct StartMenuCurtainClipShape: Shape {
    var hiddenTopFraction: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(hiddenTopFraction, 0), 0.995)
        let topCut = rect.height * clamped
        let visibleRect = CGRect(
            x: rect.minX,
            y: rect.minY + topCut,
            width: rect.width,
            height: max(1, rect.height - topCut)
        )
        return Path(roundedRect: visibleRect, cornerRadius: min(cornerRadius, visibleRect.height * 0.5))
    }
}

// MARK: - Tarjeta de Previsualización en Vivo para Configuración (8 Animaciones del Menú Inicio)

/// Tarjeta interactiva con una mini barra de tareas, botón Inicio iluminado y un mini Menú Inicio
/// que demuestra en vivo cada una de las 8 animaciones y refleja la duración elegida (`0 ms` = instantáneo).
public struct TaskbarStartMenuAnimationCard: View {
    public let style: TaskbarStartMenuAnimation
    public let duration: Double
    public let isSelected: Bool
    public let previewDark: Bool
    public let timelineDate: Date
    public let onSelect: () -> Void

    @Bindable private var loc = LocalizationManager.shared

    public init(
        style: TaskbarStartMenuAnimation,
        duration: Double,
        isSelected: Bool,
        previewDark: Bool,
        timelineDate: Date,
        onSelect: @escaping () -> Void
    ) {
        self.style = style
        self.duration = duration
        self.isSelected = isSelected
        self.previewDark = previewDark
        self.timelineDate = timelineDate
        self.onSelect = onSelect
    }

    private var previewAnchor: UnitPoint {
        switch style {
        case .springPop, .jellyBounce, .twirlGenie:
            return .bottomLeading
        case .spotlightFocus:
            return .center
        case .fadeLift, .riseFromBar, .flipReveal, .executiveCurtain:
            return .bottom
        }
    }

    private var previewState: (frame: TaskbarStartMenuMotionFrame, startButtonActive: Bool) {
        let enterDur = max(0.0, duration)
        let holdDur: Double = 1.10
        let exitDur: Double = enterDur <= 0.001 ? 0.0 : min(max(enterDur * 0.55, 0.14), 0.24)
        let pauseDur: Double = 0.55
        let cycle = max(1.85, enterDur + holdDur + exitDur + pauseDur)

        let rawT = timelineDate.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        let t = rawT >= 0 ? rawT : (rawT + cycle)

        if enterDur <= 0.001 {
            // Demuestra fielmente la apertura 100% instantánea (0 ms)
            if t < holdDur {
                return (.identity, true)
            } else {
                return (TaskbarStartMenuMotionFrame(opacity: 0), false)
            }
        }

        if t < enterDur {
            let p = max(0.0, min(1.0, t / enterDur))
            return (style.evaluate(progress: p, motionScale: 0.42), true)
        } else if t < (enterDur + holdDur) {
            return (.identity, true)
        } else if t < (enterDur + holdDur + exitDur) {
            let p = max(0.0, min(1.0, 1.0 - (t - enterDur - holdDur) / exitDur))
            return (style.evaluate(progress: p, motionScale: 0.42), true)
        } else {
            return (TaskbarStartMenuMotionFrame(opacity: 0), false)
        }
    }

    private var categoryBadgeColor: Color {
        switch style.category {
        case .classic: return .secondary
        case .professional: return .indigo
        case .fun: return .pink
        }
    }

    public var body: some View {
        let state = previewState
        let motion = state.frame

        Button(action: onSelect) {
            VStack(spacing: 6) {
                // Encabezado compacto: categoría (Clásica / Pro / Divertida) + tilde de selección sin tapar la animación
                HStack(spacing: 4) {
                    if let badge = style.category.localizedBadge(using: loc) {
                        Text(badge)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(categoryBadgeColor)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(categoryBadgeColor.opacity(0.16), in: Capsule())
                    } else {
                        Text(loc.text(es: "Clásica", en: "Classic"))
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Color.clear
                            .frame(width: 12.5, height: 12.5)
                    }
                }

                // Escenario miniatura: mini Menú Inicio sobre mini barra con botón Inicio
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(previewDark ? Color(white: 0.13) : Color(white: 0.93))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(
                                    previewDark ? Color.white.opacity(0.09) : Color.black.opacity(0.08),
                                    lineWidth: 0.75
                                )
                        )

                    // Mini Menú Inicio desplegándose desde arriba del botón Inicio
                    VStack(spacing: 3) {
                        // Mini barra de búsqueda
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(previewDark ? Color.white.opacity(0.14) : Color.black.opacity(0.09))
                            .frame(height: 5.5)

                        // Mini 2 columnas: fijadas (izquierda) + lista (derecha)
                        HStack(spacing: 3) {
                            VStack(spacing: 2.5) {
                                HStack(spacing: 2.5) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.75)).frame(width: 7, height: 7)
                                    RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.75)).frame(width: 7, height: 7)
                                }
                                HStack(spacing: 2.5) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.75)).frame(width: 7, height: 7)
                                    RoundedRectangle(cornerRadius: 2).fill(Color.purple.opacity(0.75)).frame(width: 7, height: 7)
                                }
                            }
                            .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2.5) {
                                RoundedRectangle(cornerRadius: 1.5).fill(previewDark ? Color.white.opacity(0.38) : Color.black.opacity(0.28)).frame(height: 2.5)
                                RoundedRectangle(cornerRadius: 1.5).fill(previewDark ? Color.white.opacity(0.24) : Color.black.opacity(0.18)).frame(width: 24, height: 2.5)
                                RoundedRectangle(cornerRadius: 1.5).fill(previewDark ? Color.white.opacity(0.24) : Color.black.opacity(0.18)).frame(width: 19, height: 2.5)
                                RoundedRectangle(cornerRadius: 1.5).fill(previewDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)).frame(width: 22, height: 2.5)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(4.5)
                    .frame(width: 62, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(previewDark ? Color(white: 0.24) : Color.white)
                    )
                    .clipShape(
                        StartMenuCurtainClipShape(
                            hiddenTopFraction: motion.clipTopFraction,
                            cornerRadius: 6
                        )
                    )
                    .overlay(
                        StartMenuCurtainClipShape(
                            hiddenTopFraction: motion.clipTopFraction,
                            cornerRadius: 6
                        )
                        .stroke(previewDark ? Color.white.opacity(0.22) : Color.black.opacity(0.14), lineWidth: 0.7)
                    )
                    .shadow(color: .black.opacity(previewDark ? 0.42 : 0.16), radius: 4, y: 2)
                    .blur(radius: motion.blurRadius > 0.1 ? motion.blurRadius * 0.45 : 0)
                    .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: previewAnchor)
                    .rotationEffect(.degrees(motion.rotationZ), anchor: previewAnchor)
                    .rotation3DEffect(
                        .degrees(motion.rotationX),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .bottom,
                        perspective: 0.48
                    )
                    .offset(x: 9 + motion.offsetX, y: -18 + motion.offsetY)
                    .opacity(motion.opacity)

                    // Mini barra de tareas en el borde inferior
                    HStack(spacing: 4) {
                        // Mini botón Inicio a la izquierda
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(state.startButtonActive ? Color.accentColor : (previewDark ? Color.white.opacity(0.24) : Color.black.opacity(0.20)))
                            .frame(width: 10, height: 9)

                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(previewDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10))
                            .frame(width: 22, height: 7)

                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(previewDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08))
                            .frame(width: 18, height: 7)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 15)
                    .frame(maxWidth: .infinity)
                    .background(previewDark ? Color(white: 0.08) : Color(white: 0.85))
                }
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(spacing: 1.5) {
                    Text(style.localizedTitle(using: loc))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(style.localizedSubtitle(using: loc))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
