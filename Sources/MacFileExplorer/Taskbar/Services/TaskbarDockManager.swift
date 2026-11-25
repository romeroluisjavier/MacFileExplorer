import AppKit
import Foundation

/// Operación atómica sobre `com.apple.dock` (útil tanto para ejecución segura como para verificación en tests unitarios).
public enum TaskbarDockDefaultsOperation: Equatable, Sendable {
    case writeString(key: String, value: String)
    case writeBool(key: String, value: Bool)
    case writeFloat(key: String, value: Double)
    case deleteKey(key: String)

    public var defaultsArguments: [String] {
        switch self {
        case let .writeString(key, value):
            return ["write", "com.apple.dock", key, "-string", value]
        case let .writeBool(key, value):
            return ["write", "com.apple.dock", key, "-bool", value ? "true" : "false"]
        case let .writeFloat(key, value):
            return ["write", "com.apple.dock", key, "-float", String(value)]
        case let .deleteKey(key):
            return ["delete", "com.apple.dock", key]
        }
    }
}

/// Gestor opcional y 100% reversible del Dock nativo de macOS (`com.apple.dock`).
///
/// Garantías clave:
/// - **Nunca modifica el Dock por defecto:** el Dock original de macOS permanece siempre activo salvo elección explícita del usuario.
/// - Guarda un snapshot persistente del estado original antes del primer cambio.
/// - Incluye **Restauración de Emergencia** siempre disponible (restaura el snapshot guardado, o restablece a valores seguros de fábrica de macOS: abajo y visible).
/// - Si se activó `fullyHidden`, restaura automáticamente el retardo normal al desactivar la barra o al salir de `MacFileExplorer`.
@MainActor
public final class TaskbarDockManager {

    public static let shared = TaskbarDockManager()

    private static let dockDomain = "com.apple.dock" as CFString

    private init() {}

    // MARK: - Planificador Puro (Testeable sin tocar el Dock real del sistema)

    public nonisolated static func operations(
        for mode: TaskbarDockMode,
        backup: TaskbarDockBackupSnapshot?
    ) -> [TaskbarDockDefaultsOperation] {
        switch mode {
        case .unchanged:
            return []
        case .autoHideLeft:
            var ops: [TaskbarDockDefaultsOperation] = [
                .writeString(key: "orientation", value: "left"),
                .writeBool(key: "autohide", value: true)
            ]
            ops.append(contentsOf: restoreAutohideTimingOperations(from: backup))
            return ops
        case .autoHideRight:
            var ops: [TaskbarDockDefaultsOperation] = [
                .writeString(key: "orientation", value: "right"),
                .writeBool(key: "autohide", value: true)
            ]
            ops.append(contentsOf: restoreAutohideTimingOperations(from: backup))
            return ops
        case .fullyHidden:
            return [
                .writeBool(key: "autohide", value: true),
                .writeFloat(key: "autohide-delay", value: 1000.0),
                .writeFloat(key: "autohide-time-modifier", value: 0.0)
            ]
        }
    }

    /// Genera la secuencia exacta de operaciones para restaurar un respaldo original del Dock.
    public nonisolated static func restoreOperations(from backup: TaskbarDockBackupSnapshot) -> [TaskbarDockDefaultsOperation] {
        var ops: [TaskbarDockDefaultsOperation] = []
        if let orientation = backup.orientation, !orientation.isEmpty {
            ops.append(.writeString(key: "orientation", value: orientation))
        } else {
            ops.append(.deleteKey(key: "orientation"))
        }

        if let autohide = backup.autohide {
            ops.append(.writeBool(key: "autohide", value: autohide))
        } else {
            ops.append(.deleteKey(key: "autohide"))
        }

        ops.append(contentsOf: restoreAutohideTimingOperations(from: backup))
        return ops
    }

    /// Genera las operaciones garantizadas de fábrica de macOS (Dock abajo, visible y sin retardo artificial).
    public nonisolated static func factoryDefaultMacOSDockOperations() -> [TaskbarDockDefaultsOperation] {
        [
            .writeString(key: "orientation", value: "bottom"),
            .writeBool(key: "autohide", value: false),
            .deleteKey(key: "autohide-delay"),
            .deleteKey(key: "autohide-time-modifier")
        ]
    }

    private nonisolated static func restoreAutohideTimingOperations(from backup: TaskbarDockBackupSnapshot?) -> [TaskbarDockDefaultsOperation] {
        var ops: [TaskbarDockDefaultsOperation] = []
        if let delay = backup?.autohideDelay {
            ops.append(.writeFloat(key: "autohide-delay", value: delay))
        } else {
            ops.append(.deleteKey(key: "autohide-delay"))
        }
        if let modifier = backup?.autohideTimeModifier {
            ops.append(.writeFloat(key: "autohide-time-modifier", value: modifier))
        } else {
            ops.append(.deleteKey(key: "autohide-time-modifier"))
        }
        return ops
    }

    // MARK: - Lectura y Respaldo del Estado Real de `com.apple.dock`

