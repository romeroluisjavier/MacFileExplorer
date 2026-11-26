import AppKit
import SwiftUI

/// Constantes, URLs y colores oficiales de Ko-fi para MacFileExplorer.
public enum KoFiSupportConstants {
    public static let pageURL = URL(string: "https://ko-fi.com/luisjavierromero")!
    public static let widgetID = "S5U62BAGY7"
    public static let qrResourceName = "KoFi-QR"

    /// Rojo coral vibrante característico del botón de Ko-fi (`#F57373` -> `#D9534F`).
    public static let coralTop = Color(red: 0.961, green: 0.451, blue: 0.451)
    public static let coralBottom = Color(red: 0.851, green: 0.325, blue: 0.310)
    public static let badgeTint = Color(red: 0.851, green: 0.325, blue: 0.310)

    @MainActor
    public static func openKoFiPage() {
        NSWorkspace.shared.open(pageURL)
    }
}

/// Ícono vectorial nítido estilo taza Ko-fi con corazón interior.
public struct KoFiCupIconView: View {
    public var size: CGFloat = 16
    public var cupColor: Color = .white
    public var heartColor: Color = Color(red: 0.96, green: 0.36, blue: 0.24)

    public init(
        size: CGFloat = 16,
        cupColor: Color = .white,
        heartColor: Color = Color(red: 0.96, green: 0.36, blue: 0.24)
    ) {
        self.size = size
        self.cupColor = cupColor
        self.heartColor = heartColor
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Cuerpo principal de la taza Ko-fi
            let bodyRect = CGRect(x: w * 0.08, y: h * 0.22, width: w * 0.64, height: h * 0.60)
            var cupPath = Path()
            cupPath.move(to: CGPoint(x: bodyRect.minX + bodyRect.width * 0.08, y: bodyRect.minY))
            cupPath.addLine(to: CGPoint(x: bodyRect.maxX - bodyRect.width * 0.04, y: bodyRect.minY))
            cupPath.addQuadCurve(
                to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + bodyRect.height * 0.14),
                control: CGPoint(x: bodyRect.maxX, y: bodyRect.minY)
            )
            cupPath.addLine(to: CGPoint(x: bodyRect.maxX - bodyRect.width * 0.05, y: bodyRect.maxY - bodyRect.height * 0.24))
            cupPath.addQuadCurve(
                to: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
                control: CGPoint(x: bodyRect.maxX - bodyRect.width * 0.14, y: bodyRect.maxY)
            )
            cupPath.addQuadCurve(
                to: CGPoint(x: bodyRect.minX + bodyRect.width * 0.05, y: bodyRect.maxY - bodyRect.height * 0.24),
                control: CGPoint(x: bodyRect.minX + bodyRect.width * 0.14, y: bodyRect.maxY)
            )
            cupPath.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + bodyRect.height * 0.14))
            cupPath.addQuadCurve(
                to: CGPoint(x: bodyRect.minX + bodyRect.width * 0.08, y: bodyRect.minY),
                control: CGPoint(x: bodyRect.minX, y: bodyRect.minY)
            )
            cupPath.closeSubpath()

            context.fill(cupPath, with: .color(cupColor))

            // Asa derecha de la taza
            var handlePath = Path()
            let handleStart = CGPoint(x: bodyRect.maxX - w * 0.03, y: bodyRect.minY + bodyRect.height * 0.18)
            let handleEnd = CGPoint(x: bodyRect.maxX - w * 0.05, y: bodyRect.minY + bodyRect.height * 0.66)
            handlePath.move(to: handleStart)
            handlePath.addCurve(
                to: handleEnd,
                control1: CGPoint(x: w * 0.96, y: bodyRect.minY + bodyRect.height * 0.12),
                control2: CGPoint(x: w * 0.96, y: bodyRect.minY + bodyRect.height * 0.72)
            )
            context.stroke(
                handlePath,
                with: .color(cupColor),
                style: StrokeStyle(lineWidth: max(1.5, w * 0.125), lineCap: .round)
            )

            // Corazón en el centro de la taza
            let hx = bodyRect.midX
            let hy = bodyRect.midY + h * 0.02
            let hs = bodyRect.width * 0.27
            var heart = Path()
            heart.move(to: CGPoint(x: hx, y: hy + hs * 0.85))
            heart.addCurve(
                to: CGPoint(x: hx - hs, y: hy - hs * 0.15),
                control1: CGPoint(x: hx - hs * 0.55, y: hy + hs * 0.45),
                control2: CGPoint(x: hx - hs, y: hy + hs * 0.20)
            )
            heart.addCurve(
                to: CGPoint(x: hx, y: hy - hs * 0.35),
                control1: CGPoint(x: hx - hs, y: hy - hs * 0.72),
                control2: CGPoint(x: hx - hs * 0.22, y: hy - hs * 0.78)
            )
            heart.addCurve(
                to: CGPoint(x: hx + hs, y: hy - hs * 0.15),
                control1: CGPoint(x: hx + hs * 0.22, y: hy - hs * 0.78),
                control2: CGPoint(x: hx + hs, y: hy - hs * 0.72)
            )
            heart.addCurve(
                to: CGPoint(x: hx, y: hy + hs * 0.85),
                control1: CGPoint(x: hx + hs, y: hy + hs * 0.20),
                control2: CGPoint(x: hx + hs * 0.55, y: hy + hs * 0.45)
            )
            heart.closeSubpath()
            context.fill(heart, with: .color(heartColor))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Código QR escaneable de Ko-fi sobre tarjeta blanca de alto contraste (siempre legible en modo claro y oscuro).
