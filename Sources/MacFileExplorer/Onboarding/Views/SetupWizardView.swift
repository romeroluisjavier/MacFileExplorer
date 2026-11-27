import AppKit
import Observation
import SwiftUI

// MARK: - Window Controller del Asistente Inicial

/// Controlador singleton de la ventana nativa del Asistente de instalación inicial de `MacFileExplorer`.
/// Libera el árbol SwiftUI (`contentView = nil`) al cerrarse para mantener 0% de consumo en reposo.
@MainActor
public final class SetupWizardWindowController: NSObject, NSWindowDelegate {
    public static let shared = SetupWizardWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show() {
        let title = localizedWindowTitle()
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.title = title
            existing.contentView = NSHostingView(rootView: SetupWizardView(onboarding: .shared))
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 675),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.delegate = self
        created.title = title
        created.minSize = NSSize(width: 700, height: 590)
        created.titlebarAppearsTransparent = true
        created.titleVisibility = .hidden
        created.isMovableByWindowBackground = true
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.contentView = NSHostingView(rootView: SetupWizardView(onboarding: .shared))
        created.center()
        created.makeKeyAndOrderFront(nil)
        self.window = created
    }

    public func close() {
        window?.close()
    }

    public func refreshLocalizedTitle() {
        window?.title = localizedWindowTitle()
    }

    public func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        if AppOnboardingManager.shared.isWizardPresented {
            AppOnboardingManager.shared.dismissWizardWithoutApplying(markCompleted: true)
        }
    }

    private func localizedWindowTitle() -> String {
        LocalizationManager.shared.text(
            es: "Asistente de configuración · MacFileExplorer",
            en: "Setup Wizard · MacFileExplorer"
        )
    }
}

// MARK: - Vista Determinista de Previsualización por Paso (QA & Capturas)

/// Vista autocontenida de tamaño fijo (`760 × 675 pt`) para renderizar cualquiera de los 6 pasos del asistente
/// de forma determinista y sin modificar las preferencias reales del usuario.
public struct SetupWizardStepPreviewView: View {
    public let step: SetupWizardStep
    public let draft: SetupWizardDraft

    public init(
        step: SetupWizardStep,
        draft: SetupWizardDraft = .recommendedDefaults()
    ) {
        self.step = step
        self.draft = draft
    }

    public var body: some View {
        SetupWizardView(previewStep: step, previewDraft: draft)
            .frame(width: 760, height: 675)
    }
}

// MARK: - Vista Principal del Asistente de Configuración (6 Pasos)

