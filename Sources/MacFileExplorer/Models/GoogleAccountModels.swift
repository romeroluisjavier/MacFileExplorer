import Foundation
import AppKit
import SwiftUI

/// Accesos directos de Google Workspace disponibles bajo cada cuenta de Google autenticada.
public enum GoogleServiceShortcut: String, CaseIterable, Identifiable, Codable, Sendable {
    case gmail = "gmail"
    case drive = "drive"
    case calendar = "calendar"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gmail:
            return "Gmail"
        case .drive:
            return "Google Drive"
        case .calendar:
            return "Google Calendar"
        }
    }

    public var systemImage: String {
        switch self {
        case .gmail:
            return "envelope.fill"
        case .drive:
            return "externaldrive.fill.badge.icloud"
        case .calendar:
            return "calendar"
        }
    }

    public var iconColor: Color {
        switch self {
        case .gmail:
            return Color(red: 0.92, green: 0.26, blue: 0.21) // Rojo Gmail
        case .drive:
            return Color(red: 0.20, green: 0.66, blue: 0.33) // Verde Google Drive
        case .calendar:
            return Color(red: 0.26, green: 0.52, blue: 0.96) // Azul Google Calendar
        }
    }

    public var targetURL: URL {
        switch self {
        case .gmail:
            return URL(string: "https://mail.google.com/mail/u/0/")!
        case .drive:
            return URL(string: "https://drive.google.com/drive/u/0/")!
        case .calendar:
            return URL(string: "https://calendar.google.com/calendar/u/0/")!
        }
    }
}

/// Representa una cuenta de Google con su propio contenedor de sesión aislado (`WKWebsiteDataStore(forIdentifier: id)`).
/// Cada cuenta posee un `UUID` único que garantiza que sus cookies, LocalStorage e IndexedDB nunca se mezclen con otra cuenta.
public struct GoogleAccount: Identifiable, Codable, Hashable, Sendable {
    /// Identificador único de la cuenta y clave del contenedor aislado `WKWebsiteDataStore(forIdentifier: id)`.
    public let id: UUID

    /// Correo electrónico de la cuenta (ej. `usuario@gmail.com`).
    public var email: String

    /// Nombre visible opcional del perfil.
    public var displayName: String

    /// Indica si el usuario ya completó el inicio de sesión en Google dentro de este contenedor aislado.
    public var isAuthenticated: Bool

    /// Índice de color para distinguir visualmente pestañas de distintas cuentas.
    public var colorIndex: Int

    /// URL de la foto de perfil de la cuenta detectada en Google.
    public var avatarURLString: String?

    /// Imagen PNG normalizada (`64×64`) de la foto de perfil de Google persistida localmente.
    public var avatarData: Data?

    public init(
        id: UUID = UUID(),
        email: String = "",
        displayName: String = "",
        isAuthenticated: Bool = false,
        colorIndex: Int = 0,
        avatarURLString: String? = nil,
        avatarData: Data? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.isAuthenticated = isAuthenticated
        self.colorIndex = colorIndex
        self.avatarURLString = avatarURLString
        self.avatarData = avatarData
    }

    @MainActor
    public var displayLabel: String {
        if !email.isEmpty {
            return email
        }
        if !displayName.isEmpty {
            return displayName
        }
        return LocalizationManager.shared.text(es: "Iniciando sesión...", en: "Signing in...")
    }

    public var badgeColor: Color {
        let palette: [Color] = [
            Color(red: 0.26, green: 0.52, blue: 0.96),
            Color(red: 0.20, green: 0.66, blue: 0.33),
            Color(red: 0.61, green: 0.35, blue: 0.71),
            Color(red: 0.95, green: 0.60, blue: 0.07),
            Color(red: 0.91, green: 0.12, blue: 0.39)
        ]
        return palette[abs(colorIndex) % palette.count]
    }
}

