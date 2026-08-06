import AVFoundation
import Combine
import Foundation

enum MicrophoneAccess: Equatable {
    case unknown
    case denied
    case granted
}

enum AudioCaptureState: Equatable {
    case stopped
    case starting
    case monitoring
    case failed(String)
}

final class AudioCaptureService: ObservableObject {
    @Published private(set) var state: AudioCaptureState = .stopped
    @Published private(set) var microphoneAccess: MicrophoneAccess = .unknown
    @Published private(set) var normalizedLevel: Double = 0
    @Published private(set) var isWritingClip = false
    @Published private(set) var recordingErrorMessage: String?

    var onClap: (() -> Void)?
    var onClipSaved: ((URL) -> Void)?

    private var engine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let processingQueue = DispatchQueue(label: "com.armsone.stand.audio-processing", qos: .userInitiated)
    private var detector = AudioEventDetector(
        configuration: AudioDetectorConfiguration(soundThresholdDB: AppSettings.recommended.soundThresholdDB)
    )
    private lazy var clipRecorder = ClipSegmentRecorder(
        directory: recordingsDirectory,
        onRecordingChanged: { [weak self] isRecording in
            DispatchQueue.main.async {
                self?.isWritingClip = isRecording
                if isRecording {
                    self?.recordingErrorMessage = nil
                }
            }
        },
        onSaved: { [weak self] url in
            DispatchQueue.main.async { self?.onClipSaved?(url) }
        },
        onFailure: { [weak self] message in
            DispatchQueue.main.async { self?.recordingErrorMessage = message }
        }
    )
    private let recordingsDirectory: URL
    private var recordingEnabled = true
    private var tapInstalled = false
    private var lastLevelPublication: TimeInterval = 0
    private var notificationObservers: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false

    init(recordingsDirectory: URL) {
        self.recordingsDirectory = recordingsDirectory
        refreshPermissionState()
        installAudioObservers()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine.stop()
    }

