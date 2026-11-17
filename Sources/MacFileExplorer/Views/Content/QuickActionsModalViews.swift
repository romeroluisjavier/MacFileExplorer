@preconcurrency import AVFoundation
import AVKit
import SwiftUI

/// Modal para convertir una o más imágenes a `.jpg` o `.png` con calidad, PPP (DPI), ancho y peso máximo en MB.
public struct QuickActionImageConvertModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    let targetURLs: [URL]
    @Environment(\.dismiss) private var dismiss

    @ViewState private var options = QuickActionImageConvertOptions()
    @ViewState private var isProcessing = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel, targetURLs: [URL]) {
        self.viewModel = viewModel
        self.targetURLs = targetURLs
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.arrow.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(es: "Convertir imagen(es)", en: "Convert Image(s)"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(loc.text(
                        es: "\(targetURLs.count) archivo(s) seleccionado(s)",
                        en: "\(targetURLs.count) file(s) selected"
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            Form {
                Picker(loc.text(es: "Formato de salida:", en: "Output format:"), selection: $options.format) {
                    ForEach(QuickActionImageFormat.allCases) { format in
                        Text(format.displayTitle).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if options.format == .jpg {
                    HStack {
                        Text(loc.text(es: "Calidad JPG:", en: "JPG Quality:"))
                        Slider(value: $options.quality, in: 0.1...1.0, step: 0.05)
                        Text("\(Int((options.quality * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                HStack {
                    Text(loc.text(es: "Resolución (PPP / DPI):", en: "Resolution (DPI):"))
                    Spacer()
                    Picker("", selection: $options.dpi) {
                        Text("72 PPP (Pantalla)").tag(72)
                        Text("150 PPP (Web/Doc)").tag(150)
                        Text("300 PPP (Impresión)").tag(300)
                    }
                    .frame(width: 190)
                }

                Toggle(
                    loc.text(es: "Mantener tamaño original", en: "Keep original size"),
                    isOn: $options.keepOriginalSize
                )

                if !options.keepOriginalSize {
                    HStack {
                        Text(loc.text(es: "Ancho esperado (px):", en: "Target width (px):"))
                        Spacer()
                        TextField("1920", value: $options.targetWidth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(
                    loc.text(es: "Limitar peso máximo esperado (MB)", en: "Limit target file size (MB)"),
                    isOn: $options.useTargetMaxSizeMB
                )

                if options.useTargetMaxSizeMB {
                    HStack {
                        Text(loc.text(es: "Peso máximo (MB):", en: "Max size (MB):"))
                        Spacer()
                        TextField("1.0", value: $options.targetMaxSizeMB, format: .number.precision(.fractionLength(1...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("MB")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(loc.text(es: "Cancelar", en: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    isProcessing = true
                    let urls = targetURLs
                    let opts = options
                    Task { @MainActor in
                        do {
                            let created = try await QuickActionsService.convertImages(urls, options: opts)
                            await viewModel.reloadDirectoryAndSelect(created, startRenameOn: nil)
                            isProcessing = false
                            dismiss()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                            isProcessing = false
                        }
                    }
                } label: {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(loc.text(es: "Convertir", en: "Convert"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 470)
    }
}

/// Modal para convertir videos (`.mov`, etc.) a `.mp4` eligiendo calidad y peso máximo en MB.
public struct QuickActionVideoConvertModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    let targetURLs: [URL]
    @Environment(\.dismiss) private var dismiss

    @ViewState private var options = QuickActionVideoConvertOptions()
    @ViewState private var isProcessing = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel, targetURLs: [URL]) {
        self.viewModel = viewModel
        self.targetURLs = targetURLs
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(es: "Convertir video(s) a MP4", en: "Convert Video(s) to MP4"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(loc.text(
                        es: "\(targetURLs.count) video(s) seleccionado(s)",
                        en: "\(targetURLs.count) video(s) selected"
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            Form {
                Picker(loc.text(es: "Calidad de exportación:", en: "Export quality:"), selection: $options.quality) {
                    ForEach(QuickActionVideoQuality.allCases) { quality in
                        Text(quality.localizedTitle(using: loc)).tag(quality)
                    }
                }

                Toggle(
                    loc.text(es: "Limitar peso máximo esperado (MB)", en: "Limit target file size (MB)"),
                    isOn: $options.useTargetMaxSizeMB
                )

                if options.useTargetMaxSizeMB {
                    HStack {
                        Text(loc.text(es: "Peso máximo (MB):", en: "Max size (MB):"))
                        Spacer()
                        TextField("10.0", value: $options.targetMaxSizeMB, format: .number.precision(.fractionLength(1...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("MB")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(loc.text(es: "Cancelar", en: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    isProcessing = true
                    let urls = targetURLs
                    let opts = options
                    Task { @MainActor in
                        do {
                            let created = try await QuickActionsService.convertVideosToMP4(urls, options: opts)
                            await viewModel.reloadDirectoryAndSelect(created, startRenameOn: nil)
                            isProcessing = false
                            dismiss()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                            isProcessing = false
                        }
                    }
                } label: {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(loc.text(es: "Convertir a MP4", en: "Convert to MP4"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 450)
    }
}

/// Modal para recortar (Trim) un video con vista previa en vivo, milisegundos, zoom de línea de tiempo y Fade In / Fade Out.
public struct QuickActionVideoTrimModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    let targetURL: URL
    @Environment(\.dismiss) private var dismiss

    @ViewState private var player: AVPlayer? = nil
    @ViewState private var durationSeconds: Double = 10.0
    @ViewState private var startSeconds: Double = 0.0
    @ViewState private var endSeconds: Double = 10.0
    @ViewState private var timelineZoom: Double = 1.0
    @ViewState private var fadeInSeconds: Double = 0.0
    @ViewState private var fadeOutSeconds: Double = 0.0
    @ViewState private var isLoaded = false
    @ViewState private var isProcessing = false
    @ViewState private var segmentStopTask: Task<Void, Never>? = nil

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel, targetURL: URL) {
        self.viewModel = viewModel
        self.targetURL = targetURL
    }

    private func zoomedRange(around anchor: Double) -> ClosedRange<Double> {
        let total = max(0.2, durationSeconds)
        guard timelineZoom > 1.0 else { return 0...total }
        let span = total / timelineZoom
        let half = span / 2.0
        var low = max(0, anchor - half)
        var high = min(total, low + span)
        if high - low < span {
            low = max(0, high - span)
        }
        if high <= low { high = min(total, low + 0.1) }
        return low...high
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "scissors")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(es: "Recortar video (Trim)", en: "Trim Video"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(targetURL.lastPathComponent)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isLoaded {
                    Picker("", selection: $timelineZoom) {
                        Text("1×").tag(1.0)
                        Text("2×").tag(2.0)
                        Text("5×").tag(5.0)
                        Text("10×").tag(10.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .help(loc.text(es: "Expandir línea de tiempo para mayor precisión", en: "Expand timeline for finer precision"))
                }

                if isLoaded, player != nil {
                    Button {
                        playSelectedSegment()
                    } label: {
                        Label(
                            loc.text(es: "Reproducir", en: "Play"),
                            systemImage: "play.fill"
                        )
                        .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Vista previa del video en vivo
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.9))

                if let player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ProgressView(loc.text(es: "Cargando video…", en: "Loading video…"))
                        .tint(.white)
                }
            }
            .frame(height: 290)

            if isLoaded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text(loc.text(es: "Inicio:", en: "Start:"))
                            .frame(width: 46, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { startSeconds },
                                set: { newVal in
                                    let clamped = min(newVal, max(0, endSeconds - 0.05))
                                    startSeconds = clamped
                                    seekPlayer(to: clamped)
                                }
                            ),
                            in: zoomedRange(around: startSeconds)
                        )
                        Button("-0.1s") {
                            let next = max(0, startSeconds - 0.1)
                            startSeconds = next
                            seekPlayer(to: next)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        Button("+0.1s") {
                            let next = min(max(0, endSeconds - 0.05), startSeconds + 0.1)
                            startSeconds = next
                            seekPlayer(to: next)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Text(formatTime(startSeconds))
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(width: 78, alignment: .trailing)

                        Button {
                            if let current = player?.currentTime() {
                                let secs = CMTimeGetSeconds(current)
                                if secs.isFinite {
                                    startSeconds = min(max(0, secs), max(0, endSeconds - 0.05))
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.left.to.line")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(loc.text(es: "Fijar inicio en la posición actual del video", en: "Set start to current playhead"))
                    }

                    HStack(spacing: 6) {
                        Text(loc.text(es: "Fin:", en: "End:"))
                            .frame(width: 46, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { endSeconds },
                                set: { newVal in
                                    let clamped = max(newVal, min(durationSeconds, startSeconds + 0.05))
                                    endSeconds = clamped
                                    seekPlayer(to: clamped)
                                }
                            ),
                            in: zoomedRange(around: endSeconds)
                        )
                        Button("-0.1s") {
                            let next = max(min(durationSeconds, startSeconds + 0.05), endSeconds - 0.1)
                            endSeconds = next
                            seekPlayer(to: next)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        Button("+0.1s") {
                            let next = min(durationSeconds, endSeconds + 0.1)
                            endSeconds = next
                            seekPlayer(to: next)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Text(formatTime(endSeconds))
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(width: 78, alignment: .trailing)

                        Button {
                            if let current = player?.currentTime() {
                                let secs = CMTimeGetSeconds(current)
                                if secs.isFinite {
                                    endSeconds = max(min(durationSeconds, secs), min(durationSeconds, startSeconds + 0.05))
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.right.to.line")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(loc.text(es: "Fijar fin en la posición actual del video", en: "Set end to current playhead"))
                    }

                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text(loc.text(es: "Fade In (negro):", en: "Fade In (black):"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $fadeInSeconds) {
                                Text("0s").tag(0.0)
                                Text("0.5s").tag(0.5)
                                Text("1.0s").tag(1.0)
                                Text("1.5s").tag(1.5)
                                Text("2.0s").tag(2.0)
                            }
                            .frame(width: 82)
                        }

                        HStack(spacing: 6) {
                            Text(loc.text(es: "Fade Out (negro):", en: "Fade Out (black):"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $fadeOutSeconds) {
                                Text("0s").tag(0.0)
                                Text("0.5s").tag(0.5)
                                Text("1.0s").tag(1.0)
                                Text("1.5s").tag(1.5)
                                Text("2.0s").tag(2.0)
                            }
                            .frame(width: 82)
                        }

                        Spacer()

                        Text(loc.text(
                            es: "Duración: \(formatTime(max(0, endSeconds - startSeconds)))",
                            en: "Duration: \(formatTime(max(0, endSeconds - startSeconds)))"
                        ))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button(loc.text(es: "Cancelar", en: "Cancel")) {
                    cleanupPlayer()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    cleanupPlayer()
                    isProcessing = true
                    let url = targetURL
                    let start = startSeconds
                    let end = endSeconds
                    let fIn = fadeInSeconds
                    let fOut = fadeOutSeconds
                    Task { @MainActor in
                        do {
                            let created = try await QuickActionsService.trimVideo(
                                url,
                                startSeconds: start,
                                endSeconds: end,
                                fadeInSeconds: fIn,
                                fadeOutSeconds: fOut
                            )
                            isProcessing = false
                            dismiss()
                            await viewModel.reloadDirectoryAndSelect([created], startRenameOn: nil)
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                            isProcessing = false
                        }
                    }
                } label: {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(loc.text(es: "Recortar y guardar", en: "Trim & Save"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isLoaded || isProcessing || endSeconds <= startSeconds)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 680)
        .task {
            let asset = AVURLAsset(url: targetURL)
            if let cmDuration = try? await asset.load(.duration) {
                let secs = max(0.5, CMTimeGetSeconds(cmDuration))
                durationSeconds = secs
                startSeconds = 0
                endSeconds = secs
            }
            player = AVPlayer(url: targetURL)
            isLoaded = true
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func seekPlayer(to seconds: Double) {
        segmentStopTask?.cancel()
        player?.pause()
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 1000)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func playSelectedSegment() {
        guard let player else { return }
        segmentStopTask?.cancel()
        let start = CMTime(seconds: max(0, startSeconds), preferredTimescale: 1000)
        let segmentDuration = max(0.05, endSeconds - startSeconds)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                player.play()
            }
        }
        segmentStopTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(segmentDuration))
            if !Task.isCancelled {
                player.pause()
            }
        }
    }

    private func cleanupPlayer() {
        segmentStopTask?.cancel()
        segmentStopTask = nil
        player?.pause()
        player = nil
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let mins = Int(total) / 60
        let secs = Int(total) % 60
        let millis = Int((total - Double(Int(total))) * 1000.0)
        return String(format: "%02d:%02d.%03d", mins, secs, millis)
    }
}
