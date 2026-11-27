import AppKit
import Foundation
import SwiftUI

// MARK: - Fuente de Calendario del Notch

public enum NotchCalendarSourceMode: String, CaseIterable, Identifiable, Sendable {
    case googleCalendar
    case macOSCalendar
    case both

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .googleCalendar: return loc.text(es: "Google Calendar (Gmail)", en: "Google Calendar (Gmail)")
        case .macOSCalendar: return loc.text(es: "Calendario de macOS", en: "macOS Calendar")
        case .both: return loc.text(es: "Ambos (Google + macOS)", en: "Both (Google + macOS)")
        }
    }
}

// MARK: - Rango Visible (Diario / Semanal)

public enum NotchCalendarRangeMode: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .daily: return loc.text(es: "Diario (Hoy)", en: "Daily (Today)")
        case .weekly: return loc.text(es: "Semanal (7 días)", en: "Weekly (7 Days)")
        }
    }

    @MainActor
    public func shortTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .daily: return loc.text(es: "Día", en: "Day")
        case .weekly: return loc.text(es: "Semana", en: "Week")
        }
    }
}

// MARK: - Formato Visual Estilo Google Calendar

public enum NotchCalendarDisplayFormat: String, CaseIterable, Identifiable, Sendable {
    case googleAgenda
    case googleTimeline
    case compactList

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .googleAgenda: return loc.text(es: "Agenda Google", en: "Google Agenda")
        case .googleTimeline: return loc.text(es: "Línea de tiempo", en: "Timeline")
        case .compactList: return loc.text(es: "Compacto", en: "Compact")
        }
    }
}

// MARK: - Dónde Abrir Google Calendar / Meet al Hacer Clic

public enum NotchCalendarOpenTarget: String, CaseIterable, Identifiable, Sendable {
    case googleChrome
    case macFileExplorerTab
    case defaultBrowser

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .googleChrome: return loc.text(es: "Google Chrome", en: "Google Chrome")
        case .macFileExplorerTab: return loc.text(es: "Pestaña en MacFileExplorer", en: "MacFileExplorer Tab")
        case .defaultBrowser: return loc.text(es: "Navegador predeterminado", en: "Default Browser")
        }
    }
}

// MARK: - Animación Superior al Acercarse una Meet

public enum NotchCalendarAlertAnimationStyle: String, CaseIterable, Identifiable, Sendable {
    case dropDownBanner
    case greenMeetPulse
    case expandSideways
    case subtleGlow
    case none

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .dropDownBanner: return loc.text(es: "Desplegar aviso hacia abajo", en: "Drop-Down Alert Banner")
        case .greenMeetPulse: return loc.text(es: "Pulso verde de Meet", en: "Green Meet Pulse")
        case .expandSideways: return loc.text(es: "Ensanchar a los costados", en: "Expand Sideways")
        case .subtleGlow: return loc.text(es: "Brillo sutil en el borde", en: "Subtle Rim Glow")
        case .none: return loc.text(es: "Sin animación", en: "No Animation")
        }
    }
}

// MARK: - Sonido de Alerta de Reunión

public enum NotchCalendarAlertSound: String, CaseIterable, Identifiable, Sendable {
    case glass = "Glass"
    case ping = "Ping"
    case hero = "Hero"
    case submarine = "Submarine"
    case tink = "Tink"

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}

// MARK: - Convivencia con Música Reproduciéndose

public enum NotchCalendarMusicCoexistenceMode: String, CaseIterable, Identifiable, Sendable {
    case alertMeetOverMusic
    case alwaysShowBadgeWithMusic
    case manualTabOnly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .alertMeetOverMusic:
            return loc.text(es: "Avisar Meet sobre la música", en: "Alert Meet Over Music")
        case .alwaysShowBadgeWithMusic:
            return loc.text(es: "Mostrar siempre cuenta regresiva junto a la música", en: "Always Show Countdown Beside Music")
        case .manualTabOnly:
            return loc.text(es: "Solo al abrir el ícono Calendario", en: "Only When Opening Calendar Icon")
        }
    }
}

// MARK: - Estilo, Posición y Tamaño del Ícono de Calendario en la Barra del Notch