/// Representa una pestaña web estilo Chrome abierta dentro de `MacFileExplorer` y vinculada a una sesión aislada de Google.
public struct BrowserTabItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let accountID: UUID
    public var title: String
    public var currentURL: URL
    public var service: GoogleServiceShortcut?
    public var bookmarkID: UUID?
    public var faviconData: Data?
    public var isLoading: Bool
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var pageZoom: Double

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        title: String,
        currentURL: URL,
        service: GoogleServiceShortcut? = nil,
        bookmarkID: UUID? = nil,
        faviconData: Data? = nil,
        isLoading: Bool = true,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        pageZoom: Double = 1.0
    ) {
        self.id = id
        self.accountID = accountID
        self.title = title
        self.currentURL = currentURL
        self.service = service
        self.bookmarkID = bookmarkID
        self.faviconData = faviconData
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.pageZoom = pageZoom
    }
}

// MARK: - Iconos Vectoriales Oficiales de Google (G, Gmail, Google Drive, Google Calendar)

/// Logo oficial multicolor "G" de Google para el encabezado de Cuentas de Google.
public struct GoogleGLogoView: View {
    public var size: CGFloat = 14

    public init(size: CGFloat = 14) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let strokeWidth = w * 0.22
            let radius = (w - strokeWidth) / 2

            let blue = Color(red: 0.26, green: 0.52, blue: 0.96)   // #4285F4
            let red = Color(red: 0.92, green: 0.26, blue: 0.21)    // #EA4335
            let yellow = Color(red: 0.98, green: 0.74, blue: 0.02) // #FBBC05
            let green = Color(red: 0.20, green: 0.66, blue: 0.33)  // #34A853

            // Arco superior rojo
            var redArc = Path()
            redArc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(212),
                endAngle: .degrees(318),
                clockwise: false
            )
            context.stroke(redArc, with: .color(red), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))

            // Arco izquierdo amarillo
            var yellowArc = Path()
            yellowArc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(146),
                endAngle: .degrees(214),
                clockwise: false
            )
            context.stroke(yellowArc, with: .color(yellow), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))

            // Arco inferior verde
            var greenArc = Path()
            greenArc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(44),
                endAngle: .degrees(148),
                clockwise: false
            )
            context.stroke(greenArc, with: .color(green), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))

            // Arco derecho azul + barra horizontal de la "G"
            var blueArc = Path()
            blueArc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(-8),
                endAngle: .degrees(46),
                clockwise: false
            )
            context.stroke(blueArc, with: .color(blue), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))

            let barRect = CGRect(
                x: center.x - strokeWidth * 0.15,
                y: center.y - strokeWidth * 0.48,
                width: radius + strokeWidth * 0.62,
                height: strokeWidth * 0.95
            )
            context.fill(Path(barRect), with: .color(blue))
        }
        .frame(width: size, height: size)
    }
}

/// Iconos vectoriales multicolor oficiales de Google Workspace para Gmail, Google Drive y Google Calendar.
public struct GoogleServiceIconView: View {
    public let service: GoogleServiceShortcut
    public var size: CGFloat = 15

    public init(service: GoogleServiceShortcut, size: CGFloat = 15) {
        self.service = service
        self.size = size
    }

    public var body: some View {
        switch service {
        case .gmail:
            gmailIcon
        case .drive:
            driveIcon
        case .calendar:
            calendarIcon
        }
    }

    // MARK: - 1. Icono Oficial de Gmail (M Multicolor)
    private var gmailIcon: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let topY = h * 0.14
            let bottomY = h * 0.86
            let legW = w * 0.22

