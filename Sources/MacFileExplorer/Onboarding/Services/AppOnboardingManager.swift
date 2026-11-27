import AppKit
import Foundation
import Observation

/// Resultado de la evaluación de arranque realizada por `AppOnboardingManager`.
public enum OnboardingLaunchAction: Equatable, Sendable {
    case none
    case showFirstInstallWizard
    case showPreviewWizard(step: SetupWizardStep)
    case startPreviewTour
    case showUpgradeNotes(previousVersion: String, currentVersion: String)
}

/// Motor central (`@MainActor @Observable`) que administra:
/// 1. Detección inteligente de primera instalación vs. actualización desde una versión anterior.
/// 2. Estado y aplicación segura del Asistente de instalación inicial (`SetupWizardStep` + `SetupWizardDraft`).
/// 3. Ciclo de vida del Tour interactivo paso a paso (con suspensión inmediata en cualquier momento).
@MainActor
@Observable
public final class AppOnboardingManager {

    public static let shared = AppOnboardingManager()

    /// Claves persistentes en `UserDefaults` para onboarding, versión y tour.
    public enum DefaultsKeys {
        public static let hasCompletedOnboarding = "com.macfileexplorer.onboarding.hasCompletedOnboarding"
        public static let lastLaunchedVersion = "com.macfileexplorer.onboarding.lastLaunchedVersion"
        public static let hasCompletedTour = "com.macfileexplorer.onboarding.hasCompletedTour"
    }

    /// Claves legadas escritas por versiones anteriores de `MacFileExplorer` tras uso real
    /// (se excluyen claves que el arranque inicial de la ventana podría escribir en primer plano).
    public static let legacyInstallationUserDefaultsKeys: [String] = [
        "com.macfileexplorer.monthlySupport.firstLaunchAt",
        "com.macfileexplorer.languagePreference",
        "com.macfileexplorer.selectedAppIcon",
        "com.macfileexplorer.taskbar.startEnabledByDefault",
        "com.macfileexplorer.taskbar.hasCompletedSetup",
        "com.macfileexplorer.alttab.startEnabledByDefault",
        "com.macfileexplorer.notch.startEnabledByDefault",
        "com.macfileexplorer.state.savedSessionSnapshot",
        "com.macfileexplorer.state.windowFrame",
        "com.macfileexplorer.state.hasMigratedTrashToQuickAccess.v1",
        "com.macfileexplorer.state.visibleQuickAccessFolders",
        "com.macfileexplorer.state.showTrayIcon",
        "com.macfileexplorer.clipboardHistory.isEnabled",
        "com.macfileexplorer.office.isEditingEnabled.v1",
        "com.macfileexplorer.shortcuts.customMap.v1",
        "MacFileExplorer.quickAccess.showModifiedToday",
        "com.macfileexplorer.googleAccounts.v1",
        "com.macfileexplorer.chromeBookmarks.v1"
    ]

    // MARK: - Estado Persistente Observable

    /// Indica si el usuario ya completó el asistente inicial (o ya usaba una versión anterior).
    public private(set) var hasCompletedOnboarding: Bool

    /// Última versión de `MacFileExplorer` ejecutada por el usuario (ej. `"2.6.0"`).
    public private(set) var lastLaunchedVersion: String?

    /// Indica si el usuario ya completó o suspendió el tour interactivo al menos una vez.
    public private(set) var hasCompletedTour: Bool

    // MARK: - Estado del Asistente (Setup Wizard)

    /// Borrador en edición con todas las selecciones del usuario en el asistente.
    public var draft: SetupWizardDraft

    /// Paso activo del asistente (`welcome` ... `summary`).
    public var currentWizardStep: SetupWizardStep = .welcome

    /// Indica si la ventana del asistente está actualmente solicitada/visible.
    public var isWizardPresented: Bool = false

    // MARK: - Estado del Tour Interactivo

    /// Indica si los globitos del tour interactivo deben mostrarse sobre la ventana principal.
    public var isTourActive: Bool = false

    /// Parada activa del tour interactivo (`commandBar` ... `helpAndAbout`).
    public var currentTourStep: InteractiveTourStep = .commandBar

    // MARK: - Estado de Actualización de Versión (Post-Upgrade What's New)

    /// Comparación activa de actualización (`previous` → `current`) para resaltar novedades en Release Notes.
    public var pendingUpgradeComparison: (previous: String, current: String)?

