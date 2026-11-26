import AppKit
import CoreGraphics
import QuartzCore
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
    let backgroundMaterial: TaskbarBackgroundMaterial
    let cornerRadius: CGFloat

    private var resolvedMaterial: NSVisualEffectView.Material {
        switch backgroundMaterial {
        case .frostedGlass: return .hudWindow
        case .crystalBlur: return .popover
        case .solid: return .hudWindow
        }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = resolvedMaterial
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = resolvedMaterial
        nsView.state = .active
        let alphaFactor: Double = (backgroundMaterial == .crystalBlur) ? 0.86 : 1.0
        nsView.alphaValue = CGFloat(min(max(opacity * alphaFactor, 0.25), 1.0))
        nsView.wantsLayer = true
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.masksToBounds = cornerRadius > 0
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
        switch prefs.backgroundMaterial {
        case .frostedGlass:
            return effectiveDark
                ? Color(white: 0.11).opacity(prefs.opacity * 0.72)
                : Color(white: 0.94).opacity(prefs.opacity * 0.76)
        case .crystalBlur:
            return effectiveDark
                ? Color(white: 0.15).opacity(prefs.opacity * 0.34)
                : Color.white.opacity(prefs.opacity * 0.44)
        case .solid:
            return effectiveDark
                ? Color(white: 0.105).opacity(prefs.opacity)
                : Color(white: 0.955).opacity(prefs.opacity)
        }
    }

    private var topBorderColor: Color {
        effectiveDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    private var barCornerRadius: CGFloat {
        prefs.barStyle == .floatingIsland ? min(15, max(10, CGFloat(prefs.barHeight) * 0.32)) : 0
    }

    private var windows: [TaskbarWindowItem] {
        manager.windowsForDisplay(displayID)
    }

    public var body: some View {
        let isFloating = (prefs.barStyle == .floatingIsland)
        let cornerRadius = barCornerRadius

        GeometryReader { geo in
            ZStack(alignment: .top) {
                if prefs.backgroundMaterial == .solid {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(barTintColor)
                } else {
                    TaskbarVisualEffectBackground(
                        themeMode: prefs.themeMode,
                        opacity: prefs.opacity,
                        backgroundMaterial: prefs.backgroundMaterial,
                        cornerRadius: cornerRadius
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(barTintColor)
                    )
                }

                // Fondo interactivo para clic derecho y soltado de apps `.app` sobre espacio libre de la barra
                TaskbarEmptyBackgroundMouseOverlay(
                    displayID: displayID,
                    onAppDropTargetedChanged: { targeted in
                        isDropTargeted = targeted
                    }
                )

                // Línea divisoria superior configurable (en modo acoplado)
                if prefs.showTopBorder && !isFloating {
                    Rectangle()
                        .fill(topBorderColor)
                        .frame(height: 0.75)
                }

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
                .padding(.horizontal, isFloating ? 10 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        (isFloating && prefs.showTopBorder) ? topBorderColor : Color.clear,
                        lineWidth: (isFloating && prefs.showTopBorder) ? 0.9 : 0
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(4, cornerRadius), style: .continuous)
                    .stroke(Color.accentColor.opacity(isDropTargeted ? 0.85 : 0), lineWidth: 2)
            )
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
        let isFloating = (prefs.barStyle == .floatingIsland)
        let outerPadding: CGFloat = isFloating ? 20 : 16
        let startW: CGFloat = max(26, CGFloat(prefs.barHeight) - 8)
        let pinnedItemW: CGFloat = max(30, CGFloat(prefs.barHeight) - 6)
        let pinnedCount = prefs.pinnedApps.count
        let pinnedW: CGFloat = pinnedCount > 0
            ? CGFloat(pinnedCount) * pinnedItemW + CGFloat(max(0, pinnedCount - 1)) * 4
            : 0
        let hStackGaps: CGFloat = pinnedCount > 0 ? 18 : 12
        let separatorW: CGFloat = 5
        return outerPadding + startW + pinnedW + hStackGaps + separatorW + 4
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

        let btnCornerRadius: CGFloat = (prefs.buttonStyle == .pill) ? (btnSide * 0.5) : 7
        return ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: btnCornerRadius, style: .continuous)
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
                    buttonStyle: prefs.buttonStyle,
                    activeIndicatorColor: prefs.activeIndicatorColor,
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
            let isPinnedOrderFlags: [Bool] = windows.map { item in
                guard prefs.orderWindowsByPinnedApps else { return false }
                return prefs.isPinned(
                    bundleIdentifier: item.bundleIdentifier,
                    bundlePath: item.appBundleURL?.standardizedFileURL.path(percentEncoded: false)
                )
            }
            let pinnedBoundaryIndex: Int? = {
                guard prefs.orderWindowsByPinnedApps else { return nil }
                for idx in 1..<isPinnedOrderFlags.count {
                    if isPinnedOrderFlags[idx - 1] && !isPinnedOrderFlags[idx] {
                        return idx
                    }
                }
                return nil
            }()
            let effectiveAvailableWidth = pinnedBoundaryIndex != nil
                ? max(120, availableWidth - 10)
                : availableWidth

            let layout = TaskbarButtonLayoutCalculator.computeLayout(
                windows: windows,
                availableWidth: effectiveAvailableWidth,
                barHeight: CGFloat(prefs.barHeight),
                showWindowTitles: prefs.showWindowTitles,
                minimizedDisplayMode: prefs.minimizedWindowDisplayMode,
                groupWindowsByApp: prefs.groupWindowsByApp,
                overflowMode: prefs.overflowMode
            )

            let buttonsRow = HStack(spacing: 0) {
                if prefs.alignment == .center && !layout.needsHorizontalScroll {
                    Spacer(minLength: 0)
                }
                ForEach(Array(windows.enumerated()), id: \.element.id) { idx, item in
                    if pinnedBoundaryIndex == idx {
                        Capsule()
                            .fill(effectiveDark ? Color.white.opacity(0.22) : Color.black.opacity(0.18))
                            .frame(width: 1.5, height: max(14, CGFloat(prefs.barHeight) * 0.40))
                            .padding(.leading, 5)
                            .padding(.trailing, 3.5)
                            .help(LocalizationManager.shared.text(
                                es: "A la izquierda: apps con orden fijado · A la derecha: apps no fijadas",
                                en: "Left: pinned-order apps · Right: unpinned apps"
                            ))
                    }

                    TaskbarWindowButtonView(
                        item: item,
                        displayID: displayID,
                        buttonWidth: layout.buttonWidths[idx],
                        barHeight: CGFloat(prefs.barHeight),
                        fontSize: CGFloat(prefs.fontSize),
                        showTitle: layout.showTitles[idx],
                        showMinimizedIndicator: prefs.showMinimizedIndicator,
                        showNotificationBadges: prefs.showNotificationBadges,
                        notificationAnimation: prefs.notificationAnimation,
                        notificationCadence: prefs.notificationAnimationCadence,
                        buttonStyle: prefs.buttonStyle,
                        activeIndicatorStyle: prefs.activeIndicatorStyle,
                        activeIndicatorColor: prefs.activeIndicatorColor,
                        effectiveDark: effectiveDark,
                        isDragging: manager.draggingWindowID == item.id,
                        isPinnedOrderLocked: isPinnedOrderFlags[idx]
                    )
                    .padding(.leading, pinnedBoundaryIndex == idx ? 0 : layout.leadingSpacings[idx])
                }
                if prefs.alignment == .center && !layout.needsHorizontalScroll {
                    Spacer(minLength: 0)
                }
            }

            if layout.needsHorizontalScroll {
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
    let buttonStyle: TaskbarButtonStyle
    let activeIndicatorColor: TaskbarActiveIndicatorColor
    let isRunning: Bool
    let isFocused: Bool
    let badgeLabel: String?
    let notificationAnimation: TaskbarNotificationAnimation
    let notificationCadence: TaskbarNotificationAnimationCadence
    let isBeingDragged: Bool

    @ViewState private var isHovered = false
    @ViewState private var dragHoverState: TaskbarDragHoverState = .idle

    var body: some View {
        let height = max(26, barHeight - 8)
        let cornerRadius: CGFloat = (buttonStyle == .pill) ? (height * 0.5) : 7
        let iconSize = max(16, min(24, barHeight * 0.52))
        let maxJumpUp = TaskbarNotificationAnimationEngine.safeMaxJumpUp(forBarHeight: barHeight, iconSize: iconSize)
        let isDragHovering = dragHoverState.isHovering
        let dragTint: Color = dragHoverState.didActivate ? Color.green : Color.accentColor

        TaskbarNotificationAnimatedSlot(
            badgeLabel: badgeLabel,
            style: notificationAnimation,
            cadence: notificationCadence,
            isFocused: isFocused,
            maxJumpUp: maxJumpUp
        ) { animFrame in
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isHovered
                            ? (effectiveDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                            : Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                Color(red: 1.0, green: 0.34, blue: 0.22)
                                    .opacity((effectiveDark ? 0.34 : 0.24) * animFrame.buttonGlowIntensity)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                dragTint.opacity(
                                    isDragHovering
                                        ? (dragHoverState.didActivate ? (effectiveDark ? 0.30 : 0.22) : (effectiveDark ? 0.22 : 0.15))
                                        : 0
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                isDragHovering
                                    ? dragTint.opacity(0.95)
                                    : Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.85 * animFrame.buttonGlowIntensity),
                                lineWidth: isDragHovering ? 1.5 : (animFrame.buttonGlowIntensity > 0.05 ? 1.25 : 0)
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
            .shadow(color: isDragHovering ? dragTint.opacity(0.35) : .clear, radius: isDragHovering ? 4 : 0)
            .scaleEffect(dragHoverState.didActivate ? 1.05 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.65), value: dragHoverState.didActivate)
            .overlay(alignment: .bottom) {
                if isDragHovering {
                    let trackWidth = max(14, height - 10)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(dragTint.opacity(effectiveDark ? 0.26 : 0.20))
                            .frame(width: trackWidth, height: 3.0)
                        Capsule()
                            .fill(dragTint)
                            .frame(width: max(4, trackWidth * max(0, min(1, dragHoverState.progress))), height: 3.0)
                    }
                    .padding(.bottom, 1.5)
                } else if isRunning {
                    Capsule()
                        .fill(
                            animFrame.buttonGlowIntensity > 0.25
                                ? Color(red: 1.0, green: 0.42, blue: 0.28)
                                : (isFocused
                                    ? activeIndicatorColor.resolvedColor(effectiveDark: effectiveDark)
                                    : (effectiveDark ? Color.white.opacity(0.75) : activeIndicatorColor.resolvedColor(effectiveDark: effectiveDark).opacity(0.75)))
                        )
                        .frame(width: isFocused ? 13 : 10, height: 2.5)
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
                },
                onDragHoverChanged: { state in
                    dragHoverState = state
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
    let buttonStyle: TaskbarButtonStyle
    let activeIndicatorStyle: TaskbarActiveIndicatorStyle
    let activeIndicatorColor: TaskbarActiveIndicatorColor
    let effectiveDark: Bool
    let isDragging: Bool
    let isPinnedOrderLocked: Bool

    @ViewState private var isHovered = false
    @ViewState private var dragHoverState: TaskbarDragHoverState = .idle

    private var isInactiveOrHidden: Bool {
        item.isMinimized || item.isAppHidden || item.isWindowlessApp
    }

    private var backgroundFill: Color {
        if buttonStyle == .minimalBorderless {
            if item.isFocused {
                return effectiveDark
                    ? Color.white.opacity(0.15)
                    : Color.white.opacity(0.78)
            }
            if isHovered {
                return effectiveDark
                    ? Color.white.opacity(0.08)
                    : Color.white.opacity(0.38)
            }
            return Color.clear
        }

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
        if buttonStyle == .minimalBorderless {
            return Color.clear
        }
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
        let cornerRadius: CGFloat = (buttonStyle == .pill) ? (height * 0.5) : 7
        let baseIconSize = max(16, min(24, barHeight * 0.52))
        let iconSize = (!showTitle && buttonWidth < 34) ? max(14, min(baseIconSize, buttonWidth - 8)) : baseIconSize
        let isCompactTitled = showTitle && buttonWidth < 78
        let horizontalPadding: CGFloat = showTitle
            ? (isCompactTitled ? 5 : (buttonStyle == .pill ? 11 : 9))
            : (buttonWidth < 32 ? 2 : 4)
        let activeBadge: String? = showNotificationBadges ? item.badgeLabel : nil
        let maxJumpUp = TaskbarNotificationAnimationEngine.safeMaxJumpUp(forBarHeight: barHeight, iconSize: iconSize)
        let indicatorAccent = activeIndicatorColor.resolvedColor(effectiveDark: effectiveDark)
        let isDragHovering = dragHoverState.isHovering
        let dragTint: Color = dragHoverState.didActivate ? Color.green : Color.accentColor

        TaskbarNotificationAnimatedSlot(
            badgeLabel: activeBadge,
            style: notificationAnimation,
            cadence: notificationCadence,
            isFocused: item.isFocused,
            maxJumpUp: maxJumpUp
        ) { animFrame in
            let isButtonGlowing = animFrame.buttonGlowIntensity > 0.1
            let buttonShadowColor: Color = isDragHovering
                ? dragTint.opacity(0.38)
                : (isButtonGlowing
                    ? Color(red: 1.0, green: 0.36, blue: 0.24).opacity(0.35 * animFrame.buttonGlowIntensity)
                    : (item.isFocused && buttonStyle != .minimalBorderless ? Color.black.opacity(effectiveDark ? 0.28 : 0.10) : .clear))
            let buttonShadowRadius: CGFloat = isDragHovering ? 4.5 : (isButtonGlowing ? 4.0 : (item.isFocused && buttonStyle != .minimalBorderless ? 2.5 : 0.0))
            let buttonShadowY: CGFloat = isDragHovering ? 0.0 : (isButtonGlowing ? 0.0 : (item.isFocused && buttonStyle != .minimalBorderless ? 1.0 : 0.0))

            HStack(spacing: showTitle ? (isCompactTitled ? 4 : 7) : 0) {
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
            .padding(.horizontal, horizontalPadding)
            .frame(width: buttonWidth, height: height, alignment: showTitle ? .leading : .center)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                Color(red: 1.0, green: 0.34, blue: 0.22)
                                    .opacity((effectiveDark ? 0.30 : 0.22) * animFrame.buttonGlowIntensity)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                dragTint.opacity(
                                    isDragHovering
                                        ? (dragHoverState.didActivate ? (effectiveDark ? 0.30 : 0.22) : (effectiveDark ? 0.20 : 0.14))
                                        : 0
                                )
                            )
                    )
                    .shadow(
                        color: buttonShadowColor,
                        radius: buttonShadowRadius,
                        y: buttonShadowY
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isDragHovering
                            ? dragTint.opacity(0.95)
                            : (animFrame.buttonGlowIntensity > 0.05
                                ? Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.85 * animFrame.buttonGlowIntensity)
                                : borderColor),
                        lineWidth: isDragHovering ? 1.5 : (animFrame.buttonGlowIntensity > 0.05 ? 1.25 : 0.75)
                    )
            )
            .scaleEffect(dragHoverState.didActivate ? 1.03 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.65), value: dragHoverState.didActivate)
            .overlay(alignment: showTitle ? .topTrailing : .topLeading) {
                if isPinnedOrderLocked {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7.5, weight: .semibold))
                        .rotationEffect(.degrees(32))
                        .foregroundStyle(
                            effectiveDark
                                ? Color.white.opacity(isHovered || item.isFocused ? 0.56 : 0.34)
                                : Color.black.opacity(isHovered || item.isFocused ? 0.48 : 0.26)
                        )
                        .padding(.top, 3)
                        .padding(.trailing, showTitle ? (buttonStyle == .pill ? 7 : 4.5) : 0)
                        .padding(.leading, showTitle ? 0 : 4)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if isDragHovering {
                    let trackWidth = max(14, buttonWidth - (buttonStyle == .pill ? 24 : 14))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(dragTint.opacity(effectiveDark ? 0.26 : 0.20))
                            .frame(width: trackWidth, height: 3.0)
                        Capsule()
                            .fill(dragTint)
                            .frame(width: max(4, trackWidth * max(0, min(1, dragHoverState.progress))), height: 3.0)
                    }
                    .padding(.bottom, 1.5)
                } else if item.isFocused {
                    switch activeIndicatorStyle {
                    case .pill:
                        Capsule()
                            .fill(indicatorAccent)
                            .frame(width: showTitle ? min(28, buttonWidth * 0.25) : 14, height: 2.5)
                            .padding(.bottom, 1.5)
                    case .fullUnderline:
                        Capsule()
                            .fill(indicatorAccent)
                            .frame(width: max(16, buttonWidth - (buttonStyle == .pill ? 24 : 14)), height: 2.5)
                            .padding(.bottom, 1.5)
                    case .dot:
                        Circle()
                            .fill(indicatorAccent)
                            .frame(width: 5, height: 5)
                            .padding(.bottom, 1.5)
                    case .none:
                        EmptyView()
                    }
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
                },
                onDragHoverChanged: { state in
                    dragHoverState = state
                }
            )
        )
        .help(buttonHelpTooltip)
    }

    private var buttonHelpTooltip: String {
        let loc = LocalizationManager.shared
        let base = item.isWindowlessApp
            ? loc.text(
                es: "\(item.appName) — Abierta sin ventanas (clic para abrir)",
                en: "\(item.appName) — Running without open windows (click to open)"
            )
            : item.displayTitle
        if isPinnedOrderLocked {
            return base + loc.text(
                es: " · Orden fijado según tus apps pineadas (arrastrá su ícono fijado a la izquierda para reordenar)",
                en: " · Locked to pinned apps order (drag its pinned icon on the left to reorder)"
            )
        }
        return base
    }
}

