import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Panel Flotante de Barra de Tareas (`NSPanel` no activable)

@MainActor
public final class TaskbarPanel: NSPanel {
    public let displayID: String

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(displayID: String, contentRect: NSRect) {
        self.displayID = displayID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.tabbingMode = .disallowed
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false
        // Nivel Dock - 1: por encima de ventanas normales, pero por debajo de menús contextuales y popups
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    public func applyThemeAppearance(_ themeMode: TaskbarThemeMode) {
        switch themeMode {
        case .system:
            self.appearance = nil
        case .light:
            self.appearance = NSAppearance(named: .aqua)
        case .dark:
            self.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Material Translúcido Nativo de Fondo

private struct TaskbarVisualEffectBackground: NSViewRepresentable {
    let themeMode: TaskbarThemeMode
    let opacity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.state = .active
        nsView.alphaValue = CGFloat(min(max(opacity, 0.25), 1.0))
        switch themeMode {
        case .system:
            nsView.appearance = nil
        case .light:
            nsView.appearance = NSAppearance(named: .aqua)
        case .dark:
            nsView.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Vista Principal de la Barra de Tareas

public struct TaskbarBarView: View {
    public let displayID: String

    @Bindable private var prefs = TaskbarPreferences.shared
    @Bindable private var tracker = TaskbarWindowTracker.shared
    @Bindable private var manager = TaskbarManager.shared
    @Bindable private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var systemColorScheme

    @ViewState private var isDropTargeted = false
    @ViewState private var isStartButtonHovered = false
    @ViewState private var isStartButtonPressed = false

    public init(displayID: String) {
        self.displayID = displayID
    }

    private var effectiveDark: Bool {
        switch prefs.themeMode {
        case .system: return systemColorScheme == .dark
        case .light: return false
        case .dark: return true
        }
    }

    private var barTintColor: Color {
        effectiveDark
            ? Color(white: 0.11).opacity(prefs.opacity * 0.72)
            : Color(white: 0.94).opacity(prefs.opacity * 0.76)
    }

    private var topBorderColor: Color {
        effectiveDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    private var windows: [TaskbarWindowItem] {
        manager.windowsForDisplay(displayID)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                TaskbarVisualEffectBackground(themeMode: prefs.themeMode, opacity: prefs.opacity)
                    .overlay(barTintColor)

                // Fondo interactivo para clic derecho sobre espacio libre de la barra
                TaskbarEmptyBackgroundMouseOverlay(displayID: displayID)

                // Borde superior sutil
                Rectangle()
                    .fill(topBorderColor)
                    .frame(height: 0.75)

                HStack(spacing: 6) {
                    // 1. Botón Inicio a la izquierda
                    startMenuButton

                    // 2. Aplicaciones fijadas (Pinned Apps)
                    if !prefs.pinnedApps.isEmpty {
                        pinnedAppsSection
                    }

                    // Separador vertical entre fijadas y ventanas abiertas
                    Rectangle()
                        .fill(effectiveDark ? Color.white.opacity(0.16) : Color.black.opacity(0.14))
                        .frame(width: 1, height: max(18, CGFloat(prefs.barHeight) * 0.52))
                        .padding(.horizontal, 2)

                    // 3. Botones de ventanas (un botón por ventana)
                    windowButtonsSection(availableWidth: max(120, geo.size.width - leadingReservedWidth))
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(isDropTargeted ? 0.85 : 0), lineWidth: 2)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDropAppProviders(providers)
            }
        }
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: ColorScheme? {
        switch prefs.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var leadingReservedWidth: CGFloat {
        let startW: CGFloat = CGFloat(prefs.barHeight)
        let pinnedItemW: CGFloat = max(30, CGFloat(prefs.barHeight) - 6)
        let pinnedW = CGFloat(prefs.pinnedApps.count) * (pinnedItemW + 4)
        return startW + pinnedW + 34
    }

    // MARK: - Botón Inicio

    private var startMenuButton: some View {
        let isOpenHere = manager.openStartMenuDisplayID == displayID
        let btnSide = max(26, CGFloat(prefs.barHeight) - 8)
        let iconSide = max(18, min(26, CGFloat(prefs.barHeight) * 0.56))
        let iconScale: CGFloat = {
            if isStartButtonPressed { return 0.94 }
            if isStartButtonHovered { return 1.14 }
            if isOpenHere { return 1.06 }
            return 1.0
        }()

        return ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isOpenHere
                        ? (effectiveDark ? Color.white.opacity(0.22) : Color.black.opacity(0.12))
                        : (isStartButtonHovered
                            ? (effectiveDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                            : Color.clear)
                )
                .animation(.easeOut(duration: 0.14), value: isStartButtonHovered)

            TaskbarStartIconGraphicView(
                iconStyle: prefs.startButtonIcon,
                size: iconSide,
                effectiveDark: effectiveDark,
                isHighlighted: isOpenHere
            )
            .scaleEffect(iconScale)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: iconScale)
        }
        .frame(width: btnSide, height: btnSide)
        .overlay(
            TaskbarStartButtonMouseOverlay(
                displayID: displayID,
                onHoverChanged: { hovered in
                    isStartButtonHovered = hovered
                },
                onPressChanged: { pressed in
                    isStartButtonPressed = pressed
                }
            )
        )
        .help(loc.text(es: "Menú Inicio", en: "Start Menu"))
    }

    // MARK: - Apps Fijadas

    private var pinnedAppsSection: some View {
        let focusedWindow = tracker.windows.first(where: { $0.isFocused })
        return HStack(spacing: 4) {
            ForEach(prefs.pinnedApps) { pinned in
                let isFocusedApp: Bool = {
                    guard let fw = focusedWindow else { return false }
                    if !pinned.bundleIdentifier.isEmpty && fw.bundleIdentifier.caseInsensitiveCompare(pinned.bundleIdentifier) == .orderedSame {
                        return true
                    }
                    if let url = fw.appBundleURL, url.standardizedFileURL == pinned.bundleURL.standardizedFileURL {
                        return true
                    }
                    return false
                }()
                TaskbarPinnedAppButtonView(
                    pinned: pinned,
                    barHeight: CGFloat(prefs.barHeight),
                    effectiveDark: effectiveDark,
                    isRunning: tracker.isAppRunning(bundleIdentifier: pinned.bundleIdentifier, bundlePath: pinned.bundlePath),
                    isFocused: isFocusedApp,
                    badgeLabel: prefs.showNotificationBadges
                        ? tracker.badgeLabel(
                            forBundleIdentifier: pinned.bundleIdentifier,
                            appName: pinned.displayName,
                            bundleURL: pinned.bundleURL
                        )
                        : nil,
                    notificationAnimation: prefs.notificationAnimation,
                    notificationCadence: prefs.notificationAnimationCadence,
                    isBeingDragged: manager.draggingPinnedAppID == pinned.id
                )
            }
        }
    }

    // MARK: - Botones de Ventanas

    @ViewBuilder
    private func windowButtonsSection(availableWidth: CGFloat) -> some View {
        if windows.isEmpty {
            HStack {
                if prefs.alignment == .center { Spacer(minLength: 0) }
                if !tracker.isAccessibilityGranted {
                    Button {
                        TaskbarSetupWizardWindowController.shared.show()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 11, weight: .semibold))
                            Text(loc.text(
                                es: "Conceder permiso de Accesibilidad para ver ventanas…",
                                en: "Grant Accessibility permission to list windows…"
                            ))
                            .font(.system(size: max(11, prefs.fontSize - 1), weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.orange.opacity(effectiveDark ? 0.25 : 0.16))
                        )
                        .foregroundStyle(effectiveDark ? Color.orange : Color(red: 0.72, green: 0.36, blue: 0.0))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let buttonSpacing: CGFloat = 5
            let count = max(1, windows.count)
            let totalSpacing = CGFloat(max(0, count - 1)) * buttonSpacing
            let iconOnlyWidth = max(34, CGFloat(prefs.barHeight) - 2)
            let maxButtonWidth: CGFloat = prefs.showWindowTitles ? 215 : iconOnlyWidth
            let minButtonWidth: CGFloat = prefs.showWindowTitles ? 96 : iconOnlyWidth
            let idealWidth = floor((availableWidth - totalSpacing) / CGFloat(count))
            let computedButtonWidth = min(maxButtonWidth, max(minButtonWidth, idealWidth))
            let needsHorizontalScroll = (computedButtonWidth * CGFloat(count) + totalSpacing) > availableWidth

            let buttonsRow = HStack(spacing: buttonSpacing) {
                if prefs.alignment == .center && !needsHorizontalScroll {
                    Spacer(minLength: 0)
                }
                ForEach(windows) { item in
                    TaskbarWindowButtonView(
                        item: item,
                        displayID: displayID,
                        buttonWidth: computedButtonWidth,
                        barHeight: CGFloat(prefs.barHeight),
                        fontSize: CGFloat(prefs.fontSize),
                        showTitle: prefs.showWindowTitles,
                        showMinimizedIndicator: prefs.showMinimizedIndicator,
                        showNotificationBadges: prefs.showNotificationBadges,
                        notificationAnimation: prefs.notificationAnimation,
                        notificationCadence: prefs.notificationAnimationCadence,
                        effectiveDark: effectiveDark,
                        isDragging: manager.draggingWindowID == item.id
                    )
                }
                if prefs.alignment == .center && !needsHorizontalScroll {
                    Spacer(minLength: 0)
                }
            }

            if needsHorizontalScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    buttonsRow
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                buttonsRow
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: prefs.alignment == .center ? .center : .leading)
            }
        }
    }

    private func handleDropAppProviders(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                } else {
                    url = nil
                }
                guard let appURL = url?.standardizedFileURL,
                      appURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    return
                }
                Task { @MainActor in
                    let bundle = Bundle(url: appURL)
                    let bundleID = bundle?.bundleIdentifier ?? ""
                    let name = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
                        .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive, .anchored, .backwards])
                    TaskbarPreferences.shared.pinApp(bundleIdentifier: bundleID, bundleURL: appURL, displayName: name)
                }
            }
        }
        return accepted
    }
}

