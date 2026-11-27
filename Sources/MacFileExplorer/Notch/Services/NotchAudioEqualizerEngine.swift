import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import Observation
import os

// MARK: - Banco Lock-Free de Filtros Biquad de 5 Bandas (Real-Time Audio Safe)

/// Coeficientes normalizados de un filtro IIR Biquad (Direct Form II Transposed).
private struct BiquadCoefficients: Sendable {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    static let identity = BiquadCoefficients()

    /// Calcula coeficientes RBJ Audio EQ Cookbook para LowShelf, PeakingEQ o HighShelf.
    static func make(
        bandIndex: Int,
        frequency: Double,
        gainDB: Double,
        sampleRate: Double
    ) -> BiquadCoefficients {
        guard sampleRate > 1000, abs(gainDB) >= 0.05 else {
            return .identity
        }
        let nyquist = sampleRate * 0.45
        let clampedFreq = min(max(frequency, 20.0), nyquist)
        let clampedGain = min(max(gainDB, -12.0), 12.0)

        let A = pow(10.0, clampedGain / 40.0)
        let w0 = 2.0 * Double.pi * clampedFreq / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)

        let b0: Double
        let b1: Double
        let b2: Double
        let a0: Double
        let a1: Double
        let a2: Double

        if bandIndex == 0 {
            // 60 Hz — Low Shelf (pendiente musical S = 0.85)
            let S = 0.85
            let alpha = sinW0 / 2.0 * sqrt((A + 1.0 / A) * (1.0 / S - 1.0) + 2.0)
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha)
            b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0)
            b2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha)
            a0 = (A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha
            a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0)
            a2 = (A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha
        } else if bandIndex == 4 {
            // 12 kHz — High Shelf (pendiente musical S = 0.85)
            let S = 0.85
            let alpha = sinW0 / 2.0 * sqrt((A + 1.0 / A) * (1.0 / S - 1.0) + 2.0)
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha)
            b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0)
            b2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha)
            a0 = (A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha
            a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0)
            a2 = (A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha
        } else {
            // 250 Hz, 1 kHz, 4 kHz — Peaking EQ (Q musical = 1.1)
            let Q = 1.1
            let alpha = sinW0 / (2.0 * Q)
            b0 = 1.0 + alpha * A
            b1 = -2.0 * cosW0
            b2 = 1.0 - alpha * A
            a0 = 1.0 + alpha / A
            a1 = -2.0 * cosW0
            a2 = 1.0 - alpha / A
        }

        guard abs(a0) > 1e-9 else { return .identity }
        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }
}

/// Bloque contiguo de 5 filtros Biquad (value-type puro, cero heap/ARC en el hilo de audio).
private struct FiveBandCoefficients: Sendable {
    var b0: BiquadCoefficients = .identity
    var b1: BiquadCoefficients = .identity
    var b2: BiquadCoefficients = .identity
    var b3: BiquadCoefficients = .identity
    var b4: BiquadCoefficients = .identity

    subscript(index: Int) -> BiquadCoefficients {
        get {
            switch index {
            case 0: return b0
            case 1: return b1
            case 2: return b2
            case 3: return b3
            default: return b4
            }
        }
        set {
            switch index {
            case 0: b0 = newValue
            case 1: b1 = newValue
            case 2: b2 = newValue
            case 3: b3 = newValue
            default: b4 = newValue
            }
        }
    }
}

/// Estado de retardo (Direct Form II Transposed) para 1 canal × 5 bandas sin arrays ni heap.
private struct FiveBandChannelDelay: Sendable {
    var z1_0: Float = 0; var z2_0: Float = 0
    var z1_1: Float = 0; var z2_1: Float = 0
    var z1_2: Float = 0; var z2_2: Float = 0
    var z1_3: Float = 0; var z2_3: Float = 0
    var z1_4: Float = 0; var z2_4: Float = 0

    mutating func reset() {
        self = FiveBandChannelDelay()
    }

