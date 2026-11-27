import AppKit
import Observation
import SwiftUI

/// Pestaña activa dentro de la ventana «Acerca de MacFileExplorer».
public enum AboutAppTab: String, CaseIterable, Identifiable, Sendable {
    case releaseNotes
    case reportBug

    public var id: String { rawValue }
}

/// Comparación activa de actualización de versión para resaltar novedades en «Notas de la versión».
public struct AboutUpgradeComparison: Equatable, Sendable {
    public let previousVersion: String
    public let currentVersion: String

    public init(previousVersion: String, currentVersion: String) {
        self.previousVersion = AppVersionComparator.displayVersion(previousVersion)
        self.currentVersion = AppVersionComparator.displayVersion(currentVersion)
    }
}

@MainActor
@Observable
private final class AboutWindowNavigationState {
    var selectedTab: AboutAppTab = .releaseNotes
    var upgradeComparison: AboutUpgradeComparison? = nil
}

/// Controlador singleton para presentar la ventana nativa "Acerca de MacFileExplorer"
/// con información de autoría, versión, Notas de la versión y formulario para reportar errores/ideas en GitHub.
@MainActor
public final class AboutWindowController {
    public static let shared = AboutWindowController()

    private var window: NSWindow?
    private let navigationState = AboutWindowNavigationState()

    private init() {}

    public func show(initialTab: AboutAppTab = .releaseNotes) {
        navigationState.selectedTab = initialTab
        navigationState.upgradeComparison = nil
        BugReportService.shared.refreshLogScan(allowRelayAutoSubmit: false)
        presentWindow(title: localizedWindowTitle())
    }

    /// Abre la ventana directamente en «Notas de la versión» resaltando todas las novedades
    /// agregadas entre `previousVersion` y `currentVersion` tras una actualización.
    public func showWhatsNewUpgrade(
        fromPreviousVersion previousVersion: String,
        toCurrentVersion currentVersion: String
    ) {
        navigationState.selectedTab = .releaseNotes
        navigationState.upgradeComparison = AboutUpgradeComparison(
            previousVersion: previousVersion,
            currentVersion: currentVersion
        )
        BugReportService.shared.refreshLogScan(allowRelayAutoSubmit: false)
        presentWindow(title: localizedWindowTitle())
    }

    public func refreshLocalizedTitle() {
        window?.title = localizedWindowTitle()
    }

    public func close() {
        window?.close()
    }

    private func localizedWindowTitle() -> String {
        if let upgrade = navigationState.upgradeComparison {
            return LocalizationManager.shared.text(
                es: "Novedades en MacFileExplorer v\(upgrade.currentVersion)",
                en: "What's New in MacFileExplorer v\(upgrade.currentVersion)"
            )
        }
        return LocalizationManager.shared.text(
            es: "Acerca de MacFileExplorer",
            en: "About MacFileExplorer"
        )
    }

    private func presentWindow(title: String) {
        if let existingWindow = window {
            existingWindow.title = title
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let createdWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 730),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        createdWindow.minSize = NSSize(width: 670, height: 640)
        createdWindow.title = title
        createdWindow.titlebarAppearsTransparent = true
        createdWindow.titleVisibility = .hidden
        createdWindow.isMovableByWindowBackground = true
        createdWindow.isReleasedWhenClosed = false
        createdWindow.contentView = NSHostingView(
            rootView: AboutAppView(
                navigationState: navigationState,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        createdWindow.center()
        createdWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = createdWindow
    }
}

/// Ventana "Acerca de MacFileExplorer" con créditos de autoría, Release Notes y Reporte de errores/ideas en GitHub.
public struct AboutAppView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var updateManager = AppUpdateManager.shared
    @Bindable private var iconProvider = FileIconProvider.shared
    @Bindable private var bugReport = BugReportService.shared
    @Bindable private var navigationState: AboutWindowNavigationState

    // Estado del formulario nativo de reporte de bugs / ideas
    @ViewState private var selectedCategory: BugReportCategory = .bug
    @ViewState private var reportSummary: String = ""
    @ViewState private var reportDetails: String = ""
    @ViewState private var attachSanitizedLogs: Bool = true
    @ViewState private var showSanitizedPreview: Bool = false
    @ViewState private var submissionFeedback: String? = nil
    @ViewState private var submissionSucceeded: Bool = false

    private let onClose: (() -> Void)?

    public init(initialTab: AboutAppTab = .releaseNotes, onClose: (() -> Void)? = nil) {
        let state = AboutWindowNavigationState()
        state.selectedTab = initialTab
        self._navigationState = Bindable(state)
        self.onClose = onClose
    }

    /// Inicializador directo para abrir o previsualizar «Notas de la versión» en modo comparación post-actualización.
    public init(
        upgradeFrom previousVersion: String,
        to currentVersion: String,
        onClose: (() -> Void)? = nil
    ) {
        let state = AboutWindowNavigationState()
        state.selectedTab = .releaseNotes
        state.upgradeComparison = AboutUpgradeComparison(
            previousVersion: previousVersion,
            currentVersion: currentVersion
        )
        self._navigationState = Bindable(state)
        self.onClose = onClose
    }

    fileprivate init(navigationState: AboutWindowNavigationState, onClose: (() -> Void)? = nil) {
        self._navigationState = Bindable(navigationState)
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 12)

            if navigationState.selectedTab == .releaseNotes && navigationState.upgradeComparison == nil {
                KoFiSupportCardView(compact: true)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 12)
            }