// MARK: - Renderizador Compartido de Íconos del Botón Inicio (Barra + Configuración)

public struct TaskbarStartIconGraphicView: View {
    public let iconStyle: TaskbarStartButtonIcon
    public let size: CGFloat
    public let effectiveDark: Bool
    public let isHighlighted: Bool

    public init(
        iconStyle: TaskbarStartButtonIcon,
        size: CGFloat,
        effectiveDark: Bool,
        isHighlighted: Bool = false
    ) {
        self.iconStyle = iconStyle
        self.size = size
        self.effectiveDark = effectiveDark
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        switch iconStyle {
        case .windowsGrid:
            symbolGraphic(named: "square.grid.2x2.fill", scale: 0.84)

        case .macOSApps:
            if let nativeAppsIcon = Self.nativeMacOSAppsIcon() {
                Image(nsImage: nativeAppsIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                macOSAppsVectorFallback
            }

        case .brain:
            if let brainImage = FileIconProvider.shared.bundledResourceImage(named: "StartIcon-Brain") {
                Image(nsImage: brainImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 1.04, height: size * 1.04)
            } else {
                symbolGraphic(named: "brain.head.profile", scale: 0.86)
            }

        case .appleLogo:
            symbolGraphic(named: "apple.logo", scale: 0.86)

        case .macFileExplorer:
            if let appIcon = FileIconProvider.shared.appIcon(for: effectiveDark ? .dark : .light) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                symbolGraphic(named: "folder.fill", scale: 0.84)
            }

        case .macFileExplorerMono:
            TaskbarCustomMonochromeGlyphView(
                glyph: .macFileExplorerMono,
                size: size,
                effectiveDark: effectiveDark,
                isHighlighted: isHighlighted
            )

        case .macFileExplorerLayers:
            TaskbarCustomMonochromeGlyphView(
                glyph: .macFileExplorerLayers,
                size: size,
                effectiveDark: effectiveDark,
                isHighlighted: isHighlighted
            )

        case .macFileExplorerSquircle:
            TaskbarCustomMonochromeGlyphView(
                glyph: .macFileExplorerSquircle,
                size: size,
                effectiveDark: effectiveDark,
                isHighlighted: isHighlighted
            )

        case .brainMono:
            TaskbarCustomMonochromeGlyphView(
                glyph: .brainMono,
                size: size,
                effectiveDark: effectiveDark,
                isHighlighted: isHighlighted
            )

        case .brainSquircle:
            TaskbarCustomMonochromeGlyphView(
                glyph: .brainSquircle,
                size: size,
                effectiveDark: effectiveDark,
                isHighlighted: isHighlighted
            )

        case .dotsGrid:
            symbolGraphic(named: "circle.grid.3x3.fill", scale: 0.84)

        case .commandKey:
            symbolGraphic(named: "command.square.fill", scale: 0.86)
        }
    }

