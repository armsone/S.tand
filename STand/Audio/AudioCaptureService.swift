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
    @Published private(set) var lastClassifiedSound: SleepSoundClassification?
    @Published private(set) var adaptiveNoiseFloorDB: Float?
    @Published private(set) var effectiveSoundThresholdDB: Float = -50
    @Published private(set) var noiseCalibrationProgress: Double = 0

    var onClap: (() -> Void)?
    var onRelativeSoundRise: (() -> Void)?
    var onSoundClassified: ((SleepSoundClassification) -> Void)?
    var onClipSaved: ((URL) -> Void)?

    private var engine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let processingQueue = DispatchQueue(label: "com.armsone.stand.audio-processing", qos: .userInitiated)
    private var detector = AudioEventDetector(
        configuration: AudioDetectorConfiguration(soundThresholdDB: AppSettings.recommended.soundThresholdDB)
    )
    private var adaptiveNoiseTracker = AdaptiveNoiseFloorTracker()
    private var soundClassifier = SleepSoundClassifier()
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
            let adaptiveState = adaptiveNoiseTracker.state
            detector.configuration.soundThresholdDB = adaptiveState.effectiveSoundThresholdDB
            detector.configuration.clapPeakThresholdDB = adaptiveState.effectiveClapPeakThresholdDB
            let recordingSettingChanged = recordingEnabled != settings.recordingEnabled
            recordingEnabled = settings.recordingEnabled
            if !settings.recordingEnabled {
                clipRecorder.finalizeApprovedOrDiscard()
                clipRecorder.clearPreRoll()
            } else if recordingSettingChanged {
                detector.reset()
                soundClassifier.reset()
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
            state = .failed("마이크 권한이 없어 소리 감지를 사용할 수 없습니다.")
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.microphoneAccess = granted ? .granted : .denied
                    if granted {
                        self.startEngine()
                    } else {
                        self.state = .failed("마이크 권한이 없어 소리 감지를 사용할 수 없습니다.")
                    }
                }
            }
        @unknown default:
            microphoneAccess = .unknown
            state = .failed("마이크 상태를 확인할 수 없어 소리 감지를 사용할 수 없습니다.")
        }
    }

    func startIfAuthorized() {
        refreshPermissionState()
        guard microphoneAccess == .granted else {
            state = .failed("마이크 권한이 없어 소리 감지를 사용할 수 없습니다.")
            return
        }
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
            adaptiveNoiseTracker.reset()
            soundClassifier.reset()
            clipRecorder.finalizeApprovedOrDiscard()
            clipRecorder.clearPreRoll()
        }
        normalizedLevel = 0
        adaptiveNoiseFloorDB = nil
        effectiveSoundThresholdDB = -50
        noiseCalibrationProgress = 0
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

#if targetEnvironment(simulator)
        normalizedLevel = 0
        state = .failed("시뮬레이터에서는 소리 감지를 사용하지 않습니다.")
