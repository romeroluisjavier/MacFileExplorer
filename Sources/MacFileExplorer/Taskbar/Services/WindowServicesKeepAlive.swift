import Foundation

/// Identificador de módulos del explorador que requieren monitoreo continuo de ventanas
/// y protección contra macOS App Nap (`Taskbar` y `AltTab`).
public enum WindowServiceConsumer: String, Hashable, Sendable {
    case taskbar
    case altTab
}

/// Coordinador compartido con conteo de referencias que evita que macOS App Nap duerma `MacFileExplorer`
/// mientras **cualquiera** de los servicios activos (`Barra de tareas` o `AltTab`) esté encendido,
/// liberando recursos automáticamente en cuanto ambos se desactivan.
/// Además mantiene un único observador de desbloqueo de pantalla (`com.apple.screenIsUnlocked`).
@MainActor
public final class WindowServicesKeepAlive {

    public static let shared = WindowServicesKeepAlive()

    public private(set) var activeConsumers: Set<WindowServiceConsumer> = []

    private var antiAppNapActivity: NSObjectProtocol?
    private var isAutomaticTerminationDisabled = false
    private var screenUnlockObserver: NSObjectProtocol?

    private init() {}

    public var isKeepAliveActive: Bool {
        !activeConsumers.isEmpty
    }

    public func acquire(for consumer: WindowServiceConsumer) {
        let wasEmpty = activeConsumers.isEmpty
        activeConsumers.insert(consumer)
        guard wasEmpty else { return }

        if antiAppNapActivity == nil {
            // Evitar App Nap sin `.latencyCritical` para permitir timer coalescing y núcleos de eficiencia en Apple Silicon
            antiAppNapActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "MacFileExplorer active window management (Taskbar / AltTab)"
            )
        }
        if !isAutomaticTerminationDisabled {
            ProcessInfo.processInfo.disableAutomaticTermination("MacFileExplorer active window services")
            ProcessInfo.processInfo.disableSuddenTermination()
            isAutomaticTerminationDisabled = true
        }
        installScreenUnlockObserverIfNeeded()
    }

    public func release(for consumer: WindowServiceConsumer) {
        activeConsumers.remove(consumer)
        guard activeConsumers.isEmpty else { return }

        removeScreenUnlockObserver()
        if let token = antiAppNapActivity {
            ProcessInfo.processInfo.endActivity(token)
            antiAppNapActivity = nil
        }
        if isAutomaticTerminationDisabled {
            ProcessInfo.processInfo.enableAutomaticTermination("MacFileExplorer active window services")
            ProcessInfo.processInfo.enableSuddenTermination()
            isAutomaticTerminationDisabled = false
        }
    }

    public func releaseAll() {
        activeConsumers.removeAll()
        removeScreenUnlockObserver()
        if let token = antiAppNapActivity {
            ProcessInfo.processInfo.endActivity(token)
            antiAppNapActivity = nil
        }
        if isAutomaticTerminationDisabled {
            ProcessInfo.processInfo.enableAutomaticTermination("MacFileExplorer active window services")
            ProcessInfo.processInfo.enableSuddenTermination()
            isAutomaticTerminationDisabled = false
        }
    }

    private func installScreenUnlockObserverIfNeeded() {
        guard screenUnlockObserver == nil else { return }
        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                TaskbarWindowTracker.shared.recoverAfterSystemWake()
            }
        }
    }

    private func removeScreenUnlockObserver() {
        if let observer = screenUnlockObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockObserver = nil
        }
    }
}