public enum NotchCalendarIconStyle: String, CaseIterable, Identifiable, Sendable {
    case microCircle
    case pillLikeMusic
    case dateBadgeTile
    case pillWithNextEvent

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .microCircle:
            return loc.text(es: "Ícono circular compacto", en: "Compact Circle Icon")
        case .pillLikeMusic:
            return loc.text(es: "Cápsula como «YouTube Music»", en: "Pill Like \"YouTube Music\"")
        case .dateBadgeTile:
            return loc.text(es: "Mosaico con número de día", en: "Date Tile Badge")
        case .pillWithNextEvent:
            return loc.text(es: "Cápsula con próxima hora / Meet", en: "Pill With Next Event Time")
        }
    }
}

public enum NotchCalendarIconPosition: String, CaseIterable, Identifiable, Sendable {
    case leftNextToMusic
    case center
    case rightBeforeControls
    case rightBeforeClose

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .leftNextToMusic:
            return loc.text(es: "Izquierda (junto a YouTube Music)", en: "Left (Next to YouTube Music)")
        case .center:
            return loc.text(es: "Centro de la barra superior", en: "Center of Top Bar")
        case .rightBeforeControls:
            return loc.text(es: "Derecha (antes de Ecualizador)", en: "Right (Before Equalizer)")
        case .rightBeforeClose:
            return loc.text(es: "Extremo derecho (junto a Cerrar)", en: "Far Right (Next to Close)")
        }
    }
}

public enum NotchCalendarIconSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .small:
            return loc.text(es: "Pequeño", en: "Small")
        case .medium:
            return loc.text(es: "Mediano (Igual a YouTube Music)", en: "Medium (Matches YouTube Music)")
        case .large:
            return loc.text(es: "Grande (Destacado)", en: "Large (Prominent)")
        }
    }
}

// MARK: - Modelo de Evento de Calendario

public struct NotchCalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let isGoogleCalendar: Bool
    public let accountEmail: String?
    public let calendarName: String
    public let color: NotchRGBColor
    public let eventURL: URL?
    public let meetingURL: URL?
    public let location: String?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        isGoogleCalendar: Bool,
        accountEmail: String? = nil,
        calendarName: String,
        color: NotchRGBColor = NotchRGBColor(r: 0.26, g: 0.52, b: 0.96),
        eventURL: URL? = nil,
        meetingURL: URL? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isGoogleCalendar = isGoogleCalendar
        self.accountEmail = accountEmail
        self.calendarName = calendarName
        self.color = color
        self.eventURL = eventURL
        self.meetingURL = meetingURL
        self.location = location
    }

    public var hasMeetingLink: Bool {
        meetingURL != nil
    }

    public var isOngoingNow: Bool {
        let now = Date()
        return !isAllDay && now >= startDate && now < endDate
    }

    public func minutesUntilStart(from now: Date = Date()) -> Int {
        Int(ceil(startDate.timeIntervalSince(now) / 60.0))
    }

    @MainActor
    public func countdownLabel(from now: Date = Date(), using loc: LocalizationManager = .shared) -> String {
        if isAllDay {
            return loc.text(es: "Todo el día", en: "All day")
        }
        if now >= startDate && now < endDate {
            return loc.text(es: "En curso", en: "Live now")
        }
        let secs = startDate.timeIntervalSince(now)
        if secs <= 60 {
            return loc.text(es: "Ahora", en: "Now")
        }
        let mins = Int(ceil(secs / 60.0))
        if mins < 60 {
            return loc.text(es: "En \(mins) min", en: "In \(mins)m")
        }
        let hours = mins / 60
        let rem = mins % 60
        if rem == 0 {
            return loc.text(es: "En \(hours)h", en: "In \(hours)h")
        }
        return loc.text(es: "En \(hours)h \(rem)m", en: "In \(hours)h \(rem)m")
    }

    public var formattedTimeRange: String {
        if isAllDay { return "—" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "\(df.string(from: startDate)) – \(df.string(from: endDate))"
    }

    public var formattedStartTime: String {
        if isAllDay { return "—" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: startDate)
    }

    /// Extrae el primer enlace de Google Meet, Zoom o Microsoft Teams de un texto arbitrario.
    public nonisolated static func extractMeetingURL(from texts: [String?]) -> URL? {
        let pattern = #"https?://(?:meet\.google\.com/[a-zA-Z0-9\-?=&_]+|[a-z0-9.-]*zoom\.us/j/[0-9a-zA-Z?=&_\-]+|teams\.microsoft\.com/l/meetup-join/[^\s"'<>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        for raw in texts {
            guard let text = raw, !text.isEmpty else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let swiftRange = Range(match.range, in: text),
               let url = URL(string: String(text[swiftRange])) {
                return url
            }
        }
        return nil
    }
}