public struct KoFiQRCodeCardView: View {
    public var size: CGFloat = 86

    public init(size: CGFloat = 86) {
        self.size = size
    }

    public var body: some View {
        Button {
            KoFiSupportConstants.openKoFiPage()
        } label: {
            Group {
                if let qrImage = FileIconProvider.shared.bundledResourceImage(named: KoFiSupportConstants.qrResourceName) {
                    Image(nsImage: qrImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: size * 0.55))
                        .foregroundStyle(.black)
                }
            }
            .padding(5)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1.5)
        }
        .buttonStyle(.plain)
        .help(LocalizationManager.shared.text(
            es: "Escaneá con tu celular o hacé clic para abrir Ko-fi (propina opcional)",
            en: "Scan with your phone or click to open Ko-fi (optional tip)"
        ))
    }
}

/// Botón estilizado con ícono Ko-fi en degradado coral oficial.
public struct KoFiActionButton: View {
    public var title: String
    public var compact: Bool = false
    public var action: () -> Void

    public init(
        title: String,
        compact: Bool = false,
        action: @escaping () -> Void = { KoFiSupportConstants.openKoFiPage() }
    ) {
        self.title = title
        self.compact = compact
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 6 : 7) {
                KoFiCupIconView(size: compact ? 15 : 17)
                Text(title)
                    .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 6 : 7.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [KoFiSupportConstants.coralTop, KoFiSupportConstants.coralBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
            )
            .shadow(color: KoFiSupportConstants.coralBottom.opacity(0.32), radius: 4, y: 1.5)
        }
        .buttonStyle(.plain)
    }
}

/// Tarjeta completa y amigable de apoyo por Ko-fi con QR + botón + aclaración explícita de que la app es 100% gratis.
/// Usada en «Acerca de MacFileExplorer» y en la sección «Historial de releases».
public struct KoFiSupportCardView: View {
    @Bindable private var loc = LocalizationManager.shared
    public var compact: Bool = false

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack(spacing: 6) {
                    KoFiCupIconView(
                        size: 15,
                        cupColor: KoFiSupportConstants.coralBottom,
                        heartColor: .white
                    )

                    Text(loc.text(
                        es: "Apoyá MacFileExplorer con una propina",
                        en: "Support MacFileExplorer with a Tip"
                    ))
                    .font(.system(size: compact ? 12 : 13, weight: .bold))
                    .foregroundStyle(.primary)

                    Text(loc.text(es: "100% Gratis", en: "100% Free"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.green.opacity(0.14))
                        )
                }