    private func symbolGraphic(named symbol: String, scale: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: isHighlighted
                        ? [Color.accentColor, Color.accentColor.opacity(0.8)]
                        : (effectiveDark
                            ? [Color.white.opacity(0.94), Color.white.opacity(0.74)]
                            : [Color.accentColor, Color.blue.opacity(0.75)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
    }

    /// Fallback vectorial fiel al ícono nativo de Apps de macOS (squircle oscuro + barra de búsqueda + 6 cuadraditos de color).
    private var macOSAppsVectorFallback: some View {
        let corner = size * 0.24
        let dot = max(2.5, size * 0.16)
        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.19), Color(white: 0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                )

            VStack(spacing: size * 0.08) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: size * 0.64, height: max(2.2, size * 0.13))
                HStack(spacing: size * 0.07) {
                    RoundedRectangle(cornerRadius: dot * 0.25).fill(Color.blue).frame(width: dot, height: dot)
                    RoundedRectangle(cornerRadius: dot * 0.25).fill(Color.green).frame(width: dot, height: dot)
                    RoundedRectangle(cornerRadius: dot * 0.25).fill(Color.pink).frame(width: dot, height: dot)
                }
                HStack(spacing: size * 0.07) {
                    RoundedRectangle(cornerRadius: dot * 0.25).fill(Color.orange).frame(width: dot, height: dot)
                    RoundedRectangle(cornerRadius: dot * 0.25).fill(Color.purple).frame(width: dot, height: dot)
                    RoundedRectangle(cornerRadius: dot * 0.25).fill(Color.gray).frame(width: dot, height: dot)
                }
            }
        }
        .frame(width: size, height: size)
    }

    @MainActor
    private static var cachedAppsAppIcon: NSImage?
    @MainActor
    private static var didProbeAppsApp = false

    @MainActor
    private static func nativeMacOSAppsIcon() -> NSImage? {
        if didProbeAppsApp {
            return cachedAppsAppIcon
        }
        didProbeAppsApp = true
        let candidates = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 64, height: 64)
            cachedAppsAppIcon = icon
            return icon
        }
        return nil
    }

    @MainActor
    public static func menuPreviewImage(for iconStyle: TaskbarStartButtonIcon) -> NSImage? {
        let targetSize = NSSize(width: 16, height: 16)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch iconStyle {
        case .macOSApps:
            if let copy = nativeMacOSAppsIcon()?.copy() as? NSImage {
                copy.size = targetSize
                return copy
            }
        case .brain:
            if let copy = FileIconProvider.shared.bundledResourceImage(named: "StartIcon-Brain")?.copy() as? NSImage {
                copy.size = targetSize
                return copy
            }
        case .macFileExplorer:
            if let copy = FileIconProvider.shared.appIcon(for: isDark ? .dark : .light)?.copy() as? NSImage {
                copy.size = targetSize
                return copy
            }
        case .macFileExplorerMono:
            return TaskbarCustomMonochromeGlyphView.renderMenuImage(for: .macFileExplorerMono, pointSize: 16, effectiveDark: isDark)
        case .macFileExplorerLayers:
            return TaskbarCustomMonochromeGlyphView.renderMenuImage(for: .macFileExplorerLayers, pointSize: 16, effectiveDark: isDark)
        case .macFileExplorerSquircle:
            return TaskbarCustomMonochromeGlyphView.renderMenuImage(for: .macFileExplorerSquircle, pointSize: 16, effectiveDark: isDark)
        case .brainMono:
            return TaskbarCustomMonochromeGlyphView.renderMenuImage(for: .brainMono, pointSize: 16, effectiveDark: isDark)
        case .brainSquircle:
            return TaskbarCustomMonochromeGlyphView.renderMenuImage(for: .brainSquircle, pointSize: 16, effectiveDark: isDark)
        default:
            break
        }
        return LocalizationManager.symbolImage(named: iconStyle.menuSymbolName)
    }
}

// MARK: - Botón de Aplicación Fijada

private struct TaskbarPinnedAppButtonView: View {
    let pinned: TaskbarPinnedApp
    let barHeight: CGFloat
    let effectiveDark: Bool
    let isRunning: Bool
    let isFocused: Bool
    let badgeLabel: String?
    let notificationAnimation: TaskbarNotificationAnimation
    let notificationCadence: TaskbarNotificationAnimationCadence
    let isBeingDragged: Bool

    @ViewState private var isHovered = false

