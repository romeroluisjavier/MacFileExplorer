import AppKit
import Foundation
import Observation

/// Categoría de reporte de usuario (homologada con el formulario de la web oficial).
public enum BugReportCategory: String, CaseIterable, Identifiable, Sendable {
    case bug
    case enhancement
    case question

    public var id: String { rawValue }

    public var githubLabel: String {
        switch self {
        case .bug: return "bug"
        case .enhancement: return "enhancement"
        case .question: return "question"
        }
    }

    public var titlePrefix: String {
        switch self {
        case .bug: return "[Bug]"
        case .enhancement: return "[Idea]"
        case .question: return "[Help]"
        }
    }

    public var systemImage: String {
        switch self {
        case .bug: return "ladybug.fill"
        case .enhancement: return "lightbulb.fill"
        case .question: return "questionmark.circle.fill"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .bug: return loc.text(es: "Error / Bug", en: "Bug / Issue")
        case .enhancement: return loc.text(es: "Idea / Sugerencia", en: "Feature Idea")
        case .question: return loc.text(es: "Consulta / Ayuda", en: "Question / Help")
        }
    }

    @MainActor
    public func localizedSubmitButtonTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .bug: return loc.text(es: "Enviar reporte", en: "Send Report")
        case .enhancement: return loc.text(es: "Enviar idea", en: "Send Idea")
        case .question: return loc.text(es: "Enviar consulta", en: "Send Question")
        }
    }
}

/// Resultado de enviar o abrir un reporte de error.
public enum BugReportSubmissionOutcome: Equatable, Sendable {
    case openedGitHubBrowser(URL)
    case submittedViaRelay(issueURL: URL?, deduplicated: Bool)
    case failed(String)
}

/// Servicio central híbrido de reporte de errores y diagnóstico mensual de `INTERNAL_ERROR.log`.
///
/// Modo híbrido:
/// 1. **Hoy (sin servidor ni tokens):** arma un Issue prellenado, sanitizado y deduplicado en GitHub
///    para que el usuario revise y envíe en 1 clic desde «Acerca de» o el Check-in mensual.
/// 2. **Futuro opcional (Cloudflare Worker):** si se configura `relayEndpointURL` (usando el template
///    listo en `scripts/github-bug-relay-worker.js`), puede enviar reportes directos sin cuenta GitHub
///    y reportar errores del log automáticamente (opt-in) con deduplicación por firma.
@MainActor
@Observable
public final class BugReportService {

    public static let shared = BugReportService()

    /// Endpoint opcional de Cloudflare Worker (dejar en `nil` hasta desplegar el Worker gratuito).
    public static let defaultRelayEndpointURL: String? = nil

    private enum Keys {
        static let monthlyLogScanEnabled = "com.macfileexplorer.bugReport.monthlyLogScanEnabled"
        static let autoSubmitViaRelayEnabled = "com.macfileexplorer.bugReport.autoSubmitViaRelayEnabled"
        static let customRelayEndpointURL = "com.macfileexplorer.bugReport.customRelayEndpointURL"
    }

    private let defaults: UserDefaults

    /// Reporte actual de errores nuevos sin reportar en `INTERNAL_ERROR.log`.
    public private(set) var unreportedScan: InternalErrorScanReport?

    /// Último análisis reciente completo (útil para adjuntar en reportes manuales desde «Acerca de»).
    public private(set) var recentScan: InternalErrorScanReport?

    /// Estado de envío (cuando usa un Worker o recién abrió GitHub).
    public private(set) var isSubmitting: Bool = false
    public private(set) var lastSubmissionStatus: String?
    public private(set) var lastRelayAutoSubmittedCount: Int = 0

    /// Activa o desactiva la revisión automática mensual de `INTERNAL_ERROR.log`.
    public var monthlyLogScanEnabled: Bool {
        didSet {
            defaults.set(monthlyLogScanEnabled, forKey: Keys.monthlyLogScanEnabled)
        }
    }

    /// Si existe un Cloudflare Worker configurado, permite enviar el resumen mensual sin intervención manual.
    public var autoSubmitViaRelayEnabled: Bool {
        didSet {
            defaults.set(autoSubmitViaRelayEnabled, forKey: Keys.autoSubmitViaRelayEnabled)
        }
    }