            Divider()

            tabSelectorBar
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.02))

            Divider()

            Group {
                switch navigationState.selectedTab {
                case .releaseNotes:
                    releaseNotesSection
                case .reportBug:
                    reportBugSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if navigationState.selectedTab == .releaseNotes {
                Divider()

                legalDisclaimerSection
                    .padding(.horizontal, 26)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.025))
            }

            Divider()

            footerSection
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        }
        .frame(minWidth: 670, idealWidth: 750, minHeight: 640, idealHeight: 730)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            bugReport.refreshLogScan(allowRelayAutoSubmit: false)
        }
        .onExitCommand {
            closeWindow()
        }
    }

    private var versionLabel: String {
        "v\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild) • Swift 6)"
    }

    private var activeLogScan: InternalErrorScanReport? {
        bugReport.unreportedScan ?? bugReport.recentScan
    }

    // MARK: - Encabezado

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 6) {
                Group {
                    if let appIcon = iconProvider.appIcon(for: colorScheme) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                    } else {
                        Image(systemName: "folder.fill.badge.gearshape")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 70, height: 70)
                    }
                }
                .onTapGesture {
                    AppIconPickerWindowController.shared.show()
                }
                .help(loc.text(es: "Clic para cambiar el ícono de MacFileExplorer", en: "Click to change the MacFileExplorer app icon"))

                Button {
                    AppIconPickerWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Cambiar ícono…", en: "Change Icon…"),
                        systemImage: "app.badge.checkmark"
                    )
                    .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("MacFileExplorer")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(versionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )
                }

                HStack(spacing: 4) {
                    Text(loc.text(es: "Desarrollado por", en: "Developed by"))
                        .foregroundStyle(.secondary)
                    Text("Luis Javier Romero")
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(loc.text(es: "Creador y Arquitecto de Software", en: "Creator & Software Architect"))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))

                Text(loc.text(
                    es: "Explorador de Archivos estilo Windows 11 con estética nativa para macOS. Construido con Swift 6, SwiftUI y AppKit.",
                    en: "Windows 11 Style File Explorer with native macOS aesthetics. Built with Swift 6, SwiftUI & AppKit."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                checkUpgradesControl

                Button {
                    AppOnboardingManager.shared.startWizardManually()
                } label: {
                    Label(
                        loc.text(es: "Asistente inicial…", en: "Setup Wizard…"),
                        systemImage: "wand.and.stars"
                    )
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(loc.text(
                    es: "Volver a ejecutar el asistente de configuración paso a paso",
                    en: "Re-run the step-by-step Setup Wizard"
                ))
            }
            .fixedSize()
        }
    }

    // MARK: - Selector de Pestañas (Notas de la versión | Reportar error / Idea)

    private var tabSelectorBar: some View {
        HStack(spacing: 8) {
            aboutTabPill(
                tab: .releaseNotes,
                icon: "sparkles",
                title: loc.text(es: "Notas de la versión", en: "Release Notes"),
                badgeText: "\(totalFeatureCount)",
                badgeTint: .secondary
            )

            aboutTabPill(
                tab: .reportBug,
                icon: "ladybug.fill",
                title: loc.text(es: "Reportar error / Idea", en: "Report Bug / Idea"),
                badgeText: bugReport.hasUnreportedErrors ? "\(bugReport.unreportedUniqueCount)" : nil,
                badgeTint: .orange
            )

            Spacer()

            if navigationState.selectedTab == .reportBug {
                Button {
                    NSWorkspace.shared.open(bugReport.allIssuesPageURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(loc.text(es: "Ver reportes anteriores", en: "View past reports"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func aboutTabPill(
        tab: AboutAppTab,
        icon: String,
        title: String,
        badgeText: String?,
        badgeTint: Color
    ) -> some View {
        let isSelected = navigationState.selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                navigationState.selectedTab = tab
            }
            if tab == .reportBug {
                bugReport.refreshLogScan(allowRelayAutoSubmit: false)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : (tab == .reportBug ? Color.orange : Color.accentColor))

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : .primary)

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.white : badgeTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.22) : badgeTint.opacity(0.16))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.09), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pestaña 1: Notas de la Versión

    private var releaseNotesSection: some View {
        let upgradeComparison = navigationState.upgradeComparison
        let sections = ReleaseNotesCatalog.sections
        let hasNewerSections = upgradeComparison.map { cmp in
            sections.contains { $0.isNewer(than: cmp.previousVersion) }
        } ?? false
        let firstOlderSectionID: String? = upgradeComparison.flatMap { cmp in
            guard hasNewerSections else { return nil }
            return sections.first { !$0.isNewer(than: cmp.previousVersion) }?.id
        }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let comparison = upgradeComparison {
                    upgradeCelebrationBanner(comparison)
                }

                ForEach(sections) { section in
                    let isNewSinceUpgrade = upgradeComparison.map { section.isNewer(than: $0.previousVersion) } ?? false
                    let isDimmedOlder = (upgradeComparison != nil) && !isNewSinceUpgrade

                    if firstOlderSectionID == section.id {
                        previouslyInstalledDivider
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            if let comparison = upgradeComparison, isNewSinceUpgrade {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 9.5, weight: .bold))
                                    Text(loc.text(
                                        es: "NUEVO DESDE v\(comparison.previousVersion)",
                                        en: "NEW SINCE v\(comparison.previousVersion)"
                                    ))
                                    .font(.system(size: 9.5, weight: .heavy))
                                    .tracking(0.35)
                                }
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor)
                                )
                                .fixedSize()
                            }

                            Text(section.localizedVersionLabel(using: loc))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isDimmedOlder ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            Text(section.localizedDateLabel(using: loc))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(isDimmedOlder ? .secondary : Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isDimmedOlder ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.12))
                                )
                                .fixedSize()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.items) { item in
                                ReleaseNoteRow(
                                    icon: item.icon,
                                    title: item.localizedTitle(using: loc),
                                    detail: item.localizedSummary(using: loc),
                                    newBadgeText: isNewSinceUpgrade ? loc.text(es: "NUEVO", en: "NEW") : nil
                                )
                            }
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isNewSinceUpgrade
                                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.11 : 0.065)
                                        : Color.primary.opacity(0.035)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isNewSinceUpgrade ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.07),
                                    lineWidth: isNewSinceUpgrade ? 1.2 : 0.8
                                )
                        )
                    }
                    .opacity(isDimmedOlder ? 0.72 : 1.0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private func upgradeCelebrationBanner(_ comparison: AboutUpgradeComparison) -> some View {
        let newCount = ReleaseNotesCatalog.newItemsCount(since: comparison.previousVersion)
        let summaryText: String = {
            if newCount == 1 {
                return loc.text(
                    es: "Se agregó 1 novedad y mejora desde v\(comparison.previousVersion). Todo lo nuevo aparece resaltado abajo.",
                    en: "1 new feature & update added since v\(comparison.previousVersion). Everything new is highlighted below."
                )
            } else if newCount > 1 {
                return loc.text(
                    es: "Se agregaron \(newCount) novedades y mejoras desde v\(comparison.previousVersion). Todo lo nuevo aparece resaltado abajo.",
                    en: "\(newCount) new features & updates added since v\(comparison.previousVersion). Everything new is highlighted below."
                )
            } else {
                return loc.text(
                    es: "Ya estás usando MacFileExplorer v\(comparison.currentVersion) con todas las mejoras más recientes.",
                    en: "You're now running MacFileExplorer v\(comparison.currentVersion) with all the latest improvements."
                )
            }
        }()

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.purple.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(loc.text(
                    es: "✨ ¡MacFileExplorer se actualizó de v\(comparison.previousVersion) a v\(comparison.currentVersion)!",
                    en: "✨ MacFileExplorer upgraded from v\(comparison.previousVersion) to v\(comparison.currentVersion)!"
                ))
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

                Text(summaryText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.4)

                HStack(spacing: 8) {
                    if newCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(loc.text(
                                es: newCount == 1 ? "1 novedad desde v\(comparison.previousVersion)" : "\(newCount) novedades desde v\(comparison.previousVersion)",
                                en: newCount == 1 ? "1 update since v\(comparison.previousVersion)" : "\(newCount) updates since v\(comparison.previousVersion)"
                            ))
                            .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                    }

                    Button {
                        dismissUpgradeHighlights()
                    } label: {
                        Text(loc.text(es: "Ver todo sin resaltar", en: "View all without highlights"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismissUpgradeHighlights()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Quitar resaltado de actualización", en: "Dismiss upgrade highlights"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14),
                            Color.purple.opacity(colorScheme == .dark ? 0.16 : 0.09),
                            Color.blue.opacity(colorScheme == .dark ? 0.12 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.42), lineWidth: 1.1)
        )
    }

    private var previouslyInstalledDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text(loc.text(
                    es: "Versiones ya instaladas anteriormente",
                    en: "Previously installed versions"
                ))
                .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .fixedSize()

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func dismissUpgradeHighlights() {
        withAnimation(.easeInOut(duration: 0.2)) {
            navigationState.upgradeComparison = nil
        }
        AppOnboardingManager.shared.clearPendingUpgradeComparison()
        AboutWindowController.shared.refreshLocalizedTitle()
    }

    // MARK: - Pestaña 2: Reportar Error / Idea (sin scroll, simple y directa)

    private var reportBugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Encabezado cálido + selector de tipo en una sola franja limpia
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(
                        es: "¿Algo falló o tenés una idea?",
                        en: "Something went wrong or have an idea?"
                    ))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.primary)

                    Text(loc.text(
                        es: "Contanos en dos líneas. Completamos los datos de tu Mac automáticamente.",
                        en: "Tell us in a couple of lines. We fill in your Mac details automatically."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            // Selector de tipo (Error / Idea / Consulta)
            HStack(spacing: 8) {
                ForEach(BugReportCategory.allCases) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.systemImage)
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(category.localizedTitle(using: loc))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.10), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Título breve (obligatorio)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(loc.text(es: "Título breve", en: "Short title"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("*")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                TextField(
                    selectedCategory == .enhancement
                        ? loc.text(
                            es: "Ej: Agregar vista en columnas al explorador",
                            en: "e.g. Add a quick column view option"
                        )
                        : loc.text(
                            es: "Ej: El reproductor del Notch no actualizó el título de la canción",
                            en: "e.g. Notch player didn't update the song title"
                        ),
                    text: $reportSummary
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
            }

            // Descripción opcional (flexible, sin scroll externo)
            VStack(alignment: .leading, spacing: 5) {
                Text(loc.text(es: "Contanos qué pasó (opcional)", en: "What happened? (optional)"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    if reportDetails.isEmpty {
                        Text(
                            selectedCategory == .enhancement
                                ? loc.text(
                                    es: "Explicanos brevemente cómo te gustaría que funcione…",
                                    en: "Briefly explain how you'd like it to work…"
                                )
                                : loc.text(
                                    es: "Contanos qué estabas haciendo y qué esperabas ver…",
                                    en: "Tell us what you were doing and what you expected to see…"
                                )
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                    }

                    TextEditor(text: $reportDetails)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                }
                .frame(minHeight: 72, maxHeight: 118)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8)
                )
            }

            // Tarjeta compacta y amigable de privacidad y diagnóstico automático
            internalDiagnosticsCard

            if let submissionFeedback {
                HStack(spacing: 7) {
                    Image(systemName: submissionSucceeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(submissionSucceeded ? .green : .orange)
                    Text(submissionFeedback)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((submissionSucceeded ? Color.green : Color.orange).opacity(0.12))
                )
            }

            Spacer(minLength: 2)

            // Barra de acción principal siempre visible (sin necesidad de hacer scroll)
            let canSubmit = !reportSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !bugReport.isSubmitting
            HStack(alignment: .center, spacing: 10) {
                Button {
                    submitCurrentForm()
                } label: {
                    HStack(spacing: 7) {
                        if bugReport.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(selectedCategory.localizedSubmitButtonTitle(using: loc))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(canSubmit ? 1.0 : 0.88))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(canSubmit ? 1.0 : 0.48))
                    )
                }
                .buttonStyle(.plain)
                .disabled(bugReport.isSubmitting)

                if let scan = bugReport.unreportedScan, !scan.isEmpty {
                    Button {
                        Task {
                            let outcome = await bugReport.submitMonthlyAutoReport(from: scan)
                            applyFeedback(for: outcome)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text(loc.text(
                                es: scan.uniqueCount == 1
                                    ? "Enviar 1 error detectado"
                                    : "Enviar \(scan.uniqueCount) errores detectados",
                                en: scan.uniqueCount == 1
                                    ? "Send 1 Detected Error"
                                    : "Send \(scan.uniqueCount) Detected Errors"
                            ))
                            .font(.system(size: 11.8, weight: .semibold))
                            .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.11))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.9)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 8)

                if !bugReport.hasRelayConfigured {
                    Text(loc.text(
                        es: "Se abre listo para confirmar en GitHub",
                        en: "Opens pre-filled on GitHub to confirm"
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var internalDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Toggle(isOn: $attachSanitizedLogs) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                            Text(loc.text(
                                es: "Incluir diagnóstico técnico (sin datos personales)",
                                en: "Include technical diagnostics (no personal data)"
                            ))
                            .font(.system(size: 11.8, weight: .semibold))
                        }

                        if let scan = activeLogScan, !scan.isEmpty {
                            Text(loc.text(
                                es: scan.uniqueCount == 1
                                    ? "1 error reciente detectado · oculta tu nombre, archivos y correos"
                                    : "\(scan.uniqueCount) errores recientes detectados · oculta tu nombre, archivos y correos",
                                en: scan.uniqueCount == 1
                                    ? "1 recent error found · hides your name, filenames & emails"
                                    : "\(scan.uniqueCount) recent errors found · hides your name, filenames & emails"
                            ))
                            .font(.system(size: 10.8))
                            .foregroundStyle(.orange)
                        } else {
                            Text(loc.text(
                                es: "Sin errores recientes · solo se adjunta versión de la app y macOS",
                                en: "No recent errors · only your app & macOS version are included"
                            ))
                            .font(.system(size: 10.8))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)

                Spacer(minLength: 8)

                Button {
                    showSanitizedPreview.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(loc.text(es: "Ver detalle", en: "Preview"))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showSanitizedPreview, arrowEdge: .top) {
                    sanitizedDiagnosticsPopover
                }
            }

            Divider().opacity(0.45)

            Toggle(isOn: $bugReport.monthlyLogScanEnabled) {
                Text(loc.text(
                    es: "Avisarme una vez al mes si la app detecta errores internos",
                    en: "Notify me once a month if the app detects internal errors"
                ))
                .font(.system(size: 11.2, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)

            if bugReport.hasRelayConfigured {
                Toggle(isOn: $bugReport.autoSubmitViaRelayEnabled) {
                    Text(loc.text(
                        es: "Enviar errores mensuales automáticamente en segundo plano",
                        en: "Automatically send monthly error summaries in the background"
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
        )
    }

    private var sanitizedDiagnosticsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text(loc.text(
                    es: "Datos técnicos que se incluirán",
                    en: "Technical details included"
                ))
                .font(.system(size: 12.5, weight: .bold))
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                Text(bugReport.environmentSummaryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let scan = activeLogScan, !scan.isEmpty {
                ScrollView {
                    Text(bugReport.formattedSanitizedLogMarkdown(for: scan))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
                )
            } else {
                Text(loc.text(
                    es: "No hay errores registrados en el historial interno. Solo se enviará la versión de la app y de tu Mac.",
                    en: "No internal errors recorded. Only your app and macOS version will be included."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }

            HStack(spacing: 8) {
                Button {
                    bugReport.revealInternalErrorLog()
                } label: {
                    Label(loc.text(es: "Ver archivo de registro", en: "Reveal Log File"), systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if activeLogScan != nil {
                    Button {
                        bugReport.clearInternalErrorLog()
                    } label: {
                        Label(loc.text(es: "Limpiar historial", en: "Clear Log"), systemImage: "trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Button(loc.text(es: "Listo", en: "Done")) {
                    showSanitizedPreview = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 440)
    }

    private func submitCurrentForm() {
        let trimmedSummary = reportSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else {
            submissionSucceeded = false
            submissionFeedback = loc.text(
                es: "Escribí un título breve arriba para poder enviar tu mensaje.",
                en: "Please enter a short title above before sending."
            )
            return
        }
        submissionFeedback = nil
        let details = reportDetails
        let category = selectedCategory
        let includeLogs = attachSanitizedLogs && activeLogScan != nil

        Task {
            let outcome = await bugReport.submitManualReport(
                category: category,
                summary: trimmedSummary,
                details: details,
                includeSanitizedLogs: includeLogs
            )
            applyFeedback(for: outcome)
        }
    }

    private func applyFeedback(for outcome: BugReportSubmissionOutcome?) {
        guard let outcome else { return }
        switch outcome {
        case .openedGitHubBrowser:
            submissionSucceeded = true
            submissionFeedback = loc.text(
                es: "Se abrió tu reporte ya prellenado en GitHub. Solo revisalo y hacé clic en «Create».",
                en: "Opened your pre-filled report on GitHub. Just review it and click «Create»."
            )
        case .submittedViaRelay(_, let deduplicated):
            submissionSucceeded = true
            submissionFeedback = deduplicated
                ? loc.text(es: "Reporte sumado a un issue existente en GitHub. ¡Gracias!", en: "Report added to an existing GitHub issue. Thank you!")
                : loc.text(es: "¡Reporte enviado directamente a GitHub! Muchas gracias.", en: "Report submitted directly to GitHub! Thank you.")
            reportSummary = ""
            reportDetails = ""
        case .failed(let msg):
            submissionSucceeded = false
            submissionFeedback = loc.text(
                es: "No se pudo enviar el reporte (\(msg)).",
                en: "Could not send report (\(msg))."
            )
        }
    }

    // MARK: - Legal & Footer

    private var legalDisclaimerSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2.5) {
                Text(loc.text(
                    es: "Aviso legal y exención de responsabilidad",
                    en: "Legal Disclaimer & Limitation of Liability"
                ))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

                Text(loc.text(
                    es: "MacFileExplorer se ofrece de forma gratuita «TAL CUAL» («AS IS»), sin garantías de ningún tipo. Su uso corre bajo tu propia responsabilidad. El autor no se hace responsable por errores del sistema, pérdida de información, borrado o modificación de archivos ni daños directos o indirectos derivados de su uso. Mantené siempre copias de seguridad de tus archivos importantes. Proyecto independiente no afiliado a Apple Inc. ni a Microsoft Corporation.",
                    en: "MacFileExplorer is provided free of charge \"AS IS\", without warranty of any kind, express or implied. You use this software entirely at your own risk. The author shall not be liable for any system errors, data loss, accidental file deletion or modification, or any direct or indirect damages arising from its use. Always keep regular backups of your important files. Independent project not affiliated with Apple Inc. or Microsoft Corporation."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerSection: some View {
        HStack {
            Text(loc.text(
                es: "© 2026 Luis Javier Romero. Todos los derechos reservados.",
                en: "© 2026 Luis Javier Romero. All rights reserved."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)

            Spacer()

            if navigationState.selectedTab == .reportBug {
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    closeWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var totalFeatureCount: Int {
        ReleaseNotesCatalog.sections.reduce(0) { $0 + $1.items.count }
    }

    @ViewBuilder
    private var checkUpgradesControl: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button {
                UpdateWindowController.shared.showAndCheck()
            } label: {
                HStack(spacing: 5) {
                    switch updateManager.state {
                    case .checking:
                        ProgressView()
                            .controlSize(.mini)
                        Text(loc.text(es: "Comprobando…", en: "Checking…"))
                    case .downloading(let info, _, _, let progress):
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        if let progress {
                            Text(loc.text(
                                es: "Descargando v\(info.versionString) (\(Int((progress * 100).rounded()))%)…",
                                en: "Downloading v\(info.versionString) (\(Int((progress * 100).rounded()))%)…"
                            ))
                        } else {
                            Text(loc.text(
                                es: "Descargando v\(info.versionString)…",
                                en: "Downloading v\(info.versionString)…"
                            ))
                        }
                    case .downloaded(let info, _, _):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(loc.text(
                            es: "Actualización v\(info.versionString) lista",
                            en: "Update v\(info.versionString) Ready"
                        ))
                    default:
                        Image(systemName: "arrow.down.circle")
                        Text(loc.text(es: "Buscar actualizaciones", en: "Check for Updates"))
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if case .upToDate = updateManager.state {
                Label(
                    loc.text(es: "Estás al día", en: "Up to date"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
            }
        }
    }

    private func closeWindow() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

private struct ReleaseNoteRow: View {
    let icon: String
    let title: String
    let detail: String
    var newBadgeText: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 7) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let newBadgeText {
                        Text(newBadgeText)
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.35)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor)
                            )
                            .fixedSize()
                            .padding(.top, 1)
                    }
                }

                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
        }
    }
}
