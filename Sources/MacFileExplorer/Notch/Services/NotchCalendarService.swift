import AppKit
import EventKit
import Foundation
import Observation
import WebKit

/// Servicio de sincronización de **Google Calendar** (desde las cuentas Gmail logueadas en `MacFileExplorer`
/// mediante `WKWebsiteDataStore(forIdentifier:)`) + soporte opcional de **Calendario de macOS (`EventKit`)**,
/// con alertas inteligentes antes de iniciar una Meet y apertura directa en Google Chrome.
@MainActor
@Observable
public final class NotchCalendarService: NSObject {

    public static let shared = NotchCalendarService()

    public private(set) var events: [NotchCalendarEvent] = []
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var lastSyncStatusMessage: String?
    public private(set) var eventKitAuthorized: Bool = false

    /// Reunión inminente (o de prueba) activa para mostrar aviso superior en el Notch y botón «Unirse a Meet».
    public private(set) var activeAlertEvent: NotchCalendarEvent?

    private let eventStore = EKEventStore()
    private var refreshLoopTask: Task<Void, Never>?
    private var alertTickTask: Task<Void, Never>?
    private var activeGoogleScrapers: [UUID: HeadlessGoogleCalendarScraper] = [:]
    private var googleEventsByAccountID: [UUID: [NotchCalendarEvent]] = [:]
    private var macOSEvents: [NotchCalendarEvent] = []
    private var alertedEventIDs: Set<String> = []
    private var testAlertDismissTask: Task<Void, Never>?
    private var isMonitoring = false

    private override init() {
        super.init()
    }

    // MARK: - Ciclo de Vida