                Text(loc.text(
                    es: "MacFileExplorer es totalmente gratuito, libre de anuncios y sin funciones bloqueadas. Ko-fi es únicamente una propina opcional por si te resulta útil y querés invitarme un café para seguir mejorándolo.",
                    en: "MacFileExplorer is completely free, ad-free, and has zero locked features. Ko-fi is purely an optional tip in case you enjoy using it and want to buy me a coffee to support future updates."
                ))
                .font(.system(size: compact ? 11 : 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)

                HStack(spacing: 10) {
                    KoFiActionButton(
                        title: loc.text(es: "Dejar una propina en Ko-fi", en: "Leave a Tip on Ko-fi"),
                        compact: compact
                    )

                    Text("ko-fi.com/luisjavierromero")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 3) {
                KoFiQRCodeCardView(size: compact ? 74 : 88)
                Text(loc.text(es: "Escaneá el QR", en: "Scan QR"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(compact ? 11 : 14)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(KoFiSupportConstants.coralTop.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(KoFiSupportConstants.coralBottom.opacity(0.22), lineWidth: 0.9)
        )
    }
}

/// Aviso flotante mensual no invasivo (esquina inferior derecha sobre el Explorador):
/// 1) Comprueba automáticamente si hay actualizaciones de MacFileExplorer y avisa en el mismo panel.
/// 2) Pregunta amablemente si el usuario desea dejar una propina opcional en Ko-fi (con botón y QR).
/// No roba el foco ni bloquea la navegación de carpetas.
public struct MonthlySupportFloatingToastView: View {
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var supportManager = MonthlySupportCheckManager.shared
    @Bindable private var updateManager = AppUpdateManager.shared
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Encabezado compacto con ícono, badge «100% Gratis» y botón cerrar (✕)
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [KoFiSupportConstants.coralTop, KoFiSupportConstants.coralBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    KoFiCupIconView(size: 16)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(loc.text(es: "¿Te sirve MacFileExplorer?", en: "Enjoying MacFileExplorer?"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(loc.text(es: "100% Gratis", en: "100% Free"))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.green.opacity(0.15))
                            )
                    }

                    Text(loc.text(
                        es: "Resumen mensual · Sin compromiso",
                        en: "Monthly check-in · Always free"
                    ))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        supportManager.snoozeForNextMonth()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help(loc.text(es: "Cerrar por este mes", en: "Dismiss for this month"))
            }

            // 2. Franja integrada de comprobación automática de actualizaciones
            updateStatusStrip

            // 3. Invitación cálida + Botón Ko-fi + QR escaneable
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(loc.text(
                        es: "Esta app es gratuita y sin anuncios. Si querés ayudarme a seguir mejorándola, podés dejarme una propina opcional invitándome un café.",
                        en: "This app is free and ad-free. If you'd like to help me keep improving it, you can leave an optional tip by buying me a coffee."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)

                    KoFiActionButton(
                        title: loc.text(es: "Invitar un café (Ko-fi)", en: "Leave a Tip (Ko-fi)"),
                        compact: true
                    ) {
                        KoFiSupportConstants.openKoFiPage()
                        withAnimation(.easeOut(duration: 0.18)) {
                            supportManager.snoozeForNextMonth()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2.5) {
                    KoFiQRCodeCardView(size: 76)
                    Text(loc.text(es: "Propina QR", en: "Tip QR"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()
                .opacity(0.6)

            // 4. Pie discreto y respetuoso (1 clic para posponer un mes o silenciar definitivamente)
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        supportManager.dismissPermanently()
                    }
                } label: {
                    Text(loc.text(es: "No volver a mostrar", en: "Don't show again"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        supportManager.snoozeForNextMonth()
                    }
                } label: {
                    Text(loc.text(es: "Recordar el mes que viene", en: "Remind next month"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 376)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10),
                    lineWidth: 0.9
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, y: 8)
    }

    @ViewBuilder
    private var updateStatusStrip: some View {
        switch updateManager.state {
        case .checking:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.mini)
                Text(loc.text(
                    es: "Comprobando si hay una versión nueva (v\(AppVersionInfo.currentVersion))…",
                    en: "Checking for updates (v\(AppVersionInfo.currentVersion))…"
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

        case .updateAvailable(let info), .updateAvailableNoInstaller(let info):
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.text(
                        es: "¡Nueva versión v\(info.versionString) disponible!",
                        en: "New version v\(info.versionString) available!"
                    ))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text(loc.text(
                        es: "Tenés instalada v\(AppVersionInfo.currentVersion)",
                        en: "Currently installed: v\(AppVersionInfo.currentVersion)"
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    UpdateWindowController.shared.showAndCheck()
                    withAnimation(.easeOut(duration: 0.18)) {
                        supportManager.snoozeForNextMonth()
                    }
                } label: {
                    Text(loc.text(es: "Actualizar", en: "Update"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.75)
            )

        case .downloading(let info, _, _, let progress):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text(
                    progress.map {
                        loc.text(
                            es: "Descargando v\(info.versionString) (\(Int(($0 * 100).rounded()))%)…",
                            en: "Downloading v\(info.versionString) (\(Int(($0 * 100).rounded()))%)…"
                        )
                    } ?? loc.text(
                        es: "Descargando v\(info.versionString)…",
                        en: "Downloading v\(info.versionString)…"
                    )
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )

        case .downloaded(let info, let fileURL, _):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)

                Text(loc.text(
                    es: "v\(info.versionString) lista para instalar",
                    en: "v\(info.versionString) ready to install"
                ))
                .font(.system(size: 11.5, weight: .semibold))

                Spacer(minLength: 4)

                Button {
                    updateManager.openInstaller(fileURL)
                    supportManager.snoozeForNextMonth()
                } label: {
                    Text(loc.text(es: "Abrir .dmg", en: "Open .dmg"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(Color.green))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.12))
            )

        case .upToDate:
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text(loc.text(
                    es: "Estás al día · MacFileExplorer v\(AppVersionInfo.currentVersion)",
                    en: "You're up to date · MacFileExplorer v\(AppVersionInfo.currentVersion)"
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.09))
            )

        case .failed, .idle:
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(loc.text(
                    es: "MacFileExplorer v\(AppVersionInfo.currentVersion)",
                    en: "MacFileExplorer v\(AppVersionInfo.currentVersion)"
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    updateManager.checkForUpgrades(autoDownload: false)
                } label: {
                    Text(loc.text(es: "Buscar actualizaciones", en: "Check updates"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
}
