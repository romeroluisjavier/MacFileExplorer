import AppKit
import SwiftUI

// MARK: - Banner Flotante de Alerta de Meet Inminente (Convive con la Música)

public struct NotchImminentMeetBannerView: View {
    public let event: NotchCalendarEvent
    public let showDirectJoinButton: Bool
    public let enableAnimations: Bool
    public let onJoin: () -> Void
    public let onOpenCalendar: () -> Void
    public let onDismiss: () -> Void

    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var prefs = NotchPreferences.shared

    private var bannerAccentColor: Color {
        if prefs.calendarUseNativeEventColors {
            return event.color.swiftUIColor
        }
        return Color(red: 0.16, green: 0.78, blue: 0.44)
    }

    public init(
        event: NotchCalendarEvent,
        showDirectJoinButton: Bool,
        enableAnimations: Bool,
        onJoin: @escaping () -> Void,
        onOpenCalendar: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.event = event
        self.showDirectJoinButton = showDirectJoinButton
        self.enableAnimations = enableAnimations
        self.onJoin = onJoin
        self.onOpenCalendar = onOpenCalendar
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(bannerAccentColor.opacity(0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(bannerAccentColor.opacity(0.45), lineWidth: 0.9)
                        )
                    Image(systemName: event.hasMeetingLink ? "video.fill" : "calendar.badge.clock")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(bannerAccentColor)
                }
                .frame(width: 40, height: 40)

                Button(action: onOpenCalendar) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(event.countdownLabel(using: loc).uppercased())
                                .font(.system(size: 9.5, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(bannerAccentColor))

                            Text(event.formattedTimeRange)
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.74))
                        }

                        Text(event.title)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(loc.text(es: "Ocultar aviso y volver a la música", en: "Dismiss alert and return to music"))
            }

            HStack(spacing: 8) {
                if showDirectJoinButton && event.hasMeetingLink {
                    Button(action: onJoin) {
                        HStack(spacing: 5.5) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 10.5, weight: .bold))
                            Text(loc.text(es: "Unirse a Meet", en: "Join Meet"))
                                .font(.system(size: 11.5, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(bannerAccentColor)
                        )
                    }
                    .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.95, enableAnimations: enableAnimations))
                    .help(loc.text(es: "Unirse a la Meet en Google Chrome", en: "Join Meet in Google Chrome"))
                }

                Button(action: onOpenCalendar) {
                    HStack(spacing: 4.5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                        Text(loc.text(es: "Ver en Calendar", en: "Open Calendar"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                            )
                    )
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.95, enableAnimations: enableAnimations))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bannerAccentColor.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(bannerAccentColor.opacity(0.42), lineWidth: 0.9)
                )
        )
    }
}

// MARK: - Vista Integrada Estilo Google Calendar en el Notch Expandido

public struct NotchCalendarContentView: View {
    public let accentColor: Color
    public let showBackButton: Bool
    public let onBack: () -> Void

    @Bindable private var prefs = NotchPreferences.shared
    @Bindable private var calService = NotchCalendarService.shared
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var selectedDayOffset: Int = 0