    public var configuredRelayURL: URL? {
        let raw = (defaults.string(forKey: Keys.customRelayEndpointURL) ?? Self.defaultRelayEndpointURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }

    public var hasRelayConfigured: Bool {
        configuredRelayURL != nil
    }

    public var hasUnreportedErrors: Bool {
        !(unreportedScan?.isEmpty ?? true)
    }

    public var unreportedUniqueCount: Int {
        unreportedScan?.uniqueCount ?? 0
    }

    public var unreportedTotalOccurrences: Int {
        unreportedScan?.totalOccurrences ?? 0
    }

    public var allIssuesPageURL: URL {
        URL(string: "https://github.com/\(AppVersionInfo.repositoryOwner)/\(AppVersionInfo.repositoryName)/issues")!
    }

    public var environmentSummaryText: String {
        "MacFileExplorer v\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild)) · macOS \(Self.macOSVersionSummary) · \(Self.architectureSummary)"
    }

    public static var architectureSummary: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "macOS"
        #endif
    }

    public static var macOSVersionSummary: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.monthlyLogScanEnabled = defaults.object(forKey: Keys.monthlyLogScanEnabled) as? Bool ?? true
        self.autoSubmitViaRelayEnabled = defaults.object(forKey: Keys.autoSubmitViaRelayEnabled) as? Bool ?? false
    }

    // MARK: - Escaneo del Log Interno

    /// Actualiza el estado de errores nuevos y recientes desde `INTERNAL_ERROR.log` en segundo plano.
    public func refreshLogScan(allowRelayAutoSubmit: Bool = false) {
        guard monthlyLogScanEnabled || !allowRelayAutoSubmit else {
            unreportedScan = nil
            return
        }

        Task.detached(priority: .utility) {
            let unreported = InternalErrorLogger.shared.scanUnreportedErrors(maxGroups: 8)
            let recent = InternalErrorLogger.shared.scanRecentErrors(maxGroups: 6)

            await MainActor.run {
                self.unreportedScan = unreported.isEmpty ? nil : unreported
                self.recentScan = recent.isEmpty ? nil : recent

                if allowRelayAutoSubmit,
                   !unreported.isEmpty,
                   self.autoSubmitViaRelayEnabled,
                   self.hasRelayConfigured {
                    Task {
                        _ = await self.submitMonthlyAutoReport(from: unreported)
                    }
                }
            }
        }
    }

    /// Marca los errores nuevos detectados como ignorados/revisados por este mes.
    public func dismissUnreportedErrorsForThisMonth() {
        let fps = unreportedScan?.groups.map(\.id) ?? []
        InternalErrorLogger.shared.markCurrentErrorsAsReported(fingerprints: fps)
        unreportedScan = nil
    }

    /// Limpia por completo `INTERNAL_ERROR.log` y refresca contadores.
    public func clearInternalErrorLog() {
        InternalErrorLogger.shared.clearLog()
        unreportedScan = nil
        recentScan = nil
    }

    /// Muestra `INTERNAL_ERROR.log` en Finder / MacFileExplorer para inspección local del usuario.
    public func revealInternalErrorLog() {
        let url = InternalErrorLogger.logFileURL
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Construcción de Texto Sanitizado y URLs de GitHub Issues

    /// Genera la vista previa exacta (sanitizada y segura para GitHub) de los errores internos a adjuntar.
    public func formattedSanitizedLogMarkdown(for scan: InternalErrorScanReport?) -> String {
        guard let scan, !scan.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("### Internal Error Summary (Sanitized · \(scan.totalOccurrences) events / \(scan.uniqueCount) unique)")
        lines.append("| Category | Count | Last Seen | Sanitized Message |")
        lines.append("| --- | ---: | --- | --- |")
        for g in scan.groups.prefix(6) {
            let safeMsg = g.sampleMessage
                .replacingOccurrences(of: "|", with: "/")
                .replacingOccurrences(of: "\n", with: " ")
            let shortDate = String(g.lastSeen.prefix(19))
            lines.append("| `\(g.category)` | \(g.count) | `\(shortDate)` | \(String(safeMsg.prefix(120))) |")
        }
        if let topWithStack = scan.groups.first(where: { !$0.sampleStack.isEmpty }) {
            lines.append("")
            lines.append("<details><summary>Top stack sample (\(topWithStack.category))</summary>")
            lines.append("")
            lines.append("```text")
            lines.append(String(topWithStack.sampleStack.prefix(650)))
            lines.append("```")
            lines.append("</details>")
        }
        lines.append("")
        lines.append("<!-- auto-bug-fp:\(scan.combinedFingerprint) -->")
        return lines.joined(separator: "\n")
    }

    public func buildManualIssueComponents(
        category: BugReportCategory,
        summary: String,
        details: String,
        includeSanitizedLogs: Bool,
        loc: LocalizationManager = .shared
    ) -> (title: String, body: String, labels: [String], fingerprint: String?) {
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = "\(category.titlePrefix) \(cleanSummary)"
        let isSpanish = loc.effectiveLanguage == .spanish

        var sections: [String] = []
        if isSpanish {
            sections.append("### Descripción del problema / sugerencia")
            sections.append(cleanDetails.isEmpty ? "_(Sin detalles adicionales)_" : cleanDetails)
            sections.append("")
            sections.append("### Entorno")
            sections.append("- **Versión de MacFileExplorer:** v\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild))")
            sections.append("- **macOS:** \(Self.macOSVersionSummary)")
            sections.append("- **Mac:** \(Self.architectureSummary)")
            sections.append("- **Reportado desde:** Acerca de MacFileExplorer (app nativa)")
        } else {
            sections.append("### Description")
            sections.append(cleanDetails.isEmpty ? "_(No additional details)_" : cleanDetails)
            sections.append("")
            sections.append("### Environment")
            sections.append("- **MacFileExplorer Version:** v\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild))")
            sections.append("- **macOS:** \(Self.macOSVersionSummary)")
            sections.append("- **Mac:** \(Self.architectureSummary)")
            sections.append("- **Reported via:** About MacFileExplorer (native app)")
        }

        let scanToAttach = unreportedScan ?? recentScan
        var fp: String?
        if includeSanitizedLogs, let scanToAttach, !scanToAttach.isEmpty {
            sections.append("")
            sections.append(formattedSanitizedLogMarkdown(for: scanToAttach))
            fp = scanToAttach.combinedFingerprint
        }

        return (title, sections.joined(separator: "\n"), [category.githubLabel], fp)
    }

    public func buildMonthlyAutoIssueComponents(
        from scan: InternalErrorScanReport
    ) -> (title: String, body: String, labels: [String], fingerprint: String) {
        let topCat = scan.groups.first?.category ?? "INTERNAL_ERROR"
        let title = "[Auto-Bug] v\(AppVersionInfo.currentVersion) · \(topCat) (\(scan.totalOccurrences) events / \(scan.uniqueCount) unique)"
        let sections: [String] = [
            "### Automated Monthly Internal Diagnostics Report",
            "Reported from MacFileExplorer's monthly check-in after sanitizing user paths and personal filenames.",
            "",
            "### Environment",
            "- **MacFileExplorer Version:** v\(AppVersionInfo.currentVersion) (Build \(AppVersionInfo.currentBuild))",
            "- **macOS:** \(Self.macOSVersionSummary)",
            "- **Mac:** \(Self.architectureSummary)",
            "",
            formattedSanitizedLogMarkdown(for: scan)
        ]
        let body = sections.joined(separator: "\n")
        return (title, body, ["bug", "auto-bug"], scan.combinedFingerprint)
    }

    /// Construye la URL prellenada para abrir el Issue directo en GitHub (acotada de forma segura bajo 6800 caracteres).
    public func makePreFilledGitHubIssueURL(title: String, body: String, labels: [String]) -> URL {
        let safeBody = body.count > 4800 ? String(body.prefix(4760)) + "\n\n_(Truncated to fit GitHub URL limit)_" : body
        var comps = URLComponents(string: "https://github.com/\(AppVersionInfo.repositoryOwner)/\(AppVersionInfo.repositoryName)/issues/new")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: safeBody),
            URLQueryItem(name: "labels", value: labels.joined(separator: ","))
        ]
        return comps.url ?? allIssuesPageURL
    }

    // MARK: - Envío Híbrido (Worker Relay si está configurado, o GitHub Prellenado en 1 Clic)

    public func submitManualReport(
        category: BugReportCategory,
        summary: String,
        details: String,
        includeSanitizedLogs: Bool
    ) async -> BugReportSubmissionOutcome {
        let payload = buildManualIssueComponents(
            category: category,
            summary: summary,
            details: details,
            includeSanitizedLogs: includeSanitizedLogs
        )
        let outcome = await dispatchReport(
            title: payload.title,
            body: payload.body,
            labels: payload.labels,
            fingerprint: payload.fingerprint,
            isAutomaticMonthly: false
        )
        if includeSanitizedLogs, case .openedGitHubBrowser = outcome {
            dismissUnreportedErrorsForThisMonth()
        } else if includeSanitizedLogs, case .submittedViaRelay = outcome {
            dismissUnreportedErrorsForThisMonth()
        }
        return outcome
    }

    /// Envía o abre en GitHub el reporte mensual de errores internos detectados en `INTERNAL_ERROR.log`.
    @discardableResult
    public func submitMonthlyAutoReport(from explicitScan: InternalErrorScanReport? = nil) async -> BugReportSubmissionOutcome? {
        guard let scan = explicitScan ?? unreportedScan, !scan.isEmpty else { return nil }
        let payload = buildMonthlyAutoIssueComponents(from: scan)
        let outcome = await dispatchReport(
            title: payload.title,
            body: payload.body,
            labels: payload.labels,
            fingerprint: payload.fingerprint,
            isAutomaticMonthly: true
        )
        switch outcome {
        case .openedGitHubBrowser, .submittedViaRelay:
            if case .submittedViaRelay = outcome {
                lastRelayAutoSubmittedCount = scan.uniqueCount
            }
            InternalErrorLogger.shared.markCurrentErrorsAsReported(fingerprints: scan.groups.map(\.id))
            unreportedScan = nil
        case .failed:
            break
        }
        return outcome
    }

    private struct RelayPayload: Encodable {
        let title: String
        let body: String
        let labels: [String]
        let fingerprint: String?
        let appVersion: String
        let macOSVersion: String
        let architecture: String
        let automatic: Bool
    }

    private struct RelayResponse: Decodable {
        let ok: Bool?
        let issueUrl: String?
        let deduplicated: Bool?
        let error: String?
    }

    private func dispatchReport(
        title: String,
        body: String,
        labels: [String],
        fingerprint: String?,
        isAutomaticMonthly: Bool
    ) async -> BugReportSubmissionOutcome {
        isSubmitting = true
        defer { isSubmitting = false }

        // 1. Si hay un Cloudflare Worker relay configurado, enviar directo vía HTTPS POST (sin cuenta GitHub).
        if let relayURL = configuredRelayURL {
            let payload = RelayPayload(
                title: title,
                body: body,
                labels: labels,
                fingerprint: fingerprint,
                appVersion: AppVersionInfo.currentVersion,
                macOSVersion: Self.macOSVersionSummary,
                architecture: Self.architectureSummary,
                automatic: isAutomaticMonthly
            )
            var request = URLRequest(url: relayURL, timeoutInterval: 12)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("MacFileExplorer/\(AppVersionInfo.currentVersion)", forHTTPHeaderField: "User-Agent")
            if let jsonData = try? JSONEncoder().encode(payload) {
                request.httpBody = jsonData
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        let decoded = try? JSONDecoder().decode(RelayResponse.self, from: data)
                        let issueURL = decoded?.issueUrl.flatMap(URL.init(string:))
                        return .submittedViaRelay(issueURL: issueURL, deduplicated: decoded?.deduplicated ?? false)
                    }
                } catch {
                    // Si el relay falla en modo manual, hacemos fallback limpio al navegador prellenado.
                    if isAutomaticMonthly {
                        return .failed(error.localizedDescription)
                    }
                }
            }
        }

        // 2. Modo sin servidor (default actual): abrir GitHub Issues prellenado en el navegador.
        let issueURL = makePreFilledGitHubIssueURL(title: title, body: body, labels: labels)
        NSWorkspace.shared.open(issueURL)
        return .openedGitHubBrowser(issueURL)
    }
}
