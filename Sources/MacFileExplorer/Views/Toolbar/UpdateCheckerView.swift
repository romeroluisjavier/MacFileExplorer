import AppKit
import SwiftUI

/// Controlador singleton de la ventana nativa de búsqueda y descarga de actualizaciones desde GitHub.
@MainActor
public final class UpdateWindowController {
    public static let shared = UpdateWindowController()

    private var window: NSWindow?

    private init() {}

    /// Muestra la ventana de actualizaciones (sin reiniciar si ya está comprobando o descargando).
    public func show() {
        let title = LocalizationManager.shared.text(
            es: "Buscar actualizaciones",
            en: "Check Upgrades"
        )

        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = window {
            existingWindow.title = title
            if !existingWindow.isVisible {
                existingWindow.center()
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let createdWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 220),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        createdWindow.title = title
        createdWindow.titlebarAppearsTransparent = true
        createdWindow.titleVisibility = .hidden
        createdWindow.isMovableByWindowBackground = true
        createdWindow.isReleasedWhenClosed = false

        let hostingView = NSHostingView(
            rootView: UpdateCheckerView(onClose: { [weak self] in
                self?.close()
            })
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        createdWindow.contentView = hostingView
        createdWindow.center()
        createdWindow.makeKeyAndOrderFront(nil)
        self.window = createdWindow
    }

    /// Abre la ventana y consulta inmediatamente GitHub en busca de una versión nueva para descargarla.
    public func showAndCheck() {
        show()
        switch AppUpdateManager.shared.state {
        case .checking, .downloading:
            break
        case .downloaded(_, let fileURL, _) where FileManager.default.fileExists(atPath: fileURL.path):
            break
        default:
            AppUpdateManager.shared.checkForUpgrades(autoDownload: true)
        }
    }

    public func close() {
        window?.close()
    }
}

/// Vista SwiftUI nativa para consultar GitHub, mostrar novedades y descargar automáticamente `.dmg`.
public struct UpdateCheckerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var manager = AppUpdateManager.shared

    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                appIconWithBadge
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(headerTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(headerSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1.5)

                    detailContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 18)

            Divider()

            footerButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        }
        .frame(width: 490)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            if !manager.isBusy {
                onClose()
            }
        }
    }

    // MARK: - Subvistas

    private var appIconWithBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let appIcon = FileIconProvider.shared.appIcon(for: colorScheme) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 56, height: 56)
                }
            }

            if let badge = statusBadge {
                Image(systemName: badge.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(badge.color)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                    )
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 60, height: 60)
    }

    private var statusBadge: (symbol: String, color: Color)? {
        switch manager.state {
        case .idle:
            return ("arrow.down.circle.fill", .accentColor)
        case .checking:
            return nil
        case .upToDate, .downloaded:
            return ("checkmark", .green)
        case .updateAvailable, .downloading:
            return ("arrow.down", .accentColor)
        case .updateAvailableNoInstaller:
            return ("sparkles", .orange)
        case .failed:
            return ("exclamationmark", .red)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch manager.state {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(loc.text(
                    es: "Conectando con github.com/\(AppVersionInfo.repositoryOwner)/\(AppVersionInfo.repositoryName)…",
                    en: "Connecting to github.com/\(AppVersionInfo.repositoryOwner)/\(AppVersionInfo.repositoryName)…"
                ))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

        case .upToDate(_, let latestKnown):
            if let latestKnown {
                Text(loc.text(
                    es: "Última versión publicada: v\(latestKnown.versionString)",
                    en: "Latest published version: v\(latestKnown.versionString)"
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }

        case .updateAvailable(let info):
            releaseNotesBox(info.releaseNotesText)

        case .downloading(let info, let downloadedBytes, let totalBytes, let progress):
            VStack(alignment: .leading, spacing: 6) {
                if let progress {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                HStack {
                    Text(byteProgressText(downloaded: downloadedBytes, total: totalBytes))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                releaseNotesBox(info.releaseNotesText)
            }
            .padding(.top, 4)

        case .downloaded(let info, let fileURL, let reusedExisting):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill.badge.checkmark")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.green)

                    Text(fileURL.lastPathComponent)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let sizeText = formattedFileSize(for: fileURL, fallback: info.expectedFileSize) {
                        Text("(\(sizeText))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Button {
                        manager.downloadUpdate(info, forceRedownload: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Volver a descargar", en: "Re-download"))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                Text(loc.text(
                    es: reusedExisting
                        ? "Ya existía en tu carpeta Descargas. Abre el .dmg y arrastra MacFileExplorer a Aplicaciones."
                        : "Guardado en ~/Downloads. Abre el .dmg y arrastra MacFileExplorer a Aplicaciones para instalar.",
                    en: reusedExisting
                        ? "Already saved in Downloads. Open the .dmg and drag MacFileExplorer to Applications."
                        : "Saved to ~/Downloads. Open the .dmg and drag MacFileExplorer to Applications to install."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                releaseNotesBox(info.releaseNotesText)
            }
            .padding(.top, 4)

        case .updateAvailableNoInstaller(let info):
            releaseNotesBox(info.releaseNotesText)

        case .failed(let message):
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func releaseNotesBox(_ notes: String?) -> some View {
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.text(es: "Novedades:", en: "What's new:"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                }
                .frame(maxHeight: 92)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            )
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        HStack(spacing: 8) {
            switch manager.state {
            case .idle:
                Spacer()
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    onClose()
                }
                Button(loc.text(es: "Buscar actualizaciones", en: "Check Upgrades")) {
                    manager.checkForUpgrades(autoDownload: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            case .checking:
                Spacer()
                Button(loc.text(es: "Cancelar", en: "Cancel")) {
                    manager.cancelCurrentOperation()
                    onClose()
                }

            case .upToDate:
                Button(loc.text(es: "Ver en GitHub", en: "View on GitHub")) {
                    manager.openGitHubPage()
                }
                Spacer()
                Button(loc.text(es: "Volver a comprobar", en: "Check Again")) {
                    manager.checkForUpgrades(autoDownload: true)
                }
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            case .updateAvailable(let info):
                Button(loc.text(es: "Ver en GitHub", en: "View on GitHub")) {
                    manager.openGitHubPage(info.pageURL)
                }
                Spacer()
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    onClose()
                }
                Button(loc.text(es: "Descargar", en: "Download")) {
                    manager.downloadUpdate(info, forceRedownload: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            case .downloading:
                Spacer()
                Button(loc.text(es: "Cancelar descarga", en: "Cancel Download")) {
                    manager.cancelCurrentOperation()
                }

            case .downloaded(_, let fileURL, _):
                Button(loc.text(es: "Mostrar en Descargas", en: "Show in Downloads")) {
                    manager.showInDownloads(fileURL)
                }
                Spacer()
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    onClose()
                }
                Button(loc.text(es: "Abrir instalador (.dmg)", en: "Open Installer (.dmg)")) {
                    manager.openInstaller(fileURL)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            case .updateAvailableNoInstaller(let info):
                Spacer()
                Button(loc.text(es: "Volver a comprobar", en: "Check Again")) {
                    manager.checkForUpgrades(autoDownload: true)
                }
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    onClose()
                }
                Button(loc.text(es: "Abrir en GitHub", en: "Open on GitHub")) {
                    manager.openGitHubPage(info.pageURL)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            case .failed:
                Button(loc.text(es: "Abrir GitHub", en: "Open GitHub")) {
                    manager.openGitHubPage()
                }
                Spacer()
                Button(loc.text(es: "Cerrar", en: "Close")) {
                    onClose()
                }
                Button(loc.text(es: "Reintentar", en: "Retry")) {
                    manager.checkForUpgrades(autoDownload: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.regular)
    }

    // MARK: - Textos por estado

    private var headerTitle: String {
        switch manager.state {
        case .idle:
            return loc.text(es: "Buscar actualizaciones", en: "Check Upgrades")
        case .checking:
            return loc.text(es: "Buscando actualizaciones…", en: "Checking for Upgrades…")
        case .upToDate:
            return loc.text(es: "Estás al día", en: "You're up to date")
        case .updateAvailable(let info):
            return loc.text(
                es: "Nueva versión \(info.versionString) disponible",
                en: "New Version \(info.versionString) Available"
            )
        case .downloading(let info, _, _, _):
            return loc.text(
                es: "Descargando versión \(info.versionString)…",
                en: "Downloading Version \(info.versionString)…"
            )
        case .downloaded(let info, _, _):
            return loc.text(
                es: "Actualización v\(info.versionString) lista",
                en: "Upgrade v\(info.versionString) Ready"
            )
        case .updateAvailableNoInstaller(let info):
            return loc.text(
                es: "Nueva versión \(info.versionString) en GitHub",
                en: "New Version \(info.versionString) on GitHub"
            )
        case .failed:
            return loc.text(
                es: "Error al buscar actualizaciones",
                en: "Upgrade Check Failed"
            )
        }
    }

    private var headerSubtitle: String {
        let installed = "\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild))"
        switch manager.state {
        case .idle:
            return loc.text(
                es: "Versión instalada: \(installed). Comprobará si hay un nuevo instalador en GitHub.",
                en: "Installed version: \(installed). Checks GitHub for a newer release installer."
            )
        case .checking:
            return loc.text(
                es: "Versión actual: \(installed)",
                en: "Current version: \(installed)"
            )
        case .upToDate:
            return loc.text(
                es: "MacFileExplorer \(installed) es la versión más reciente disponible en el repositorio.",
                en: "MacFileExplorer \(installed) is the latest version available in the GitHub repository."
            )
        case .updateAvailable(let info):
            return loc.text(
                es: "Se encontró la versión \(info.versionString) (tienes instalada la \(AppVersionInfo.currentVersion)).",
                en: "Version \(info.versionString) is available (currently installed: \(AppVersionInfo.currentVersion))."
            )
        case .downloading(let info, _, _, _):
            return loc.text(
                es: "Descargando \(info.installerFileName ?? "instalador") desde GitHub (actual: \(AppVersionInfo.currentVersion))…",
                en: "Downloading \(info.installerFileName ?? "installer") from GitHub (current: \(AppVersionInfo.currentVersion))…"
            )
        case .downloaded(let info, _, _):
            return loc.text(
                es: "Versión \(info.versionString) descargada correctamente desde GitHub.",
                en: "Version \(info.versionString) downloaded successfully from GitHub."
            )
        case .updateAvailableNoInstaller(let info):
            return loc.text(
                es: "La versión \(info.versionString) existe en GitHub (actual: \(AppVersionInfo.currentVersion)), pero aún no tiene un paquete .dmg disponible para descarga directa.",
                en: "Version \(info.versionString) exists on GitHub (current: \(AppVersionInfo.currentVersion)), but no .dmg installer is published for it yet."
            )
        case .failed:
            return loc.text(
                es: "No se pudo completar la operación para la versión actual (\(installed)).",
                en: "Could not complete the check for your current version (\(installed))."
            )
        }
    }

    private func byteProgressText(downloaded: Int64, total: Int64?) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        let dlStr = formatter.string(fromByteCount: downloaded)
        if let total, total > 0 {
            let totalStr = formatter.string(fromByteCount: total)
            return "\(dlStr) / \(totalStr)"
        }
        return dlStr
    }

    private func formattedFileSize(for fileURL: URL, fallback: Int64?) -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? fallback
        guard let bytes, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