#else
        recordingErrorMessage = nil

        processingQueue.sync {
            detector.reset()
            adaptiveNoiseTracker.reset()
            let adaptiveState = adaptiveNoiseTracker.state
            detector.configuration.soundThresholdDB = adaptiveState.effectiveSoundThresholdDB
            detector.configuration.clapPeakThresholdDB = adaptiveState.effectiveClapPeakThresholdDB
        }
        adaptiveNoiseFloorDB = nil
        effectiveSoundThresholdDB = -50
        noiseCalibrationProgress = 0

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

            guard audioSession.isInputAvailable else {
                throw AudioCaptureError.unavailableInput
            }

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
#endif
    }

    private func receive(buffer: AVAudioPCMBuffer) {
        guard let copiedBuffer = buffer.copied() else { return }

        processingQueue.async { [weak self] in
            guard let self else { return }
            let levels = copiedBuffer.levels()
            let duration = Double(copiedBuffer.frameLength) / copiedBuffer.format.sampleRate
            let now = ProcessInfo.processInfo.systemUptime
            let adaptiveState = adaptiveNoiseTracker.observe(
                rmsDB: levels.rmsDB,
                duration: duration
            )
            detector.configuration.soundThresholdDB = adaptiveState.effectiveSoundThresholdDB
            detector.configuration.clapPeakThresholdDB = adaptiveState.effectiveClapPeakThresholdDB
            let detection = detector.analyze(
                rmsDB: levels.rmsDB,
                peakDB: levels.peakDB,
                bufferDuration: duration,
                now: now
            )

            if detection.clapDetected {
                DispatchQueue.main.async { self.onClap?() }
            }
            if detection.soundBegan {
                DispatchQueue.main.async { self.onRelativeSoundRise?() }
            }
            let features = copiedBuffer.sleepSoundFeatures(
                rmsDB: levels.rmsDB,
                peakDB: levels.peakDB
            )
            if let classification = soundClassifier.analyze(
                features: features,
                detection: detection
            ) {
                if recordingEnabled {
                    if SleepSoundRecordingPolicy.shouldKeep(classification) {
                        clipRecorder.approveCurrentClip()
                    } else {
                        clipRecorder.rejectCurrentClip()
                    }
                }
                DispatchQueue.main.async {
                    self.lastClassifiedSound = classification
                    self.onSoundClassified?(classification)
                }
            }

            if recordingEnabled {
                clipRecorder.process(buffer: copiedBuffer, detection: detection, now: now)
            }

            if now - lastLevelPublication >= 0.08 {
                lastLevelPublication = now
                let normalized = Self.normalize(rmsDB: levels.rmsDB)
                DispatchQueue.main.async {
                    self.normalizedLevel = normalized
                    self.adaptiveNoiseFloorDB = adaptiveState.noiseFloorDB
                    self.effectiveSoundThresholdDB = adaptiveState.effectiveSoundThresholdDB
                    self.noiseCalibrationProgress = adaptiveState.calibrationProgress
                }
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
                clipRecorder.finalizeApprovedOrDiscard()
                clipRecorder.clearPreRoll()
                detector.reset()
                soundClassifier.reset()
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
            clipRecorder.finalizeApprovedOrDiscard()
            clipRecorder.clearPreRoll()
            detector.reset()
            soundClassifier.reset()
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

    func sleepSoundFeatures(rmsDB: Float, peakDB: Float) -> SleepSoundFeatures {
        guard let samples = floatChannelData?[0], frameLength > 1 else {
            return SleepSoundFeatures(
                rmsDB: rmsDB,
                peakDB: peakDB,
                zeroCrossingRate: 0,
                lowFrequencyRatio: 0,
                duration: 0
            )
        }

        let count = Int(frameLength)
        let sampleRate = format.sampleRate
        let smoothing = exp(-2 * Double.pi * 400 / sampleRate)
        var lowPassSample = 0.0
        var lowEnergy = 0.0
        var totalEnergy = 0.0
        var zeroCrossings = 0
        var previousSample = Double(samples[0])

        for index in 0..<count {
            let sample = Double(samples[index])
            lowPassSample = (1 - smoothing) * sample + smoothing * lowPassSample
            lowEnergy += lowPassSample * lowPassSample
            totalEnergy += sample * sample
            if index > 0, (sample >= 0) != (previousSample >= 0) {
                zeroCrossings += 1
            }
            previousSample = sample
        }

        return SleepSoundFeatures(
            rmsDB: rmsDB,
            peakDB: peakDB,
            zeroCrossingRate: Double(zeroCrossings) / Double(count - 1),
            lowFrequencyRatio: totalEnergy > 0 ? min(1, lowEnergy / totalEnergy) : 0,
            duration: Double(frameLength) / sampleRate
        )
    }
}

final class ClipSegmentRecorder {
    private struct BufferedAudio {
        let buffer: AVAudioPCMBuffer
        let duration: TimeInterval
    }

    private let directory: URL
    private let stagingDirectory: URL
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
    private var pendingSegmentURLs: [URL] = []
    private var isApproved = false

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
        stagingDirectory = directory.appendingPathComponent(".Pending", isDirectory: true)
        self.onRecordingChanged = onRecordingChanged
        self.onSaved = onSaved
        self.onFailure = onFailure
        self.preRollDuration = preRollDuration
        self.postRollDuration = postRollDuration
        self.maximumClipDuration = maximumClipDuration
        removeStalePendingFiles()
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
            rollCurrentClip()
            if detection.isAboveSoundThreshold {
                startClip(format: buffer.format, now: now)
            } else {
                finalizeApprovedOrDiscard()
            }
        } else if let silenceDeadline, now >= silenceDeadline {
            finalizeApprovedOrDiscard()
        }
    }

    func clearPreRoll() {
        preRoll.removeAll(keepingCapacity: true)
        preRollLength = 0
    }

    func approveCurrentClip() {
        guard file != nil || !pendingSegmentURLs.isEmpty else { return }
        isApproved = true
    }

    func rejectCurrentClip() {
        guard !isApproved else { return }
        discardCurrentClip()
    }

    func finalizeApprovedOrDiscard() {
        if isApproved {
            commitCurrentClip()
        } else {
            discardCurrentClip()
        }
    }

    private func commitCurrentClip() {
        guard file != nil || !pendingSegmentURLs.isEmpty else { return }
        file = nil
        let savedURL = currentURL
        currentURL = nil
        startedAt = nil
        silenceDeadline = nil
        clearPreRoll()
        onRecordingChanged(false)

        let completedURLs = pendingSegmentURLs + [savedURL].compactMap { $0 }
        pendingSegmentURLs.removeAll(keepingCapacity: true)
        isApproved = false
        for stagingURL in completedURLs {
            let finalURL = directory.appendingPathComponent(stagingURL.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: stagingURL, to: finalURL)
                onSaved(finalURL)
            } catch {
                try? FileManager.default.removeItem(at: stagingURL)
                onFailure("승인된 녹음 파일을 보관함으로 옮길 수 없습니다.")
            }
        }
        removeStagingDirectoryIfEmpty()
    }

    private func rollCurrentClip() {
        guard file != nil else { return }
        let rolledURL = currentURL
        file = nil
        if let rolledURL {
            pendingSegmentURLs.append(rolledURL)
        }
        currentURL = nil
        startedAt = nil
        silenceDeadline = nil
        clearPreRoll()
    }

    func discardCurrentClip() {
        guard file != nil || !pendingSegmentURLs.isEmpty else { return }
        file = nil
        let discardedURL = currentURL
        currentURL = nil
        startedAt = nil
        silenceDeadline = nil
        clearPreRoll()
        onRecordingChanged(false)

        let discardedURLs = pendingSegmentURLs + [discardedURL].compactMap { $0 }
        pendingSegmentURLs.removeAll(keepingCapacity: true)
        isApproved = false
        for url in discardedURLs {
            try? FileManager.default.removeItem(at: url)
        }
        removeStagingDirectoryIfEmpty()
    }

    private func startClip(format: AVAudioFormat, now: TimeInterval) {
        let url = stagingDirectory.appendingPathComponent(Self.fileName(), isDirectory: false)
        do {
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
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
            try? FileManager.default.removeItem(at: url)
            abortCurrentClip(message: "녹음 파일을 시작할 수 없습니다.")
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
        let failedURLs = pendingSegmentURLs + [failedURL].compactMap { $0 }
        pendingSegmentURLs.removeAll(keepingCapacity: true)
        isApproved = false
        for url in failedURLs {
            try? FileManager.default.removeItem(at: url)
        }
        removeStagingDirectoryIfEmpty()
        onFailure(message)
    }

    private func removeStalePendingFiles() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        removeStagingDirectoryIfEmpty()
    }

    private func removeStagingDirectoryIfEmpty() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil
        ), contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: stagingDirectory)
    }

    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let nonce = UUID().uuidString.prefix(8).lowercased()
        return "sleep-sound-\(formatter.string(from: Date()))-\(nonce).m4a"
    }
}