    var body: some View {
        let height = max(26, barHeight - 8)
        let iconSize = max(16, min(24, barHeight * 0.52))
        let maxJumpUp = TaskbarNotificationAnimationEngine.safeMaxJumpUp(forBarHeight: barHeight, iconSize: iconSize)

        TaskbarNotificationAnimatedSlot(
            badgeLabel: badgeLabel,
            style: notificationAnimation,
            cadence: notificationCadence,
            isFocused: isFocused,
            maxJumpUp: maxJumpUp
        ) { animFrame in
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isHovered
                            ? (effectiveDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                            : Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                Color(red: 1.0, green: 0.34, blue: 0.22)
                                    .opacity((effectiveDark ? 0.34 : 0.24) * animFrame.buttonGlowIntensity)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                Color(red: 1.0, green: 0.42, blue: 0.28)
                                    .opacity(0.85 * animFrame.buttonGlowIntensity),
                                lineWidth: animFrame.buttonGlowIntensity > 0.05 ? 1.25 : 0
                            )
                    )

                ZStack(alignment: .topTrailing) {
                    Image(nsImage: TaskbarAppCatalogService.shared.icon(forAppAt: pinned.bundleURL))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: iconSize, height: iconSize)

                    if let badgeLabel, !badgeLabel.isEmpty {
                        TaskbarNotificationBadgeView(label: badgeLabel, frame: animFrame)
                            .offset(x: 4, y: -3)
                    }
                }
                .scaleEffect(x: animFrame.iconScaleX, y: animFrame.iconScaleY, anchor: animFrame.iconAnchor)
                .rotationEffect(.degrees(animFrame.iconRotationDegrees), anchor: animFrame.iconAnchor)
                .offset(x: animFrame.iconOffsetX, y: animFrame.iconOffsetY)
            }
            .frame(width: height, height: height)
            .overlay(alignment: .bottom) {
                if isRunning {
                    Capsule()
                        .fill(
                            animFrame.buttonGlowIntensity > 0.25
                                ? Color(red: 1.0, green: 0.42, blue: 0.28)
                                : (effectiveDark ? Color.white.opacity(0.75) : Color.accentColor)
                        )
                        .frame(width: 10, height: 2.5)
                        .padding(.bottom, 1.5)
                }
            }
        }
        .opacity(isBeingDragged ? 0.55 : 1.0)
        .overlay(
            TaskbarPinnedMouseOverlay(
                pinned: pinned,
                onHoverChanged: { hovered in
                    isHovered = hovered
                }
            )
        )
        .help(pinned.displayName)
    }
}

// MARK: - Botón Individual de Ventana

private struct TaskbarWindowButtonView: View {
    let item: TaskbarWindowItem
    let displayID: String
    let buttonWidth: CGFloat
    let barHeight: CGFloat
    let fontSize: CGFloat
    let showTitle: Bool
    let showMinimizedIndicator: Bool
    let showNotificationBadges: Bool
    let notificationAnimation: TaskbarNotificationAnimation
    let notificationCadence: TaskbarNotificationAnimationCadence
    let effectiveDark: Bool
    let isDragging: Bool

    @ViewState private var isHovered = false

    private var isInactiveOrHidden: Bool {
        item.isMinimized || item.isAppHidden || item.isWindowlessApp
    }

    private var backgroundFill: Color {
        if item.isFocused {
            return effectiveDark
                ? Color.white.opacity(0.22)
                : Color.white.opacity(0.92)
        }
        if isHovered {
            return effectiveDark
                ? Color.white.opacity(0.11)
                : Color.white.opacity(0.50)
        }
        return effectiveDark
            ? Color.white.opacity(0.04)
            : Color.black.opacity(0.035)
    }

