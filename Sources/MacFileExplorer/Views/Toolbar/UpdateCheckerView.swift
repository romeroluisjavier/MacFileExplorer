import AppKit
import SwiftUI

/// Controlador singleton de la ventana nativa de búsqueda y descarga de actualizaciones desde GitHub.
@MainActor
public final class UpdateWindowController: NSObject, NSWindowDelegate {
    public static let shared = UpdateWindowController()

    private var window: NSWindow?
    private var lastAppliedStateKind: String = ""

    private override init() {
        super.init()
    }

    public func refreshLocalizedTitle() {
        window?.title = localizedWindowTitle()
    }

    private func localizedWindowTitle() -> String {
        LocalizationManager.shared.text(
            es: "Actualización de MacFileExplorer",
            en: "MacFileExplorer Update"
        )
    }

    /// Calcula el alto ideal de la ventana según el estado actual para evitar cualquier recorte vertical.
    private static func idealContentSize(for state: AppUpdateState) -> NSSize {
        let width: CGFloat = 540
        switch state {
        case .idle, .checking, .upToDate:
            return NSSize(width: width, height: 218)
        case .failed:
            return NSSize(width: width, height: 268)
        case .updateAvailable(let info), .updateAvailableNoInstaller(let info):
            let hasNotes = !(info.releaseNotesText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return NSSize(width: width, height: hasNotes ? 406 : 246)
        case .downloading(let info, _, _, _):
            let hasNotes = !(info.releaseNotesText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return NSSize(width: width, height: hasNotes ? 430 : 272)
        case .downloaded(let info, _, _):
            let hasNotes = !(info.releaseNotesText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return NSSize(width: width, height: hasNotes ? 470 : 320)
        }
    }

    private static func stateSizeKey(for state: AppUpdateState) -> String {
        switch state {
        case .idle: return "idle"
        case .checking: return "checking"
        case .upToDate: return "upToDate"
        case .failed: return "failed"
        case .updateAvailable(let info): return "avail_\(info.releaseNotesText != nil)"
        case .updateAvailableNoInstaller(let info): return "noinst_\(info.releaseNotesText != nil)"
        case .downloading(let info, _, _, _): return "dl_\(info.releaseNotesText != nil)"
        case .downloaded(let info, _, _): return "done_\(info.releaseNotesText != nil)"
        }
    }

    /// Ajusta suavemente la altura de la ventana manteniendo fijo el borde superior y centrado horizontal.
    public func resizeWindowIfNeeded(for state: AppUpdateState, animated: Bool = true) {
        guard let window else { return }
        let key = Self.stateSizeKey(for: state)
        guard key != lastAppliedStateKind else { return }
        lastAppliedStateKind = key

        let targetContent = Self.idealContentSize(for: state)
        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContent)).size
        var nextFrame = window.frame
        let heightDelta = targetFrameSize.height - nextFrame.height
        let widthDelta = targetFrameSize.width - nextFrame.width
        nextFrame.origin.y -= heightDelta
        nextFrame.origin.x -= widthDelta * 0.5
        nextFrame.size = targetFrameSize

        if let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            if nextFrame.minY < visible.minY + 12 {
                nextFrame.origin.y = visible.minY + 12
            }
            if nextFrame.maxY > visible.maxY - 12 {
                nextFrame.origin.y = visible.maxY - 12 - nextFrame.height
            }
        }

        window.setFrame(nextFrame, display: true, animate: animated)
    }