    public func startMonitoringIfNeeded() {
        let prefs = NotchPreferences.shared
        guard prefs.isEnabled && prefs.calendarEnabled else {
            stopMonitoring()
            return
        }
        guard !isMonitoring else {
            refreshNow()
            return
        }
        isMonitoring = true
        refreshNow()

        refreshLoopTask?.cancel()
        refreshLoopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(180))
                guard !Task.isCancelled else { break }
                self?.refreshNow()
            }
        }

        alertTickTask?.cancel()
        alertTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.evaluateImminentMeetingAlert()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    public func stopMonitoring() {
        isMonitoring = false
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        alertTickTask?.cancel()
        alertTickTask = nil
        testAlertDismissTask?.cancel()
        testAlertDismissTask = nil
        for scraper in activeGoogleScrapers.values {
            scraper.teardown()
        }
        activeGoogleScrapers.removeAll()
        activeAlertEvent = nil
    }

    // MARK: - Consultas de Eventos Filtrados (Diario / Semanal)

    /// Devuelve los eventos visibles según el rango elegido (`Diario` o `Semanal`) y el filtro de «todo el día».
    public var visibleEvents: [NotchCalendarEvent] {
        let prefs = NotchPreferences.shared
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let daysSpan = (prefs.calendarRangeMode == .daily) ? 1 : 7
        let endHorizon = cal.date(byAdding: .day, value: daysSpan, to: startOfToday) ?? startOfToday.addingTimeInterval(86400)

        return events
            .filter { ev in
                if prefs.calendarHideAllDayEvents && ev.isAllDay {
                    return false
                }
                return ev.endDate >= Date().addingTimeInterval(-300) && ev.startDate < endHorizon
            }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return !lhs.isAllDay
                }
                return lhs.startDate < rhs.startDate
            }
    }

    /// Próximo evento no finalizado (ideal para la cuenta regresiva en el Notch colapsado).
    public var nextUpcomingEvent: NotchCalendarEvent? {
        let now = Date()
        return visibleEvents.first { !$0.isAllDay && $0.endDate > now }
    }

    // MARK: - Sincronización en Vivo

    public func refreshNow() {
        let prefs = NotchPreferences.shared
        guard prefs.calendarEnabled else { return }

        isSyncing = true
        let source = prefs.calendarSource

        if source == .googleCalendar || source == .both {
            syncGoogleCalendarsFromLoggedInAccounts()
        } else {
            googleEventsByAccountID.removeAll()
        }

        if source == .macOSCalendar || source == .both {
            syncMacOSEventKitCalendars()
        } else {
            macOSEvents.removeAll()
        }

        rebuildMergedEvents()
    }

    /// Solicita permiso de Calendario de macOS (`EventKit`) si el usuario eligió macOS Calendar o Ambos.
    public func requestMacOSCalendarPermission() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let granted: Bool
                if #available(macOS 14.0, *) {
                    granted = try await self.eventStore.requestFullAccessToEvents()
                } else {
                    granted = try await self.eventStore.requestAccess(to: .event)
                }
                self.eventKitAuthorized = granted
                if granted {
                    self.syncMacOSEventKitCalendars()
                    self.rebuildMergedEvents()
                }
            } catch {
                self.eventKitAuthorized = false
            }
        }
    }

    private func syncMacOSEventKitCalendars() {
        let auth = EKEventStore.authorizationStatus(for: .event)
        let isAuthorized = (auth == .fullAccess)
        eventKitAuthorized = isAuthorized
        guard isAuthorized else {
            macOSEvents = []
            return
        }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 8, to: start) ?? start.addingTimeInterval(8 * 86400)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)

        macOSEvents = ekEvents.map { ev in
            let cgColor = ev.calendar.cgColor
            let nsColor = cgColor.flatMap(NSColor.init(cgColor:)) ?? NSColor.systemBlue
            let meetURL = NotchCalendarEvent.extractMeetingURL(from: [ev.url?.absoluteString, ev.location, ev.notes])
            let isGoogleBacked = ev.calendar.source.title.localizedCaseInsensitiveContains("google")
                || ev.calendar.source.title.localizedCaseInsensitiveContains("gmail")

            return NotchCalendarEvent(
                id: "ek::\(ev.eventIdentifier ?? UUID().uuidString)::\(Int(ev.startDate.timeIntervalSince1970))",
                title: ev.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? ev.title : "(Sin título)",
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                isGoogleCalendar: isGoogleBacked,
                accountEmail: isGoogleBacked ? ev.calendar.source.title : nil,
                calendarName: ev.calendar.title,
                color: NotchRGBColor(nsColor: nsColor),
                eventURL: isGoogleBacked ? URL(string: "https://calendar.google.com/calendar/u/0/r") : ev.url,
                meetingURL: meetURL,
                location: ev.location
            )
        }
    }

    private func syncGoogleCalendarsFromLoggedInAccounts() {
        let prefs = NotchPreferences.shared
        let allAuthenticated = GoogleAccountsManager.shared.accounts.filter { $0.isAuthenticated }
        let selectedID = prefs.calendarSelectedGoogleAccountID

        let targets: [GoogleAccount]
        if !selectedID.isEmpty, let match = allAuthenticated.first(where: { $0.id.uuidString == selectedID }) {
            targets = [match]
        } else {
            targets = allAuthenticated
        }

        guard !targets.isEmpty else {
            googleEventsByAccountID.removeAll()
            lastSyncStatusMessage = LocalizationManager.shared.text(
                es: "Iniciá sesión en tu cuenta de Gmail desde MacFileExplorer para ver tu Google Calendar.",
                en: "Sign in to your Gmail account in MacFileExplorer to sync Google Calendar."
            )
            isSyncing = false
            return
        }

        // Limpiar cuentas que ya no están seleccionadas
        let targetIDs = Set(targets.map(\.id))
        for key in Array(googleEventsByAccountID.keys) where !targetIDs.contains(key) {
            googleEventsByAccountID.removeValue(forKey: key)
        }

        for account in targets {
            activeGoogleScrapers[account.id]?.teardown()
            let scraper = HeadlessGoogleCalendarScraper(account: account) { [weak self] accountID, parsedEvents, errorMsg in
                Task { @MainActor in
                    guard let self else { return }
                    self.activeGoogleScrapers.removeValue(forKey: accountID)
                    if let parsedEvents {
                        self.googleEventsByAccountID[accountID] = parsedEvents
                        self.lastSyncStatusMessage = nil
                    } else if let errorMsg {
                        self.lastSyncStatusMessage = errorMsg
                    }
                    self.rebuildMergedEvents()
                }
            }
            activeGoogleScrapers[account.id] = scraper
            scraper.start()
        }
    }

    private func rebuildMergedEvents() {
        var combined: [NotchCalendarEvent] = []
        for list in googleEventsByAccountID.values {
            combined.append(contentsOf: list)
        }

        // Deduplicar eventos macOS que ya vinieron de Google Calendar (mismo título + hora de inicio ±2 min)
        for macEv in macOSEvents {
            let duplicate = combined.contains { gEv in
                gEv.title.caseInsensitiveCompare(macEv.title) == .orderedSame
                    && abs(gEv.startDate.timeIntervalSince(macEv.startDate)) < 120
            }
            if !duplicate {
                combined.append(macEv)
            }
        }

        events = combined.sorted { $0.startDate < $1.startDate }
        lastSyncedAt = Date()
        if activeGoogleScrapers.isEmpty {
            isSyncing = false
        }
        evaluateImminentMeetingAlert()
    }

    // MARK: - Detección de Meet Inminente, Sonido y Animación en el Notch

    public func evaluateImminentMeetingAlert() {
        let prefs = NotchPreferences.shared
        guard prefs.isEnabled && prefs.calendarEnabled else {
            activeAlertEvent = nil
            return
        }

        // Si hay una alerta de prueba activa, no pisarla
        if let active = activeAlertEvent, active.id.hasPrefix("demo-meet::") {
            return
        }

        let now = Date()
        let leadSeconds = TimeInterval(prefs.calendarAlertLeadMinutes * 60)

        let candidate = visibleEvents.first { ev in
            guard !ev.isAllDay else { return false }
            let untilStart = ev.startDate.timeIntervalSince(now)
            let untilEnd = ev.endDate.timeIntervalSince(now)
            // Activo desde `leadMinutes` antes hasta 2 minutos después de iniciada (o mientras tenga Meet y esté por arrancar)
            return untilStart <= leadSeconds && untilStart >= -120 && untilEnd > 0
        }

        activeAlertEvent = candidate

        if let candidate, !alertedEventIDs.contains(candidate.id) {
            alertedEventIDs.insert(candidate.id)
            fireMeetingNotification(for: candidate)
        }
    }

    /// Dispara una alerta real de prueba (15 s) con sonido y botón «Unirse a Meet» para previsualizar en el Notch.
    public func triggerTestMeetingAlert() {
        let loc = LocalizationManager.shared
        let now = Date()
        let demoEvent = NotchCalendarEvent(
            id: "demo-meet::\(UUID().uuidString)",
            title: loc.text(es: "Daily Sync · Equipo Producto", en: "Daily Sync · Product Team"),
            startDate: now.addingTimeInterval(180),
            endDate: now.addingTimeInterval(2100),
            isAllDay: false,
            isGoogleCalendar: true,
            accountEmail: GoogleAccountsManager.shared.accounts.first?.email,
            calendarName: "Google Calendar",
            color: NotchRGBColor(r: 0.20, g: 0.66, b: 0.33),
            eventURL: URL(string: "https://calendar.google.com/calendar/u/0/r"),
            meetingURL: URL(string: "https://meet.google.com/new"),
            location: "Google Meet"
        )
        activeAlertEvent = demoEvent
        fireMeetingNotification(for: demoEvent)

        testAlertDismissTask?.cancel()
        testAlertDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            if self?.activeAlertEvent?.id == demoEvent.id {
                self?.activeAlertEvent = nil
            }
        }
    }

    public func dismissActiveAlert() {
        testAlertDismissTask?.cancel()
        activeAlertEvent = nil
    }

    private func fireMeetingNotification(for event: NotchCalendarEvent) {
        let prefs = NotchPreferences.shared
        if prefs.calendarAlertSoundEnabled {
            playAlertSound(prefs.calendarAlertSound)
        }
        NotchManager.shared.triggerCalendarMeetingAlert(for: event)
    }

    public func playAlertSound(_ sound: NotchCalendarAlertSound) {
        if let nsSound = NSSound(named: NSSound.Name(sound.rawValue)) {
            nsSound.play()
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Apertura en Google Chrome / MacFileExplorer / Calendar.app

    /// Abre Google Calendar (en Chrome si es de Google, según preferencia del usuario) o Calendar.app si es nativo.
    public func openCalendar(for event: NotchCalendarEvent? = nil) {
        let prefs = NotchPreferences.shared
        let isGoogle = event?.isGoogleCalendar ?? (prefs.calendarSource != .macOSCalendar)

        if !isGoogle {
            if let url = URL(string: "ical://") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        let baseURL = event?.eventURL ?? {
            let viewPath = (prefs.calendarRangeMode == .weekly) ? "week" : "day"
            return URL(string: "https://calendar.google.com/calendar/u/0/r/\(viewPath)")!
        }()
        let email = event?.accountEmail ?? resolvePreferredGoogleEmail()
        let finalURL = GoogleDriveUploadService.urlWithAuthUser(baseURL, email: email)

        openGoogleURL(finalURL, accountEmail: email)
    }

    /// Abre el enlace directo de Google Meet / Zoom en Google Chrome (1 clic desde «Unirse a Meet»).
    public func joinMeeting(for event: NotchCalendarEvent) {
        guard let meetURL = event.meetingURL else {
            openCalendar(for: event)
            return
        }
        let email = event.accountEmail ?? resolvePreferredGoogleEmail()
        let finalURL = meetURL.host?.lowercased().contains("google.com") == true
            ? GoogleDriveUploadService.urlWithAuthUser(meetURL, email: email)
            : meetURL
        openGoogleURL(finalURL, accountEmail: email)
    }

    private func openGoogleURL(_ url: URL, accountEmail: String?) {
        let prefs = NotchPreferences.shared
        switch prefs.calendarOpenTarget {
        case .googleChrome:
            if let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: cfg, completionHandler: nil)
            } else {
                NSWorkspace.shared.open(url)
            }
        case .macFileExplorerTab:
            let manager = GoogleAccountsManager.shared
            let account = manager.accounts.first {
                if let accountEmail, !accountEmail.isEmpty {
                    return $0.email.caseInsensitiveCompare(accountEmail) == .orderedSame
                }
                return $0.isAuthenticated
            } ?? manager.accounts.first
            if let account {
                NSApplication.shared.activate(ignoringOtherApps: true)
                _ = manager.openURLInAccountTab(url, for: account.id, service: .calendar)
            } else {
                NSWorkspace.shared.open(url)
            }
        case .defaultBrowser:
            NSWorkspace.shared.open(url)
        }
    }

    private func resolvePreferredGoogleEmail() -> String? {
        let selectedID = NotchPreferences.shared.calendarSelectedGoogleAccountID
        let accounts = GoogleAccountsManager.shared.accounts
        if !selectedID.isEmpty, let matched = accounts.first(where: { $0.id.uuidString == selectedID }) {
            return matched.email
        }
        return accounts.first(where: { $0.isAuthenticated })?.email ?? accounts.first?.email
    }
}