            let blue = Color(red: 0.26, green: 0.52, blue: 0.96)    // #4285F4
            let green = Color(red: 0.20, green: 0.66, blue: 0.33)   // #34A853
            let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)  // #FBBC04
            let red = Color(red: 0.92, green: 0.26, blue: 0.21)     // #EA4335
            let darkRed = Color(red: 0.77, green: 0.13, blue: 0.12) // #C5221F

            // Columna izquierda azul
            var leftPillar = Path()
            leftPillar.move(to: CGPoint(x: 0, y: topY + h * 0.14))
            leftPillar.addLine(to: CGPoint(x: legW, y: topY + h * 0.30))
            leftPillar.addLine(to: CGPoint(x: legW, y: bottomY))
            leftPillar.addLine(to: CGPoint(x: w * 0.06, y: bottomY))
            leftPillar.addQuadCurve(to: CGPoint(x: 0, y: bottomY - h * 0.06), control: CGPoint(x: 0, y: bottomY))
            leftPillar.closeSubpath()
            context.fill(leftPillar, with: .color(blue))

            // Columna derecha verde
            var rightPillar = Path()
            rightPillar.move(to: CGPoint(x: w, y: topY + h * 0.14))
            rightPillar.addLine(to: CGPoint(x: w - legW, y: topY + h * 0.30))
            rightPillar.addLine(to: CGPoint(x: w - legW, y: bottomY))
            rightPillar.addLine(to: CGPoint(x: w * 0.94, y: bottomY))
            rightPillar.addQuadCurve(to: CGPoint(x: w, y: bottomY - h * 0.06), control: CGPoint(x: w, y: bottomY))
            rightPillar.closeSubpath()
            context.fill(rightPillar, with: .color(green))

            // Hombro superior izquierdo rojo oscuro
            var leftCap = Path()
            leftCap.move(to: CGPoint(x: 0, y: topY + h * 0.08))
            leftCap.addQuadCurve(to: CGPoint(x: w * 0.12, y: topY), control: CGPoint(x: 0, y: topY))
            leftCap.addLine(to: CGPoint(x: legW, y: topY + h * 0.07))
            leftCap.addLine(to: CGPoint(x: legW, y: topY + h * 0.31))
            leftCap.addLine(to: CGPoint(x: 0, y: topY + h * 0.15))
            leftCap.closeSubpath()
            context.fill(leftCap, with: .color(darkRed))

            // Hombro superior derecho amarillo
            var rightCap = Path()
            rightCap.move(to: CGPoint(x: w, y: topY + h * 0.08))
            rightCap.addQuadCurve(to: CGPoint(x: w * 0.88, y: topY), control: CGPoint(x: w, y: topY))
            rightCap.addLine(to: CGPoint(x: w - legW, y: topY + h * 0.07))
            rightCap.addLine(to: CGPoint(x: w - legW, y: topY + h * 0.31))
            rightCap.addLine(to: CGPoint(x: w, y: topY + h * 0.15))
            rightCap.closeSubpath()
            context.fill(rightCap, with: .color(yellow))

            // "V" central roja de la M
            var centerV = Path()
            centerV.move(to: CGPoint(x: legW, y: topY + h * 0.06))
            centerV.addLine(to: CGPoint(x: w * 0.50, y: topY + h * 0.34))
            centerV.addLine(to: CGPoint(x: w - legW, y: topY + h * 0.06))
            centerV.addLine(to: CGPoint(x: w - legW, y: topY + h * 0.31))
            centerV.addLine(to: CGPoint(x: w * 0.50, y: topY + h * 0.58))
            centerV.addLine(to: CGPoint(x: legW, y: topY + h * 0.31))
            centerV.closeSubpath()
            context.fill(centerV, with: .color(red))
        }
        .frame(width: size, height: size)
    }

    // MARK: - 2. Icono Oficial de Google Drive (Triángulo Multicolor)
    private var driveIcon: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            let green = Color(red: 0.00, green: 0.67, blue: 0.28)  // #00AC47
            let yellow = Color(red: 1.00, green: 0.73, blue: 0.00) // #FFBA00
            let blue = Color(red: 0.15, green: 0.52, blue: 0.99)   // #2684FC
            let red = Color(red: 0.92, green: 0.26, blue: 0.21)    // #EA4335

            // Brazo izquierdo verde
            var leftArm = Path()
            leftArm.move(to: CGPoint(x: w * 0.34, y: h * 0.10))
            leftArm.addLine(to: CGPoint(x: w * 0.52, y: h * 0.42))
            leftArm.addLine(to: CGPoint(x: w * 0.22, y: h * 0.88))
            leftArm.addLine(to: CGPoint(x: w * 0.04, y: h * 0.58))
            leftArm.closeSubpath()
            context.fill(leftArm, with: .color(green))

            // Brazo derecho amarillo
            var rightArm = Path()
            rightArm.move(to: CGPoint(x: w * 0.34, y: h * 0.10))
            rightArm.addLine(to: CGPoint(x: w * 0.66, y: h * 0.10))
            rightArm.addLine(to: CGPoint(x: w * 0.96, y: h * 0.58))
            rightArm.addLine(to: CGPoint(x: w * 0.64, y: h * 0.58))
            rightArm.closeSubpath()
            context.fill(rightArm, with: .color(yellow))

            // Base inferior azul
            var bottomBar = Path()
            bottomBar.move(to: CGPoint(x: w * 0.22, y: h * 0.88))
            bottomBar.addLine(to: CGPoint(x: w * 0.38, y: h * 0.58))
            bottomBar.addLine(to: CGPoint(x: w * 0.96, y: h * 0.58))
            bottomBar.addLine(to: CGPoint(x: w * 0.78, y: h * 0.88))
            bottomBar.closeSubpath()
            context.fill(bottomBar, with: .color(blue))

            // Acento esquina derecha roja (estilo Google Workspace)
            var redCorner = Path()
            redCorner.move(to: CGPoint(x: w * 0.78, y: h * 0.88))
            redCorner.addLine(to: CGPoint(x: w * 0.64, y: h * 0.58))
            redCorner.addLine(to: CGPoint(x: w * 0.96, y: h * 0.58))
            redCorner.closeSubpath()
            context.fill(redCorner, with: .color(red.opacity(0.88)))
        }
        .frame(width: size, height: size)
    }

    // MARK: - 3. Icono Oficial de Google Calendar (Cuadrado Multicolor "31")
    private var calendarIcon: some View {
        ZStack {
            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let pad = w * 0.06
                let rect = CGRect(x: pad, y: pad, width: w - pad * 2, height: h - pad * 2)
                let band = w * 0.22

                let blue = Color(red: 0.26, green: 0.52, blue: 0.96)   // #4285F4
                let yellow = Color(red: 0.98, green: 0.74, blue: 0.02) // #FBBC04
                let green = Color(red: 0.20, green: 0.66, blue: 0.33)  // #34A853
                let red = Color(red: 0.92, green: 0.26, blue: 0.21)    // #EA4335

                // Fondo azul principal (arriba e izquierda)
                let outerPath = Path(roundedRect: rect, cornerRadius: w * 0.18)
                context.fill(outerPath, with: .color(blue))

                // Bloque derecho amarillo
                let yellowRect = CGRect(
                    x: rect.maxX - band,
                    y: rect.minY + band,
                    width: band,
                    height: rect.height - band * 2
                )
                context.fill(Path(yellowRect), with: .color(yellow))

                // Bloque inferior verde
                let greenRect = CGRect(
                    x: rect.minX + band,
                    y: rect.maxY - band,
                    width: rect.width - band * 2,
                    height: band
                )
                context.fill(Path(greenRect), with: .color(green))

                // Esquina inferior derecha plegada roja
                var redFold = Path()
                redFold.move(to: CGPoint(x: rect.maxX - band, y: rect.maxY - band))
                redFold.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - band))
                redFold.addLine(to: CGPoint(x: rect.maxX - band, y: rect.maxY))
                redFold.closeSubpath()
                context.fill(redFold, with: .color(red))

                // Centro blanco para el número "31"
                let innerRect = CGRect(
                    x: rect.minX + band,
                    y: rect.minY + band,
                    width: rect.width - band * 2,
                    height: rect.height - band * 2
                )
                context.fill(Path(roundedRect: innerRect, cornerRadius: w * 0.05), with: .color(.white))
            }

            Text("31")
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.91))
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Constructor de Iconos y Apariencia para Pestañas Nativas de macOS (`NSWindow.tab`)