// MARK: - Controlador de Activación por Permanencia al Arrastrar (Spring-Loading 1 s)

@MainActor
private final class TaskbarDragSpringLoader {
    static let acceptedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        .tiff,
        .png,
        NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        NSPasteboard.PasteboardType(UTType.item.identifier),
        NSPasteboard.PasteboardType(UTType.data.identifier)
    ]

    private var tracker = TaskbarDragDwellTracker()
    nonisolated(unsafe) private var timer: Timer?
    private var lastReportedState: TaskbarDragHoverState = .idle
    private weak var hostView: NSView?

    var onStateChanged: ((TaskbarDragHoverState) -> Void)?
    var onActivate: (() -> Void)?

    init(hostView: NSView) {
        self.hostView = hostView
    }

    deinit {
        timer?.invalidate()
    }

    static func appBundleURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else {
            return []
        }
        let appURLs = urls.map(\.standardizedFileURL).filter {
            $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        }
        // Solo tratar como "fijar aplicación" si todos los ítems arrastrados son paquetes `.app`
        return appURLs.count == urls.count ? appURLs : []
    }

    @discardableResult
    static func pinAppBundlesIfPresent(from pasteboard: NSPasteboard) -> Bool {
        let appURLs = appBundleURLs(from: pasteboard)
        guard !appURLs.isEmpty else { return false }
        for appURL in appURLs {
            let bundle = Bundle(url: appURL)
            let bundleID = bundle?.bundleIdentifier ?? ""
            let name = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
                .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive, .anchored, .backwards])
            TaskbarPreferences.shared.pinApp(bundleIdentifier: bundleID, bundleURL: appURL, displayName: name)
        }
        return true
    }

    static func hoverDragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let mask = sender.draggingSourceOperationMask
        if !appBundleURLs(from: sender.draggingPasteboard).isEmpty, mask.contains(.copy) {
            return .copy
        }
        if mask.contains(.generic) { return .generic }
        if mask.contains(.copy) { return .copy }
        if mask.contains(.link) { return .link }
        if mask.contains(.move) { return .move }
        return mask.isEmpty ? [] : .generic
    }

    func handleDraggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = Self.hoverDragOperation(for: sender)
        guard !op.isEmpty else {
            cancel()
            return []
        }
        TaskbarPreviewPanelController.shared.hideImmediately()
        let point = localPoint(from: sender)
        let state = tracker.begin(at: point, now: ProcessInfo.processInfo.systemUptime)
        publishIfChanged(state)
        startTimer()
        return op
    }

    func handleDraggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = Self.hoverDragOperation(for: sender)
        guard !op.isEmpty else {
            cancel()
            return []
        }
        let point = localPoint(from: sender)
        let result = tracker.update(location: point, now: ProcessInfo.processInfo.systemUptime)
        publishIfChanged(result.state)
        if timer == nil {
            startTimer()
        }
        if result.shouldTriggerNow {
            triggerActivation()
        }
        return op
    }

    func handlePrepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let isPinDrop = !Self.appBundleURLs(from: sender.draggingPasteboard).isEmpty
        if !isPinDrop {
            cancel()
        }
        return isPinDrop
    }

    func handlePerformDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { cancel() }
        return Self.pinAppBundlesIfPresent(from: sender.draggingPasteboard)
    }

    func cancel(deferNotification: Bool = false) {
        stopTimer()
        let wasHovering = tracker.isActive || lastReportedState.isHovering
        _ = tracker.reset()
        lastReportedState = .idle
        guard wasHovering else { return }
        if deferNotification {
            let callback = onStateChanged
            DispatchQueue.main.async {
                callback?(.idle)
            }
        } else {
            onStateChanged?(.idle)
        }
    }

    private func localPoint(from sender: NSDraggingInfo) -> CGPoint {
        if let hostView {
            return hostView.convert(sender.draggingLocation, from: nil)
        }
        return sender.draggingLocation
    }

    private func startTimer() {
        stopTimer()
        // `.common` incluye `RunLoop.Mode.eventTracking`, indispensable durante sesiones activas de arrastre (`NSDraggingSession`)
        let newTimer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTick()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        RunLoop.main.add(newTimer, forMode: .eventTracking)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func handleTick() {
        guard tracker.isActive else {
            stopTimer()
            return
        }
        guard let hostView, let window = hostView.window, window.isVisible else {
            cancel()
            return
        }
        let screenRect = window.convertToScreen(hostView.convert(hostView.bounds, to: nil))
        if !screenRect.insetBy(dx: -14, dy: -14).contains(NSEvent.mouseLocation) {
            cancel()
            return
        }
        if tracker.didTrigger {
            return
        }
        let result = tracker.evaluate(now: ProcessInfo.processInfo.systemUptime)
        publishIfChanged(result.state)
        if result.shouldTriggerNow {
            triggerActivation()
        }
    }

    private func triggerActivation() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        TaskbarPreviewPanelController.shared.hideImmediately()
        onActivate?()
    }

    private func publishIfChanged(_ next: TaskbarDragHoverState) {
        let changed = next.isHovering != lastReportedState.isHovering
            || next.didActivate != lastReportedState.didActivate
            || abs(next.progress - lastReportedState.progress) >= 0.015
            || (next.progress == 0 && lastReportedState.progress != 0)
            || (next.progress == 1 && lastReportedState.progress != 1)
        guard changed else { return }
        lastReportedState = next
        onStateChanged?(next)
    }
}