    @inline(__always)
    mutating func process(_ sample: Float, preamp: Float, coeffs: FiveBandCoefficients) -> Float {
        var x = sample * preamp

        var y = coeffs.b0.b0 * x + z1_0
        z1_0 = coeffs.b0.b1 * x - coeffs.b0.a1 * y + z2_0
        z2_0 = coeffs.b0.b2 * x - coeffs.b0.a2 * y
        x = y

        y = coeffs.b1.b0 * x + z1_1
        z1_1 = coeffs.b1.b1 * x - coeffs.b1.a1 * y + z2_1
        z2_1 = coeffs.b1.b2 * x - coeffs.b1.a2 * y
        x = y

        y = coeffs.b2.b0 * x + z1_2
        z1_2 = coeffs.b2.b1 * x - coeffs.b2.a1 * y + z2_2
        z2_2 = coeffs.b2.b2 * x - coeffs.b2.a2 * y
        x = y

        y = coeffs.b3.b0 * x + z1_3
        z1_3 = coeffs.b3.b1 * x - coeffs.b3.a1 * y + z2_3
        z2_3 = coeffs.b3.b2 * x - coeffs.b3.a2 * y
        x = y

        y = coeffs.b4.b0 * x + z1_4
        z1_4 = coeffs.b4.b1 * x - coeffs.b4.a1 * y + z2_4
        z2_4 = coeffs.b4.b2 * x - coeffs.b4.a2 * y
        x = y

        let threshold: Float = 0.94
        let headroom: Float = 0.06
        if x > threshold {
            return threshold + headroom * tanhf((x - threshold) / headroom)
        } else if x < -threshold {
            return -threshold - headroom * tanhf((-x - threshold) / headroom)
        }
        return x
    }
}

/// Estado DSP estéreo de 5 bandas 100% libre de asignaciones/ARC en tiempo real (`os_unfair_lock_trylock`).
private final class NotchEQDSPState: @unchecked Sendable {
    private var lock = os_unfair_lock_s()

    // Coeficientes activos (5 bandas en value-type inline) + ganancia de headroom
    private var coeffs = FiveBandCoefficients()
    private var preampLinear: Float = 1.0
    private var activeCoeffs = FiveBandCoefficients()
    private var activePreamp: Float = 1.0
    private var isBypassed: Bool = false
    private var activeBypassed: Bool = false
    private var needsDelayReset: Bool = false

    // Estado interno del filtro (Direct Form II Transposed) para L/R × 5 bandas (solo lo toca el audio thread)
    private var delayL = FiveBandChannelDelay()
    private var delayR = FiveBandChannelDelay()

    func update(gainsDB: [Double], sampleRate: Double, bypassed: Bool) {
        let freqs = NotchEQPreset.bandFrequencies
        var nextCoeffs = FiveBandCoefficients()
        var maxBoost: Double = 0.0
        for i in 0..<5 {
            let g = i < gainsDB.count ? gainsDB[i] : 0.0
            if g > maxBoost { maxBoost = g }
            nextCoeffs[i] = BiquadCoefficients.make(
                bandIndex: i,
                frequency: freqs[i],
                gainDB: g,
                sampleRate: sampleRate
            )
        }
        // Headroom suave automático para prevenir clipping al subir graves/agudos
        let headroomDB = maxBoost > 0.5 ? -(maxBoost * 0.28) : 0.0
        let nextPreamp = Float(pow(10.0, headroomDB / 20.0))

        os_unfair_lock_lock(&lock)
        coeffs = nextCoeffs
        preampLinear = nextPreamp
        isBypassed = bypassed
        os_unfair_lock_unlock(&lock)
    }

    func resetDelayLines() {
        os_unfair_lock_lock(&lock)
        needsDelayReset = true
        os_unfair_lock_unlock(&lock)
    }