/// Asistente interactivo de instalación inicial (6 pasos guiados + «Instalar por defecto»).
public struct SetupWizardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var iconProvider = FileIconProvider.shared
    @Bindable private var onboarding: AppOnboardingManager

    private let isPreviewMode: Bool

    public init(onboarding: AppOnboardingManager = .shared) {
        self._onboarding = Bindable(onboarding)
        self.isPreviewMode = false
    }

    /// Inicializador determinista para previsualizar o capturar un paso específico sin alterar preferencias persistidas.
    public init(
        previewStep: SetupWizardStep,
        previewDraft: SetupWizardDraft = .recommendedDefaults()
    ) {
        let previewDefaults = UserDefaults(suiteName: "com.macfileexplorer.wizard.preview.\(previewStep.rawValue)") ?? .standard
        let previewManager = AppOnboardingManager(defaults: previewDefaults)
        previewManager.draft = previewDraft
        previewManager.currentWizardStep = previewStep
        previewManager.isWizardPresented = true
        self._onboarding = Bindable(previewManager)
        self.isPreviewMode = true
    }

    private var currentStep: SetupWizardStep {
        onboarding.currentWizardStep
    }

    private var activePreviewIcon: NSImage? {
        iconProvider.previewImage(for: onboarding.draft.selectedAppIcon, colorScheme: colorScheme)
    }

    public var body: some View {
        VStack(spacing: 0) {
            progressHeaderSection
                .padding(.horizontal, 26)
                .padding(.top, 28)
                .padding(.bottom, 14)
                .background(headerBackground)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    stepContentView
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerNavigationBar
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(footerBackground)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 590, idealHeight: 675)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Cabecera con Progreso Amigable y Breadcrumbs (Siempre Visible)

    private var headerBackground: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(colorScheme == .dark ? 0.11 : 0.06),
                Color(nsColor: .windowBackgroundColor).opacity(0.4)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var footerBackground: some View {
        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.55 : 0.72)
    }

    private var progressHeaderSection: some View {
        VStack(spacing: 11) {
            // Fila superior: Identidad de la app + píldora clara de avance
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    if let icon = activePreviewIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("MacFileExplorer")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("v\(AppVersionComparator.displayVersion(AppVersionInfo.currentVersion))")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.065))
                        )
                }

                Spacer(minLength: 8)

                // Píldora amigable: "Paso 2 de 6 · Quedan 4 pasos" / "Paso 6 de 6 · ¡Último paso!"
                HStack(spacing: 6) {
                    Image(systemName: currentStep.isLast ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(currentStep.localizedProgressPill(using: loc))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(currentStep.isLast ? Color.green : Color.accentColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 4.5)
                .background(
                    Capsule(style: .continuous)
                        .fill((currentStep.isLast ? Color.green : Color.accentColor).opacity(colorScheme == .dark ? 0.20 : 0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder((currentStep.isLast ? Color.green : Color.accentColor).opacity(0.28), lineWidth: 0.8)
                )
            }

            // Barra lineal animada de progreso
            GeometryReader { geo in
                let fraction = CGFloat(currentStep.progressFraction)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: currentStep.isLast
                                    ? [Color.accentColor, Color.green]
                                    : [Color.accentColor, Color.accentColor.opacity(0.76)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(18, geo.size.width * fraction))
                        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: currentStep)
                }
            }
            .frame(height: 5)

            // Breadcrumbs interactivos de los 6 pasos
            HStack(spacing: 0) {
                ForEach(SetupWizardStep.allCases) { step in
                    let isCompleted = step.rawValue < currentStep.rawValue
                    let isCurrent = step == currentStep

                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            onboarding.goToWizardStep(step)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(stepCircleFill(isCompleted: isCompleted, isCurrent: isCurrent))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                isCurrent ? Color.accentColor.opacity(0.35) : Color.clear,
                                                lineWidth: 2.5
                                            )
                                            .frame(width: 30, height: 30)
                                    )

                                Image(systemName: isCompleted ? "checkmark" : step.symbolName)
                                    .font(.system(size: isCompleted ? 10.5 : 10, weight: .bold))
                                    .foregroundStyle(
                                        (isCompleted || isCurrent) ? Color.white : Color.secondary
                                    )
                            }

                            Text(step.localizedShortTitle(using: loc))
                                .font(.system(size: 10.5, weight: isCurrent ? .semibold : .medium))
                                .foregroundStyle(isCurrent ? Color.primary : (isCompleted ? Color.accentColor : Color.secondary))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !step.isLast {
                        Rectangle()
                            .fill(
                                step.rawValue < currentStep.rawValue
                                    ? Color.green.opacity(0.55)
                                    : Color.primary.opacity(0.10)
                            )
                            .frame(height: 1.5)
                            .frame(maxWidth: 22)
                            .padding(.bottom, 16)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func stepCircleFill(isCompleted: Bool, isCurrent: Bool) -> Color {
        if isCompleted {
            return .green
        }
        if isCurrent {
            return .accentColor
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08)
    }

    // MARK: - Enrutador de Pasos

    @ViewBuilder
    private var stepContentView: some View {
        switch currentStep {
        case .welcome:
            welcomeStepContent
        case .taskbar:
            taskbarStepContent
        case .altTab:
            altTabStepContent
        case .notch:
            notchStepContent
        case .productivity:
            productivityStepContent
        case .summary:
            summaryStepContent
        }
    }

    // MARK: - Paso 1: Bienvenida, Idioma e Ícono

    private var welcomeStepContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            // Tarjeta principal de bienvenida
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                    Color.purple.opacity(colorScheme == .dark ? 0.16 : 0.07)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 74, height: 74)

                    if let icon = activePreviewIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 58, height: 58)
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(SetupWizardStep.welcome.localizedTitle(using: loc))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(SetupWizardStep.welcome.localizedSubtitle(using: loc))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.9)
            )

            // Tarjeta destacada: Inicio rápido con configuración por defecto
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(
                        es: "¿Preferís empezar ahora mismo sin configurar paso a paso?",
                        en: "Want to jump right in without step-by-step setup?"
                    ))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text(loc.text(
                        es: "Mantiene Explorador, Portapapeles y Editor Office listos; Barra de tareas, AltTab y Notch quedan apagados hasta que los actives.",
                        en: "Keeps Explorer, Clipboard & Office Editor ready; Taskbar, AltTab & Notch stay off until you turn them on."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    triggerInstallByDefault()
                } label: {
                    Text(loc.text(es: "Instalar por defecto", en: "Install by Default"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
            )

            // Selector instantáneo de idioma ES / EN
            wizardCard {
                HStack(spacing: 12) {
                    iconBadge(systemName: "globe", tint: .blue, size: 30)

                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(loc.text(es: "Idioma de MacFileExplorer", en: "Interface Language"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(loc.text(
                            es: "Cambia todos los menús y ventanas al instante.",
                            en: "Switches all menus and windows immediately."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        languagePillButton(.system, label: loc.text(es: "Auto", en: "Auto"))
                        languagePillButton(.spanish, label: "Español")
                        languagePillButton(.english, label: "English")
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055))
                    )
                }
            }

            // Selector visual de los 5 íconos de la aplicación
            wizardCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(loc.text(
                            es: "Elegí el ícono de la app (Dock, ⌘+Tab y ventanas)",
                            en: "Choose your app icon (Dock, ⌘+Tab & windows)"
                        ))
                        .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text(onboarding.draft.selectedAppIcon.localizedTitle(using: loc))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    HStack(spacing: 8) {
                        ForEach(MacFileExplorerAppIcon.allCases) { option in
                            let isSelected = onboarding.draft.selectedAppIcon == option
                            Button {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                    onboarding.draft.selectedAppIcon = option
                                    if !isPreviewMode {
                                        iconProvider.selectedAppIcon = option
                                    }
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.94))
                                            .frame(width: 50, height: 50)

                                        if let img = iconProvider.previewImage(for: option, colorScheme: colorScheme) {
                                            Image(nsImage: img)
                                                .resizable()
                                                .interpolation(.high)
                                                .scaledToFit()
                                                .frame(width: 42, height: 42)
                                        }
                                    }

                                    Text(option.localizedTitle(using: loc))
                                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.03))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                            lineWidth: isSelected ? 1.5 : 0.75
                                        )
                                )
                                .overlay(alignment: .topTrailing) {
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func languagePillButton(_ option: AppLanguagePreference, label: String) -> some View {
        let isSelected = onboarding.draft.languagePreference == option
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                onboarding.draft.languagePreference = option
                if !isPreviewMode {
                    loc.preference = option
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Paso 2: Barra de Tareas y Menú Inicio

    private var taskbarStepContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            stepHeroHeader(step: .taskbar, tint: .blue)

            // Ilustración en vivo de la Barra de tareas (Isla Flotante vs Acoplada al borde)
            taskbarMiniPreviewIllustration

            wizardCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: "Activar Barra de tareas y Menú Inicio", en: "Enable Taskbar & Start Menu"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(loc.text(
                                es: "Muestra tus ventanas abiertas en el borde inferior con vistas previas al pasar el mouse.",
                                en: "Shows open windows along the bottom edge with live hover previews and a Start Menu."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("", isOn: Binding(
                            get: { onboarding.draft.enableTaskbar },
                            set: { enabled in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    onboarding.draft.enableTaskbar = enabled
                                    if enabled {
                                        onboarding.draft.taskbarStartOnLaunch = true
                                    } else {
                                        onboarding.draft.taskbarStartOnLaunch = false
                                        onboarding.draft.hideMacOSDock = false
                                    }
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(WizardSwitchToggleStyle())
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(loc.text(es: "Iniciar automáticamente al abrir MacFileExplorer", en: "Start automatically when launching MacFileExplorer"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Si preferís encenderla solo cuando quieras, dejá esta opción desactivada.",
                                en: "Leave this off if you prefer turning it on manually from the top Taskbar menu."
                            ))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("", isOn: $onboarding.draft.taskbarStartOnLaunch)
                            .labelsHidden()
                            .toggleStyle(WizardSwitchToggleStyle())
                            .disabled(!onboarding.draft.enableTaskbar)
                    }
                    .opacity(onboarding.draft.enableTaskbar ? 1 : 0.5)

                    Divider()

                    // Estilo visual: Acoplada al borde vs Isla flotante
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.text(es: "Estilo de la barra", en: "Taskbar Style"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            taskbarStyleOptionCard(
                                style: .docked,
                                title: loc.text(es: "Acoplada al borde", en: "Edge-to-Edge"),
                                subtitle: loc.text(es: "Clásica de extremo a extremo", en: "Classic full-width bottom bar"),
                                icon: "dock.rectangle"
                            )
                            taskbarStyleOptionCard(
                                style: .floatingIsland,
                                title: loc.text(es: "Isla flotante", en: "Floating Island"),
                                subtitle: loc.text(es: "Píldora moderna redondeada", en: "Modern floating rounded pill"),
                                icon: "capsule.inset.filled"
                            )
                        }
                    }
                    .opacity(onboarding.draft.enableTaskbar ? 1 : 0.65)

                    Divider()

                    // Opción opcional para ocultar el Dock + nota tranquilizadora
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 12) {
                            Text(loc.text(
                                es: "Ocultar el Dock de macOS mientras la barra está activa (opcional)",
                                en: "Hide the macOS Dock while Taskbar is active (optional)"
                            ))
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Toggle("", isOn: $onboarding.draft.hideMacOSDock)
                                .labelsHidden()
                                .toggleStyle(WizardSwitchToggleStyle())
                                .disabled(!onboarding.draft.enableTaskbar)
                        }
                        .opacity(onboarding.draft.enableTaskbar ? 1 : 0.5)

                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                            Text(loc.text(
                                es: "Tu Dock original de macOS permanece 100% intacto salvo que actives esta opción, y siempre podés restaurarlo en 1 clic.",
                                en: "Your original macOS Dock stays 100% untouched unless you turn this on, and can always be restored in 1 click."
                            ))
                            .font(.system(size: 10.8))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.green.opacity(colorScheme == .dark ? 0.13 : 0.08))
                        )
                    }
                }
            }
        }
    }

    private func taskbarStyleOptionCard(
        style: TaskbarBarStyle,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        let isSelected = onboarding.draft.taskbarBarStyle == style
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                onboarding.draft.taskbarBarStyle = style
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.4 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var taskbarMiniPreviewIllustration: some View {
        let isFloating = onboarding.draft.taskbarBarStyle == .floatingIsland
        let isEnabled = onboarding.draft.enableTaskbar

        return ZStack(alignment: .bottom) {
            // Fondo de escritorio estilizado
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.10, green: 0.14, blue: 0.25), Color(red: 0.18, green: 0.15, blue: 0.30)]
                            : [Color(red: 0.84, green: 0.90, blue: 0.98), Color(red: 0.90, green: 0.87, blue: 0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Mini ventanas de escritorio en el fondo
            HStack(spacing: 14) {
                miniDesktopWindowCard(accent: .blue, width: 130, height: 30)
                miniDesktopWindowCard(accent: .purple, width: 112, height: 26)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 37)
            .opacity(isEnabled ? 0.92 : 0.55)

            // Mini barra inferior (Isla flotante vs Acoplada)
            HStack(spacing: 8) {
                // Botón Inicio
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )

                // Botón activo con indicador inferior
                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.blue)
                        Text("MacFileExplorer")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09))
                    )
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 2)
                }

                // Otras ventanas en la barra
                miniTaskbarChip(icon: "globe", tint: .teal, label: "Chrome")
                miniTaskbarChip(icon: "doc.text.fill", tint: .orange, label: loc.text(es: "Notas", en: "Notes"))

                if !isFloating {
                    Spacer(minLength: 4)
                }

                // Mini reloj derecho
                Text("10:24")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, isFloating ? 8 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: isFloating ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: isFloating ? 11 : 0, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isFloating ? 11 : 0, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.45), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(isFloating ? 0.18 : 0.06), radius: isFloating ? 8 : 2, y: 2)
            .padding(.horizontal, isFloating ? 26 : 0)
            .padding(.bottom, isFloating ? 8 : 0)
            .opacity(isEnabled ? 1.0 : 0.48)
        }
        .frame(height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.9)
        )
        .overlay(alignment: .topTrailing) {
            previewStatusBadge(isEnabled: isEnabled)
                .padding(8)
        }
    }

    private func miniDesktopWindowCard(accent: Color, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Circle().fill(Color.red.opacity(0.75)).frame(width: 4.5, height: 4.5)
                Circle().fill(Color.yellow.opacity(0.75)).frame(width: 4.5, height: 4.5)
                Circle().fill(Color.green.opacity(0.75)).frame(width: 4.5, height: 4.5)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(0.28))
                .frame(width: width * 0.52, height: 4)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.10))
                .frame(width: width * 0.72, height: 3.5)
        }
        .padding(6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
        )
    }

    private func miniTaskbarChip(icon: String, tint: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
        )
    }

    // MARK: - Paso 3: Selector de Ventanas AltTab

    private var altTabStepContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeroHeader(step: .altTab, tint: .indigo)

            // Ilustración en vivo del selector AltTab según el estilo elegido
            altTabMiniPreviewIllustration

            wizardCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(loc.text(es: "Activar selector AltTab", en: "Enable AltTab Switcher"))
                                    .font(.system(size: 13, weight: .semibold))
                                shortcutKeyChip("⌥ + Tab")
                            }
                            Text(loc.text(
                                es: "Muestra cada ventana individual con vista previa y filtro rápido al presionar ⌥+Tab.",
                                en: "Shows every individual window with live preview and instant search when pressing ⌥+Tab."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("", isOn: Binding(
                            get: { onboarding.draft.enableAltTab },
                            set: { enabled in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    onboarding.draft.enableAltTab = enabled
                                    onboarding.draft.altTabStartOnLaunch = enabled
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(WizardSwitchToggleStyle())
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(loc.text(es: "Iniciar automáticamente al abrir MacFileExplorer", en: "Start automatically when launching MacFileExplorer"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Listo para usar con ⌥+Tab desde que iniciás la app.",
                                en: "Ready whenever you press ⌥+Tab right after opening the app."
                            ))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("", isOn: $onboarding.draft.altTabStartOnLaunch)
                            .labelsHidden()
                            .toggleStyle(WizardSwitchToggleStyle())
                            .disabled(!onboarding.draft.enableAltTab)
                    }
                    .opacity(onboarding.draft.enableAltTab ? 1 : 0.5)

                    Divider()

                    // Selector de estilo de visualización (Miniaturas / Íconos / Lista compacta)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(loc.text(es: "Estilo de visualización del selector", en: "Switcher Display Style"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 9) {
                            altTabStyleCard(
                                style: .thumbnails,
                                title: loc.text(es: "Miniaturas", en: "Thumbnails"),
                                subtitle: loc.text(es: "Vista previa visual", en: "Visual window cards")
                            )
                            altTabStyleCard(
                                style: .appIcons,
                                title: loc.text(es: "Íconos de app", en: "App Icons"),
                                subtitle: loc.text(es: "Cuadrícula limpia", en: "Clean icon grid")
                            )
                            altTabStyleCard(
                                style: .titlesList,
                                title: loc.text(es: "Lista compacta", en: "Compact List"),
                                subtitle: loc.text(es: "Títulos en filas", en: "Compact title rows")
                            )
                        }
                    }
                    .opacity(onboarding.draft.enableAltTab ? 1 : 0.65)
                }
            }
        }
    }

    private func altTabStyleCard(style: AltTabDisplayStyle, title: String, subtitle: String) -> some View {
        let isSelected = onboarding.draft.altTabDisplayStyle == style
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                onboarding.draft.altTabDisplayStyle = style
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: style.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.4 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var altTabMiniPreviewIllustration: some View {
        let isEnabled = onboarding.draft.enableAltTab
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.12, green: 0.11, blue: 0.24), Color(red: 0.09, green: 0.15, blue: 0.24)]
                            : [Color(red: 0.88, green: 0.89, blue: 0.98), Color(red: 0.84, green: 0.92, blue: 0.97)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Panel HUD flotante estilo AltTab
            Group {
                switch onboarding.draft.altTabDisplayStyle {
                case .thumbnails:
                    HStack(spacing: 10) {
                        altTabThumbSample(icon: "folder.fill", tint: .blue, title: loc.text(es: "Proyectos", en: "Projects"), selected: false)
                        altTabThumbSample(icon: "globe", tint: .teal, title: "Docs · Chrome", selected: true)
                        altTabThumbSample(icon: "doc.text.fill", tint: .orange, title: loc.text(es: "Notas.md", en: "Notes.md"), selected: false)
                    }
                case .appIcons:
                    HStack(spacing: 12) {
                        altTabIconSample(icon: "folder.fill", tint: .blue, label: "Explorer", selected: false)
                        altTabIconSample(icon: "globe", tint: .teal, label: "Chrome", selected: true)
                        altTabIconSample(icon: "doc.text.fill", tint: .orange, label: loc.text(es: "Notas", en: "Notes"), selected: false)
                        altTabIconSample(icon: "terminal.fill", tint: .purple, label: "Terminal", selected: false)
                    }
                case .titlesList:
                    VStack(spacing: 4) {
                        altTabListSample(icon: "folder.fill", tint: .blue, title: loc.text(es: "MacFileExplorer — Descargas", en: "MacFileExplorer — Downloads"), selected: false)
                        altTabListSample(icon: "globe", tint: .teal, title: loc.text(es: "Google Chrome — Presentación Q4", en: "Google Chrome — Q4 Deck"), selected: true)
                        altTabListSample(icon: "doc.text.fill", tint: .orange, title: loc.text(es: "Notas — Ideas de producto", en: "Notes — Product Ideas"), selected: false)
                    }
                    .frame(width: 310)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThickMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.55), lineWidth: 0.9)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .frame(height: 102)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.9)
        )
        .overlay(alignment: .topLeading) {
            shortcutKeyChip("⌥ Tab")
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            previewStatusBadge(isEnabled: isEnabled)
                .padding(8)
        }
    }

    private func altTabThumbSample(icon: String, tint: Color, title: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.25 : 0.16))
                .frame(width: 96, height: 34)
                .overlay(
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.22)).frame(width: 54, height: 3)
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.14)).frame(width: 72, height: 3)
                    }
                    .padding(6),
                    alignment: .topLeading
                )
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.8 : 0.7)
        )
    }

    private func altTabIconSample(icon: String, tint: Color, label: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.20))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.system(size: 9, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    private func altTabListSample(icon: String, tint: Color, title: String, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? Color.white : tint)
            Text(title)
                .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : .primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor : Color.primary.opacity(0.04))
        )
    }

    // MARK: - Paso 4: Reproductor Musical Notch

    private var notchStepContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeroHeader(step: .notch, tint: Color(red: 0.96, green: 0.24, blue: 0.44))

            // Ilustración del Notch con carátula, resplandor y ecualizador
            notchMiniPreviewIllustration

            wizardCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(
                                es: "Activar reproductor Notch (YouTube Music, Spotify y Apple Music)",
                                en: "Enable Notch Music Player (YouTube Music, Spotify & Apple Music)"
                            ))
                            .font(.system(size: 13, weight: .semibold))
                            Text(loc.text(
                                es: "Aparece suavemente arriba de la pantalla sin robar el foco mientras escuchás música.",
                                en: "Rests neatly at the top edge of your screen without stealing window focus while music plays."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("", isOn: Binding(
                            get: { onboarding.draft.enableNotch },
                            set: { enabled in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    onboarding.draft.enableNotch = enabled
                                    onboarding.draft.notchStartOnLaunch = enabled
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(WizardSwitchToggleStyle())
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(loc.text(es: "Iniciar automáticamente al abrir MacFileExplorer", en: "Start automatically when launching MacFileExplorer"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(
                                es: "Se mantiene oculto si no hay música sonando y nunca abre apps cerradas.",
                                en: "Stays discreet when idle and never auto-launches closed music apps."
                            ))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("", isOn: $onboarding.draft.notchStartOnLaunch)
                            .labelsHidden()
                            .toggleStyle(WizardSwitchToggleStyle())
                            .disabled(!onboarding.draft.enableNotch)
                    }
                    .opacity(onboarding.draft.enableNotch ? 1 : 0.5)

                    Divider()

                    // Selector de tamaño de la píldora (Compacto / Normal / Amplio)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(loc.text(es: "Tamaño de la píldora Notch", en: "Notch Pill Size"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 9) {
                            ForEach(NotchPillSize.allCases) { size in
                                notchSizeOptionCard(size: size)
                            }
                        }
                    }
                    .opacity(onboarding.draft.enableNotch ? 1 : 0.65)
                }
            }
        }
    }

    private func notchSizeOptionCard(size: NotchPillSize) -> some View {
        let isSelected = onboarding.draft.notchPillSize == size
        let subtitle: String = {
            switch size {
            case .compact: return loc.text(es: "Discreto y minimalista", en: "Discreet & minimal")
            case .normal: return loc.text(es: "Equilibrio recomendado", en: "Recommended balance")
            case .spacious: return loc.text(es: "Más espacio y letras", en: "Roomier pill & lyrics")
            }
        }()

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                onboarding.draft.notchPillSize = size
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: size.symbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(size.localizedTitle(using: loc))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.4 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var notchMiniPreviewIllustration: some View {
        let isEnabled = onboarding.draft.enableNotch
        let pillWidth: CGFloat = {
            switch onboarding.draft.notchPillSize {
            case .compact: return 226
            case .normal: return 268
            case .spacious: return 316
            }
        }()

        return ZStack(alignment: .top) {
            // Fondo oscuro/luminoso simulando la parte superior de una pantalla Mac
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.11, green: 0.08, blue: 0.19), Color(red: 0.08, green: 0.12, blue: 0.22)]
                            : [Color(red: 0.92, green: 0.88, blue: 0.98), Color(red: 0.85, green: 0.91, blue: 0.99)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Brillo ambiental radial suave detrás de la píldora (sin bordes duros en capturas)
            Rectangle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color(red: 0.98, green: 0.22, blue: 0.46).opacity(isEnabled ? 0.36 : 0.12), location: 0.0),
                            .init(color: Color(red: 0.68, green: 0.22, blue: 0.88).opacity(isEnabled ? 0.16 : 0.05), location: 0.45),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.12),
                        startRadius: 10,
                        endRadius: pillWidth * 0.68
                    )
                )
                .allowsHitTesting(false)

            // Barra de menús simulada en los costados
            HStack {
                HStack(spacing: 8) {
                    Text("MacFileExplorer").fontWeight(.semibold)
                    Text(loc.text(es: "Archivo", en: "File"))
                    Text(loc.text(es: "Ver", en: "View"))
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("10:24").monospacedDigit()
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 7)

            // Píldora negra del Notch acoplada al borde superior
            HStack(spacing: 10) {
                // Carátula circular con anillo de progreso
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 2)
                        .frame(width: 28, height: 28)
                    Circle()
                        .trim(from: 0, to: 0.68)
                        .stroke(Color(red: 1.0, green: 0.34, blue: 0.50), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 28, height: 28)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.24, blue: 0.46), Color(red: 0.42, green: 0.24, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 21, height: 21)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Midnight City")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("M83 · YouTube Music")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.66))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Mini ecualizador
                HStack(alignment: .bottom, spacing: 2.5) {
                    ForEach([0.45, 0.92, 0.65, 1.0, 0.52], id: \.self) { level in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.40, blue: 0.58), Color(red: 0.52, green: 0.64, blue: 1.0)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 2.6, height: CGFloat(14 * level))
                    }
                }
                .frame(height: 15, alignment: .bottom)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: pillWidth)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
            .opacity(isEnabled ? 1.0 : 0.55)

            // Etiquetas de fuentes compatibles en la parte inferior de la tarjeta
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    sourcePill(name: "YouTube Music", color: Color(red: 0.99, green: 0.14, blue: 0.24), icon: "play.circle.fill")
                    sourcePill(name: "Spotify", color: Color(red: 0.11, green: 0.73, blue: 0.33), icon: "dot.radiowaves.left.and.right")
                    sourcePill(name: "Apple Music", color: Color(red: 0.98, green: 0.18, blue: 0.33), icon: "music.note")
                }
                .padding(.bottom, 10)
            }
        }
        .frame(height: 102)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.9)
        )
        .overlay(alignment: .bottomTrailing) {
            previewStatusBadge(isEnabled: isEnabled)
                .padding(8)
        }
    }

    private func sourcePill(name: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(color)
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
        )
    }

    // MARK: - Paso 5: Productividad, Herramientas y Tour

    private var productivityStepContent: some View {
        let gridColumns = [
            GridItem(.flexible(), spacing: 11),
            GridItem(.flexible(), spacing: 11)
        ]

        return VStack(alignment: .leading, spacing: 13) {
            stepHeroHeader(step: .productivity, tint: .orange)

            LazyVGrid(columns: gridColumns, spacing: 11) {
                productivityToggleCard(
                    icon: "doc.on.clipboard.fill",
                    tint: .purple,
                    title: loc.text(es: "Historial del Portapapeles", en: "Clipboard History"),
                    shortcut: "⌃⌘V",
                    description: loc.text(
                        es: "Guarda tus últimos textos, enlaces e imágenes para volver a pegarlos al instante.",
                        en: "Keeps your recently copied text, links, and images ready to paste anytime."
                    ),
                    isOn: $onboarding.draft.enableClipboardHistory
                )

                productivityToggleCard(
                    icon: "menubar.arrow.up.rectangle",
                    tint: .teal,
                    title: loc.text(es: "Ícono en barra superior", en: "Menu Bar Tray Icon"),
                    shortcut: nil,
                    description: loc.text(
                        es: "Acceso en 1 clic junto al reloj de macOS para abrir ventanas, Portapapeles y herramientas.",
                        en: "One-click menu bar access next to your clock for Explorer, Clipboard, and tools."
                    ),
                    isOn: $onboarding.draft.enableTrayIcon
                )

                productivityToggleCard(
                    icon: "macwindow.on.rectangle",
                    tint: .indigo,
                    title: loc.text(es: "Atajo Ver Escritorio", en: "View Desktop Shortcut"),
                    shortcut: "⌘D",
                    description: loc.text(
                        es: "Mostrá tu Escritorio de inmediato al estilo Windows (Win+D) con un solo atajo.",
                        en: "Reveal your Desktop immediately Windows-style (Win+D) with one keyboard shortcut."
                    ),
                    isOn: $onboarding.draft.enableViewDesktopShortcut
                )

                productivityToggleCard(
                    icon: "doc.richtext.fill",
                    tint: .orange,
                    title: loc.text(es: "Editor Office y CSV en Vista Rápida", en: "Quick Look Office & CSV Editor"),
                    shortcut: loc.text(es: "Espacio", en: "Space"),
                    description: loc.text(
                        es: "Editá documentos Word, Excel, PowerPoint y planillas CSV directamente con la barra espaciadora.",
                        en: "Edit Word, Excel, PowerPoint documents, and CSV sheets right inside Spacebar preview."
                    ),
                    isOn: $onboarding.draft.enableOfficeQuickLookEditor
                )
            }

            // Tarjeta destacada: Iniciar tour interactivo al terminar
            HStack(alignment: .center, spacing: 12) {
                iconBadge(systemName: "map.fill", tint: .accentColor, size: 36)

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(loc.text(
                        es: "Iniciar tour interactivo al terminar",
                        en: "Start interactive guided tour after setup"
                    ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text(loc.text(
                        es: "7 globitos breves sobre la ventana principal explicando las herramientas clave. Podés suspenderlo en cualquier momento con un clic o presionando Esc.",
                        en: "7 brief callout bubbles over the main window showing key tools. You can stop or suspend it anytime with one click or by pressing Esc."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $onboarding.draft.startTourAfterSetup)
                    .labelsHidden()
                    .toggleStyle(WizardSwitchToggleStyle())
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 1)
            )
        }
    }

    private func productivityToggleCard(
        icon: String,
        tint: Color,
        title: String,
        shortcut: String?,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 9) {
                iconBadge(systemName: icon, tint: tint, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.2, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    if let shortcut {
                        shortcutKeyChip(shortcut)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(WizardSwitchToggleStyle())
                    .controlSize(.small)
            }

            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isOn.wrappedValue ? tint.opacity(colorScheme == .dark ? 0.11 : 0.055) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isOn.wrappedValue ? tint.opacity(0.35) : Color.primary.opacity(0.08),
                    lineWidth: isOn.wrappedValue ? 1.1 : 0.8
                )
        )
    }

    // MARK: - Paso 6: Resumen y Listo

    private var summaryStepContent: some View {
        let draft = onboarding.draft
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 13) {
            stepHeroHeader(step: .summary, tint: .green)

            LazyVGrid(columns: columns, spacing: 10) {
                summaryRecapCard(
                    icon: "globe",
                    tint: .blue,
                    title: loc.text(es: "Idioma e Ícono", en: "Language & Icon"),
                    detail: "\(loc.displayName(for: draft.languagePreference)) · \(draft.selectedAppIcon.localizedTitle(using: loc))",
                    isActive: true,
                    activeLabel: loc.text(es: "Configurado", en: "Ready"),
                    targetStep: .welcome
                )

                summaryRecapCard(
                    icon: "dock.rectangle",
                    tint: .blue,
                    title: loc.text(es: "Barra de tareas", en: "Taskbar & Start Menu"),
                    detail: draft.enableTaskbar
                        ? "\(draft.taskbarBarStyle.localizedTitle(using: loc)) · \(draft.hideMacOSDock ? loc.text(es: "Dock oculto", en: "Dock hidden") : loc.text(es: "Dock intacto", en: "Dock untouched"))"
                        : loc.text(es: "Apagada · tu Dock original queda intacto", en: "Off · original macOS Dock untouched"),
                    isActive: draft.enableTaskbar,
                    targetStep: .taskbar
                )

                summaryRecapCard(
                    icon: "rectangle.stack.fill",
                    tint: .indigo,
                    title: "AltTab (⌥+Tab)",
                    detail: draft.enableAltTab
                        ? "\(draft.altTabDisplayStyle.localizedTitle(using: loc))\(draft.altTabStartOnLaunch ? loc.text(es: " · Al iniciar", en: " · Auto-start") : "")"
                        : loc.text(es: "Desactivado (podés activarlo luego)", en: "Off (enable anytime from menu)"),
                    isActive: draft.enableAltTab,
                    targetStep: .altTab
                )

                summaryRecapCard(
                    icon: "waveform",
                    tint: Color(red: 0.96, green: 0.24, blue: 0.44),
                    title: loc.text(es: "Reproductor Notch", en: "Notch Music Player"),
                    detail: draft.enableNotch
                        ? "\(loc.text(es: "Tamaño", en: "Size")): \(draft.notchPillSize.localizedTitle(using: loc))\(draft.notchStartOnLaunch ? loc.text(es: " · Al iniciar", en: " · Auto-start") : "")"
                        : loc.text(es: "Desactivado (YouTube Music / Spotify / Apple)", en: "Off (YouTube Music / Spotify / Apple)"),
                    isActive: draft.enableNotch,
                    targetStep: .notch
                )

                summaryRecapCard(
                    icon: "wrench.and.screwdriver.fill",
                    tint: .orange,
                    title: loc.text(es: "Productividad y Herramientas", en: "Productivity & Tools"),
                    detail: productivitySummaryText(for: draft),
                    isActive: draft.enableClipboardHistory || draft.enableTrayIcon || draft.enableViewDesktopShortcut || draft.enableOfficeQuickLookEditor,
                    targetStep: .productivity
                )

                summaryRecapCard(
                    icon: "map.fill",
                    tint: .accentColor,
                    title: loc.text(es: "Tour interactivo", en: "Interactive Tour"),
                    detail: draft.startTourAfterSetup
                        ? loc.text(es: "Se iniciará al finalizar (7 pasos · podés suspenderlo)", en: "Starts after finish (7 stops · stop anytime)")
                        : loc.text(es: "Omitido (siempre disponible en Ayuda)", en: "Skipped (always available under Help)"),
                    isActive: draft.startTourAfterSetup,
                    targetStep: .productivity
                )
            }

            // Nota de privacidad y mínimos permisos
            HStack(alignment: .top, spacing: 11) {
                iconBadge(systemName: "checkmark.shield.fill", tint: .green, size: 32)

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(loc.text(
                        es: "Privacidad total y permisos bajo demanda",
                        en: "Full privacy & least-privilege permissions"
                    ))
                    .font(.system(size: 12.2, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text(loc.text(
                        es: "Todo corre localmente en tu Mac. MacFileExplorer nunca pide permisos que no necesites: solo solicitará Accesibilidad o Grabación de pantalla si usás una función que los requiera, y podés encender o apagar cada módulo cuando quieras desde los menús superiores.",
                        en: "Everything runs locally on your Mac. MacFileExplorer never asks for permissions you don't need—it only requests Accessibility or Screen Recording if you use a feature that requires them, and every module can be toggled anytime from the top menu bar."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.green.opacity(colorScheme == .dark ? 0.12 : 0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.28), lineWidth: 0.9)
            )
        }
    }

    private func productivitySummaryText(for draft: SetupWizardDraft) -> String {
        var enabled: [String] = []
        if draft.enableClipboardHistory {
            enabled.append(loc.text(es: "Portapapeles", en: "Clipboard"))
        }
        if draft.enableTrayIcon {
            enabled.append(loc.text(es: "Barra superior", en: "Tray Icon"))
        }
        if draft.enableViewDesktopShortcut {
            enabled.append("⌘D")
        }
        if draft.enableOfficeQuickLookEditor {
            enabled.append("Office/CSV")
        }
        if enabled.isEmpty {
            return loc.text(es: "Todas desactivadas por ahora", en: "All turned off for now")
        }
        return enabled.joined(separator: " · ")
    }

    private func summaryRecapCard(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        isActive: Bool,
        activeLabel: String? = nil,
        targetStep: SetupWizardStep
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                onboarding.goToWizardStep(targetStep)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    iconBadge(systemName: icon, tint: isActive ? tint : .secondary, size: 26)

                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(
                        isActive
                            ? (activeLabel ?? loc.text(es: "Activo", en: "Active"))
                            : loc.text(es: "Apagado", en: "Off")
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isActive ? Color.green.opacity(0.15) : Color.primary.opacity(0.07))
                    )
                }

                HStack(alignment: .bottom, spacing: 6) {
                    Text(detail)
                        .font(.system(size: 10.8))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(loc.text(es: "Editar", en: "Edit"))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.green.opacity(0.26) : Color.primary.opacity(0.08),
                        lineWidth: 0.9
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pie de Navegación Persistente

    private var footerNavigationBar: some View {
        HStack(spacing: 10) {
            // Botón siempre visible para omitir y aplicar valores por defecto seguros
            Button {
                triggerInstallByDefault()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(loc.text(
                        es: "Instalar por defecto (omitir asistente)",
                        en: "Install by Default (skip Wizard)"
                    ))
                    .font(.system(size: 11.8, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer(minLength: 10)

            if !currentStep.isFirst {
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        onboarding.previousWizardStep()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(loc.text(es: "Atrás", en: "Back"))
                            .font(.system(size: 12.2, weight: .medium))
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            if currentStep.isLast {
                Button {
                    guard !isPreviewMode else { return }
                    onboarding.completeWizardApplyingDraft()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(loc.text(es: "Finalizar y empezar", en: "Finish & Launch"))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        onboarding.nextWizardStep()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(loc.text(es: "Siguiente", en: "Next"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func triggerInstallByDefault() {
        guard !isPreviewMode else { return }
        onboarding.installByDefaultAndSkipWizard()
    }

    // MARK: - Componentes Visuales Reutilizables

    private func stepHeroHeader(step: SetupWizardStep, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 13) {
            iconBadge(systemName: step.symbolName, tint: tint, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.localizedTitle(using: loc))
                    .font(.system(size: 17.5, weight: .bold))
                    .foregroundStyle(.primary)

                Text(step.localizedSubtitle(using: loc))
                    .font(.system(size: 11.8))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wizardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.085), lineWidth: 0.85)
        )
    }

    private func iconBadge(systemName: String, tint: Color, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.22 : 0.13))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func shortcutKeyChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
            )
    }

    private func previewStatusBadge(isEnabled: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isEnabled ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(isEnabled ? loc.text(es: "Activo", en: "Enabled") : loc.text(es: "Desactivado", en: "Off"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
        )
    }
}

// MARK: - Estilo Nativo Consistente de Interruptor (Visible en Ventanas Activas e Inactivas)

/// Estilo de interruptor tipo macOS (`38 × 22 pt`) que conserva su color de acento azul al estar activo
/// incluso cuando la ventana pierde foco o se renderiza en capturas/previsualizaciones.
public struct WizardSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        return HStack(spacing: 0) {
            configuration.label
            Button {
                guard isEnabled else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.primary.opacity(0.16))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    isOn ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08),
                                    lineWidth: 0.7
                                )
                        )
                        .frame(width: 38, height: 22)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.22), radius: 1.8, y: 0.8)
                        .offset(x: isOn ? 8 : -8)
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isOn)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAction {
                guard isEnabled else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}