// MARK: - Interceptores Nativos de Mouse AppKit (Clic Izq, Clic Central, Clic Derecho, Hover y Drag & Drop)

private struct TaskbarWindowButtonMouseOverlay: NSViewRepresentable {
    let item: TaskbarWindowItem
    let displayID: String
    let onHoverChanged: (Bool) -> Void
    let onDragHoverChanged: (TaskbarDragHoverState) -> Void

    func makeNSView(context: Context) -> TaskbarWindowMouseNSView {
        let view = TaskbarWindowMouseNSView()
        view.item = item
        view.displayID = displayID
        view.onHoverChanged = onHoverChanged
        view.onDragHoverChanged = onDragHoverChanged
        return view
    }

    func updateNSView(_ nsView: TaskbarWindowMouseNSView, context: Context) {
        let itemChanged = nsView.item?.id != item.id
        nsView.item = item
        nsView.displayID = displayID
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragHoverChanged = onDragHoverChanged
        if itemChanged {
            nsView.resetDragSpringLoaderDeferred()
        }
    }
}

private final class TaskbarWindowMouseNSView: NSView {
    var item: TaskbarWindowItem?
    var displayID: String = ""
    var onHoverChanged: ((Bool) -> Void)?
    var onDragHoverChanged: ((TaskbarDragHoverState) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var didStartDragging = false
    private var didShowPinnedOrderHintThisDrag = false
    private var didMoveWindowDuringDrag = false
    private lazy var springLoader: TaskbarDragSpringLoader = {
        let loader = TaskbarDragSpringLoader(hostView: self)
        loader.onStateChanged = { [weak self] state in
            self?.onDragHoverChanged?(state)
        }
        loader.onActivate = { [weak self] in
            guard let self, let item = self.item else { return }
            TaskbarWindowTracker.shared.focusWindow(item)
        }
        return loader
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(TaskbarDragSpringLoader.acceptedPasteboardTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(TaskbarDragSpringLoader.acceptedPasteboardTypes)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            springLoader.cancel(deferNotification: true)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func resetDragSpringLoaderDeferred() {
        springLoader.cancel(deferNotification: true)
    }

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
            let result = TaskbarWindowTracker.shared.moveWindow(sourceID: draggedID, toTargetID: item.id)
            if case .blockedByPinnedOrder(let appName, let isSourcePinned) = result,
               let screenRect = buttonScreenRect() {
                TaskbarPinnedOrderHintController.shared.show(
                    anchorScreenRect: screenRect,
                    displayID: displayID,
                    appName: appName,
                    isSourcePinned: isSourcePinned
                )
            }
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
        didShowPinnedOrderHintThisDrag = false
        didMoveWindowDuringDrag = false
        TaskbarPreviewPanelController.shared.hideImmediately()
        TaskbarPinnedOrderHintController.shared.hideImmediately()
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
                let result = TaskbarWindowTracker.shared.moveWindow(sourceID: item.id, toTargetID: targetItem.id)
                switch result {
                case .moved:
                    didMoveWindowDuringDrag = true
                case .blockedByPinnedOrder(let appName, let isSourcePinned):
                    if !didShowPinnedOrderHintThisDrag, let screenRect = buttonScreenRect() {
                        didShowPinnedOrderHintThisDrag = true
                        TaskbarPinnedOrderHintController.shared.show(
                            anchorScreenRect: screenRect,
                            displayID: displayID,
                            appName: appName,
                            isSourcePinned: isSourcePinned
                        )
                    }
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = didStartDragging
        let hadShownHint = didShowPinnedOrderHintThisDrag
        let hadMoved = didMoveWindowDuringDrag
        defer {
            mouseDownLocation = nil
            if didStartDragging {
                TaskbarManager.shared.draggingWindowID = nil
                didStartDragging = false
            }
            didShowPinnedOrderHintThisDrag = false
            didMoveWindowDuringDrag = false
        }
        if wasDragging {
            // Si el usuario arrastró una app fijada con ventana única sin cruzar otra app, igual explicar por qué no se movió
            if !hadMoved && !hadShownHint,
               let item,
               TaskbarPreferences.shared.orderWindowsByPinnedApps,
               TaskbarPreferences.shared.isPinned(
                   bundleIdentifier: item.bundleIdentifier,
                   bundlePath: item.appBundleURL?.standardizedFileURL.path(percentEncoded: false)
               ),
               let screenRect = buttonScreenRect() {
                TaskbarPinnedOrderHintController.shared.show(
                    anchorScreenRect: screenRect,
                    displayID: displayID,
                    appName: item.appName,
                    isSourcePinned: true
                )
            }
            return
        }
        guard let item else { return }
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

    // MARK: - `NSDraggingDestination` (Spring-Loading 1 s + Fijado de `.app`)

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        springLoader.handleDraggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        springLoader.handleDraggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        springLoader.cancel()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        springLoader.cancel()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        springLoader.handlePrepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        springLoader.handlePerformDragOperation(sender)
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
    let onDragHoverChanged: (TaskbarDragHoverState) -> Void

    func makeNSView(context: Context) -> TaskbarPinnedMouseNSView {
        let view = TaskbarPinnedMouseNSView()
        view.pinned = pinned
        view.onHoverChanged = onHoverChanged
        view.onDragHoverChanged = onDragHoverChanged
        return view
    }

    func updateNSView(_ nsView: TaskbarPinnedMouseNSView, context: Context) {
        let pinnedChanged = nsView.pinned?.id != pinned.id
        nsView.pinned = pinned
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragHoverChanged = onDragHoverChanged
        if pinnedChanged {
            nsView.resetDragSpringLoaderDeferred()
        }
    }
}

private final class TaskbarPinnedMouseNSView: NSView {
    var pinned: TaskbarPinnedApp?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragHoverChanged: ((TaskbarDragHoverState) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var didStartDragging = false
    private lazy var springLoader: TaskbarDragSpringLoader = {
        let loader = TaskbarDragSpringLoader(hostView: self)
        loader.onStateChanged = { [weak self] state in
            self?.onDragHoverChanged?(state)
        }
        loader.onActivate = { [weak self] in
            guard let self, let pinned = self.pinned else { return }
            TaskbarWindowTracker.shared.launchOrFocusApplication(
                bundleIdentifier: pinned.bundleIdentifier,
                bundleURL: pinned.bundleURL
            )
        }
        return loader
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(TaskbarDragSpringLoader.acceptedPasteboardTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(TaskbarDragSpringLoader.acceptedPasteboardTypes)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            springLoader.cancel(deferNotification: true)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func resetDragSpringLoaderDeferred() {
        springLoader.cancel(deferNotification: true)
    }

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

    // MARK: - `NSDraggingDestination` (Spring-Loading 1 s + Fijado de `.app`)

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        springLoader.handleDraggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        springLoader.handleDraggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        springLoader.cancel()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        springLoader.cancel()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        springLoader.handlePrepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        springLoader.handlePerformDragOperation(sender)
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
    let onAppDropTargetedChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TaskbarEmptyBackgroundMouseNSView {
        let view = TaskbarEmptyBackgroundMouseNSView()
        view.displayID = displayID
        view.onAppDropTargetedChanged = onAppDropTargetedChanged
        return view
    }

    func updateNSView(_ nsView: TaskbarEmptyBackgroundMouseNSView, context: Context) {
        nsView.displayID = displayID
        nsView.onAppDropTargetedChanged = onAppDropTargetedChanged
    }
}

private final class TaskbarEmptyBackgroundMouseNSView: NSView {
    var displayID: String = ""
    var onAppDropTargetedChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType(UTType.fileURL.identifier)])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType(UTType.fileURL.identifier)])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        TaskbarPreviewPanelController.shared.hideImmediately()
        let menu = TaskbarContextMenuBuilder.buildBarBackgroundMenu(displayID: displayID)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canPin = !TaskbarDragSpringLoader.appBundleURLs(from: sender.draggingPasteboard).isEmpty
        onAppDropTargetedChanged?(canPin)
        return canPin ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canPin = !TaskbarDragSpringLoader.appBundleURLs(from: sender.draggingPasteboard).isEmpty
        onAppDropTargetedChanged?(canPin)
        return canPin ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onAppDropTargetedChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onAppDropTargetedChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !TaskbarDragSpringLoader.appBundleURLs(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onAppDropTargetedChanged?(false)
        return TaskbarDragSpringLoader.pinAppBundlesIfPresent(from: sender.draggingPasteboard)
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
            if item.bundleIdentifier.caseInsensitiveCompare("com.apple.finder") != .orderedSame && prefs.showWindowlessRunningApps {
                let alreadyHiddenWhenWindowless = prefs.isHiddenWhenWindowless(bundleIdentifier: item.bundleIdentifier)
                let windowlessItem = makeItem(
                    title: loc.text(
                        es: "Ocultar \(item.appName) cuando no tenga ventanas",
                        en: "Hide \(item.appName) When Windowless"
                    ),
                    symbol: "macwindow.badge.minus"
                ) {
                    if alreadyHiddenWhenWindowless {
                        prefs.removeAppHiddenWhenWindowless(bundleIdentifier: item.bundleIdentifier)
                    } else {
                        prefs.hideAppWhenWindowless(bundleIdentifier: item.bundleIdentifier)
                    }
                }
                windowlessItem.state = alreadyHiddenWhenWindowless ? .on : .off
                menu.addItem(windowlessItem)
            }

            menu.addItem(makeItem(
                title: loc.text(es: "Ocultar \(item.appName) de la barra de tareas", en: "Exclude \(item.appName) from Taskbar"),
                symbol: "eye.slash.circle"
            ) {
                prefs.excludeApp(bundleIdentifier: item.bundleIdentifier)
            })
        }

        let groupToggleItem = makeItem(
            title: loc.text(
                es: "Mantener ventanas de la misma app juntas (lado a lado)",
                en: "Keep Same-App Windows Side by Side"
            ),
            symbol: "rectangle.split.2x1"
        ) {
            prefs.groupWindowsByApp.toggle()
        }
        groupToggleItem.state = prefs.groupWindowsByApp ? .on : .off
        menu.addItem(groupToggleItem)

        let pinnedOrderItem = makeItem(
            title: loc.text(
                es: "Apps fijadas primero en la barra (en su mismo orden)",
                en: "Pinned Apps' Windows First (in Pinned Order)"
            ),
            symbol: "pin.circle"
        ) {
            prefs.orderWindowsByPinnedApps.toggle()
        }
        pinnedOrderItem.state = prefs.orderWindowsByPinnedApps ? .on : .off
        menu.addItem(pinnedOrderItem)

        let shrinkToFitItem = makeItem(
            title: loc.text(
                es: "Ajustar ancho sin scroll horizontal",
                en: "Auto-Shrink Buttons (No Scroll)"
            ),
            symbol: "arrow.right.and.line.vertical.and.arrow.left"
        ) {
            prefs.overflowMode = (prefs.overflowMode == .shrinkToFit) ? .horizontalScroll : .shrinkToFit
        }
        shrinkToFitItem.state = (prefs.overflowMode == .shrinkToFit) ? .on : .off
        menu.addItem(shrinkToFitItem)

        let iconsOnlyItem = makeItem(
            title: loc.text(
                es: "Mostrar solo íconos",
                en: "Show Icons Only"
            ),
            symbol: "square.grid.2x2"
        ) {
            prefs.iconsOnlyMode.toggle()
        }
        iconsOnlyItem.state = prefs.iconsOnlyMode ? .on : .off
        menu.addItem(iconsOnlyItem)

        let minimizedIconOnlyItem = makeItem(
            title: loc.text(
                es: "Solo ícono en ventanas minimizadas",
                en: "Icon Only for Minimized Windows"
            ),
            symbol: "app.dashed",
            isEnabled: prefs.showWindowTitles
        ) {
            prefs.minimizedWindowDisplayMode = (prefs.minimizedWindowDisplayMode == .iconOnly) ? .sameAsNormal : .iconOnly
        }
        minimizedIconOnlyItem.state = (prefs.minimizedWindowDisplayMode == .iconOnly) ? .on : .off
        menu.addItem(minimizedIconOnlyItem)

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

        let groupToggleItem = makeItem(
            title: loc.text(
                es: "Mantener ventanas de la misma app juntas (lado a lado)",
                en: "Keep Same-App Windows Side by Side"
            ),
            symbol: "rectangle.split.2x1"
        ) {
            prefs.groupWindowsByApp.toggle()
        }
        groupToggleItem.state = prefs.groupWindowsByApp ? .on : .off
        menu.addItem(groupToggleItem)

        let pinnedOrderItem = makeItem(
            title: loc.text(
                es: "Apps fijadas primero en la barra (en su mismo orden)",
                en: "Pinned Apps' Windows First (in Pinned Order)"
            ),
            symbol: "pin.circle"
        ) {
            prefs.orderWindowsByPinnedApps.toggle()
        }
        pinnedOrderItem.state = prefs.orderWindowsByPinnedApps ? .on : .off
        menu.addItem(pinnedOrderItem)

        let shrinkToFitItem = makeItem(
            title: loc.text(
                es: "Ajustar ancho sin scroll horizontal",
                en: "Auto-Shrink Buttons (No Scroll)"
            ),
            symbol: "arrow.right.and.line.vertical.and.arrow.left"
        ) {
            prefs.overflowMode = (prefs.overflowMode == .shrinkToFit) ? .horizontalScroll : .shrinkToFit
        }
        shrinkToFitItem.state = (prefs.overflowMode == .shrinkToFit) ? .on : .off
        menu.addItem(shrinkToFitItem)

        let iconsOnlyItem = makeItem(
            title: loc.text(
                es: "Mostrar solo íconos",
                en: "Show Icons Only"
            ),
            symbol: "square.grid.2x2"
        ) {
            prefs.iconsOnlyMode.toggle()
        }
        iconsOnlyItem.state = prefs.iconsOnlyMode ? .on : .off
        menu.addItem(iconsOnlyItem)

        let minimizedIconOnlyItem = makeItem(
            title: loc.text(
                es: "Solo ícono en ventanas minimizadas",
                en: "Icon Only for Minimized Windows"
            ),
            symbol: "app.dashed",
            isEnabled: prefs.showWindowTitles
        ) {
            prefs.minimizedWindowDisplayMode = (prefs.minimizedWindowDisplayMode == .iconOnly) ? .sameAsNormal : .iconOnly
        }
        minimizedIconOnlyItem.state = (prefs.minimizedWindowDisplayMode == .iconOnly) ? .on : .off
        menu.addItem(minimizedIconOnlyItem)

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

// MARK: - Aviso Flotante Explicativo al Intentar Mover una App con Orden Fijado

@MainActor
public final class TaskbarPinnedOrderHintController {

    public static let shared = TaskbarPinnedOrderHintController()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    public var panelWindowNumber: Int? {
        panel?.windowNumber
    }

    private init() {}

    public func show(
        anchorScreenRect: NSRect,
        displayID: String,
        appName: String,
        isSourcePinned: Bool
    ) {
        dismissWorkItem?.cancel()
        TaskbarPreviewPanelController.shared.hideImmediately()

        let hintPanel = ensurePanel()
        let contentView = TaskbarPinnedOrderHintView(
            appName: appName,
            isSourcePinned: isSourcePinned,
            onDisableLock: { [weak self] in
                TaskbarPreferences.shared.orderWindowsByPinnedApps = false
                self?.hideImmediately()
            },
            onDismiss: { [weak self] in
                self?.hideImmediately()
            }
        )

        let hosting = NSHostingView(rootView: contentView)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let width = min(372, max(290, ceil(fitting.width)))
        let height = max(62, ceil(fitting.height))

        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: anchorScreenRect.midX, y: anchorScreenRect.midY))
        }) ?? NSScreen.main ?? NSScreen.screens.first
        let bounds = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let idealX = anchorScreenRect.midX - (width * 0.5)
        let clampedX = min(max(bounds.minX + 10, idealX), bounds.maxX - width - 10)
        let barTopY = TaskbarManager.shared.barFrame(for: displayID)?.maxY ?? anchorScreenRect.maxY
        let targetY = min(bounds.maxY - height - 10, barTopY + 8)

        hintPanel.contentView = hosting
        hintPanel.setFrame(NSRect(x: round(clampedX), y: round(targetY), width: width, height: height), display: true)

        if !hintPanel.isVisible {
            hintPanel.alphaValue = 0
            hintPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hintPanel.animator().alphaValue = 1
            }
        } else {
            hintPanel.alphaValue = 1
            hintPanel.orderFrontRegardless()
        }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.fadeOutAndHide()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    public func hideImmediately() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
    }

    private func fadeOutAndHide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel?.orderOut(nil)
                self?.panel?.alphaValue = 1
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let existing = panel {
            return existing
        }
        let created = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.isReleasedWhenClosed = false
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = true
        created.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        created.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.panel = created
        return created
    }
}

