import AppKit
import Foundation
import WebKit

/// Servicio encargado de descubrir, descargar, rasterizar y normalizar favicons en PNG (`64×64`)
/// tanto mediante inspección directa del DOM/sesión en `WKWebView` como vía HTTP para marcadores aún no abiertos.
public enum FaviconService {

    /// Hosts de autenticación OAuth/SSO de terceros que no deben sobrescribir el icono de un marcador propio durante redirecciones temporales.
    private static let transientThirdPartyAuthHosts: Set<String> = [
        "accounts.google.com",
        "login.microsoftonline.com",
        "login.live.com",
        "appleid.apple.com",
        "auth0.com",
        "login.yahoo.com"
    ]

    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    // MARK: - Utilidades de Host / Dominio

    /// Normaliza un nombre de host a minúsculas y sin el prefijo opcional `www.`.
    public static func normalizedHost(_ host: String?) -> String {
        guard let host else { return "" }
        let lower = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("www.") {
            return String(lower.dropFirst(4))
        }
        return lower
    }

    /// Indica si dos hosts corresponden al mismo dominio efectivo (ignorando `www.`).
    public static func hostsMatchNormalized(_ hostA: String?, _ hostB: String?) -> Bool {
        let normA = normalizedHost(hostA)
        let normB = normalizedHost(hostB)
        return !normA.isEmpty && normA == normB
    }

    /// Indica si el host cargado pertenece a una pasarela de login SSO de terceros distinta al marcador original.
    public static func isTransientThirdPartyAuthHost(_ loadedHost: String?, bookmarkHost: String?) -> Bool {
        let normLoaded = normalizedHost(loadedHost)
        guard !normLoaded.isEmpty else { return false }
        let normBookmark = normalizedHost(bookmarkHost)
        if normLoaded == normBookmark {
            return false
        }
        if transientThirdPartyAuthHosts.contains(normLoaded) {
            return true
        }
        return normLoaded.hasSuffix(".auth0.com") || normLoaded.hasSuffix(".okta.com")
    }

    // MARK: - Normalización de Imagen a PNG Compacto (`64×64`)

    /// Decodifica bytes de imagen (PNG, ICO, JPEG, GIF, WebP, SVG) y los normaliza a PNG RGBA `64×64`.
    public static func normalizedPNGData(from data: Data, targetPixelSize: Int = 64) -> Data? {
        guard !data.isEmpty, let image = NSImage(data: data) else { return nil }
        return normalizedPNGData(from: image, targetPixelSize: targetPixelSize)
    }

    /// Renderiza un `NSImage` en un bitmap PNG cuadrado de `targetPixelSize × targetPixelSize` píxeles preservando transparencia y proporción.
    public static func normalizedPNGData(from image: NSImage, targetPixelSize: Int = 64) -> Data? {
        let maxRepPixels = image.representations
            .map { max($0.pixelsWide, $0.pixelsHigh) }
            .max() ?? 0
        let maxPointDim = max(image.size.width, image.size.height)

        // Descartar píxeles de seguimiento (1×1) o imágenes corruptas sin dimensiones válidas.
        guard max(CGFloat(maxRepPixels), maxPointDim) >= 8,
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetPixelSize,
            pixelsHigh: targetPixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmap.size = NSSize(width: targetPixelSize, height: targetPixelSize)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let side = CGFloat(targetPixelSize)
        let scale = min(side / image.size.width, side / image.size.height)
        let drawW = image.size.width * scale
        let drawH = image.size.height * scale
        let drawRect = NSRect(
            x: (side - drawW) / 2.0,
            y: (side - drawH) / 2.0,
            width: drawW,
            height: drawH
        )

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.flushGraphics()

        return bitmap.representation(using: .png, properties: [:])
    }