    /// Muestra la ventana de actualizaciones (sin reiniciar si ya está comprobando o descargando).
    public func show() {
        let title = localizedWindowTitle()
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = window {
            existingWindow.title = title
            resizeWindowIfNeeded(for: AppUpdateManager.shared.state, animated: false)
            if !existingWindow.isVisible {
                existingWindow.center()
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let initialSize = Self.idealContentSize(for: AppUpdateManager.shared.state)
        let createdWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        createdWindow.delegate = self
        createdWindow.title = title
        createdWindow.minSize = NSSize(width: 500, height: 210)
        createdWindow.maxSize = NSSize(width: 720, height: 680)
        createdWindow.isMovableByWindowBackground = true
        createdWindow.isReleasedWhenClosed = false
        createdWindow.tabbingMode = .disallowed

        let hostingView = NSHostingView(
            rootView: UpdateCheckerView(
                onClose: { [weak self] in
                    self?.close()
                },
                onStateChanged: { [weak self] newState in
                    self?.resizeWindowIfNeeded(for: newState, animated: true)
                }
            )
        )
        createdWindow.contentView = hostingView
        lastAppliedStateKind = Self.stateSizeKey(for: AppUpdateManager.shared.state)
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

/// Vista SwiftUI nativa para consultar GitHub, mostrar novedades legibles y descargar automáticamente `.dmg`.
public struct UpdateCheckerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var manager = AppUpdateManager.shared

    private let onClose: () -> Void
    private let onStateChanged: ((AppUpdateState) -> Void)?

    public init(
        onClose: @escaping () -> Void,
        onStateChanged: ((AppUpdateState) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onStateChanged = onStateChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Encabezado limpio con ícono, título, píldora de versión y subtítulo
            HStack(alignment: .top, spacing: 16) {
                appIconWithBadge
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(headerTitle)
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let badgeText = versionTransitionBadge {
                            Text(badgeText)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7.5)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.13))
                                )
                                .fixedSize()
                        }
                    }

                    Text(headerSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            // Cuerpo principal adaptable (nunca recorta el encabezado ni el pie)
            detailContent
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            // Barra inferior de acciones siempre visible y anclada abajo
            footerButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: manager.state) { _, newState in
            onStateChanged?(newState)
        }
        .onExitCommand {
            if !manager.isBusy {
                onClose()
            }
        }
    }

    // MARK: - Subvistas

    private var versionTransitionBadge: String? {
        let current = AppVersionInfo.currentVersion
        switch manager.state {
        case .updateAvailable(let info),
             .downloading(let info, _, _, _),
             .downloaded(let info, _, _),
             .updateAvailableNoInstaller(let info):
            return "v\(current) → v\(info.versionString)"
        default:
            return nil
        }
    }