    func configure(settings: AppSettings) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            detector.configuration.soundThresholdDB = settings.soundThresholdDB
            let recordingSettingChanged = recordingEnabled != settings.recordingEnabled
            recordingEnabled = settings.recordingEnabled
            if !settings.recordingEnabled {
                clipRecorder.finishCurrentClip()
                clipRecorder.clearPreRoll()
            } else if recordingSettingChanged {
                detector.reset()
                clipRecorder.clearPreRoll()
            }
        }
    }

    func requestAccessAndStart() {
        state = .starting

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneAccess = .granted
            startEngine()
        case .denied:
            microphoneAccess = .denied
            state = .stopped
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.microphoneAccess = granted ? .granted : .denied
                    if granted {
                        self.startEngine()
                    } else {
                        self.state = .stopped
                    }
                }
            }
        @unknown default:
            microphoneAccess = .unknown
            state = .stopped
        }
    }

    func startIfAuthorized() {
        refreshPermissionState()
        guard microphoneAccess == .granted else { return }
        startEngine()
    }

    func stop() {
        shouldResumeAfterInterruption = false
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        processingQueue.sync {
            detector.reset()
            clipRecorder.finishCurrentClip()
            clipRecorder.clearPreRoll()
        }
        normalizedLevel = 0
        state = .stopped
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func refreshPermissionState() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphoneAccess = .granted
        case .denied: microphoneAccess = .denied
        case .undetermined: microphoneAccess = .unknown
        @unknown default: microphoneAccess = .unknown
        }
    }

    private func startEngine() {
        guard !engine.isRunning else {
            state = .monitoring
            return
        }

        recordingErrorMessage = nil

        do {
            try FileManager.default.createDirectory(
                at: recordingsDirectory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: recordingsDirectory.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = recordingsDirectory
            try? mutableDirectory.setResourceValues(values)

            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setPreferredIOBufferDuration(0.02)
            try audioSession.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw AudioCaptureError.unavailableInput
            }

            if tapInstalled {
                input.removeTap(onBus: 0)
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.receive(buffer: buffer)
            }
            tapInstalled = true

            engine.prepare()
            try engine.start()
            state = .monitoring
        } catch {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            state = .failed(error.localizedDescription)
        }
    }

    private func receive(buffer: AVAudioPCMBuffer) {
        guard let copiedBuffer = buffer.copied() else { return }

        processingQueue.async { [weak self] in
            guard let self else { return }
            let levels = copiedBuffer.levels()
            let duration = Double(copiedBuffer.frameLength) / copiedBuffer.format.sampleRate
            let now = ProcessInfo.processInfo.systemUptime
            let detection = detector.analyze(
                rmsDB: levels.rmsDB,
                peakDB: levels.peakDB,
                bufferDuration: duration,
                now: now
            )

            if detection.clapDetected {
                DispatchQueue.main.async { self.onClap?() }
            }

            if recordingEnabled {
                clipRecorder.process(buffer: copiedBuffer, detection: detection, now: now)
            }

            if now - lastLevelPublication >= 0.08 {
                lastLevelPublication = now
                let normalized = Self.normalize(rmsDB: levels.rmsDB)
                DispatchQueue.main.async { self.normalizedLevel = normalized }
            }
        }
    }

    private func installAudioObservers() {
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                self?.restartAfterAudioChange(recreateEngine: true)
            }
        ]
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruption = AVAudioSession.InterruptionType(rawValue: rawValue)
        else { return }

        switch interruption {
        case .began:
            shouldResumeAfterInterruption = engine.isRunning || state == .monitoring
            engine.stop()
            processingQueue.sync {
                clipRecorder.finishCurrentClip()
                clipRecorder.clearPreRoll()
                detector.reset()
            }
            normalizedLevel = 0
            state = .stopped
        case .ended:
            guard shouldResumeAfterInterruption else { return }
            shouldResumeAfterInterruption = false
            startEngine()
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            engine.isRunning,
            let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue)
        else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            restartAfterAudioChange(recreateEngine: false)
        default:
            break
        }
    }

    private func restartAfterAudioChange(recreateEngine: Bool) {
        let shouldRestart = engine.isRunning || state == .monitoring || state == .starting
        guard shouldRestart else { return }

        if tapInstalled, !recreateEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        tapInstalled = false
        engine.stop()
        processingQueue.sync {
            clipRecorder.finishCurrentClip()
            clipRecorder.clearPreRoll()
            detector.reset()
        }

        if recreateEngine {
            engine = AVAudioEngine()
        }
        state = .starting
        startEngine()
    }

    private static func normalize(rmsDB: Float) -> Double {
        Double(min(1, max(0, (rmsDB + 70) / 55)))
    }
}

private enum AudioCaptureError: LocalizedError {
    case unavailableInput

    var errorDescription: String? {
        "마이크 입력을 사용할 수 없습니다."
    }
}

private struct AudioLevels {
    let rmsDB: Float
    let peakDB: Float
}

private extension AVAudioPCMBuffer {
    func copied() -> AVAudioPCMBuffer? {
        guard
            let sourceChannels = floatChannelData,
            let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
            let destinationChannels = copy.floatChannelData
        else { return nil }

        copy.frameLength = frameLength
        let sampleCount = Int(frameLength)
        for channel in 0..<Int(format.channelCount) {
            destinationChannels[channel].update(from: sourceChannels[channel], count: sampleCount)
        }
        return copy
    }

    func levels() -> AudioLevels {
        guard let samples = floatChannelData?[0], frameLength > 0 else {
            return AudioLevels(rmsDB: -90, peakDB: -90)
        }

        var sumOfSquares: Float = 0
        var peak: Float = 0
        for index in 0..<Int(frameLength) {
            let magnitude = abs(samples[index])
            sumOfSquares += magnitude * magnitude
            peak = max(peak, magnitude)
        }

        let rms = sqrt(sumOfSquares / Float(frameLength))
        let floor: Float = 0.000_031_622_78
        return AudioLevels(
            rmsDB: 20 * log10(max(rms, floor)),
            peakDB: 20 * log10(max(peak, floor))
        )
    }
}

final class ClipSegmentRecorder {
    private struct BufferedAudio {
        let buffer: AVAudioPCMBuffer
        let duration: TimeInterval
    }

