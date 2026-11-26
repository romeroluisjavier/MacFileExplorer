import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import ImageIO
import Observation

// MARK: - Extractor de Color Dominante Vibrante de Carátulas

/// Extrae en < 1 ms un color vibrante dominante de la carátula para el brillo ambiental del Notch.
/// Opera completamente sobre `Data` / `CGImage` fuera del hilo principal sin bloquear la UI.
public enum NotchDominantColorExtractor {

    public nonisolated static func extractVibrantColor(
        from imageData: Data?,
        fallback: NotchRGBColor = .defaultAccent
    ) -> NotchRGBColor {
        guard let imageData, !imageData.isEmpty else { return fallback }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return fallback
        }
        return extractVibrantColor(from: cgImage, fallback: fallback)
    }

    @MainActor
    public static func extractVibrantColor(
        from nsImage: NSImage?,
        fallback: NotchRGBColor = .defaultAccent
    ) -> NotchRGBColor {
        guard let nsImage else { return fallback }
        var rect = NSRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return fallback
        }
        return extractVibrantColor(from: cgImage, fallback: fallback)
    }

    public nonisolated static func extractVibrantColor(
        from cgImage: CGImage,
        fallback: NotchRGBColor = .defaultAccent
    ) -> NotchRGBColor {
        let side = 16
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return fallback
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // 18 cubetas de matiz (cada 20°) ponderadas por saturación y brillo agradable.
        let bucketCount = 18
        var bucketWeight = [Double](repeating: 0, count: bucketCount)
        var bucketR = [Double](repeating: 0, count: bucketCount)
        var bucketG = [Double](repeating: 0, count: bucketCount)
        var bucketB = [Double](repeating: 0, count: bucketCount)

        var fallbackWeight: Double = 0
        var fallbackR: Double = 0
        var fallbackG: Double = 0
        var fallbackB: Double = 0

        for idx in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = Double(pixels[idx + 3]) / 255.0
            guard alpha > 0.25 else { continue }

            let r = min(Double(pixels[idx]) / 255.0 / alpha, 1.0)
            let g = min(Double(pixels[idx + 1]) / 255.0 / alpha, 1.0)
            let b = min(Double(pixels[idx + 2]) / 255.0 / alpha, 1.0)

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let delta = maxC - minC
            let value = maxC
            let saturation = maxC > 0.001 ? (delta / maxC) : 0.0

            // Acumular media de respaldo para carátulas monocromáticas.
            if value > 0.14 && value < 0.94 {
                let w = 0.5 + (1.0 - abs(value - 0.55))
                fallbackWeight += w
                fallbackR += r * w
                fallbackG += g * w
                fallbackB += b * w
            }

            // Ignorar negros muy oscuros, blancos lavados y grises apagados en el cálculo vibrante.
            guard value >= 0.16, saturation >= 0.16 else { continue }
            guard !(value > 0.93 && saturation < 0.22) else { continue }

            var hue: Double = 0
            if delta > 0.0001 {
                if maxC == r {
                    hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
                } else if maxC == g {
                    hue = ((b - r) / delta) + 2.0
                } else {
                    hue = ((r - g) / delta) + 4.0
                }
                hue /= 6.0
                if hue < 0 { hue += 1.0 }
            }

            let bucketIndex = min(Int(hue * Double(bucketCount)), bucketCount - 1)
            let luminanceBell = 1.0 - abs(value - 0.62) * 0.85
            let weight = pow(saturation, 1.65) * max(0.25, luminanceBell)

            bucketWeight[bucketIndex] += weight
            bucketR[bucketIndex] += r * weight
            bucketG[bucketIndex] += g * weight
            bucketB[bucketIndex] += b * weight
        }

        var bestIndex = -1
        var bestWeight: Double = 0
        for i in 0..<bucketCount where bucketWeight[i] > bestWeight {
            bestWeight = bucketWeight[i]
            bestIndex = i
        }

        let rawR: Double
        let rawG: Double
        let rawB: Double

        if bestIndex >= 0, bestWeight > 0.15 {
            rawR = bucketR[bestIndex] / bestWeight
            rawG = bucketG[bestIndex] / bestWeight
            rawB = bucketB[bestIndex] / bestWeight
        } else if fallbackWeight > 0.01 {
            rawR = fallbackR / fallbackWeight
            rawG = fallbackG / fallbackWeight
            rawB = fallbackB / fallbackWeight
        } else {
            return fallback
        }

        return tuneForAmbientGlow(r: rawR, g: rawG, b: rawB)
    }

    /// Ajusta suavemente saturación y brillo para que el brillo ambiental resalte sobre fondo negro `#000000`.
    private nonisolated static func tuneForAmbientGlow(r: Double, g: Double, b: Double) -> NotchRGBColor {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var h: Double = 0
        if delta > 0.0001 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
            } else if maxC == g {
                h = ((b - r) / delta) + 2.0
            } else {
                h = ((r - g) / delta) + 4.0
            }
            h /= 6.0
            if h < 0 { h += 1.0 }
        }

        let s = maxC > 0.001 ? delta / maxC : 0
        let v = maxC

        let tunedS = s > 0.08 ? min(max(s * 1.15, 0.42), 0.92) : s
        let tunedV = min(max(v, 0.48), 0.90)

        let c = tunedV * tunedS
        let x = c * (1.0 - abs((h * 6.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = tunedV - c

        let (pr, pg, pb): (Double, Double, Double)
        switch h * 6.0 {
        case 0..<1: (pr, pg, pb) = (c, x, 0)
        case 1..<2: (pr, pg, pb) = (x, c, 0)
        case 2..<3: (pr, pg, pb) = (0, c, x)
        case 3..<4: (pr, pg, pb) = (0, x, c)
        case 4..<5: (pr, pg, pb) = (x, 0, c)
        default: (pr, pg, pb) = (c, 0, x)
        }

        return NotchRGBColor(r: pr + m, g: pg + m, b: pb + m)
    }
}

// MARK: - Servicio Unificado de Letras Sincronizadas (LRCLIB) y Audio (CoreAudio)

/// Gestiona:
/// 1. Letras sincronizadas vía LRCLIB (`https://lrclib.net/api/get` con respaldo `/api/search`), parseo LRC,
///    caché positivo y negativo, letras integradas para modo Demo y cálculo rápido de la línea activa.
/// 2. Listado en vivo y cambio en 1 clic de dispositivos de salida de audio mediante CoreAudio HAL.
@MainActor
@Observable
public final class NotchLyricsAndAudioService {

    public static let shared = NotchLyricsAndAudioService()

    // MARK: - Estado Observable de Letras

    public private(set) var lyricsState: NotchLyricsState = .idle
    public private(set) var currentLyricsTrackKey: String?

    public var syncedLines: [NotchLyricLine] {
        if case .synced(let lines) = lyricsState { return lines }
        return []
    }

    public var plainLines: [String] {
        if case .plain(let lines) = lyricsState { return lines }
        return []
    }

    public var isLoadingLyrics: Bool {
        lyricsState == .loading
    }

    // MARK: - Estado Observable de Dispositivos de Audio

    public private(set) var outputDevices: [NotchAudioOutputDevice] = []
    public private(set) var defaultOutputDevice: NotchAudioOutputDevice?

    // MARK: - Estado Interno

    private struct LyricsCacheEntry: Sendable {
        let state: NotchLyricsState
        let cachedAt: Date
    }

    private var lyricsCache: [String: LyricsCacheEntry] = [:]
    private let maxLyricsCacheEntries = 200
    private let negativeCacheTTL: TimeInterval = 15 * 60
    private var lyricsFetchTask: Task<Void, Never>?

    private var isAudioMonitoringInstalled = false
    private let audioListenerQueue = DispatchQueue(label: "com.macfileexplorer.notch.coreaudio", qos: .utility)
    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?

    private nonisolated static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 10.0
        config.httpAdditionalHeaders = [
            "User-Agent": "MacFileExplorer-Notch/1.0 (https://github.com/romeroluisjavier/MacFileExplorer)"
        ]
        return URLSession(configuration: config)
    }()

    private init() {
        refreshOutputDevices()
    }

    // MARK: - API Pública de Letras Sincronizadas

    /// Actualiza las letras para la pista indicada (con deduplicación, caché positivo/negativo y soporte offline Demo).
    public func updateLyrics(for track: NotchTrackInfo?) {
        guard let track, !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearLyrics()
            return
        }

        // Las pistas del modo Demo siempre cargan letras sincronizadas instantáneas sin red.
        if let demoLines = Self.demoLyrics(forTrackID: track.id) {
            lyricsFetchTask?.cancel()
            lyricsFetchTask = nil
            currentLyricsTrackKey = track.trackLookupKey
            lyricsState = .synced(demoLines)
            return
        }

        guard NotchPreferences.shared.showSyncedLyrics else {
            lyricsFetchTask?.cancel()
            lyricsFetchTask = nil
            if currentLyricsTrackKey != track.trackLookupKey {
                currentLyricsTrackKey = track.trackLookupKey
                lyricsState = .idle
            }
            return
        }

        let key = track.trackLookupKey
        if currentLyricsTrackKey == key {
            switch lyricsState {
            case .synced, .plain, .instrumental, .loading:
                return
            case .idle, .unavailable:
                break
            }
        }

        currentLyricsTrackKey = key

        if let cached = lyricsCache[key] {
            if cached.state == .unavailable {
                if Date().timeIntervalSince(cached.cachedAt) < negativeCacheTTL {
                    lyricsState = .unavailable
                    return
                }
            } else {
                lyricsState = cached.state
                return
            }
        }

        lyricsFetchTask?.cancel()
        lyricsState = .loading

        let title = track.title
        let artist = track.artist
        let album = track.album
        let duration = track.duration

        lyricsFetchTask = Task.detached(priority: .utility) { [key, title, artist, album, duration] in
            let fetched = await Self.fetchLyricsFromLRCLIB(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let service = NotchLyricsAndAudioService.shared
                service.storeLyricsCache(fetched, forKey: key)
                if service.currentLyricsTrackKey == key {
                    service.lyricsState = fetched
                }
            }
        }
    }

    public func clearLyrics() {
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        currentLyricsTrackKey = nil
        lyricsState = .idle
    }

    /// Devuelve el índice de la línea sincronizada activa para el tiempo transcurrido actual.
    public func activeLyricLineIndex(at elapsedTime: TimeInterval, leadOffset: TimeInterval = 0.25) -> Int? {
        guard case .synced(let lines) = lyricsState else { return nil }
        return Self.activeLineIndex(in: lines, at: elapsedTime, leadOffset: leadOffset)
    }

    /// Devuelve la línea sincronizada activa para el tiempo transcurrido actual.
    public func activeLyricLine(at elapsedTime: TimeInterval, leadOffset: TimeInterval = 0.25) -> NotchLyricLine? {
        guard case .synced(let lines) = lyricsState,
              let idx = Self.activeLineIndex(in: lines, at: elapsedTime, leadOffset: leadOffset),
              lines.indices.contains(idx) else {
            return nil
        }
        return lines[idx]
    }

    /// Búsqueda binaria O(log n) de la línea LRC activa para un `elapsedTime` dado.
    public nonisolated static func activeLineIndex(
        in lines: [NotchLyricLine],
        at elapsedTime: TimeInterval,
        leadOffset: TimeInterval = 0.25
    ) -> Int? {
        guard !lines.isEmpty else { return nil }
        let target = elapsedTime + leadOffset
        if target < lines[0].time {
            return nil
        }
        var low = 0
        var high = lines.count - 1
        var result = 0
        while low <= high {
            let mid = low + (high - low) / 2
            if lines[mid].time <= target {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// Parsea texto LRC estándar y extendido (`[mm:ss.xx]`, `[mm:ss.xxx]`, múltiples marcas por línea, `<mm:ss.xx>`).
    public nonisolated static func parseLRC(_ lrc: String) -> [NotchLyricLine] {
        var rawItems: [(time: TimeInterval, text: String)] = []
        let timestampPattern = #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
        let inlineWordTagPattern = #"<\d{1,3}:\d{2}(?:[\.:]\d{1,3})?>"#

        guard let tsRegex = try? NSRegularExpression(pattern: timestampPattern) else {
            return []
        }
        let inlineRegex = try? NSRegularExpression(pattern: inlineWordTagPattern)

        for rawLine in lrc.components(separatedBy: .newlines) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            let nsLine = trimmedLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = tsRegex.matches(in: trimmedLine, range: fullRange)
            guard !matches.isEmpty else { continue }

            var strippedText = tsRegex.stringByReplacingMatches(in: trimmedLine, range: fullRange, withTemplate: "")
            if let inlineRegex {
                let r = NSRange(location: 0, length: (strippedText as NSString).length)
                strippedText = inlineRegex.stringByReplacingMatches(in: strippedText, range: r, withTemplate: "")
            }
            let cleanText = strippedText
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanText.isEmpty else { continue }

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                guard let minutes = Double(minStr), let seconds = Double(secStr) else { continue }

                var fraction: Double = 0
                if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                    let fracStr = nsLine.substring(with: match.range(at: 3))
                    if let fracVal = Double(fracStr) {
                        switch fracStr.count {
                        case 1: fraction = fracVal / 10.0
                        case 2: fraction = fracVal / 100.0
                        default: fraction = fracVal / 1000.0
                        }
                    }
                }

                let time = minutes * 60.0 + seconds + fraction
                rawItems.append((time: time, text: cleanText))
            }
        }

        rawItems.sort { $0.time < $1.time }

        return rawItems.enumerated().map { index, item in
            NotchLyricLine(
                id: "\(index)-\(Int((item.time * 100).rounded()))",
                time: item.time,
                text: item.text
            )
        }
    }

    private func storeLyricsCache(_ state: NotchLyricsState, forKey key: String) {
        if lyricsCache.count >= maxLyricsCacheEntries {
            let sortedOldest = lyricsCache.sorted { $0.value.cachedAt < $1.value.cachedAt }
            for entry in sortedOldest.prefix(maxLyricsCacheEntries / 4) {
                lyricsCache.removeValue(forKey: entry.key)
            }
        }
        lyricsCache[key] = LyricsCacheEntry(state: state, cachedAt: Date())
    }

    // MARK: - Cliente HTTP LRCLIB

    private struct LRCLIBRecord: Decodable, Sendable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private nonisolated static func fetchLyricsFromLRCLIB(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> NotchLyricsState {
        let cleanTitle = sanitizeTrackTitle(title)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Intento exacto /api/get cuando tenemos título y artista.
        if !cleanTitle.isEmpty, !cleanArtist.isEmpty {
            if let record = await queryLRCLIBGet(
                title: cleanTitle,
                artist: cleanArtist,
                album: album.isEmpty ? nil : album,
                duration: duration > 5 ? duration : nil
            ), let state = convertLRCLIBRecord(record) {
                return state
            }

            // Reintentar sin álbum/duración por si YouTube Music tiene distinta duración de versión.
            if !album.isEmpty || duration > 5 {
                if let record = await queryLRCLIBGet(
                    title: cleanTitle,
                    artist: cleanArtist,
                    album: nil,
                    duration: nil
                ), let state = convertLRCLIBRecord(record) {
                    return state
                }
            }
        }

        // 2. Respaldo inteligente con /api/search (útil para títulos de navegador o variaciones de artista).
        if !cleanTitle.isEmpty {
            let query = cleanArtist.isEmpty ? cleanTitle : "\(cleanTitle) \(cleanArtist)"
            if let best = await queryLRCLIBSearch(
                query: query,
                expectedTitle: cleanTitle,
                expectedArtist: cleanArtist,
                expectedDuration: duration
            ), let state = convertLRCLIBRecord(best) {
                return state
            }
        }

        return .unavailable
    }

    private nonisolated static func queryLRCLIBGet(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval?
    ) async -> LRCLIBRecord? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration, duration > 5 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(LRCLIBRecord.self, from: data)
        } catch {
            return nil
        }
    }

    private nonisolated static func queryLRCLIBSearch(
        query: String,
        expectedTitle: String,
        expectedArtist: String,
        expectedDuration: TimeInterval
    ) async -> LRCLIBRecord? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)
            guard !records.isEmpty else { return nil }

            let lowerTitle = expectedTitle.lowercased()
            let lowerArtist = expectedArtist.lowercased()

            return records
                .map { record -> (record: LRCLIBRecord, score: Int) in
                    var score = 0
                    if let synced = record.syncedLyrics, !synced.isEmpty { score += 50 }
                    else if let plain = record.plainLyrics, !plain.isEmpty { score += 15 }

                    let rTitle = (record.trackName ?? "").lowercased()
                    let rArtist = (record.artistName ?? "").lowercased()

                    if rTitle == lowerTitle { score += 40 }
                    else if rTitle.contains(lowerTitle) || lowerTitle.contains(rTitle) { score += 20 }

                    if !lowerArtist.isEmpty {
                        if rArtist == lowerArtist { score += 35 }
                        else if rArtist.contains(lowerArtist) || lowerArtist.contains(rArtist) { score += 18 }
                    }

                    if expectedDuration > 5, let rDur = record.duration {
                        let diff = abs(rDur - expectedDuration)
                        if diff <= 3 { score += 20 }
                        else if diff <= 8 { score += 10 }
                        else if diff > 30 { score -= 15 }
                    }
                    return (record, score)
                }
                .filter { $0.score >= 30 }
                .max(by: { $0.score < $1.score })?
                .record
        } catch {
            return nil
        }
    }

    private nonisolated static func convertLRCLIBRecord(_ record: LRCLIBRecord) -> NotchLyricsState? {
        if let synced = record.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = parseLRC(synced)
            if !parsed.isEmpty {
                return .synced(parsed)
            }
        }
        if record.instrumental == true {
            return .instrumental
        }
        if let plain = record.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                return .plain(lines)
            }
        }
        return nil
    }

    private nonisolated static func sanitizeTrackTitle(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"\s*\((?:Official|Music|Lyric|Audio|HD|4K|Live)[^)]*\)"#,
            #"\s*\[(?:Official|Music|Lyric|Audio|HD|4K|Live)[^\]]*\]"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (cleaned as NSString).length)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Letras Sincronizadas Integradas para Modo Demo

    private static func demoLyrics(forTrackID id: String) -> [NotchLyricLine]? {
        switch id {
        case "demo-midnight-pulse":
            return parseLRC("""
            [00:08.00]City lights blur through the midnight glass
            [00:15.50]Shadows dancing as the sirens pass
            [00:23.00]Neon echoes in the quiet rain
            [00:30.50]Every rhythm pulling us again
            [00:38.00]Feel the bassline rising in the dark
            [00:44.00]Glowing softly like a distant spark
            [00:51.00]Hold the moment while the colors bloom
            [00:58.50]Floating weightless in a velvet room
            [01:06.00]Midnight pulse, don't let the music fade
            [01:14.00]Tracing starlight in the waves we made
            [01:22.00]Turn the dial up to the skyline haze
            [01:30.00]Lost together in a golden phase
            [01:39.00]Drifting slowly past the avenue
            [01:47.50]Every frequency is painted blue
            [01:56.00]Let the echo carry through the night
            [02:05.00]Till the morning turns the skyline bright
            """)
        case "demo-velvet-skyline":
            return parseLRC("""
            [00:06.00]Emerald skies above the quiet bay
            [00:14.00]Cool horizons wash the noise away
            [00:22.00]Soft reflections on the harbor glass
            [00:30.00]Counting seconds as the evening lasts
            [00:38.50]Breathe the melody into the air
            [00:46.00]Weightless chords are floating everywhere
            [00:54.50]Velvet skyline shining over me
            [01:03.00]Every heartbeat moving effortlessly
            [01:12.00]Stay a little longer in this glow
            [01:21.00]Where the midnight currents gently flow
            [01:30.00]Silver moonlight on a quiet street
            [01:40.00]Finding rhythm in the steady beat
            """)
        case "demo-golden-hour":
            return parseLRC("""
            [00:10.00]Warm horizon melting into gold
            [00:18.50]Ocean breezes whispering untold
            [00:27.00]Amber sunlight drifting on the tide
            [00:36.00]Leave the hurry of the day behind
            [00:45.00]Slow motion waves along the coast
            [00:54.00]Golden hour is the song we love the most
            [01:03.00]Every color glowing soft and wide
            [01:12.00]Let the sunset be our only guide
            [01:22.00]Fading gently into twilight blue
            [01:32.00]Every melody comes back to you
            """)
        default:
            return nil
        }
    }

    // MARK: - Gestión de Dispositivos de Salida CoreAudio

    /// Inicia los listeners de CoreAudio para mantener los dispositivos de salida actualizados en vivo.
    public func startAudioDeviceMonitoring() {
        refreshOutputDevices()
        guard !isAudioMonitoringInstalled else { return }
        isAudioMonitoringInstalled = true

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let queue = audioListenerQueue

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devicesBlock: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                NotchLyricsAndAudioService.shared.refreshOutputDevices()
            }
        }
        devicesListenerBlock = devicesBlock
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, queue, devicesBlock)

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                NotchLyricsAndAudioService.shared.refreshOutputDevices()
            }
        }
        defaultOutputListenerBlock = defaultBlock
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultAddress, queue, defaultBlock)
    }

    /// Detiene los listeners de CoreAudio al desactivar Notch o cerrar la aplicación.
    public func stopAudioDeviceMonitoring() {
        guard isAudioMonitoringInstalled else { return }
        isAudioMonitoringInstalled = false

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        if let devicesBlock = devicesListenerBlock {
            var devicesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &devicesAddress, audioListenerQueue, devicesBlock)
            devicesListenerBlock = nil
        }
        if let defaultBlock = defaultOutputListenerBlock {
            var defaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &defaultAddress, audioListenerQueue, defaultBlock)
            defaultOutputListenerBlock = nil
        }
    }

    /// Refresca la lista de dispositivos de salida CoreAudio disponibles y el dispositivo predeterminado actual.
    public func refreshOutputDevices() {
        let fetched = Self.queryCoreAudioOutputDevices()
        if fetched != outputDevices {
            outputDevices = fetched
        }
        defaultOutputDevice = fetched.first(where: \.isDefault) ?? fetched.first
    }

    /// Cambia el dispositivo de salida predeterminado de macOS en 1 clic.
    @discardableResult
    public func setDefaultOutputDevice(_ device: NotchAudioOutputDevice) -> Bool {
        setDefaultOutputDevice(id: device.id)
    }

    /// Cambia el dispositivo de salida predeterminado de macOS por `AudioDeviceID`.
    @discardableResult
    public func setDefaultOutputDevice(id deviceID: AudioDeviceID) -> Bool {
        var mutableID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &mutableID
        )
        if status == noErr {
            refreshOutputDevices()
            return true
        }
        return false
    }

    /// Devuelve `true` si el dispositivo de salida predeterminado está reproduciendo audio actualmente en algún proceso.
    public nonisolated static func isDefaultOutputDeviceRunningAudio() -> Bool {
        var defaultDev: AudioDeviceID = 0
        var devSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            &devSize,
            &defaultDev
        ) == noErr, defaultDev != kAudioObjectUnknown else {
            return false
        }

        var isRunning: UInt32 = 0
        var runSize = UInt32(MemoryLayout<UInt32>.size)
        var runAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(defaultDev, &runAddr, 0, nil, &runSize, &isRunning)
        return status == noErr && isRunning != 0
    }

    private nonisolated static func queryCoreAudioOutputDevices() -> [NotchAudioOutputDevice] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        var defaultDeviceID: AudioDeviceID = kAudioObjectUnknown
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(systemObject, &defaultAddress, 0, nil, &defaultSize, &defaultDeviceID)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &devicesAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &devicesAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        var results: [NotchAudioOutputDevice] = []
        results.reserveCapacity(count)

        for devID in deviceIDs {
            guard outputChannelCount(for: devID) > 0 else { continue }
            guard !isHiddenAudioDevice(devID) else { continue }

            let name = copyStringProperty(selector: kAudioObjectPropertyName, for: devID) ?? "Audio Output"
            let uid = copyStringProperty(selector: kAudioDevicePropertyDeviceUID, for: devID) ?? "\(devID)"
            let rawTransport = copyUInt32Property(selector: kAudioDevicePropertyTransportType, for: devID) ?? 0
            let (transportLabel, sfSymbol) = classifyTransport(rawTransport, deviceName: name)

            results.append(
                NotchAudioOutputDevice(
                    id: devID,
                    uid: uid,
                    name: name,
                    isDefault: devID == defaultDeviceID,
                    transportType: transportLabel,
                    systemImage: sfSymbol
                )
            )
        }

        return results.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private nonisolated static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return 0
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawBuffer) == noErr else {
            return 0
        }

        let listPointer = UnsafeMutableAudioBufferListPointer(rawBuffer.assumingMemoryBound(to: AudioBufferList.self))
        return listPointer.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private nonisolated static func isHiddenAudioDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &hidden) == noErr else {
            return false
        }
        return hidden != 0
    }

    private nonisolated static func copyStringProperty(
        selector: AudioObjectPropertySelector,
        for deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfValue: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfValue)
        guard status == noErr, let value = cfValue?.takeRetainedValue() else {
            return nil
        }
        return value as String
    }

    private nonisolated static func copyUInt32Property(
        selector: AudioObjectPropertySelector,
        for deviceID: AudioDeviceID
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private nonisolated static func classifyTransport(_ transport: UInt32, deviceName: String) -> (String, String) {
        let lower = deviceName.lowercased()
        if lower.contains("airpods max") {
            return ("bluetooth", "airpodsmax")
        }
        if lower.contains("airpods pro") {
            return ("bluetooth", "airpodspro")
        }
        if lower.contains("airpods") {
            return ("bluetooth", "airpods")
        }
        if lower.contains("homepod") {
            return ("airPlay", "homepod.fill")
        }
        if lower.contains("headphone") || lower.contains("auricular") || lower.contains("beats") || lower.contains("sony wh") || lower.contains("bose") {
            return ("bluetooth", "headphones")
        }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return ("builtIn", "speaker.wave.2.fill")
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return ("bluetooth", "headphones")
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return ("hdmi", "display")
        case kAudioDeviceTransportTypeUSB:
            return ("usb", "cable.connector")
        case kAudioDeviceTransportTypeAirPlay:
            return ("airPlay", "airplayaudio")
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return ("virtual", "waveform.circle")
        default:
            return ("other", "speaker.wave.2.fill")
        }
    }
}
