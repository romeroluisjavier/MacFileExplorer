import SwiftUI
import AppKit
import WebKit

// MARK: - Vista Principal de Pestaña Chrome Aislada (Ancho Completo en Tab Nativo)

public struct IsolatedGoogleWebTabView: View {
    public let tabID: UUID
    @Bindable var googleManager: GoogleAccountsManager = .shared

    @ViewState private var urlDraft: String = ""
    @FocusState private var isURLFieldFocused: Bool

    private var loc: LocalizationManager { LocalizationManager.shared }

    private var tab: BrowserTabItem? {
        googleManager.tab(for: tabID)
    }

    private var account: GoogleAccount? {
        guard let tab else { return nil }
        return googleManager.account(for: tab)
    }

    public init(tabID: UUID) {
        self.tabID = tabID
        let initialURL = GoogleAccountsManager.shared.tab(for: tabID)?.currentURL.absoluteString ?? ""
        _urlDraft = ViewState(initialValue: initialURL)
    }

    public var body: some View {
        Group {
            if let tab {
                VStack(spacing: 0) {
                    // Barra de Navegación Superior estilo Chrome con indicador de Sesión Aislada y Zoom
                    chromeToolbar(for: tab)

                    Divider()

                    // Contenedor WebKit ocupando el 100% del ancho con `WKWebsiteDataStore(forIdentifier: account.id)` aislado
                    IsolatedWebViewRepresentable(tab: tab, googleManager: googleManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onAppear {
                    urlDraft = tab.currentURL.absoluteString
                }
                .onChange(of: tab.currentURL) { _, newURL in
                    urlDraft = newURL.absoluteString
                }
                .onChange(of: tabID) { _, newID in
                    urlDraft = googleManager.tab(for: newID)?.currentURL.absoluteString ?? ""
                }
                .background {
                    hiddenWebShortcuts
                }
                .navigationTitle(tab.title)
            } else {
                Color.clear
            }
        }
    }

    private var hiddenWebShortcuts: some View {
        Group {
            Button("") {
                isURLFieldFocused = true
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button("") {
                googleManager.reloadTab(tabID)
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button("") {
                googleManager.goBackInTab(tabID)
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("") {
                googleManager.goForwardInTab(tabID)
            }
            .keyboardShortcut("]", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    private func chromeToolbar(for tab: BrowserTabItem) -> some View {
        HStack(spacing: 8) {
            // Botones Atrás / Adelante / Recargar
            HStack(spacing: 3) {
                Button {
                    googleManager.goBackInTab(tab.id)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(!tab.canGoBack)
                .opacity(tab.canGoBack ? 1.0 : 0.35)

                Button {
                    googleManager.goForwardInTab(tab.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(!tab.canGoForward)
                .opacity(tab.canGoForward ? 1.0 : 0.35)

                Button {
                    googleManager.reloadTab(tab.id)
                } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }

            // Píldora de Sesión Aislada por Cuenta de Google
            if let account {
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(account.badgeColor)

                    Text(account.displayLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(account.badgeColor.opacity(0.14))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(account.badgeColor.opacity(0.35), lineWidth: 0.7)
                )
                .help(loc.text(
                    es: "Contenedor aislado (cookies y sesión exclusivas de \(account.displayLabel))",
                    en: "Isolated container (cookies & session exclusive to \(account.displayLabel))"
                ))
            }

            // Barra de direcciones estilo Omnibox de Chrome
            HStack(spacing: 6) {
                Image(systemName: tab.currentURL.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                TextField("https://...", text: $urlDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        googleManager.navigateTab(tab.id, to: urlDraft)
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
            )

            // Accesos rápidos a Gmail / Drive / Calendar de ESTA misma cuenta aislada
            if let account {
                HStack(spacing: 4) {
                    ForEach(GoogleServiceShortcut.allCases) { service in
                        Button {
                            googleManager.openServiceTab(service, for: account)
                        } label: {
                            HStack(spacing: 5) {
                                GoogleServiceIconView(service: service, size: 12)
                                Text(service == .gmail ? "Gmail" : (service == .drive ? "Drive" : "Calendar"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(tab.service == service ? account.badgeColor.opacity(0.16) : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Control de Zoom de la Web Completa (25% - 300%)
            webZoomControl(for: tab)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func webZoomControl(for tab: BrowserTabItem) -> some View {
        let currentZoomPercent = Int((tab.pageZoom * 100).rounded())

        return HStack(spacing: 2) {
            Button {
                googleManager.zoomOutTab(tab.id)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(tab.pageZoom <= 0.25)
            .help(loc.text(es: "Alejar página web (Zoom -)", en: "Zoom Out Web Page (Zoom -)"))

            Menu {
                Button {
                    googleManager.resetZoomInTab(tab.id)
                } label: {
                    Label(
                        loc.text(es: "Restablecer al 100%", en: "Reset to 100%"),
                        systemImage: "arrow.counterclockwise"
                    )
                }

                Divider()

                ForEach([0.50, 0.67, 0.75, 0.80, 0.90, 1.00, 1.10, 1.25, 1.50, 1.75, 2.00], id: \.self) { step in
                    let pct = Int((step * 100).rounded())
                    Toggle(
                        "\(pct)%",
                        isOn: Binding(
                            get: { abs(tab.pageZoom - step) < 0.01 },
                            set: { _ in googleManager.setZoom(for: tab.id, zoom: step) }
                        )
                    )
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(currentZoomPercent)%")
                        .font(.system(size: 11, weight: abs(tab.pageZoom - 1.0) > 0.01 ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(abs(tab.pageZoom - 1.0) > 0.01 ? Color.accentColor : Color.primary)
                }
                .padding(.horizontal, 4)
                .frame(height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(loc.text(es: "Zoom de la página web completa", en: "Full web page zoom"))

            Button {
                googleManager.zoomInTab(tab.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(tab.pageZoom >= 3.0)
            .help(loc.text(es: "Acercar página web (Zoom +)", en: "Zoom In Web Page (Zoom +)"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
        )
    }
}

// MARK: - Contenedor `NSViewRepresentable` para `WKWebView` Persistente

private struct IsolatedWebViewRepresentable: NSViewRepresentable {
    let tab: BrowserTabItem
    let googleManager: GoogleAccountsManager

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        embedWebView(in: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        embedWebView(in: nsView)
    }

    private func embedWebView(in container: NSView) {
        let targetWebView = googleManager.webView(for: tab)
        if abs(targetWebView.pageZoom - CGFloat(tab.pageZoom)) > 0.001 {
            targetWebView.pageZoom = CGFloat(tab.pageZoom)
        }
        if container.subviews.first === targetWebView {
            return
        }
        container.subviews.forEach { $0.removeFromSuperview() }
        targetWebView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(targetWebView)
        NSLayoutConstraint.activate([
            targetWebView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            targetWebView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            targetWebView.topAnchor.constraint(equalTo: container.topAnchor),
            targetWebView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