    public init(
        accentColor: Color,
        showBackButton: Bool,
        onBack: @escaping () -> Void
    ) {
        self.accentColor = accentColor
        self.showBackButton = showBackButton
        self.onBack = onBack
    }

    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private var filteredEventsForDisplay: [NotchCalendarEvent] {
        let all = calService.visibleEvents
        if prefs.calendarRangeMode == .daily {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            return all.filter { cal.isDate($0.startDate, inSameDayAs: today) || $0.isOngoingNow }
        }
        let days = weekDays
        guard selectedDayOffset >= 0 && selectedDayOffset < days.count else { return all }
        let targetDay = days[selectedDayOffset]
        let cal = Calendar.current
        return all.filter { cal.isDate($0.startDate, inSameDayAs: targetDay) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            calendarTopBar

            if prefs.calendarRangeMode == .weekly {
                weeklyDayStrip
            }

            if filteredEventsForDisplay.isEmpty {
                emptyCalendarBody
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: prefs.calendarDisplayFormat == .compactList ? 3.5 : 5) {
                        ForEach(filteredEventsForDisplay) { event in
                            eventRow(for: event)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var calendarTopBar: some View {
        HStack(spacing: 6) {
            // Clic en el título abre Google Calendar en Chrome (o Calendar.app si es macOS)
            Button {
                calService.openCalendar()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.32, green: 0.62, blue: 1.0))
                    Text(
                        prefs.calendarSource == .macOSCalendar
                            ? loc.text(es: "Calendario", en: "Calendar")
                            : "Google Calendar"
                    )
                    .font(.system(size: 11.8, weight: .bold))
                    .foregroundStyle(.white)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Abrir Google Calendar en Chrome", en: "Open Google Calendar in Chrome"))

            // Conmutador rápido Día / Semana
            HStack(spacing: 2) {
                ForEach(NotchCalendarRangeMode.allCases) { mode in
                    let isSelected = prefs.calendarRangeMode == mode
                    Button {
                        prefs.calendarRangeMode = mode
                        selectedDayOffset = 0
                    } label: {
                        Text(mode.shortTitle(using: loc))
                            .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.62))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.45) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))

            // Cambio rápido de formato (Agenda / Línea / Compacto)
            Button {
                let all = NotchCalendarDisplayFormat.allCases
                if let idx = all.firstIndex(of: prefs.calendarDisplayFormat) {
                    prefs.calendarDisplayFormat = all[(idx + 1) % all.count]
                }
            } label: {
                Image(systemName: formatSymbolName)
                    .font(.system(size: 9.8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(loc.text(
                es: "Cambiar formato (\(prefs.calendarDisplayFormat.localizedTitle(using: loc)))",
                en: "Switch format (\(prefs.calendarDisplayFormat.localizedTitle(using: loc)))"
            ))

            Spacer(minLength: 2)

            Button {
                calService.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Sincronizar eventos ahora", en: "Sync events now"))

            if showBackButton {
                Button(action: onBack) {
                    Text(loc.text(es: "Volver", en: "Done"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
            }
        }
    }

    private var formatSymbolName: String {
        switch prefs.calendarDisplayFormat {
        case .googleAgenda: return "rectangle.grid.1x2"
        case .googleTimeline: return "clock.arrow.2.circlepath"
        case .compactList: return "list.bullet"
        }
    }

    private var weeklyDayStrip: some View {
        let cal = Calendar.current
        let dfDay = DateFormatter()
        dfDay.dateFormat = "EE"
        let dfNum = DateFormatter()
        dfNum.dateFormat = "d"
        let all = calService.visibleEvents

        return HStack(spacing: 4) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                let isSelected = idx == selectedDayOffset
                let hasEvents = all.contains { cal.isDate($0.startDate, inSameDayAs: day) }
                Button {
                    selectedDayOffset = idx
                } label: {
                    VStack(spacing: 1.5) {
                        Text(dfDay.string(from: day).prefix(3).uppercased())
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.55))
                        Text(dfNum.string(from: day))
                            .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.85))
                        Circle()
                            .fill(hasEvents ? Color(red: 0.32, green: 0.62, blue: 1.0) : Color.clear)
                            .frame(width: 3.5, height: 3.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.42) : Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resolvedEventColor(for event: NotchCalendarEvent) -> Color {
        if prefs.calendarUseNativeEventColors {
            return event.color.swiftUIColor
        }
        return event.hasMeetingLink
            ? Color(red: 0.16, green: 0.72, blue: 0.42)
            : Color(red: 0.26, green: 0.52, blue: 0.96)
    }

    @ViewBuilder
    private func eventRow(for event: NotchCalendarEvent) -> some View {
        let stripeColor = resolvedEventColor(for: event)
        switch prefs.calendarDisplayFormat {
        case .googleAgenda:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(stripeColor)
                    .frame(width: 3.5, height: 28)

                Button {
                    calService.openCalendar(for: event)
                } label: {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(event.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(event.formattedTimeRange)
                                .font(.system(size: 9.8, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.62))
                            Text("· \(event.countdownLabel(using: loc))")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(event.isOngoingNow ? Color.green : stripeColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if prefs.calendarShowDirectJoinMeetButton && event.hasMeetingLink {
                    joinMeetMiniButton(for: event)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(stripeColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(stripeColor.opacity(0.30), lineWidth: 0.7)
                    )
            )

        case .googleTimeline:
            HStack(spacing: 8) {
                Text(event.formattedStartTime)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(event.isOngoingNow ? Color.green : Color.white.opacity(0.75))
                    .frame(width: 36, alignment: .trailing)

                Circle()
                    .fill(stripeColor)
                    .frame(width: 7, height: 7)

                Button {
                    calService.openCalendar(for: event)
                } label: {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.system(size: 11.3, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(event.countdownLabel(using: loc))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(stripeColor.opacity(0.20))
                    )
                }
                .buttonStyle(.plain)

                if prefs.calendarShowDirectJoinMeetButton && event.hasMeetingLink {
                    joinMeetMiniButton(for: event)
                }
            }

        case .compactList:
            HStack(spacing: 6) {
                Circle()
                    .fill(stripeColor)
                    .frame(width: 6, height: 6)
                Text(event.formattedStartTime)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.68))
                Button {
                    calService.openCalendar(for: event)
                } label: {
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if prefs.calendarShowDirectJoinMeetButton && event.hasMeetingLink {
                    joinMeetMiniButton(for: event)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.05)))
        }
    }

    private func joinMeetMiniButton(for event: NotchCalendarEvent) -> some View {
        let buttonColor = prefs.calendarUseNativeEventColors
            ? event.color.swiftUIColor
            : Color(red: 0.12, green: 0.68, blue: 0.38)
        return Button {
            calService.joinMeeting(for: event)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "video.fill")
                    .font(.system(size: 8.5, weight: .bold))
                Text("Meet")
                    .font(.system(size: 9.5, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(buttonColor))
        }
        .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.92, enableAnimations: prefs.enableAnimations))
        .help(loc.text(es: "Unirse a la reunión en Google Chrome", en: "Join meeting in Google Chrome"))
    }

    private var emptyCalendarBody: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.22))
                Image(systemName: calService.isSyncing ? "arrow.triangle.2.circlepath" : "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.70, blue: 1.0))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    calService.isSyncing
                        ? loc.text(es: "Sincronizando Google Calendar…", en: "Syncing Google Calendar…")
                        : loc.text(es: "Sin eventos próximos", en: "No upcoming events")
                )
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)

                Text(
                    calService.lastSyncStatusMessage ?? loc.text(
                        es: "Hacé clic para abrir tu Google Calendar en Chrome.",
                        en: "Click to open your Google Calendar in Chrome."
                    )
                )
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button {
                calService.openCalendar()
            } label: {
                Text(loc.text(es: "Abrir Chrome", en: "Open Chrome"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.26, green: 0.52, blue: 0.96)))
            }
            .buttonStyle(NotchSpringPressButtonStyle(pressedScale: 0.93, enableAnimations: prefs.enableAnimations))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