    // MARK: - Callbacks hacia la Capa de Ventanas / UI

    /// Invocado cuando corresponde mostrar la ventana del Asistente inicial.
    public var onRequestShowWizard: (() -> Void)?

    /// Invocado al cerrar la ventana del Asistente (al finalizar u omitir).
    public var onCloseWizard: (() -> Void)?

    /// Invocado al detectar una actualización para abrir «Acerca de → Notas de la versión» con resaltado.
    public var onRequestShowUpgradeNotes: ((_ previousVersion: String, _ currentVersion: String) -> Void)?

    /// Opcional: invocado al iniciar el tour para asegurar que una ventana principal del Explorador esté al frente.
    public var onRequestFocusMainWindow: (() -> Void)?

    // MARK: - Dependencias Internas

    private let defaults: UserDefaults
    private let currentVersionProvider: () -> String
    private let launchArgumentsProvider: () -> [String]
    private var hasHandledApplicationLaunch = false
    private var scheduledLaunchTask: Task<Void, Never>?
    private var scheduledTourTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        currentVersionProvider: @escaping () -> String = { AppVersionInfo.currentVersion },
        launchArgumentsProvider: @escaping () -> [String] = { ProcessInfo.processInfo.arguments }
    ) {
        self.defaults = defaults
        self.currentVersionProvider = currentVersionProvider
        self.launchArgumentsProvider = launchArgumentsProvider

        self.hasCompletedOnboarding = defaults.bool(forKey: DefaultsKeys.hasCompletedOnboarding)
        let savedVersion = defaults.string(forKey: DefaultsKeys.lastLaunchedVersion)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastLaunchedVersion = (savedVersion?.isEmpty == false) ? savedVersion : nil
        self.hasCompletedTour = defaults.bool(forKey: DefaultsKeys.hasCompletedTour)
        self.draft = SetupWizardDraft.recommendedDefaults()
    }

    // MARK: - Detección de Arranque (Primera Instalación vs. Upgrade vs. QA Preview)

    /// Evalúa qué flujo debe presentarse en este arranque y programa su apertura sin bloquear la ventana principal.
    @discardableResult
    public func handleApplicationLaunch() -> OnboardingLaunchAction {
        guard !hasHandledApplicationLaunch else { return .none }
        hasHandledApplicationLaunch = true

        let action = evaluateLaunchAction(commitState: true)
        scheduleActionPresentation(action)
        return action
    }

    /// Determina la acción de arranque de forma determinista (útil para QA y pruebas unitarias).
    public func evaluateLaunchAction(commitState: Bool) -> OnboardingLaunchAction {
        let currentVersion = AppVersionComparator.displayVersion(currentVersionProvider())
        let args = launchArgumentsProvider()

        // 0. Argumentos de lanzamiento dedicados para QA / previsualización instantánea
        if let previewAction = parsePreviewLaunchArguments(args, currentVersion: currentVersion) {
            if case let .showUpgradeNotes(prev, curr) = previewAction {
                pendingUpgradeComparison = (previous: prev, current: curr)
            } else if case let .showPreviewWizard(step) = previewAction {
                var freshDraft = SetupWizardDraft.recommendedDefaults()
                freshDraft.languagePreference = LocalizationManager.shared.preference
                draft = freshDraft
                currentWizardStep = step
            }
            return previewAction
        }

        // Caso 2: Usuario con versión previa registrada y actualización real a una versión superior
        if let prevVersion = lastLaunchedVersion,
           !prevVersion.isEmpty,
           AppVersionComparator.isNewer(currentVersion, than: prevVersion) {
            if commitState {
                setHasCompletedOnboarding(true)
                setLastLaunchedVersion(currentVersion)
            }
            pendingUpgradeComparison = (previous: prevVersion, current: currentVersion)
            return .showUpgradeNotes(previousVersion: prevVersion, currentVersion: currentVersion)
        }

        // Caso 3: Usuario existente migrando desde una versión anterior que aún no guardaba `lastLaunchedVersion`
        if lastLaunchedVersion == nil && (hasCompletedOnboarding || hasLegacyInstallationSignals()) {
            if commitState {
                setHasCompletedOnboarding(true)
                setLastLaunchedVersion(currentVersion)
            }
            let baseline = Self.previousKnownReleaseVersion(before: currentVersion)
            if AppVersionComparator.isNewer(currentVersion, than: baseline) {
                pendingUpgradeComparison = (previous: baseline, current: currentVersion)
                return .showUpgradeNotes(previousVersion: baseline, currentVersion: currentVersion)
            }
            return .none
        }

        // Caso 1: Instalación completamente nueva (sin onboarding previo ni claves legadas)
        if !hasCompletedOnboarding {
            var initialDraft = SetupWizardDraft.recommendedDefaults()
            initialDraft.languagePreference = LocalizationManager.shared.preference
            draft = initialDraft
            currentWizardStep = .welcome
            return .showFirstInstallWizard
        }

        // Caso 4: Arranque habitual en la misma versión
        if commitState, lastLaunchedVersion == nil {
            setLastLaunchedVersion(currentVersion)
        }
        return .none
    }

    /// Devuelve `true` si `UserDefaults` contiene señales claras de que el usuario ya había usado una versión previa.
    public func hasLegacyInstallationSignals() -> Bool {
        for key in Self.legacyInstallationUserDefaultsKeys {
            if defaults.object(forKey: key) != nil {
                return true
            }
        }
        return false
    }

    /// Resuelve la versión anterior inmediata presente en `ReleaseNotesCatalog.sections` (para migración legada).
    public static func previousKnownReleaseVersion(before currentVersion: String) -> String {
        for section in ReleaseNotesCatalog.sections {
            if AppVersionComparator.compare(section.semanticVersion, currentVersion) == .orderedAscending {
                return AppVersionComparator.displayVersion(section.semanticVersion)
            }
        }
        return "2.5.1"
    }

    private func parsePreviewLaunchArguments(
        _ args: [String],
        currentVersion: String
    ) -> OnboardingLaunchAction? {
        for arg in args {
            if arg == "--preview-wizard" {
                return .showPreviewWizard(step: .welcome)
            }
            if arg.hasPrefix("--preview-wizard=") {
                let rawValue = String(arg.dropFirst("--preview-wizard=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let resolvedStep = Self.parseWizardStepArgument(rawValue) ?? .welcome
                return .showPreviewWizard(step: resolvedStep)
            }
            if arg == "--preview-tour" {
                return .startPreviewTour
            }
            if arg == "--preview-upgrade" {
                return .showUpgradeNotes(previousVersion: "2.5.0", currentVersion: currentVersion)
            }
            if arg.hasPrefix("--preview-upgrade=") {
                let rawPrev = String(arg.dropFirst("--preview-upgrade=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanPrev = rawPrev.isEmpty ? "2.5.0" : AppVersionComparator.displayVersion(rawPrev)
                return .showUpgradeNotes(previousVersion: cleanPrev, currentVersion: currentVersion)
            }
        }
        return nil
    }

    private static func parseWizardStepArgument(_ raw: String) -> SetupWizardStep? {
        if let number = Int(raw), let step = SetupWizardStep(rawValue: number - 1) {
            return step
        }
        switch raw {
        case "welcome", "bienvenida": return .welcome
        case "taskbar", "barra": return .taskbar
        case "alttab": return .altTab
        case "notch": return .notch
        case "productivity", "tools", "herramientas": return .productivity
        case "summary", "resumen": return .summary
        default: return nil
        }
    }

    private func scheduleActionPresentation(_ action: OnboardingLaunchAction) {
        scheduledLaunchTask?.cancel()

        switch action {
        case .none:
            return

        case .showFirstInstallWizard, .showPreviewWizard:
            scheduledLaunchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self else { return }
                self.isWizardPresented = true
                self.onRequestShowWizard?()
            }

        case .startPreviewTour:
            scheduledLaunchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self else { return }
                self.startTour(from: .commandBar)
            }

        case let .showUpgradeNotes(previousVersion, currentVersion):
            scheduledLaunchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self else { return }
                self.onRequestShowUpgradeNotes?(previousVersion, currentVersion)
            }
        }
    }

    // MARK: - Navegación y Acciones del Asistente (Setup Wizard)

    /// Abre manualmente el Asistente (ej. desde el menú Ayuda), precargando las preferencias vivas actuales.
    public func startWizardManually(resetStep: Bool = true) {
        draft = captureCurrentLivePreferencesIntoDraft()
        if resetStep {
            currentWizardStep = .welcome
        }
        isWizardPresented = true
        onRequestShowWizard?()
    }

    /// Construye un `SetupWizardDraft` reflejando exactamente las preferencias activas actuales de la app.
    public func captureCurrentLivePreferencesIntoDraft() -> SetupWizardDraft {
        let taskbarPrefs = TaskbarPreferences.shared
        let altTabPrefs = AltTabPreferences.shared
        let notchPrefs = NotchPreferences.shared
        let clipboardPrefs = ClipboardHistoryPreferences.shared
        let trayPrefs = TrayIconPreferences.shared
        let shortcutPrefs = AppShortcutPreferences.shared
        let officePrefs = OfficePreferences.shared

        return SetupWizardDraft(
            languagePreference: LocalizationManager.shared.preference,
            selectedAppIcon: FileIconProvider.shared.selectedAppIcon,
            enableTaskbar: taskbarPrefs.isEnabled,
            taskbarStartOnLaunch: taskbarPrefs.startEnabledByDefault,
            taskbarBarStyle: taskbarPrefs.barStyle,
            hideMacOSDock: taskbarPrefs.dockMode != .unchanged,
            enableAltTab: altTabPrefs.isEnabled,
            altTabStartOnLaunch: altTabPrefs.startEnabledByDefault,
            altTabDisplayStyle: altTabPrefs.displayStyle,
            enableNotch: notchPrefs.isEnabled,
            notchStartOnLaunch: notchPrefs.startEnabledByDefault,
            notchPillSize: notchPrefs.pillSize,
            enableClipboardHistory: clipboardPrefs.isEnabled,
            enableTrayIcon: trayPrefs.isTrayIconEnabled,
            enableViewDesktopShortcut: shortcutPrefs.isViewDesktopShortcutEnabled,
            enableOfficeQuickLookEditor: officePrefs.isOfficeEditingEnabled,
            startTourAfterSetup: !hasCompletedTour
        )
    }

    public func goToWizardStep(_ step: SetupWizardStep) {
        currentWizardStep = step
    }

    public func nextWizardStep() {
        if let next = currentWizardStep.next {
            currentWizardStep = next
        } else {
            completeWizardApplyingDraft()
        }
    }

    public func previousWizardStep() {
        if let prev = currentWizardStep.previous {
            currentWizardStep = prev
        }
    }

    /// Aplica limpiamente cada módulo seleccionado en `draft`, marca el onboarding como completado,
    /// cierra la ventana del asistente e inicia el Tour interactivo si corresponde.
    public func completeWizardApplyingDraft(startTour: Bool? = nil) {
        applyDraftToLivePreferences(draft)

        let currentVersion = AppVersionComparator.displayVersion(currentVersionProvider())
        setHasCompletedOnboarding(true)
        setLastLaunchedVersion(currentVersion)

        isWizardPresented = false
        onCloseWizard?()

        let shouldStartTour = startTour ?? draft.startTourAfterSetup
        if shouldStartTour {
            scheduledTourTask?.cancel()
            scheduledTourTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.startTour(from: .commandBar)
            }
        }
    }

    /// Botón «Instalar por defecto (omitir asistente)»: aplica la configuración segura predeterminada
    /// (conservando el idioma actual), cierra el asistente e inicia el Tour interactivo (que puede suspenderse en cualquier momento).
    public func installByDefaultAndSkipWizard() {
        var defaultsDraft = SetupWizardDraft.recommendedDefaults()
        defaultsDraft.languagePreference = LocalizationManager.shared.preference
        draft = defaultsDraft
        completeWizardApplyingDraft(startTour: true)
    }

    /// Cierra el asistente sin sobreescribir ajustes (ej. si el usuario cierra la ventana con la cruz roja).
    public func dismissWizardWithoutApplying(markCompleted: Bool = true) {
        isWizardPresented = false
        if markCompleted && !hasCompletedOnboarding {
            setHasCompletedOnboarding(true)
            setLastLaunchedVersion(AppVersionComparator.displayVersion(currentVersionProvider()))
        }
    }

    private func applyDraftToLivePreferences(_ selectedDraft: SetupWizardDraft) {
        // 1. Idioma e Ícono de la aplicación
        if LocalizationManager.shared.preference != selectedDraft.languagePreference {
            LocalizationManager.shared.preference = selectedDraft.languagePreference
        }
        if FileIconProvider.shared.selectedAppIcon != selectedDraft.selectedAppIcon {
            FileIconProvider.shared.selectedAppIcon = selectedDraft.selectedAppIcon
        }

        // 2. Barra de tareas y gestión segura del Dock de macOS
        let taskbarPrefs = TaskbarPreferences.shared
        taskbarPrefs.barStyle = selectedDraft.taskbarBarStyle
        taskbarPrefs.startEnabledByDefault = selectedDraft.enableTaskbar ? selectedDraft.taskbarStartOnLaunch : false

        if selectedDraft.enableTaskbar && selectedDraft.hideMacOSDock {
            TaskbarDockManager.shared.applyUserSelectedDockMode(.fullyHidden)
        } else if taskbarPrefs.dockMode != .unchanged {
            TaskbarDockManager.shared.applyUserSelectedDockMode(.unchanged)
        }
        TaskbarManager.shared.setEnabled(selectedDraft.enableTaskbar, allowSetupPrompt: false)

        // 3. AltTab
        let altTabPrefs = AltTabPreferences.shared
        altTabPrefs.displayStyle = selectedDraft.altTabDisplayStyle
        altTabPrefs.startEnabledByDefault = selectedDraft.enableAltTab ? selectedDraft.altTabStartOnLaunch : false
        AltTabManager.shared.setEnabled(selectedDraft.enableAltTab, promptIfMissingPermission: false)

        // 4. Reproductor Notch
        let notchPrefs = NotchPreferences.shared
        notchPrefs.pillSize = selectedDraft.notchPillSize
        notchPrefs.startEnabledByDefault = selectedDraft.enableNotch ? selectedDraft.notchStartOnLaunch : false
        NotchManager.shared.setEnabled(selectedDraft.enableNotch)

        // 5. Productividad y Herramientas
        ClipboardHistoryPreferences.shared.isEnabled = selectedDraft.enableClipboardHistory

        TrayIconPreferences.shared.isTrayIconEnabled = selectedDraft.enableTrayIcon
        StatusBarManager.shared.syncVisibility()

        AppShortcutPreferences.shared.isViewDesktopShortcutEnabled = selectedDraft.enableViewDesktopShortcut
        ToolsShortcutManager.shared.syncGlobalHotKeys()

        let officePrefs = OfficePreferences.shared
        officePrefs.isOfficeEditingEnabled = selectedDraft.enableOfficeQuickLookEditor
        officePrefs.isInteractiveCSVEnabled = selectedDraft.enableOfficeQuickLookEditor
    }

    // MARK: - Acciones del Tour Interactivo

    /// Inicia (o reinicia) el tour interactivo de globitos desplegables desde la parada indicada.
    public func startTour(from step: InteractiveTourStep = .commandBar) {
        currentTourStep = step
        isTourActive = true
        if let focusCallback = onRequestFocusMainWindow {
            focusCallback()
        } else {
            GoogleAccountsManager.shared.openOrFocusMainWindow()
        }
    }

    /// Avanza a la siguiente parada del tour o lo finaliza suavemente al llegar a la última.
    public func nextTourStep() {
        if let next = currentTourStep.next {
            currentTourStep = next
        } else {
            suspendOrFinishTour()
        }
    }

    /// Retrocede a la parada anterior del tour.
    public func previousTourStep() {
        if let prev = currentTourStep.previous {
            currentTourStep = prev
        }
    }

    /// Salta directamente a una parada puntual del tour.
    public func goToTourStep(_ step: InteractiveTourStep) {
        currentTourStep = step
    }

    /// Suspende o finaliza el tour al instante y registra que el usuario ya lo vio para no volver a molestarlo.
    public func suspendOrFinishTour() {
        scheduledTourTask?.cancel()
        isTourActive = false
        setHasCompletedTour(true)
    }

    /// Limpia la comparación de actualización activa una vez que el usuario cierra el banner de novedades.
    public func clearPendingUpgradeComparison() {
        pendingUpgradeComparison = nil
    }

    // MARK: - Persistencia Interna

    private func setHasCompletedOnboarding(_ completed: Bool) {
        hasCompletedOnboarding = completed
        defaults.set(completed, forKey: DefaultsKeys.hasCompletedOnboarding)
    }

    private func setLastLaunchedVersion(_ version: String) {
        lastLaunchedVersion = version
        defaults.set(version, forKey: DefaultsKeys.lastLaunchedVersion)
    }

    private func setHasCompletedTour(_ completed: Bool) {
        hasCompletedTour = completed
        defaults.set(completed, forKey: DefaultsKeys.hasCompletedTour)
    }
}