    private var appIconWithBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let appIcon = FileIconProvider.shared.appIcon(for: colorScheme) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                } else {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 54, height: 54)
                }
            }

            if let badge = statusBadge {
                Image(systemName: badge.symbol)
                    .font(.system(size: 11.5, weight: .bold))
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
        .frame(width: 58, height: 58)
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
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text(loc.text(
                    es: "Consultando la última versión publicada en GitHub…",
                    en: "Checking the latest published release on GitHub…"
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

        case .upToDate(_, let latestKnown):
            if let latestKnown {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(loc.text(
                        es: "Ya tenés la última versión publicada (v\(latestKnown.versionString)).",
                        en: "You already have the latest published version (v\(latestKnown.versionString))."
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.green.opacity(0.08))
                )
            }

        case .updateAvailable(let info):
            releaseNotesBox(info.releaseNotesText)

        case .downloading(let info, let downloadedBytes, let totalBytes, let progress):
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.accentColor)
                            Text(info.installerFileName ?? "MacFileExplorer-\(info.versionString).dmg")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let progress {
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if let progress {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .controlSize(.regular)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .controlSize(.regular)
                    }

                    Text(byteProgressText(downloaded: downloadedBytes, total: totalBytes))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.8)
                        )
                )

                releaseNotesBox(info.releaseNotesText)
            }

        case .downloaded(let info, let fileURL, let reusedExisting):
            VStack(alignment: .leading, spacing: 10) {
                // Tarjeta del archivo descargado
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill.badge.checkmark")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(fileURL.lastPathComponent)
                                .font(.system(size: 12.2, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let sizeText = formattedFileSize(for: fileURL, fallback: info.expectedFileSize) {
                                Text("(\(sizeText))")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(loc.text(
                            es: reusedExisting ? "Ya guardado en tu carpeta Descargas" : "Descargado en tu carpeta Descargas",
                            en: reusedExisting ? "Already saved in your Downloads folder" : "Saved to your Downloads folder"
                        ))
                        .font(.system(size: 10.8))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 6)

                    Button {
                        manager.downloadUpdate(info, forceRedownload: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Volver a descargar", en: "Re-download"))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.green.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.green.opacity(0.24), lineWidth: 0.8)
                        )
                )

                // Pasos simples para instalar en 2 clics
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.text(es: "Cómo actualizar en 2 pasos:", en: "How to install in 2 quick steps:"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(loc.text(
                        es: "1. Hacé clic en «Abrir instalador (.dmg)» abajo.\n2. Hacé clic derecho → Abrir en «Instalar MacFileExplorer.command» (o arrastrá la app a Aplicaciones).",
                        en: "1. Click \"Open Installer (.dmg)\" below.\n2. Right-click → Open \"Instalar MacFileExplorer.command\" (or drag the app to Applications)."
                    ))
                    .font(.system(size: 11.3))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )

                releaseNotesBox(info.releaseNotesText)
            }

        case .updateAvailableNoInstaller(let info):
            releaseNotesBox(info.releaseNotesText)

        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 11.8))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.red.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.20), lineWidth: 0.8)
                    )
            )
        }
    }

    @ViewBuilder
    private func releaseNotesBox(_ notes: String?) -> some View {
        let cleaned = notes.map { GitHubUpdateParser.sanitizeReleaseNotesForDisplay($0) } ?? ""
        if !cleaned.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(loc.text(es: "Qué trae de nuevo", en: "What's new"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    Text(cleaned)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 72, maxHeight: .infinity)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            )
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
                Button(loc.text(es: "Buscar actualizaciones", en: "Check for Updates")) {
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
            return loc.text(es: "Buscar actualizaciones", en: "Check for Updates")
        case .checking:
            return loc.text(es: "Buscando actualizaciones…", en: "Checking for Updates…")
        case .upToDate:
            return loc.text(es: "¡Estás al día!", en: "You're Up to Date!")
        case .updateAvailable(let info):
            return loc.text(
                es: "Nueva versión \(info.versionString) disponible",
                en: "New Version \(info.versionString) Available"
            )
        case .downloading(let info, _, _, _):
            return loc.text(
                es: "Descargando MacFileExplorer \(info.versionString)…",
                en: "Downloading MacFileExplorer \(info.versionString)…"
            )
        case .downloaded(let info, _, _):
            return loc.text(
                es: "¡Actualización v\(info.versionString) lista!",
                en: "Update v\(info.versionString) Ready!"
            )
        case .updateAvailableNoInstaller(let info):
            return loc.text(
                es: "Nueva versión \(info.versionString) en GitHub",
                en: "New Version \(info.versionString) on GitHub"
            )
        case .failed:
            return loc.text(
                es: "No se pudo comprobar actualizaciones",
                en: "Update Check Failed"
            )
        }
    }

    private var headerSubtitle: String {
        let installed = "v\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild))"
        switch manager.state {
        case .idle:
            return loc.text(
                es: "Versión instalada: \(installed). Comprobará si hay una versión nueva lista para instalar.",
                en: "Installed version: \(installed). Checks GitHub for a newer installer."
            )
        case .checking:
            return loc.text(
                es: "Versión instalada actualmente: \(installed).",
                en: "Currently installed version: \(installed)."
            )
        case .upToDate:
            return loc.text(
                es: "MacFileExplorer \(installed) es la versión más reciente disponible.",
                en: "MacFileExplorer \(installed) is the latest available version."
            )
        case .updateAvailable(let info):
            return loc.text(
                es: "Hay una nueva versión lista para descargar (tenés instalada la v\(AppVersionInfo.currentVersion)).",
                en: "Version \(info.versionString) is ready to download (you currently have v\(AppVersionInfo.currentVersion))."
            )
        case .downloading(let info, _, _, _):
            return loc.text(
                es: "Descargando el instalador oficial v\(info.versionString) desde GitHub…",
                en: "Downloading the official v\(info.versionString) installer from GitHub…"
            )
        case .downloaded(let info, _, let reusedExisting):
            return loc.text(
                es: reusedExisting
                    ? "El instalador de la versión \(info.versionString) ya está listo en tu Mac."
                    : "La versión \(info.versionString) se descargó correctamente y está lista para instalar.",
                en: reusedExisting
                    ? "The version \(info.versionString) installer is ready on your Mac."
                    : "Version \(info.versionString) downloaded successfully and is ready to install."
            )
        case .updateAvailableNoInstaller(let info):
            return loc.text(
                es: "La versión \(info.versionString) ya figura en GitHub, pero su archivo .dmg todavía se está publicando.",
                en: "Version \(info.versionString) is live on GitHub, but its .dmg installer hasn't been published yet."
            )
        case .failed:
            return loc.text(
                es: "No se pudo completar la consulta para tu versión actual (\(installed)).",
                en: "Could not complete the update check for your current version (\(installed))."
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