@MainActor
public enum NativeWindowTabIconBuilder {

    /// Aplica título e icono nativo en la barra de pestañas de macOS (`NSWindow.tab`).
    public static func applyFolderTabAppearance(to window: NSWindow, title: String) {
        applyTabAppearance(to: window, title: title, icon: folderTabIcon(title: title))
    }

    /// Aplica título e icono web (Gmail, Drive, Calendar, Google o Favicon) en la barra de pestañas de macOS (`NSWindow.tab`).
    public static func applyWebTabAppearance(to window: NSWindow, for tab: BrowserTabItem) {
        applyTabAppearance(to: window, title: tab.title, icon: webTabIcon(for: tab))
    }

    public static func folderTabIcon(title: String) -> NSImage? {
        let view = ZStack {
            Color.clear
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.62, blue: 0.96))
        }
        .frame(width: 16, height: 16)
        return renderNSImage(from: view, size: CGSize(width: 16, height: 16))
    }

    public static func webTabIcon(for tab: BrowserTabItem) -> NSImage? {
        let image: NSImage?
        if let service = tab.service {
            let view = GoogleServiceIconView(service: service, size: 14.5)
                .frame(width: 16, height: 16)
            image = renderNSImage(from: view, size: CGSize(width: 16, height: 16))
        } else if let capturedData = tab.faviconData,
                  let capturedFavicon = NSImage(data: capturedData) {
            image = renderFaviconTabImage(capturedFavicon)
        } else if let bookmarkID = tab.bookmarkID,
                  let bookmark = BookmarksManager.shared.bookmarks.first(where: { $0.id == bookmarkID }),
                  let bookmarkFavicon = BookmarksManager.shared.cachedFavicon(for: bookmark) {
            image = renderFaviconTabImage(bookmarkFavicon)
        } else if let host = tab.currentURL.host,
                  let cachedFavicon = BookmarksManager.shared.cachedFavicon(forHost: host) {
            image = renderFaviconTabImage(cachedFavicon)
        } else if isGoogleBrandHost(tab.currentURL.host) {
            let view = GoogleGLogoView(size: 14)
                .frame(width: 16, height: 16)
            image = renderNSImage(from: view, size: CGSize(width: 16, height: 16))
        } else {
            let view = ZStack {
                Color.clear
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 16, height: 16)
            image = renderNSImage(from: view, size: CGSize(width: 16, height: 16))
        }
        image?.isTemplate = false
        return image
    }

    private static func renderFaviconTabImage(_ favicon: NSImage) -> NSImage? {
        let view = Image(nsImage: favicon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .frame(width: 16, height: 16)
        return renderNSImage(from: view, size: CGSize(width: 16, height: 16))
    }

    private static func isGoogleBrandHost(_ host: String?) -> Bool {
        let norm = FaviconService.normalizedHost(host)
        guard !norm.isEmpty else { return false }
        return norm == "google.com"
            || norm.hasPrefix("google.")
            || norm.hasSuffix(".google.com")
            || norm.contains(".google.")
    }

    public static func applyTabAppearance(to window: NSWindow, title: String, icon: NSImage?) {
        window.title = title
        window.tab.attributedTitle = nil
        window.tab.title = title
        window.tab.toolTip = title

        guard let icon else { return }

        let setImageSel = NSSelectorFromString("setImage:")
        let setShowIconSel = NSSelectorFromString("setShowIcon:")
        if window.tab.responds(to: setImageSel), window.tab.responds(to: setShowIconSel) {
            window.tab.setValue(icon, forKey: "image")
            window.tab.setValue(true, forKey: "showIcon")
        } else {
            let imageView = NSImageView(image: icon)
            imageView.imageScaling = .scaleProportionallyDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 15),
                imageView.heightAnchor.constraint(equalToConstant: 15)
            ])
            window.tab.accessoryView = imageView
        }
    }

    private static func renderNSImage<V: View>(from view: V, size: CGSize) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let nsImage = renderer.nsImage else { return nil }
        nsImage.size = size
        nsImage.isTemplate = false
        return nsImage
    }
}

/// Avatar circular de la cuenta de Google: muestra la imagen de perfil real si está disponible,
/// o cae de forma elegante a la inicial del correo / logo oficial de Google mientras se obtiene.
public struct GoogleAccountAvatarView: View {
    public let account: GoogleAccount
    public var size: CGFloat = 16
    @Bindable private var googleManager: GoogleAccountsManager = .shared

    public init(account: GoogleAccount, size: CGFloat = 16) {
        self.account = account
        self.size = size
    }

    public var body: some View {
        Group {
            if let avatar = googleManager.avatarImage(for: account) {
                Image(nsImage: avatar)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                    )
            } else if !account.email.isEmpty, let firstChar = account.email.first {
                Circle()
                    .fill(account.badgeColor.gradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(firstChar).uppercased())
                            .font(.system(size: size * 0.59, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            } else {
                GoogleGLogoView(size: size * 0.875)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}