    private let directory: URL
    private let onRecordingChanged: (Bool) -> Void
    private let onSaved: (URL) -> Void
    private let onFailure: (String) -> Void
    private let preRollDuration: TimeInterval
    private let postRollDuration: TimeInterval
    private let maximumClipDuration: TimeInterval

    private var preRoll: [BufferedAudio] = []
    private var preRollLength: TimeInterval = 0
    private var file: AVAudioFile?
    private var currentURL: URL?
    private var startedAt: TimeInterval?
    private var silenceDeadline: TimeInterval?

    init(
        directory: URL,
        onRecordingChanged: @escaping (Bool) -> Void,
        onSaved: @escaping (URL) -> Void,
        onFailure: @escaping (String) -> Void = { _ in },
        preRollDuration: TimeInterval = 0.8,
        postRollDuration: TimeInterval = 1.4,
        maximumClipDuration: TimeInterval = 90
    ) {
        self.directory = directory
        self.onRecordingChanged = onRecordingChanged
        self.onSaved = onSaved
        self.onFailure = onFailure
        self.preRollDuration = preRollDuration
        self.postRollDuration = postRollDuration
        self.maximumClipDuration = maximumClipDuration
    }

    func rememberForPreRoll(buffer: AVAudioPCMBuffer) {
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        preRoll.append(BufferedAudio(buffer: buffer, duration: duration))
        preRollLength += duration

        while preRollLength > preRollDuration, preRoll.count > 1 {
            preRollLength -= preRoll.removeFirst().duration
        }
    }

    func process(buffer: AVAudioPCMBuffer, detection: AudioDetection, now: TimeInterval) {
        if file == nil {
            rememberForPreRoll(buffer: buffer)
            if detection.soundBegan {
                startClip(format: buffer.format, now: now)
            }
            return
        }

        do {
            try file?.write(from: buffer)
        } catch {
            abortCurrentClip(message: "녹음 파일을 저장할 수 없습니다.")
            return
        }

        if detection.isAboveSoundThreshold {
            silenceDeadline = now + postRollDuration
        }

        if let startedAt, now - startedAt >= maximumClipDuration {
            finishCurrentClip()
            if detection.isAboveSoundThreshold {
                startClip(format: buffer.format, now: now)
            }
        } else if let silenceDeadline, now >= silenceDeadline {
            finishCurrentClip()
        }
    }

    func clearPreRoll() {
        preRoll.removeAll(keepingCapacity: true)
        preRollLength = 0
    }

    func finishCurrentClip() {
        guard file != nil else { return }
        file = nil
        let savedURL = currentURL
        currentURL = nil
        startedAt = nil
        silenceDeadline = nil
        clearPreRoll()
        onRecordingChanged(false)

        if let savedURL {
            onSaved(savedURL)
        }
    }

    private func startClip(format: AVAudioFormat, now: TimeInterval) {
        let url = directory.appendingPathComponent(Self.fileName(), isDirectory: false)
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: Int(format.channelCount),
                AVEncoderBitRateKey: 48_000
            ]
            let newFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )

            for chunk in preRoll {
                try newFile.write(from: chunk.buffer)
            }

            file = newFile
            currentURL = url
            startedAt = now
            silenceDeadline = now + postRollDuration
            clearPreRoll()
            onRecordingChanged(true)
        } catch {
            file = nil
            currentURL = nil
            startedAt = nil
            silenceDeadline = nil
            clearPreRoll()
            try? FileManager.default.removeItem(at: url)
            onRecordingChanged(false)
            onFailure("녹음 파일을 시작할 수 없습니다.")
        }
    }

    private func abortCurrentClip(message: String) {
        let failedURL = currentURL
        file = nil
        currentURL = nil
        startedAt = nil
        silenceDeadline = nil
        clearPreRoll()
        onRecordingChanged(false)
        if let failedURL {
            try? FileManager.default.removeItem(at: failedURL)
        }
        onFailure(message)
    }

    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let nonce = UUID().uuidString.prefix(8).lowercased()
        return "sleep-sound-\(formatter.string(from: Date()))-\(nonce).m4a"
    }
}