    /// Procesa buffers de entrada CoreAudio hacia salida aplicando el ecualizador de 5 bandas + soft-limiter.
    func process(
        input: UnsafePointer<AudioBufferList>?,
        output: UnsafeMutablePointer<AudioBufferList>?
    ) {
        guard let output else { return }
        let outList = UnsafeMutableAudioBufferListPointer(output)

        // Si no hay entrada válida, silenciar salida para evitar ruido residual
        guard let input else {
            for buf in outList {
                if let ptr = buf.mData {
                    memset(ptr, 0, Int(buf.mDataByteSize))
                }
            }
            return
        }

        // Intento sin bloqueo de leer nuevos coeficientes (copia puramente escalar, cero ARC)
        if os_unfair_lock_trylock(&lock) {
            activeCoeffs = coeffs
            activePreamp = preampLinear
            activeBypassed = isBypassed
            if needsDelayReset {
                delayL.reset()
                delayR.reset()
                needsDelayReset = false
            }
            os_unfair_lock_unlock(&lock)
        }

        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard !inList.isEmpty, !outList.isEmpty else { return }

        // Caso 1: buffers no entrelazados (1 canal por buffer)
        if inList.count >= 2 && outList.count >= 2 && inList[0].mNumberChannels == 1 && outList[0].mNumberChannels == 1 {
            let frames = min(Int(inList[0].mDataByteSize), Int(outList[0].mDataByteSize)) / MemoryLayout<Float>.size
            guard let inL = inList[0].mData?.assumingMemoryBound(to: Float.self),
                  let inR = inList[1].mData?.assumingMemoryBound(to: Float.self),
                  let outL = outList[0].mData?.assumingMemoryBound(to: Float.self),
                  let outR = outList[1].mData?.assumingMemoryBound(to: Float.self) else {
                return
            }
            if activeBypassed {
                memcpy(outL, inL, frames * MemoryLayout<Float>.size)
                memcpy(outR, inR, frames * MemoryLayout<Float>.size)
                return
            }
            let c = activeCoeffs
            let preamp = activePreamp
            for f in 0..<frames {
                outL[f] = delayL.process(inL[f], preamp: preamp, coeffs: c)
                outR[f] = delayR.process(inR[f], preamp: preamp, coeffs: c)
            }
            return
        }

        // Caso 2: buffer estéreo entrelazado (2 canales en buffer 0)
        let inBuf = inList[0]
        let outBuf = outList[0]
        let inChannels = max(1, Int(inBuf.mNumberChannels))
        let outChannels = max(1, Int(outBuf.mNumberChannels))
        let inFrames = Int(inBuf.mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
        let outFrames = Int(outBuf.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
        let frames = min(inFrames, outFrames)

        guard let inPtr = inBuf.mData?.assumingMemoryBound(to: Float.self),
              let outPtr = outBuf.mData?.assumingMemoryBound(to: Float.self) else {
            return
        }

        if activeBypassed {
            if inChannels == outChannels {
                memcpy(outPtr, inPtr, frames * outChannels * MemoryLayout<Float>.size)
            } else {
                for f in 0..<frames {
                    let sL = inPtr[f * inChannels]
                    let sR = inChannels > 1 ? inPtr[f * inChannels + 1] : sL
                    outPtr[f * outChannels] = sL
                    if outChannels > 1 { outPtr[f * outChannels + 1] = sR }
                }
            }
            return
        }

        let c = activeCoeffs
        let preamp = activePreamp
        for f in 0..<frames {
            let sL = inPtr[f * inChannels]
            let sR = inChannels > 1 ? inPtr[f * inChannels + 1] : sL
            let pL = delayL.process(sL, preamp: preamp, coeffs: c)
            let pR = delayR.process(sR, preamp: preamp, coeffs: c)
            outPtr[f * outChannels] = pL
            if outChannels > 1 {
                outPtr[f * outChannels + 1] = pR
            }
            if outChannels > 2 {
                for ch in 2..<outChannels {
                    outPtr[f * outChannels + ch] = 0
                }
            }
        }
    }
}

// MARK: - Motor de Ecualizador del Sistema CoreAudio (Process Tap macOS 14.2+, Sin Drivers Virtuales)

/// Ecualizador real en tiempo real para todo el audio del sistema usando **CoreAudio Process Tap** (`CATapDescription`).
///
/// Características de seguridad:
/// - Usa `CATapMuteBehavior.mutedWhenTapped`: macOS restaura automáticamente el audio original del sistema
///   en el instante exacto en que el ecualizador se desactiva o la app se cierra (nunca puede quedar mudo).
/// - Excluye el proceso propio de `MacFileExplorer` para evitar realimentación (feedback loop).
/// - Se re-engancha automáticamente al cambiar de salida de audio (parlantes ↔ AirPods ↔ USB/HDMI).
/// - Si macOS requiere permiso de «Grabación de audio del sistema», informa `.permissionRequired` sin silenciar nada.
@MainActor
@Observable
public final class NotchAudioEqualizerEngine {

    public static let shared = NotchAudioEqualizerEngine()

    public private(set) var status: NotchEqualizerEngineStatus = .inactive

    private let dspState = NotchEQDSPState()
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var currentSampleRate: Double = 48000.0
    private var activeOutputDeviceUID: String?

    private init() {}

    /// Sincroniza el estado del motor con `NotchPreferences.shared` (`isEnabled && isEqualizerEnabled`).
    public func syncWithPreferences() {
        let prefs = NotchPreferences.shared
        guard prefs.isEnabled && prefs.isEqualizerEnabled else {
            stop()
            return
        }

        let targetUID = NotchLyricsAndAudioService.shared.defaultOutputDevice?.uid
        if aggregateDeviceID != kAudioObjectUnknown && targetUID == activeOutputDeviceUID {
            updateGains(prefs.eqBandGains)
            return
        }

        startOrRestart()
    }

    /// Actualiza en vivo las 5 bandas del ecualizador (sin cortes ni clics de audio).
    public func updateGains(_ gainsDB: [Double]) {
        let isFlat = gainsDB.allSatisfy { abs($0) < 0.05 }
        dspState.update(gainsDB: gainsDB, sampleRate: currentSampleRate, bypassed: isFlat)
    }

    /// Reconfigura el tap cuando el usuario cambia el dispositivo de salida predeterminado.
    public func handleDefaultOutputDeviceChanged() {
        let prefs = NotchPreferences.shared
        guard prefs.isEnabled && prefs.isEqualizerEnabled else { return }
        startOrRestart()
    }

    /// Detiene el procesamiento DSP y libera el Process Tap y Aggregate Device (restaura audio directo al instante).
    public func stop() {
        if let procID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if #available(macOS 14.2, *) {
            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
                tapID = kAudioObjectUnknown
            }
        }
        activeOutputDeviceUID = nil
        dspState.resetDelayLines()
        status = .inactive
    }