    private var borderColor: Color {
        if item.isFocused {
            return effectiveDark
                ? Color.white.opacity(0.28)
                : Color.black.opacity(0.10)
        }
        return effectiveDark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.05)
    }

    var body: some View {
        let height = max(26, barHeight - 8)
        let iconSize = max(16, min(24, barHeight * 0.52))
        let activeBadge: String? = showNotificationBadges ? item.badgeLabel : nil
        let maxJumpUp = TaskbarNotificationAnimationEngine.safeMaxJumpUp(forBarHeight: barHeight, iconSize: iconSize)

        TaskbarNotificationAnimatedSlot(
            badgeLabel: activeBadge,
            style: notificationAnimation,
            cadence: notificationCadence,
            isFocused: item.isFocused,
            maxJumpUp: maxJumpUp
        ) { animFrame in
            let isButtonGlowing = animFrame.buttonGlowIntensity > 0.1
            let buttonShadowColor: Color = isButtonGlowing
                ? Color(red: 1.0, green: 0.36, blue: 0.24).opacity(0.35 * animFrame.buttonGlowIntensity)
                : (item.isFocused ? Color.black.opacity(effectiveDark ? 0.28 : 0.10) : .clear)
            let buttonShadowRadius: CGFloat = isButtonGlowing ? 4.0 : (item.isFocused ? 2.5 : 0.0)
            let buttonShadowY: CGFloat = isButtonGlowing ? 0.0 : (item.isFocused ? 1.0 : 0.0)

            HStack(spacing: showTitle ? 7 : 0) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: TaskbarAppCatalogService.shared.icon(
                        forBundleIdentifier: item.bundleIdentifier,
                        fallbackURL: item.appBundleURL
                    ))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .opacity((showMinimizedIndicator && isInactiveOrHidden) ? 0.55 : 1.0)

                    if let badge = activeBadge, !badge.isEmpty {
                        TaskbarNotificationBadgeView(label: badge, frame: animFrame)
                            .offset(x: 4, y: -3)
                    }
                }
                .scaleEffect(x: animFrame.iconScaleX, y: animFrame.iconScaleY, anchor: animFrame.iconAnchor)
                .rotationEffect(.degrees(animFrame.iconRotationDegrees), anchor: animFrame.iconAnchor)
                .offset(x: animFrame.iconOffsetX, y: animFrame.iconOffsetY)

                if showTitle {
                    Text(item.displayTitle)
                        .font(.system(size: fontSize, weight: item.isFocused ? .semibold : .regular))
                        .foregroundStyle(
                            (showMinimizedIndicator && isInactiveOrHidden)
                                ? Color.secondary
                                : Color.primary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, showTitle ? 9 : 4)
            .frame(width: buttonWidth, height: height, alignment: showTitle ? .leading : .center)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                Color(red: 1.0, green: 0.34, blue: 0.22)
                                    .opacity((effectiveDark ? 0.30 : 0.22) * animFrame.buttonGlowIntensity)
                            )
                    )
                    .shadow(
                        color: buttonShadowColor,
                        radius: buttonShadowRadius,
                        y: buttonShadowY
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        animFrame.buttonGlowIntensity > 0.05
                            ? Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.85 * animFrame.buttonGlowIntensity)
                            : borderColor,
                        lineWidth: animFrame.buttonGlowIntensity > 0.05 ? 1.25 : 0.75
                    )
            )
            .overlay(alignment: .bottom) {
                if item.isFocused {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: showTitle ? min(28, buttonWidth * 0.25) : 14, height: 2.5)
                        .padding(.bottom, 1.5)
                } else if animFrame.buttonGlowIntensity > 0.2 {
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.40, blue: 0.26).opacity(animFrame.buttonGlowIntensity))
                        .frame(width: showTitle ? min(28, buttonWidth * 0.25) : 14, height: 2.5)
                        .padding(.bottom, 1.5)
                } else if item.isWindowlessApp {
                    Circle()
                        .stroke(Color.secondary.opacity(0.75), lineWidth: 1.0)
                        .frame(width: 4.5, height: 4.5)
                        .padding(.bottom, 1.8)
                } else if showMinimizedIndicator && isInactiveOrHidden {
                    Circle()
                        .fill(Color.secondary.opacity(0.65))
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 2)
                }
            }
        }
        .opacity(isDragging ? 0.55 : 1.0)
        .overlay(
            TaskbarWindowButtonMouseOverlay(
                item: item,
                displayID: displayID,
                onHoverChanged: { hovered in
                    isHovered = hovered
                }
            )
        )
        .help(
            item.isWindowlessApp
                ? LocalizationManager.shared.text(
                    es: "\(item.appName) — Abierta sin ventanas (clic para abrir)",
                    en: "\(item.appName) — Running without open windows (click to open)"
                )
                : item.displayTitle
        )
    }
}

// MARK: - Interceptores Nativos de Mouse AppKit (Clic Izq, Clic Central, Clic Derecho, Hover y Drag & Drop)

private struct TaskbarWindowButtonMouseOverlay: NSViewRepresentable {
    let item: TaskbarWindowItem
    let displayID: String
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TaskbarWindowMouseNSView {
        let view = TaskbarWindowMouseNSView()
        view.item = item
        view.displayID = displayID
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: TaskbarWindowMouseNSView, context: Context) {
        nsView.item = item
        nsView.displayID = displayID
        nsView.onHoverChanged = onHoverChanged
    }
}

private final class TaskbarWindowMouseNSView: NSView {
    var item: TaskbarWindowItem?
    var displayID: String = ""
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var didStartDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        guard let item else { return }

        // Si se está arrastrando otro botón horizontalmente, intercambiar posiciones en vivo
        if let draggedID = TaskbarManager.shared.draggingWindowID, draggedID != item.id {
            TaskbarWindowTracker.shared.moveWindow(sourceID: draggedID, toTargetID: item.id)
            return
        }

