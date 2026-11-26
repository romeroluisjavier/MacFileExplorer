import AppKit
import Foundation
import Observation

/// Gestor (`@MainActor @Observable`) encargado de mostrar una vez al mes (cada 30 días)
/// un aviso flotante y no invasivo invitando opcionalmente a dejar una propina en Ko-fi
/// y comprobando automáticamente en ese mismo aviso si existe una nueva versión disponible.
@MainActor
@Observable
public final class MonthlySupportCheckManager {
    public static let shared = MonthlySupportCheckManager()

    private enum Keys {
        static let firstLaunchAt = "com.macfileexplorer.monthlySupport.firstLaunchAt"
        static let lastShownAt = "com.macfileexplorer.monthlySupport.lastShownAt"
        static let permanentlyDismissed = "com.macfileexplorer.monthlySupport.permanentlyDismissed"
    }

    /// Intervalo mensual entre avisos suaves (30 días).
    public static let monthlyIntervalSeconds: TimeInterval = 30 * 24 * 60 * 60

    /// Indica si la tarjeta flotante no invasiva debe mostrarse actualmente en la esquina inferior derecha.
    public var isPopupVisible: Bool = false

    /// Indica si el usuario eligió «No volver a mostrar» para los avisos mensuales automáticos.
    public private(set) var isPermanentlyDismissed: Bool

    private let defaults: UserDefaults
    private var scheduledEvaluationTask: Task<Void, Never>?
    private var hasEvaluatedThisLaunch = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPermanentlyDismissed = defaults.bool(forKey: Keys.permanentlyDismissed)
    }

    /// Programa una única evaluación diferida (4,5 s tras abrir la app) para no impactar el arranque.
    public func scheduleStartupEvaluationIfNeeded() {
        guard !hasEvaluatedThisLaunch else { return }
        hasEvaluatedThisLaunch = true

        scheduledEvaluationTask?.cancel()
        scheduledEvaluationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled, let self else { return }
            self.evaluateMonthlyCheckIn(now: Date(), triggerUpdateCheck: true)
        }
    }

    /// Evalúa si corresponde mostrar el aviso mensual (primera vez tras 30 días de uso, luego cada 30 días).
    /// Devuelve `true` si se presentó el aviso.
    @discardableResult
    public func evaluateMonthlyCheckIn(
        now: Date = Date(),
        triggerUpdateCheck: Bool = true
    ) -> Bool {
        if defaults.object(forKey: Keys.firstLaunchAt) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: Keys.firstLaunchAt)
            return false
        }

        guard !isPermanentlyDismissed else { return false }

        let firstLaunch = Date(timeIntervalSince1970: defaults.double(forKey: Keys.firstLaunchAt))
        guard now.timeIntervalSince(firstLaunch) >= Self.monthlyIntervalSeconds else {
            return false
        }

        if defaults.object(forKey: Keys.lastShownAt) != nil {
            let lastShown = Date(timeIntervalSince1970: defaults.double(forKey: Keys.lastShownAt))
            guard now.timeIntervalSince(lastShown) >= Self.monthlyIntervalSeconds else {
                return false
            }
        }

        defaults.set(now.timeIntervalSince1970, forKey: Keys.lastShownAt)
        presentPopup(triggerUpdateCheck: triggerUpdateCheck)
        return true
    }

    /// Muestra el aviso flotante manualmente (por ejemplo desde el menú de la app o para previsualizarlo)
    /// y ejecuta automáticamente la comprobación silenciosa de actualizaciones en el mismo panel.
    public func presentPopup(triggerUpdateCheck: Bool = true) {
        isPopupVisible = true
        if triggerUpdateCheck {
            AppUpdateManager.shared.checkForUpgrades(autoDownload: false)
        }
    }

    /// Oculta el aviso y programa el próximo recordatorio para dentro de 30 días.
    public func snoozeForNextMonth(now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: Keys.lastShownAt)
        isPopupVisible = false
    }

    /// Oculta el aviso y desactiva de forma permanente futuros avisos mensuales automáticos.
    public func dismissPermanently(now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: Keys.lastShownAt)
        defaults.set(true, forKey: Keys.permanentlyDismissed)
        isPermanentlyDismissed = true
        isPopupVisible = false
    }

    /// Reactiva los avisos mensuales si el usuario los había desactivado anteriormente.
    public func resetMonthlyReminderState() {
        defaults.removeObject(forKey: Keys.lastShownAt)
        defaults.set(false, forKey: Keys.permanentlyDismissed)
        isPermanentlyDismissed = false
    }
}