// MARK: - Extractor Headless de Google Calendar (Usa la Sesión Gmail Ya Logueada en MacFileExplorer)

@MainActor
private final class HeadlessGoogleCalendarScraper: NSObject, WKNavigationDelegate {
    private let account: GoogleAccount
    private let onComplete: (UUID, [NotchCalendarEvent]?, String?) -> Void
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    init(account: GoogleAccount, onComplete: @escaping (UUID, [NotchCalendarEvent]?, String?) -> Void) {
        self.account = account
        self.onComplete = onComplete
        super.init()
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        self.webView = wv

        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        if let url = URL(string: "https://calendar.google.com/calendar/u/0/r/agenda/\(y)/\(m)/\(d)") {
            wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }

        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(16))
            self?.finish(events: nil, error: nil)
        }
    }

    func teardown() {
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !finished else { return }
        let currentHost = webView.url?.host?.lowercased() ?? ""
        if currentHost.contains("accounts.google.com") {
            finish(
                events: nil,
                error: LocalizationManager.shared.text(
                    es: "Volvé a iniciar sesión en tu cuenta de Google (\(account.displayLabel)) para sincronizar el calendario.",
                    en: "Sign in again to your Google account (\(account.displayLabel)) to sync Calendar."
                )
            )
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard let self, !self.finished, let wv = self.webView else { return }
            self.extractEventsFromDOM(in: wv)
        }
    }

    private func extractEventsFromDOM(in webView: WKWebView) {
        let js = """
        (function() {
            const results = [];
            const seenEventIds = new Set();
            const seenTextKeys = new Set();
            const meetRegex = /https?:\\/\\/(?:meet\\.google\\.com\\/[a-zA-Z0-9\\-?=&_]+|[a-z0-9.-]*zoom\\.us\\/j\\/[0-9a-zA-Z?=&_\\-]+)/i;

            // Preferir nodos hoja con [data-eventid] para no duplicar contenedor [role="listitem"] + hijo [data-eventid]
            let candidates = Array.from(document.querySelectorAll('[data-eventid]'));
            if (candidates.length === 0) {
                candidates = Array.from(document.querySelectorAll('[data-eventchip], [role="button"][data-draggable-id], [role="listitem"]'));
            }

            candidates.forEach((el) => {
                // Evitar contenedores padre que envuelven otro [data-eventid]
                if (el.querySelector && el.querySelector('[data-eventid]')) return;

                const eventId = (el.getAttribute('data-eventid') || '').trim();
                const aria = (el.getAttribute('aria-label') || '').trim();
                const rawText = (el.innerText || aria || '').trim();
                if (!rawText || rawText.length < 2 || rawText.length > 420) return;

                const lines = rawText.split(/\\n+/).map(s => s.trim()).filter(Boolean);
                if (lines.length === 0) return;

                // Detectar color RGB del chip o punto indicador del evento
                let colorRGB = null;
                const colorNodes = [el, el.querySelector('[style*="background"], [style*="border-color"]')].filter(Boolean);
                for (const node of colorNodes) {
                    const style = window.getComputedStyle(node);
                    const bg = style.backgroundColor || style.borderLeftColor || style.borderColor || '';
                    const mColor = bg.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
                    if (mColor) {
                        const r = parseInt(mColor[1], 10), g = parseInt(mColor[2], 10), b = parseInt(mColor[3], 10);
                        if (!(r === 0 && g === 0 && b === 0) && !(r > 245 && g > 245 && b > 245)) {
                            colorRGB = [r / 255, g / 255, b / 255];
                            break;
                        }
                    }
                }

                // Buscar enlace Meet dentro del elemento
                let meetUrl = null;
                const links = el.querySelectorAll('a[href]');
                links.forEach(a => {
                    if (!meetUrl && meetRegex.test(a.href)) meetUrl = a.href;
                });
                if (!meetUrl) {
                    const m = (rawText + ' ' + aria).match(meetRegex);
                    if (m) meetUrl = m[0];
                }

                // Buscar fecha del día padre (`data-datekey` bit-packed, `data-date` YYYYMMDD, o encabezado del día)
                let dateKey = null;
                let dataDate = null;
                let dayHeaderText = null;
                let parent = el;
                for (let depth = 0; depth < 12 && parent; depth++) {
                    if (!dateKey && parent.getAttribute) {
                        const dk = parent.getAttribute('data-datekey');
                        if (dk) dateKey = dk.trim();
                    }
                    if (!dataDate && parent.getAttribute) {
                        const dd = parent.getAttribute('data-date');
                        if (dd) dataDate = dd.trim();
                    }
                    if (!dayHeaderText && parent.querySelector) {
                        const heading = parent.querySelector('h2, [role="heading"]');
                        if (heading && heading.innerText && heading.innerText.trim().length <= 48) {
                            dayHeaderText = heading.innerText.trim();
                        }
                    }
                    if ((dateKey || dataDate) && dayHeaderText) break;
                    parent = parent.parentElement;
                }

                const dedupEventKey = eventId ? (eventId + '|' + (dateKey || dataDate || '')) : null;
                if (dedupEventKey) {
                    if (seenEventIds.has(dedupEventKey)) return;
                    seenEventIds.add(dedupEventKey);
                }

                const textKey = lines.join('|').toLowerCase() + '|' + (dateKey || dataDate || '');
                if (seenTextKeys.has(textKey)) return;
                seenTextKeys.add(textKey);

                results.push({
                    eventId: eventId,
                    text: rawText,
                    aria: aria,
                    lines: lines,
                    color: colorRGB,
                    meetUrl: meetUrl,
                    dateKey: dateKey,
                    dataDate: dataDate,
                    dayHeaderText: dayHeaderText
                });
            });
            return JSON.stringify(results.slice(0, 80));
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] value, _ in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                guard let jsonStr = value as? String,
                      let data = jsonStr.data(using: .utf8),
                      let rawItems = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    self.finish(events: [], error: nil)
                    return
                }
                let parsed = Self.parseExtractedItems(rawItems, account: self.account)
                self.finish(events: parsed, error: nil)
            }
        }
    }

    private struct ParsedClockToken {
        var hour: Int
        let minute: Int
        let explicitMeridiem: String? // "am" | "pm" | nil
    }

    /// Decodifica el atributo `data-datekey` (entero bit-packed de Google Calendar: `((year - 1970) << 9) | (month << 5) | day`)
    /// o `data-date` (`YYYYMMDD`), garantizando cero confusión entre mes y día.
    private static func decodeGoogleDateKey(_ raw: String?, calendar cal: Calendar) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Formato YYYYMMDD (8 dígitos)
        if trimmed.count == 8, trimmed.allSatisfy(\.isNumber),
           let y = Int(trimmed.prefix(4)),
           let mo = Int(trimmed.dropFirst(4).prefix(2)),
           let d = Int(trimmed.dropFirst(6).prefix(2)),
           (2000...2100).contains(y), (1...12).contains(mo), (1...31).contains(d),
           let parsed = cal.date(from: DateComponents(year: y, month: mo, day: d)) {
            return cal.startOfDay(for: parsed)
        }

        // Formato bit-packed de Google Calendar (ej. 29051 -> 2026-11-27)
        if let packed = Int(trimmed), packed > 0, trimmed.count <= 6 {
            let day = packed & 0x1F
            let month = (packed >> 5) & 0x0F
            let year = (packed >> 9) + 1970
            if (2000...2100).contains(year), (1...12).contains(month), (1...31).contains(day),
               let parsed = cal.date(from: DateComponents(year: year, month: month, day: day)) {
                return cal.startOfDay(for: parsed)
            }
        }

        return nil
    }

    /// Extrae una fecha inequívoca con nombre de mes (ES/EN, nunca `MM/DD` numérico ambiguo) desde `aria-label` o encabezado de día.
    private static func parseExplicitMonthNameDate(from text: String, referenceDate now: Date, calendar cal: Calendar) -> Date? {
        let lower = text.lowercased()
        let monthMap: [(String, Int)] = [
            ("january", 1), ("enero", 1), ("jan", 1), ("ene", 1),
            ("february", 2), ("febrero", 2), ("feb", 2),
            ("march", 3), ("marzo", 3), ("mar", 3),
            ("april", 4), ("abril", 4), ("apr", 4), ("abr", 4),
            ("may", 5), ("mayo", 5),
            ("june", 6), ("junio", 6), ("jun", 6),
            ("july", 7), ("julio", 7), ("jul", 7),
            ("august", 8), ("agosto", 8), ("aug", 8), ("ago", 8),
            ("september", 9), ("septiembre", 9), ("setiembre", 9), ("sep", 9), ("sept", 9),
            ("october", 10), ("octubre", 10), ("oct", 10),
            ("november", 11), ("noviembre", 11), ("nov", 11),
            ("december", 12), ("diciembre", 12), ("dec", 12), ("dic", 12)
        ]

        let defaultYear = cal.component(.year, from: now)

        // Patrón ES / D-M: "27 de noviembre de 2026", "27 nov", "4 dic 2026"
        if let regexDM = try? NSRegularExpression(
            pattern: #"\b(\d{1,2})\s*(?:de\s+)?([a-záéíóú]{3,11})\.?(?:\s*(?:de\s+|,\s*)?(\d{4}))?\b"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            for match in regexDM.matches(in: lower, range: range) {
                guard let dRange = Range(match.range(at: 1), in: lower),
                      let mRange = Range(match.range(at: 2), in: lower),
                      let day = Int(lower[dRange]), (1...31).contains(day) else { continue }
                let mToken = String(lower[mRange])
                guard let month = monthMap.first(where: { $0.0 == mToken })?.1 else { continue }
                let year: Int = {
                    if let yRange = Range(match.range(at: 3), in: lower), let y = Int(lower[yRange]) {
                        return y
                    }
                    return defaultYear
                }()
                if let parsed = cal.date(from: DateComponents(year: year, month: month, day: day)) {
                    return cal.startOfDay(for: parsed)
                }
            }
        }

        // Patrón EN / M-D: "November 27, 2026", "Nov 27", "December 4, 2026"
        if let regexMD = try? NSRegularExpression(
            pattern: #"\b([a-záéíóú]{3,11})\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?\b"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            for match in regexMD.matches(in: lower, range: range) {
                guard let mRange = Range(match.range(at: 1), in: lower),
                      let dRange = Range(match.range(at: 2), in: lower),
                      let day = Int(lower[dRange]), (1...31).contains(day) else { continue }
                let mToken = String(lower[mRange])
                guard let month = monthMap.first(where: { $0.0 == mToken })?.1 else { continue }
                let year: Int = {
                    if let yRange = Range(match.range(at: 3), in: lower), let y = Int(lower[yRange]) {
                        return y
                    }
                    return defaultYear
                }()
                if let parsed = cal.date(from: DateComponents(year: year, month: month, day: day)) {
                    return cal.startOfDay(for: parsed)
                }
            }
        }

        return nil
    }

    /// Parsea un rango horario (ej. `"2:30 – 3:00pm"`, `"2:30 to 3pm"`, `"14:30 – 15:00"`) aplicando herencia correcta de AM/PM
    /// y sin leer números incrustados en el título del evento.
    private static func parseTimeRange(from timeSegment: String) -> [(hour: Int, minute: Int)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.?\s*m\.?|p\.?\s*m\.?)?\b"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(timeSegment.startIndex..<timeSegment.endIndex, in: timeSegment)
        var tokens: [ParsedClockToken] = []
        for match in regex.matches(in: timeSegment, range: range) {
            guard let hRange = Range(match.range(at: 1), in: timeSegment),
                  let h = Int(timeSegment[hRange]) else { continue }
            let hasColonMinutes = (match.range(at: 2).location != NSNotFound)
            let m: Int = {
                if let mRange = Range(match.range(at: 2), in: timeSegment), let parsedM = Int(timeSegment[mRange]) {
                    return parsedM
                }
                return 0
            }()
            let meridiem: String? = {
                guard let apRange = Range(match.range(at: 3), in: timeSegment) else { return nil }
                let ap = timeSegment[apRange].lowercased()
                if ap.contains("p") { return "pm" }
                if ap.contains("a") { return "am" }
                return nil
            }()

            // Ignorar números sueltos sin `:MM` ni `am/pm` salvo que sea un rango explícito (ej. "2 – 3pm")
            let isLikelyTime = hasColonMinutes || meridiem != nil || timeSegment.contains("–") || timeSegment.contains("-") || timeSegment.lowercased().contains(" to ") || timeSegment.lowercased().contains(" a ")
            guard isLikelyTime, h >= 0, h <= 23, m >= 0, m <= 59 else { continue }
            tokens.append(ParsedClockToken(hour: h, minute: m, explicitMeridiem: meridiem))
            if tokens.count >= 2 { break }
        }

        guard !tokens.isEmpty else { return [] }

        // Herencia de AM/PM estilo Google Calendar: "2:30 – 3:00pm" -> ambos son PM (14:30 – 15:00)
        if tokens.count >= 2 {
            if tokens[0].explicitMeridiem == nil, let endMeridiem = tokens[1].explicitMeridiem {
                let startH = tokens[0].hour
                let endH = tokens[1].hour
                if endMeridiem == "pm" {
                    let end24 = (endH < 12) ? (endH + 12) : endH
                    if startH >= 1 && startH <= 11 && (startH + 12) <= end24 {
                        tokens[0].hour = startH + 12
                    }
                } else if endMeridiem == "am" && startH == 12 {
                    tokens[0].hour = 0
                }
            } else if let startMeridiem = tokens[0].explicitMeridiem, tokens[1].explicitMeridiem == nil {
                if startMeridiem == "pm" && tokens[1].hour >= 1 && tokens[1].hour <= 11 {
                    let start24 = (tokens[0].hour < 12) ? (tokens[0].hour + 12) : tokens[0].hour
                    if (tokens[1].hour + 12) >= start24 {
                        tokens[1].hour += 12
                    }
                }
            }
        }

        // Aplicar meridiem explícito en cada token
        var resolved: [(hour: Int, minute: Int)] = []
        for token in tokens {
            var h = token.hour
            if token.explicitMeridiem == "pm" && h < 12 {
                h += 12
            } else if token.explicitMeridiem == "am" && h == 12 {
                h = 0
            }
            if h >= 0 && h < 24 {
                resolved.append((h, token.minute))
            }
        }
        return resolved
    }

    private static func parseExtractedItems(_ items: [[String: Any]], account: GoogleAccount) -> [NotchCalendarEvent] {
        let now = Date()
        let cal = Calendar.current

        var output: [NotchCalendarEvent] = []
        var dedupKeys = Set<String>()

        for (idx, item) in items.enumerated() {
            let lines = item["lines"] as? [String] ?? []
            let ariaText = (item["aria"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawText = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fullText = !ariaText.isEmpty ? ariaText : rawText
            guard !fullText.isEmpty else { continue }

            // 1. Resolver fecha del evento de forma inequívoca (NUNCA asumir "hoy" si no se conoce la fecha real)
            let dayHeaderText = (item["dayHeaderText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedDay: Date? =
                decodeGoogleDateKey(item["dataDate"] as? String, calendar: cal)
                ?? decodeGoogleDateKey(item["dateKey"] as? String, calendar: cal)
                ?? parseExplicitMonthNameDate(from: ariaText, referenceDate: now, calendar: cal)
                ?? parseExplicitMonthNameDate(from: dayHeaderText, referenceDate: now, calendar: cal)
                ?? {
                    let lower = (ariaText + " " + dayHeaderText).lowercased()
                    if lower.contains("today") || lower.contains("hoy") {
                        return cal.startOfDay(for: now)
                    }
                    return nil
                }()

            guard let baseDay = resolvedDay else {
                // Sin fecha confirmada: evitar mostrar eventos de otros días/meses como si fueran de hoy
                continue
            }

            // 2. Extraer horario SOLO desde la línea de horario o el primer segmento de aria-label (nunca desde el título)
            let timeLine = lines.first { line in
                let stripped = line.replacingOccurrences(of: #"[\d:\s–\-apmAPMa\.m\.p\.m\.to]+"#, with: "", options: .regularExpression)
                return stripped.count <= 2 && line.rangeOfCharacter(from: .decimalDigits) != nil
            }
            let ariaLeadingTimeSegment = ariaText.components(separatedBy: ",").first ?? ""
            let times: [(hour: Int, minute: Int)] = {
                if let timeLine {
                    let parsed = parseTimeRange(from: timeLine)
                    if !parsed.isEmpty { return parsed }
                }
                if !ariaLeadingTimeSegment.isEmpty {
                    let parsed = parseTimeRange(from: ariaLeadingTimeSegment)
                    if !parsed.isEmpty { return parsed }
                }
                return []
            }()

            // 3. Elegir el título más limpio (línea que no sea únicamente un rango horario)
            let titleCandidate = lines.first { line in
                let stripped = line.replacingOccurrences(of: #"[\d:\s–\-apmAPMa\.m\.p\.m\.]+"#, with: "", options: .regularExpression)
                return stripped.count >= 2
            } ?? {
                let parts = ariaText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                return parts.count >= 2 ? parts[1] : (lines.first ?? "")
            }()
            let cleanTitle = titleCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanTitle.count >= 2 else { continue }

            let isAllDay = times.isEmpty
            let startDate: Date
            let endDate: Date
            if let first = times.first {
                startDate = cal.date(bySettingHour: first.hour, minute: first.minute, second: 0, of: baseDay) ?? baseDay
                if times.count >= 2 {
                    let second = times[1]
                    var candidateEnd = cal.date(bySettingHour: second.hour, minute: second.minute, second: 0, of: baseDay) ?? startDate.addingTimeInterval(1800)
                    if candidateEnd <= startDate {
                        if second.hour == 0 && second.minute == 0 {
                            candidateEnd = cal.date(byAdding: .day, value: 1, to: baseDay) ?? startDate.addingTimeInterval(1800)
                        } else {
                            candidateEnd = startDate.addingTimeInterval(1800)
                        }
                    }
                    endDate = candidateEnd
                } else {
                    endDate = startDate.addingTimeInterval(1800)
                }
            } else {
                startDate = baseDay
                endDate = cal.date(byAdding: .day, value: 1, to: baseDay) ?? baseDay.addingTimeInterval(86400)
            }

            // 4. Deduplicar por título normalizado + día + hora de inicio (evita filas duplicadas)
            let dayStamp = Int(baseDay.timeIntervalSince1970)
            let dedupKey = "\(cleanTitle.lowercased())::\(dayStamp)::\(Int(startDate.timeIntervalSince1970))"
            guard !dedupKeys.contains(dedupKey) else { continue }
            dedupKeys.insert(dedupKey)

            var rgb = NotchRGBColor(r: 0.26, g: 0.52, b: 0.96)
            if let arr = item["color"] as? [Double], arr.count == 3 {
                rgb = NotchRGBColor(r: arr[0], g: arr[1], b: arr[2])
            }

            let rawMeet = item["meetUrl"] as? String
            let meetURL = rawMeet.flatMap(URL.init(string:)) ?? NotchCalendarEvent.extractMeetingURL(from: [fullText])

            let dayComps = cal.dateComponents([.year, .month, .day], from: baseDay)
            let eventDayURL = URL(
                string: "https://calendar.google.com/calendar/u/0/r/day/\(dayComps.year ?? 2026)/\(dayComps.month ?? 1)/\(dayComps.day ?? 1)"
            ) ?? URL(string: "https://calendar.google.com/calendar/u/0/r")

            output.append(
                NotchCalendarEvent(
                    id: "gcal::\(account.id.uuidString)::\(idx)::\(cleanTitle.lowercased())::\(Int(startDate.timeIntervalSince1970))",
                    title: cleanTitle,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    isGoogleCalendar: true,
                    accountEmail: account.email,
                    calendarName: account.displayLabel,
                    color: rgb,
                    eventURL: eventDayURL,
                    meetingURL: meetURL,
                    location: meetURL != nil ? "Google Meet" : nil
                )
            )
        }
        return output
    }

    private func finish(events: [NotchCalendarEvent]?, error: String?) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        onComplete(account.id, events, error)
    }
}