private struct TaskbarPinnedOrderHintView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var prefs = TaskbarPreferences.shared
    @Bindable private var loc = LocalizationManager.shared

    let appName: String
    let isSourcePinned: Bool
    let onDisableLock: () -> Void
    let onDismiss: () -> Void

    private var effectiveDark: Bool {
        switch prefs.themeMode {
        case .system: return colorScheme == .dark
        case .light: return false
        case .dark: return true
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(effectiveDark ? 0.22 : 0.14))
                    .frame(width: 26, height: 26)
                Image(systemName: "pin.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .rotationEffect(.degrees(32))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(loc.text(
                    es: "Orden fijado según tus apps pineadas",
                    en: "Locked to Pinned Apps Order"
                ))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)

                Text(
                    isSourcePinned
                        ? loc.text(
                            es: "«\(appName)» sigue el orden de tus íconos fijados a la izquierda. Arrastrá su ícono fijado para cambiarla de lugar.",
                            en: "\"\(appName)\" follows the order of your pinned icons on the left. Drag its pinned icon to change position."
                        )
                        : loc.text(
                            es: "Las apps no fijadas van después de las fijadas. Fijá «\(appName)» para moverla al principio.",
                            en: "Unpinned apps stay after pinned ones. Pin \"\(appName)\" to place it up front."
                        )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        onDisableLock()
                    } label: {
                        Text(loc.text(
                            es: "Desactivar «Apps fijadas primero»",
                            en: "Turn Off \"Pinned Apps First\""
                        ))
                        .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 356, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(effectiveDark ? Color(white: 0.14).opacity(0.95) : Color(white: 0.98).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(effectiveDark ? Color.white.opacity(0.16) : Color.black.opacity(0.12), lineWidth: 0.9)
        )
        .preferredColorScheme(effectiveDark ? .dark : .light)
    }
}