        if let screenRect = buttonScreenRect() {
            TaskbarPreviewPanelController.shared.handleButtonHoverEntered(
                item: item,
                buttonScreenRect: screenRect,
                displayID: displayID
            )
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        if let item {
            TaskbarPreviewPanelController.shared.handleButtonHoverExited(itemID: item.id)
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didStartDragging = false
        TaskbarPreviewPanelController.shared.hideImmediately()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, let item else { return }
        if !didStartDragging {
            let dx = abs(event.locationInWindow.x - start.x)
            let dy = abs(event.locationInWindow.y - start.y)
            // Umbral de 14 pt con dominancia horizontal para que clics rápidos con leve movimiento nunca se cancelen
            if dx >= 14 && dx > dy * 1.25 {
                didStartDragging = true
                TaskbarManager.shared.draggingWindowID = item.id
            }
        }
        if didStartDragging, let window {
            // Detectar si el puntero pasó por encima de otro botón hermano en esta misma barra
            let pointInWindow = event.locationInWindow
            if let hitView = window.contentView?.hitTest(pointInWindow) as? TaskbarWindowMouseNSView,
               let targetItem = hitView.item,
               targetItem.id != item.id {
                TaskbarWindowTracker.shared.moveWindow(sourceID: item.id, toTargetID: targetItem.id)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            if didStartDragging {
                TaskbarManager.shared.draggingWindowID = nil
                didStartDragging = false
            }
        }
        guard !didStartDragging, let item else { return }
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.insetBy(dx: -8, dy: -8).contains(loc) else { return }
        TaskbarWindowTracker.shared.handlePrimaryClick(on: item)
    }

    override func otherMouseDown(with event: NSEvent) {
        // Clic central (botón 2) cierra la ventana directamente
        guard event.buttonNumber == 2,
              TaskbarPreferences.shared.middleClickClosesWindow,
              let item else {
            super.otherMouseDown(with: event)
            return
        }
        TaskbarPreviewPanelController.shared.hideImmediately()
        TaskbarWindowTracker.shared.closeWindow(item)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let item else { return }
        TaskbarPreviewPanelController.shared.hideImmediately()
        let menu = TaskbarContextMenuBuilder.buildWindowMenu(for: item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func buttonScreenRect() -> NSRect? {
        guard let window else { return nil }
        let inWindow = convert(bounds, to: nil)
        return window.convertToScreen(inWindow)
    }
}

private struct TaskbarPinnedMouseOverlay: NSViewRepresentable {
    let pinned: TaskbarPinnedApp
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TaskbarPinnedMouseNSView {
        let view = TaskbarPinnedMouseNSView()
        view.pinned = pinned
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: TaskbarPinnedMouseNSView, context: Context) {
        nsView.pinned = pinned
        nsView.onHoverChanged = onHoverChanged
    }
}

private final class TaskbarPinnedMouseNSView: NSView {
    var pinned: TaskbarPinnedApp?
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var didStartDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        if let pinned,
           let draggedID = TaskbarManager.shared.draggingPinnedAppID,
           draggedID != pinned.id {
            TaskbarPreferences.shared.movePinnedApp(sourceID: draggedID, toTargetID: pinned.id)
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didStartDragging = false
        TaskbarPreviewPanelController.shared.hideImmediately()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, let pinned else { return }
        if !didStartDragging {
            let dx = abs(event.locationInWindow.x - start.x)
            let dy = abs(event.locationInWindow.y - start.y)
            if dx >= 14 && dx > dy * 1.25 {
                didStartDragging = true
                TaskbarManager.shared.draggingPinnedAppID = pinned.id
            }
        }
        if didStartDragging, let window,
           let hit = window.contentView?.hitTest(event.locationInWindow) as? TaskbarPinnedMouseNSView,
           let target = hit.pinned,
           target.id != pinned.id {
            TaskbarPreferences.shared.movePinnedApp(sourceID: pinned.id, toTargetID: target.id)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            if didStartDragging {
                TaskbarManager.shared.draggingPinnedAppID = nil
                didStartDragging = false
            }
        }
        guard !didStartDragging, let pinned else { return }
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.insetBy(dx: -8, dy: -8).contains(loc) else { return }
        TaskbarWindowTracker.shared.launchOrFocusApplication(
            bundleIdentifier: pinned.bundleIdentifier,
            bundleURL: pinned.bundleURL
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let pinned else { return }
        TaskbarPreviewPanelController.shared.hideImmediately()
        let menu = TaskbarContextMenuBuilder.buildPinnedAppMenu(for: pinned)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

private struct TaskbarStartButtonMouseOverlay: NSViewRepresentable {
    let displayID: String
    let onHoverChanged: (Bool) -> Void
    let onPressChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TaskbarStartButtonMouseNSView {
        let view = TaskbarStartButtonMouseNSView()
        view.displayID = displayID
        view.onHoverChanged = onHoverChanged
        view.onPressChanged = onPressChanged
        return view
    }

    func updateNSView(_ nsView: TaskbarStartButtonMouseNSView, context: Context) {
        nsView.displayID = displayID
        nsView.onHoverChanged = onHoverChanged
        nsView.onPressChanged = onPressChanged
    }
}

private final class TaskbarStartButtonMouseNSView: NSView {
    var displayID: String = ""
    var onHoverChanged: ((Bool) -> Void)?
    var onPressChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        onPressChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onPressChanged?(true)
        TaskbarPreviewPanelController.shared.hideImmediately()
        guard let window else {
            TaskbarManager.shared.toggleStartMenu(for: displayID)
            onPressChanged?(false)
            return
        }
        let rect = window.convertToScreen(convert(bounds, to: nil))
        TaskbarStartMenuController.shared.toggle(displayID: displayID, anchorButtonRect: rect)
    }

    override func mouseUp(with event: NSEvent) {
        onPressChanged?(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        TaskbarPreviewPanelController.shared.hideImmediately()
        let menu = TaskbarContextMenuBuilder.buildStartButtonMenu(displayID: displayID)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

private struct TaskbarEmptyBackgroundMouseOverlay: NSViewRepresentable {
    let displayID: String

    func makeNSView(context: Context) -> TaskbarEmptyBackgroundMouseNSView {
        let view = TaskbarEmptyBackgroundMouseNSView()
        view.displayID = displayID
        return view
    }

    func updateNSView(_ nsView: TaskbarEmptyBackgroundMouseNSView, context: Context) {
        nsView.displayID = displayID
    }
}

private final class TaskbarEmptyBackgroundMouseNSView: NSView {
    var displayID: String = ""

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        TaskbarPreviewPanelController.shared.hideImmediately()
        let menu = TaskbarContextMenuBuilder.buildBarBackgroundMenu(displayID: displayID)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - Constructor de Menús Contextuales (Clic Derecho)

@MainActor
private final class TaskbarMenuActionBox: NSObject {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func invoke(_ sender: Any?) {
        action()
    }
}

@MainActor
private enum TaskbarContextMenuBuilder {
    private static var activeRetainedBoxes: [TaskbarMenuActionBox] = []

    private static func makeItem(
        title: String,
        symbol: String,
        isEnabled: Bool = true,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let box = TaskbarMenuActionBox(action)
        activeRetainedBoxes.append(box)
        if activeRetainedBoxes.count > 120 {
            activeRetainedBoxes.removeFirst(activeRetainedBoxes.count - 120)
        }
        let item = NSMenuItem(title: title, action: #selector(TaskbarMenuActionBox.invoke(_:)), keyEquivalent: "")
        item.target = box
        item.representedObject = box
        item.isEnabled = isEnabled
        item.image = LocalizationManager.symbolImage(named: symbol)
        return item
    }

    static func buildWindowMenu(for item: TaskbarWindowItem) -> NSMenu {
        let loc = LocalizationManager.shared
        let prefs = TaskbarPreferences.shared
        let menu = NSMenu(title: item.appName)
        menu.autoenablesItems = false

        if item.isWindowlessApp {
            menu.addItem(makeItem(
                title: loc.text(es: "Abrir ventana de \(item.appName)", en: "Open \(item.appName) Window"),
                symbol: "macwindow.badge.plus"
            ) {
                TaskbarWindowTracker.shared.focusWindow(item)
            })
        } else {
            menu.addItem(makeItem(
                title: item.isMinimized
                    ? loc.text(es: "Restaurar ventana", en: "Restore Window")
                    : loc.text(es: "Enfocar ventana", en: "Focus Window"),
                symbol: "macwindow"
            ) {
                TaskbarWindowTracker.shared.focusWindow(item)
            })

            menu.addItem(makeItem(
                title: loc.text(es: "Minimizar ventana", en: "Minimize Window"),
                symbol: "minus.rectangle",
                isEnabled: !item.isMinimized
            ) {
                TaskbarWindowTracker.shared.minimizeWindow(item)
            })

            menu.addItem(makeItem(
                title: loc.text(es: "Ocultar \(item.appName)", en: "Hide \(item.appName)"),
                symbol: "eye.slash"
            ) {
                TaskbarWindowTracker.shared.hideApplication(pid: item.pid)
            })

            menu.addItem(makeItem(
                title: loc.text(es: "Cerrar ventana", en: "Close Window"),
                symbol: "xmark.circle"
            ) {
                TaskbarWindowTracker.shared.closeWindow(item)
            })
        }

        menu.addItem(.separator())

        if let appURL = item.appBundleURL {
            let pinned = prefs.isPinned(bundleIdentifier: item.bundleIdentifier, bundlePath: appURL.path(percentEncoded: false))
            menu.addItem(makeItem(
                title: pinned
                    ? loc.text(es: "Desfijar de la barra de tareas", en: "Unpin from Taskbar")
                    : loc.text(es: "Fijar en la barra de tareas", en: "Pin to Taskbar"),
                symbol: pinned ? "pin.slash" : "pin"
            ) {
                if pinned {
                    prefs.unpinApp(bundleIdentifier: item.bundleIdentifier, bundlePath: appURL.path(percentEncoded: false))
                } else {
                    prefs.pinApp(bundleIdentifier: item.bundleIdentifier, bundleURL: appURL, displayName: item.appName)
                }
            })
        }

        if !item.bundleIdentifier.isEmpty {
            menu.addItem(makeItem(
                title: loc.text(es: "Ocultar \(item.appName) de la barra de tareas", en: "Exclude \(item.appName) from Taskbar"),
                symbol: "eye.slash.circle"
            ) {
                prefs.excludeApp(bundleIdentifier: item.bundleIdentifier)
            })
        }

        menu.addItem(.separator())

        menu.addItem(makeItem(
            title: loc.text(es: "Nueva ventana", en: "New Window"),
            symbol: "macwindow.badge.plus",
            isEnabled: item.appBundleURL != nil
        ) {
            TaskbarWindowTracker.shared.openNewWindowForApplication(bundleURL: item.appBundleURL, pid: item.pid)
        })

        menu.addItem(makeItem(
            title: loc.text(es: "Salir de \(item.appName)", en: "Quit \(item.appName)"),
            symbol: "power"
        ) {
            TaskbarWindowTracker.shared.quitApplication(pid: item.pid, force: false)
        })

        menu.addItem(makeItem(
            title: loc.text(es: "Forzar salida de \(item.appName)", en: "Force Quit \(item.appName)"),
            symbol: "exclamationmark.triangle"
        ) {
            TaskbarWindowTracker.shared.quitApplication(pid: item.pid, force: true)
        })

        return menu
    }

    static func buildPinnedAppMenu(for pinned: TaskbarPinnedApp) -> NSMenu {
        let loc = LocalizationManager.shared
        let menu = NSMenu(title: pinned.displayName)
        menu.autoenablesItems = false

        menu.addItem(makeItem(
            title: loc.text(es: "Abrir \(pinned.displayName)", en: "Open \(pinned.displayName)"),
            symbol: "arrow.up.right.square"
        ) {
            TaskbarWindowTracker.shared.launchOrFocusApplication(
                bundleIdentifier: pinned.bundleIdentifier,
                bundleURL: pinned.bundleURL
            )
        })

        menu.addItem(makeItem(
            title: loc.text(es: "Desfijar de la barra de tareas", en: "Unpin from Taskbar"),
            symbol: "pin.slash"
        ) {
            TaskbarPreferences.shared.unpinApp(bundleIdentifier: pinned.bundleIdentifier, bundlePath: pinned.bundlePath)
        })

        if let running = NSWorkspace.shared.runningApplications.first(where: {
            !$0.isTerminated && (
                (!pinned.bundleIdentifier.isEmpty && $0.bundleIdentifier?.caseInsensitiveCompare(pinned.bundleIdentifier) == .orderedSame) ||
                ($0.bundleURL?.standardizedFileURL == pinned.bundleURL.standardizedFileURL)
            )
        }) {
            menu.addItem(.separator())
            menu.addItem(makeItem(
                title: loc.text(es: "Salir de \(pinned.displayName)", en: "Quit \(pinned.displayName)"),
                symbol: "power"
            ) {
                TaskbarWindowTracker.shared.quitApplication(pid: running.processIdentifier, force: false)
            })
        }

        return menu
    }

    static func buildStartButtonMenu(displayID: String) -> NSMenu {
        let loc = LocalizationManager.shared
        let menu = NSMenu(title: loc.text(es: "Menú Inicio", en: "Start Menu"))
        menu.autoenablesItems = false

        menu.addItem(makeItem(
            title: loc.text(es: "Abrir Menú Inicio", en: "Open Start Menu"),
            symbol: "square.grid.2x2"
        ) {
            TaskbarManager.shared.toggleStartMenu(for: displayID)
        })

        menu.addItem(makeItem(
            title: loc.text(es: "Abrir Configuración del Sistema", en: "Open System Settings"),
            symbol: "gearshape"
        ) {
            if let url = URL(string: "x-apple.systempreferences:") {
                NSWorkspace.shared.open(url)
            }
        })

        // Submenú rápido para cambiar el ícono del botón Inicio
        let iconSubmenu = NSMenu(title: loc.text(es: "Ícono del botón Inicio", en: "Start Button Icon"))
        iconSubmenu.autoenablesItems = false
        for iconOption in TaskbarStartButtonIcon.allCases {
            let optItem = makeItem(
                title: iconOption.localizedTitle(using: loc),
                symbol: iconOption.menuSymbolName
            ) {
                TaskbarPreferences.shared.startButtonIcon = iconOption
            }
            if let customPreview = TaskbarStartIconGraphicView.menuPreviewImage(for: iconOption) {
                optItem.image = customPreview
            }
            optItem.state = (TaskbarPreferences.shared.startButtonIcon == iconOption) ? .on : .off
            iconSubmenu.addItem(optItem)
        }
        let iconParent = NSMenuItem(
            title: loc.text(es: "Ícono del botón Inicio", en: "Start Button Icon"),
            action: nil,
            keyEquivalent: ""
        )
        iconParent.image = LocalizationManager.symbolImage(named: "sparkles.square.filled.on.square")
        iconParent.submenu = iconSubmenu
        menu.addItem(iconParent)

        // Submenú rápido para elegir la animación y velocidad del Menú Inicio (8 estilos + 0 ms instantáneo)
        let animSubmenu = NSMenu(title: loc.text(es: "Animación del Menú Inicio", en: "Start Menu Animation"))
        animSubmenu.autoenablesItems = false
        for animOption in TaskbarStartMenuAnimation.allCases {
            let badge = animOption.category.localizedBadge(using: loc)
            let label = badge.map { "\(animOption.localizedTitle(using: loc)) · \($0)" } ?? animOption.localizedTitle(using: loc)
            let optItem = makeItem(
                title: label,
                symbol: animOption.symbolName
            ) {
                TaskbarPreferences.shared.startMenuAnimation = animOption
            }
            optItem.state = (TaskbarPreferences.shared.startMenuAnimation == animOption) ? .on : .off
            animSubmenu.addItem(optItem)
        }
        animSubmenu.addItem(.separator())
        let speedPresets: [(seconds: Double, es: String, en: String, symbol: String)] = [
            (0.00, "Instantáneo (0 ms)", "Instant (0 ms)", "bolt.fill"),
            (0.15, "Rápido (150 ms)", "Fast (150 ms)", "hare"),
            (0.22, "Normal (220 ms)", "Normal (220 ms)", "gauge.with.needle"),
            (0.42, "Suave (420 ms)", "Smooth (420 ms)", "tortoise")
        ]
        let currentDuration = TaskbarPreferences.shared.startMenuAnimationDuration
        for preset in speedPresets {
            let speedItem = makeItem(
                title: loc.text(es: preset.es, en: preset.en),
                symbol: preset.symbol
            ) {
                TaskbarPreferences.shared.startMenuAnimationDuration = preset.seconds
            }
            speedItem.state = (abs(currentDuration - preset.seconds) < 0.013) ? .on : .off
            animSubmenu.addItem(speedItem)
        }
        let animParent = NSMenuItem(
            title: loc.text(es: "Animación del Menú Inicio", en: "Start Menu Animation"),
            action: nil,
            keyEquivalent: ""
        )
        animParent.image = LocalizationManager.symbolImage(named: "sparkles.rectangle.stack")
        animParent.submenu = animSubmenu
        menu.addItem(animParent)

        menu.addItem(.separator())
        appendCommonBarItems(to: menu, displayID: displayID)
        return menu
    }

    static func buildBarBackgroundMenu(displayID: String) -> NSMenu {
        let loc = LocalizationManager.shared
        let menu = NSMenu(title: loc.text(es: "Barra de tareas", en: "Taskbar"))
        menu.autoenablesItems = false
        appendCommonBarItems(to: menu, displayID: displayID)
        return menu
    }

    private static func appendCommonBarItems(to menu: NSMenu, displayID: String) {
        let loc = LocalizationManager.shared
        let prefs = TaskbarPreferences.shared

        menu.addItem(makeItem(
            title: loc.text(es: "Configuración de la barra de tareas…", en: "Taskbar Settings…"),
            symbol: "slider.horizontal.3"
        ) {
            TaskbarSettingsWindowController.shared.show()
        })

        menu.addItem(makeItem(
            title: loc.text(es: "Ocultar barra en esta pantalla", en: "Hide Taskbar on This Display"),
            symbol: "eye.slash"
        ) {
            prefs.setDisplayHidden(true, displayID: displayID)
        })

        if !prefs.hiddenDisplayIDs.isEmpty {
            menu.addItem(makeItem(
                title: loc.text(es: "Mostrar todas las pantallas ocultas", en: "Show All Hidden Displays"),
                symbol: "display.2"
            ) {
                prefs.showAllHiddenDisplays()
            })
        }

        menu.addItem(.separator())

        menu.addItem(makeItem(
            title: loc.text(es: "Emergencia: Restaurar Dock original de macOS", en: "Emergency: Restore Original macOS Dock"),
            symbol: "arrow.uturn.backward.circle"
        ) {
            TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock()
        })

        menu.addItem(makeItem(
            title: loc.text(es: "Desactivar barra de tareas", en: "Disable Taskbar"),
            symbol: "power"
        ) {
            TaskbarManager.shared.setEnabled(false)
        })
    }
}