    public func readCurrentSystemDockSnapshot() -> TaskbarDockBackupSnapshot {
        CFPreferencesAppSynchronize(Self.dockDomain)
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, Self.dockDomain) as? String
        let autohide = (CFPreferencesCopyAppValue("autohide" as CFString, Self.dockDomain) as? NSNumber)?.boolValue
        let delay = (CFPreferencesCopyAppValue("autohide-delay" as CFString, Self.dockDomain) as? NSNumber)?.doubleValue
        let modifier = (CFPreferencesCopyAppValue("autohide-time-modifier" as CFString, Self.dockDomain) as? NSNumber)?.doubleValue

        return TaskbarDockBackupSnapshot(
            orientation: orientation,
            autohide: autohide,
            autohideDelay: delay,
            autohideTimeModifier: modifier
        )
    }

    public var hasSavedBackup: Bool {
        TaskbarPreferences.shared.loadDockBackupSnapshot() != nil
    }

    /// Captura el respaldo original del Dock si todavía no existe uno guardado.
    @discardableResult
    public func captureOriginalBackupIfNeeded() -> TaskbarDockBackupSnapshot {
        if let existing = TaskbarPreferences.shared.loadDockBackupSnapshot() {
            return existing
        }
        let snapshot = readCurrentSystemDockSnapshot()
        TaskbarPreferences.shared.saveDockBackupSnapshot(snapshot)
        return snapshot
    }

    // MARK: - Aplicación Explícita de Modos y Restauración de Emergencia

    /// Aplica un modo de Dock seleccionado explícitamente por el usuario.
    /// Si `mode == .unchanged`, restaura el respaldo si previamente se había modificado desde MacFileExplorer.
    public func applyUserSelectedDockMode(_ mode: TaskbarDockMode) {
        let prefs = TaskbarPreferences.shared
        let previousMode = prefs.dockMode

        if mode == .unchanged {
            prefs.dockMode = .unchanged
            if previousMode != .unchanged, let backup = prefs.loadDockBackupSnapshot() {
                execute(operations: Self.restoreOperations(from: backup), restartDock: true)
            }
            return
        }

        let backup = captureOriginalBackupIfNeeded()
        prefs.dockMode = mode
        let ops = Self.operations(for: mode, backup: backup)
        execute(operations: ops, restartDock: true)
    }

    /// Acción de **Emergencia: Restaurar Dock original de macOS** (siempre disponible incluso con Taskbar apagada).
    /// - Si existe snapshot original previo, restaura exactamente ese estado (siempre eliminando cualquier `autohide-delay` extremo).
    /// - Si `forceFactoryDefaults == true` o no existe snapshot guardado, restablece el Dock de fábrica de macOS (abajo y visible).
    public func emergencyRestoreOriginalMacOSDock(forceFactoryDefaults: Bool = false) {
        let prefs = TaskbarPreferences.shared
        prefs.dockMode = .unchanged

        if !forceFactoryDefaults, let backup = prefs.loadDockBackupSnapshot() {
            // Seguridad extra: si por algún motivo el backup tuviera un delay extremo >= 10s, limpiarlo igual
            let safeBackup = TaskbarDockBackupSnapshot(
                orientation: backup.orientation,
                autohide: backup.autohide,
                autohideDelay: (backup.autohideDelay ?? 0) >= 10 ? nil : backup.autohideDelay,
                autohideTimeModifier: backup.autohideTimeModifier,
                capturedAt: backup.capturedAt
            )
            execute(operations: Self.restoreOperations(from: safeBackup), restartDock: true)
        } else {
            execute(operations: Self.factoryDefaultMacOSDockOperations(), restartDock: true)
        }
    }

    /// Invocado automáticamente al desactivar la barra de tareas o cerrar `MacFileExplorer`:
    /// si el usuario tenía activado `fullyHidden`, revierte el ocultamiento extremo para que el Dock nunca quede inaccesible.
    public func revertFullyHiddenIfNeededForDisableOrQuit() {
        let prefs = TaskbarPreferences.shared
        guard prefs.dockMode == .fullyHidden else { return }
        let backup = prefs.loadDockBackupSnapshot()
        let ops: [TaskbarDockDefaultsOperation]
        if let backup {
            ops = Self.restoreOperations(from: backup)
        } else {
            ops = Self.factoryDefaultMacOSDockOperations()
        }
        execute(operations: ops, restartDock: true)
    }

    /// Si el usuario reactiva la barra de tareas y tenía elegido `fullyHidden`, reaplica ese modo explícito.
    public func reapplyDockModeIfNeededOnEnable() {
        let prefs = TaskbarPreferences.shared
        guard prefs.dockMode == .fullyHidden else { return }
        let backup = captureOriginalBackupIfNeeded()
        execute(operations: Self.operations(for: .fullyHidden, backup: backup), restartDock: true)
    }

    // MARK: - Ejecución Segura de `/usr/bin/defaults` y `/usr/bin/killall Dock`

    private func execute(operations: [TaskbarDockDefaultsOperation], restartDock: Bool) {
        guard !operations.isEmpty else { return }
        for op in operations {
            runProcess(executablePath: "/usr/bin/defaults", arguments: op.defaultsArguments)
        }
        if restartDock {
            runProcess(executablePath: "/usr/bin/killall", arguments: ["Dock"])
        }
    }

    private func runProcess(executablePath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Fallo silencioso seguro (ej. `defaults delete` de una clave inexistente retorna código 1)
        }
    }
}