    /// Decodifica una URI `data:image/...;base64,...` o `data:image/svg+xml,...` a `Data`.
    public static func decodeDataURL(_ dataURLString: String) -> Data? {
        let trimmed = dataURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:"),
              let commaIdx = trimmed.firstIndex(of: ",") else {
            return nil
        }
        let meta = trimmed[..<commaIdx].lowercased()
        let payload = String(trimmed[trimmed.index(after: commaIdx)...])
        if meta.contains(";base64") {
            let cleaned = payload.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            return Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters)
        }
        let decoded = payload.removingPercentEncoding ?? payload
        return decoded.data(using: .utf8)
    }

    // MARK: - Extracción en Vivo desde `WKWebView`

    /// Script JS ejecutado dentro del contexto de la página cargada en `WKWebView` para descubrir todos los `<link rel="...icon...">`,
    /// descargar el mejor candidato usando las cookies de sesión de WebKit y rasterizar SVG/WebP/PNG en un `<canvas>` 64×64.
    private static let webViewFaviconScript = #"""
    const links = Array.from(document.querySelectorAll('link[rel]'));
    function scoreLink(relStr, typeStr, sizesStr, hrefStr) {
        const tokens = relStr.toLowerCase().split(/\s+/).filter(Boolean);
        const isIcon = tokens.includes('icon');
        const isApple = tokens.includes('apple-touch-icon') || tokens.includes('apple-touch-icon-precomposed');
        if (!isIcon && !isApple) return -1;

        let score = isIcon ? 100 : 80;
        const lowerHref = hrefStr.toLowerCase();
        const lowerType = (typeStr || '').toLowerCase();
        if (lowerType.includes('png') || lowerHref.includes('.png')) score += 20;
        else if (lowerType.includes('svg') || lowerHref.includes('.svg')) score += 15;
        else if (lowerType.includes('webp') || lowerHref.includes('.webp')) score += 12;
        else if (lowerType.includes('icon') || lowerHref.includes('.ico')) score += 5;

        const sizes = (sizesStr || '').toLowerCase();
        if (sizes.includes('any')) {
            score += 25;
        } else {
            const matches = Array.from(sizes.matchAll(/(\d+)\s*x\s*(\d+)/g));
            let bestDim = 0;
            for (const m of matches) {
                bestDim = Math.max(bestDim, parseInt(m[1], 10) || 0);
            }
            if (bestDim >= 48 && bestDim <= 192) score += 30;
            else if (bestDim >= 32 && bestDim < 48) score += 22;
            else if (bestDim > 192) score += 18;
            else if (bestDim >= 16) score += 5;
        }
        return score;
    }

    const scored = [];
    for (const el of links) {
        const href = (el.getAttribute('href') || '').trim();
        if (!href) continue;
        const s = scoreLink(
            el.getAttribute('rel') || '',
            el.getAttribute('type') || '',
            el.getAttribute('sizes') || '',
            href
        );
        if (s < 0) continue;
        try {
            const resolved = new URL(href, document.baseURI).href;
            scored.push({ url: resolved, score: s });
        } catch (_) {}
    }
    scored.sort((a, b) => b.score - a.score);

    const candidates = [];
    const seen = new Set();
    for (const item of scored) {
        if (!seen.has(item.url)) {
            seen.add(item.url);
            candidates.push(item.url);
        }
    }
    if (window.location.origin && window.location.origin !== 'null') {
        for (const path of ['/favicon.ico', '/apple-touch-icon.png']) {
            const fallbackURL = window.location.origin + path;
            if (!seen.has(fallbackURL)) {
                seen.add(fallbackURL);
                candidates.push(fallbackURL);
            }
        }
    }

    async function rasterizeDataURL(dataURL) {
        return await new Promise((resolve) => {
            const img = new Image();
            img.onload = () => {
                const w = img.naturalWidth || img.width || 0;
                const h = img.naturalHeight || img.height || 0;
                if ((w < 8 || h < 8) && !dataURL.startsWith('data:image/svg+xml')) {
                    resolve(null);
                    return;
                }
                try {
                    const canvas = document.createElement('canvas');
                    canvas.width = 64;
                    canvas.height = 64;
                    const ctx = canvas.getContext('2d');
                    if (!ctx) { resolve(null); return; }
                    const srcW = w > 0 ? w : 64;
                    const srcH = h > 0 ? h : 64;
                    const scale = Math.min(64 / srcW, 64 / srcH);
                    const dw = srcW * scale;
                    const dh = srcH * scale;
                    ctx.drawImage(img, (64 - dw) / 2, (64 - dh) / 2, dw, dh);
                    resolve(canvas.toDataURL('image/png'));
                } catch (_) {
                    resolve(null);
                }
            };
            img.onerror = () => resolve(null);
            img.src = dataURL;
        });
    }

    async function tryCapture(url) {
        if (url.startsWith('data:image/')) {
            const png = await rasterizeDataURL(url);
            return png || url;
        }
        const resp = await fetch(url, { credentials: 'include' });
        if (!resp.ok) return null;
        const blob = await resp.blob();
        if (!blob || blob.size === 0) return null;
        const mime = (blob.type || '').toLowerCase();
        if (mime && !mime.startsWith('image/') && !mime.includes('icon') && mime !== 'application/octet-stream') {
            return null;
        }
        const rawDataURL = await new Promise((resolve) => {
            const reader = new FileReader();
            reader.onloadend = () => resolve(typeof reader.result === 'string' ? reader.result : null);
            reader.onerror = () => resolve(null);
            reader.readAsDataURL(blob);
        });
        if (!rawDataURL) return null;
        const png = await rasterizeDataURL(rawDataURL);
        if (png) return png;
        if (mime.startsWith('image/') || mime.includes('icon')) return rawDataURL;
        return null;
    }

    let capturedDataURL = null;
    for (const candidate of candidates.slice(0, 5)) {
        try {
            capturedDataURL = await tryCapture(candidate);
            if (capturedDataURL) break;
        } catch (_) {}
    }

    return {
        dataURL: capturedDataURL,
        candidates: candidates.slice(0, 8),
        pageURL: window.location.href
    };
    """#

    /// Extrae el favicon de la página actualmente cargada en un `WKWebView` (aprovechando cookies, sesión autenticada y fallback sin CORS en Swift).
    @MainActor
    public static func captureFaviconData(from webView: WKWebView) async -> Data? {
        guard webView.url != nil else { return nil }

        guard let rawResult = try? await webView.callAsyncJavaScript(
            webViewFaviconScript,
            arguments: [:],
            in: nil,
            contentWorld: .defaultClient
        ) as? [String: Any] else {
            return nil
        }

        if let dataURL = rawResult["dataURL"] as? String,
           let rawBytes = decodeDataURL(dataURL),
           let normalized = normalizedPNGData(from: rawBytes) {
            return normalized
        }

        let candidateStrings = rawResult["candidates"] as? [String] ?? []
        let pageURLString = rawResult["pageURL"] as? String
        let refererURL = pageURLString.flatMap { URL(string: $0) } ?? webView.url

        for candidateString in candidateStrings {
            if candidateString.lowercased().hasPrefix("data:") {
                if let bytes = decodeDataURL(candidateString),
                   let normalized = normalizedPNGData(from: bytes) {
                    return normalized
                }
                continue
            }
            guard let candidateURL = URL(string: candidateString) else { continue }
            if let png = await downloadAndNormalizeIcon(from: candidateURL, referer: refererURL) {
                return png
            }
        }

        return nil
    }

    // MARK: - Descarga Directa (Marcadores Nuevos / No Abiertos Aún)

    /// Descarga y normaliza el favicon para una URL objetivo intentando:
    /// 1) HTML `<link rel="...icon...">` / `<link rel="apple-touch-icon...">` de la página real (siguiendo redirecciones),
    /// 2) `/favicon.ico` y `/apple-touch-icon.png` del origen final y original,
    /// 3) DuckDuckGo Icons API y Google S2 Favicons con URL completa (descartando 404).
    public static func fetchDirectFaviconData(for targetURL: URL) async -> Data? {
        var candidates: [URL] = []
        var refererURL = targetURL

        if let htmlFetch = await fetchHTMLDocument(for: targetURL) {
            refererURL = htmlFetch.finalURL
            candidates.append(contentsOf: parseHTMLIconCandidates(html: htmlFetch.html, baseURL: htmlFetch.finalURL))
        }

        appendOriginFallbacks(for: targetURL, into: &candidates)

        var visited = Set<String>()
        for candidate in candidates {
            let key = candidate.absoluteString
            guard visited.insert(key).inserted else { continue }
            if key.lowercased().hasPrefix("data:") {
                if let raw = decodeDataURL(key), let png = normalizedPNGData(from: raw) {
                    return png
                }
                continue
            }
            if let png = await downloadAndNormalizeIcon(from: candidate, referer: refererURL) {
                return png
            }
        }

        // Respaldo externo (útil para sitios SPA protegidos por anti-bot cuando el usuario aún no abrió la pestaña)
        let hostForFallback = refererURL.host ?? targetURL.host ?? ""
        if !hostForFallback.isEmpty,
           let encodedHost = hostForFallback.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let ddgURL = URL(string: "https://icons.duckduckgo.com/ip3/\(encodedHost).ico"),
           let png = await downloadAndNormalizeIcon(from: ddgURL, referer: nil) {
            return png
        }

        let targetWithScheme = refererURL.scheme == nil
            ? URL(string: "https://\(hostForFallback)") ?? targetURL
            : refererURL
        var googleComponents = URLComponents(string: "https://www.google.com/s2/favicons")
        googleComponents?.queryItems = [
            URLQueryItem(name: "sz", value: "64"),
            URLQueryItem(name: "domain_url", value: targetWithScheme.absoluteString)
        ]
        if let googleURL = googleComponents?.url,
           let png = await downloadAndNormalizeIcon(from: googleURL, referer: nil) {
            return png
        }

        return nil
    }

    // MARK: - Parser HTML de `<link>` de Favicon

    /// Extrae y ordena por prioridad las URLs candidatas de favicon desde código HTML.
    public static func parseHTMLIconCandidates(html: String, baseURL: URL) -> [URL] {
        guard let linkRegex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive]) else {
            var fallback: [URL] = []
            appendOriginFallbacks(for: baseURL, into: &fallback)
            return fallback
        }

        let nsHTML = html as NSString
        let matches = linkRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

        struct ScoredCandidate {
            let url: URL
            let score: Int
            let order: Int
        }

        var scored: [ScoredCandidate] = []
        for (idx, match) in matches.enumerated() {
            let tag = nsHTML.substring(with: match.range)
            let attrs = parseHTMLAttributes(in: tag)
            guard let relRaw = attrs["rel"], let hrefRaw = attrs["href"] else { continue }

            let hrefTrimmed = decodeBasicHTMLEntities(hrefRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hrefTrimmed.isEmpty else { continue }

            let relTokens = Set(
                relRaw.lowercased()
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
            )
            let isStandardIcon = relTokens.contains("icon")
            let isAppleTouch = relTokens.contains("apple-touch-icon") || relTokens.contains("apple-touch-icon-precomposed")
            guard isStandardIcon || isAppleTouch else { continue }

            let resolvedURL: URL?
            if hrefTrimmed.lowercased().hasPrefix("data:image/") {
                resolvedURL = URL(string: hrefTrimmed)
            } else {
                resolvedURL = URL(string: hrefTrimmed, relativeTo: baseURL)?.absoluteURL
            }
            guard let finalCandidateURL = resolvedURL else { continue }

            let score = scoreIconLink(
                isStandardIcon: isStandardIcon,
                type: attrs["type"],
                sizes: attrs["sizes"],
                href: hrefTrimmed
            )
            scored.append(ScoredCandidate(url: finalCandidateURL, score: score, order: idx))
        }

        scored.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.order < $1.order
        }

        var result: [URL] = []
        var seen = Set<String>()
        for entry in scored {
            if seen.insert(entry.url.absoluteString).inserted {
                result.append(entry.url)
            }
        }

        appendOriginFallbacks(for: baseURL, into: &result)
        return result
    }

    private static func appendOriginFallbacks(for url: URL, into list: inout [URL]) {
        guard let scheme = url.scheme, let host = url.host,
              scheme.lowercased() == "http" || scheme.lowercased() == "https" else {
            return
        }
        var originComponents = URLComponents()
        originComponents.scheme = scheme
        originComponents.host = host
        originComponents.port = url.port

        for path in ["/favicon.ico", "/apple-touch-icon.png"] {
            var comps = originComponents
            comps.path = path
            if let fallbackURL = comps.url, !list.contains(fallbackURL) {
                list.append(fallbackURL)
            }
        }
    }

    private static func scoreIconLink(isStandardIcon: Bool, type: String?, sizes: String?, href: String) -> Int {
        var score = isStandardIcon ? 100 : 80
        let lowerType = (type ?? "").lowercased()
        let lowerHref = href.lowercased()

        if lowerType.contains("png") || lowerHref.contains(".png") {
            score += 20
        } else if lowerType.contains("svg") || lowerHref.contains(".svg") {
            score += 15
        } else if lowerType.contains("webp") || lowerHref.contains(".webp") {
            score += 12
        } else if lowerType.contains("icon") || lowerHref.contains(".ico") {
            score += 5
        }

        let lowerSizes = (sizes ?? "").lowercased()
        if lowerSizes.contains("any") {
            score += 25
        } else if !lowerSizes.isEmpty,
                  let sizeRegex = try? NSRegularExpression(pattern: #"(\d+)\s*x\s*(\d+)"#, options: []) {
            let nsSizes = lowerSizes as NSString
            let matches = sizeRegex.matches(in: lowerSizes, options: [], range: NSRange(location: 0, length: nsSizes.length))
            var bestDim = 0
            for m in matches where m.numberOfRanges >= 2 {
                let dim = Int(nsSizes.substring(with: m.range(at: 1))) ?? 0
                bestDim = max(bestDim, dim)
            }
            if bestDim >= 48 && bestDim <= 192 {
                score += 30
            } else if bestDim >= 32 && bestDim < 48 {
                score += 22
            } else if bestDim > 192 {
                score += 18
            } else if bestDim >= 16 {
                score += 5
            }
        }
        return score
    }

    private static func parseHTMLAttributes(in tag: String) -> [String: String] {
        guard let attrRegex = try? NSRegularExpression(
            pattern: #"([a-zA-Z0-9:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            options: []
        ) else {
            return [:]
        }
        let nsTag = tag as NSString
        let matches = attrRegex.matches(in: tag, options: [], range: NSRange(location: 0, length: nsTag.length))
        var dict: [String: String] = [:]
        for m in matches where m.numberOfRanges >= 5 {
            let key = nsTag.substring(with: m.range(at: 1)).lowercased()
            let val: String
            if m.range(at: 2).location != NSNotFound {
                val = nsTag.substring(with: m.range(at: 2))
            } else if m.range(at: 3).location != NSNotFound {
                val = nsTag.substring(with: m.range(at: 3))
            } else if m.range(at: 4).location != NSNotFound {
                val = nsTag.substring(with: m.range(at: 4))
            } else {
                val = ""
            }
            dict[key] = val
        }
        return dict
    }

    private static func decodeBasicHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&")
    }

    // MARK: - Helpers HTTP

    private static func fetchHTMLDocument(for url: URL) async -> (html: String, finalURL: URL)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse,
                  (200...299).contains(httpResp.statusCode) else {
                return nil
            }
            let mime = (httpResp.mimeType ?? "").lowercased()
            if !mime.isEmpty && !mime.contains("html") && !mime.contains("xml") {
                return nil
            }
            let maxBytes = min(data.count, 512 * 1024)
            let prefixData = data.prefix(maxBytes)
            guard let html = String(data: prefixData, encoding: .utf8) ?? String(data: prefixData, encoding: .isoLatin1) else {
                return nil
            }
            return (html, httpResp.url ?? url)
        } catch {
            return nil
        }
    }

    private static func downloadAndNormalizeIcon(from url: URL, referer: URL?) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200 else {
                return nil
            }
            return normalizedPNGData(from: data)
        } catch {
            return nil
        }
    }
}