    /// Abre la sección de Privacidad → Grabación de audio del sistema en Configuración del Sistema.
    public func openSystemAudioPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startOrRestart() {
        stop()

        guard #available(macOS 14.2, *) else {
            status = .unavailable("macOS 14.2+")
            return
        }

        guard let outputDevice = NotchLyricsAndAudioService.shared.defaultOutputDevice else {
            status = .unavailable("No output device")
            return
        }

        // Excluir nuestro propio proceso para evitar eco / realimentación
        var excludedProcessObjects: [AudioObjectID] = []
        if let ownObjID = Self.lookupAudioProcessObjectID(forPID: ProcessInfo.processInfo.processIdentifier) {
            excludedProcessObjects.append(ownObjID)
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcessObjects)
        tapDescription.name = "MacFileExplorer Notch Equalizer"
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped
        if #available(macOS 26.0, *), let ownBundleID = Bundle.main.bundleIdentifier, !ownBundleID.isEmpty {
            tapDescription.bundleIDs = [ownBundleID]
        }

        var createdTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard tapStatus == noErr, createdTapID != kAudioObjectUnknown else {
            if tapStatus == kAudioHardwareNotRunningError
                || tapStatus == kAudioHardwareBadDeviceError
                || tapStatus == kAudioHardwareUnknownPropertyError {
                status = .unavailable("Audio tap error (\(tapStatus))")
            } else {
                status = .permissionRequired
            }
            return
        }
        tapID = createdTapID

        let tapUID = tapDescription.uuid.uuidString
        let aggUID = "com.macfileexplorer.notch.eq.agg.\(UUID().uuidString)"
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacFileExplorer Notch EQ",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDevice.uid,
            kAudioAggregateDeviceClockDeviceKey: outputDevice.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputDevice.uid,
                    kAudioSubDeviceDriftCompensationKey: false
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var createdAggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &createdAggID)
        guard aggStatus == noErr, createdAggID != kAudioObjectUnknown else {
            stop()
            status = .unavailable("Aggregate device error (\(aggStatus))")
            return
        }
        aggregateDeviceID = createdAggID

        // Leer frecuencia de muestreo real del dispositivo para calcular filtros exactos
        currentSampleRate = Self.queryNominalSampleRate(for: outputDevice.id) ?? 48000.0
        dspState.resetDelayLines()
        updateGains(NotchPreferences.shared.eqBandGains)

        let dsp = dspState
        var createdProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&createdProcID, aggregateDeviceID, nil) { _, inInputData, _, outOutputData, _ in
            dsp.process(input: inInputData, output: outOutputData)
        }
        guard procStatus == noErr, let validProcID = createdProcID else {
            stop()
            status = .unavailable("Audio IOProc error (\(procStatus))")
            return
        }
        ioProcID = validProcID

        let startStatus = AudioDeviceStart(aggregateDeviceID, validProcID)
        guard startStatus == noErr else {
            stop()
            status = .unavailable("Audio device start error (\(startStatus))")
            return
        }

        activeOutputDeviceUID = outputDevice.uid
        status = .activeSystemDSP
    }

    private nonisolated static func lookupAudioProcessObjectID(forPID pid: pid_t) -> AudioObjectID? {
        var pidCopy = pid
        var processObjID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pidCopy,
            &size,
            &processObjID
        )
        guard status == noErr, processObjID != kAudioObjectUnknown else { return nil }
        return processObjID
    }

    private nonisolated static func queryNominalSampleRate(for deviceID: AudioDeviceID) -> Double? {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        guard status == noErr, rate > 1000 else { return nil }
        return rate
    }
}
