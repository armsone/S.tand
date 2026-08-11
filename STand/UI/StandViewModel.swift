import AVFoundation
import Combine
import SwiftUI
import UIKit

enum LampPhase: Equatable {
    case off
    case holding
    case fading
}

enum BatteryPowerState: Equatable {
    case unknown
    case unplugged
    case charging
    case full
}

struct DeviceBatteryStatus: Equatable {
    let level: Double?
    let powerState: BatteryPowerState

    var isCharging: Bool {
        powerState == .charging || powerState == .full
    }

    var shouldProtectBattery: Bool {
        guard let level else { return false }
        return level <= 0.2 && !isCharging
    }

    static func current(device: UIDevice = .current) -> DeviceBatteryStatus {
        let rawLevel = device.batteryLevel
        let level = rawLevel >= 0 ? Double(rawLevel) : nil
        let powerState: BatteryPowerState = switch device.batteryState {
        case .unplugged: .unplugged
        case .charging: .charging
        case .full: .full
        case .unknown: .unknown
        @unknown default: .unknown
        }
        return DeviceBatteryStatus(level: level, powerState: powerState)
    }
}

struct AmbientDimmingPolicy {
    static let brightScreenThreshold = 0.65

    static func shouldPause(screenBrightness: Double, enabled: Bool) -> Bool {
        enabled && screenBrightness >= brightScreenThreshold
    }
}

enum EnvironmentDisplayMode: Equatable {
    case sleeping
    case stand

    static func resolve(brightness: Double, threshold: Double) -> Self {
        threshold < brightness ? .sleeping : .stand
    }
}

enum SimplifiedBrightnessModePolicy {
    static let mateUpperBound = 0.3
    static let mateTapLevel = 0.1
    static let objectTapLevel = 0.9
    static let verticalDragTravelRatio = 0.5
    static let interactiveMinimum = 0.01
    static let interactiveMaximum = 0.99
    static let fixedEdgeHoldDuration: TimeInterval = 1

    static func clamped(_ level: Double) -> Double {
        min(1, max(0, level))
    }

    static func level(
        startingAt startingLevel: Double,
        verticalTranslation: CGFloat,
        viewportHeight: CGFloat
    ) -> Double {
        min(interactiveMaximum, max(interactiveMinimum, rawLevel(
            startingAt: startingLevel,
            verticalTranslation: verticalTranslation,
            viewportHeight: viewportHeight
        )))
    }

    static func rawLevel(
        startingAt startingLevel: Double,
        verticalTranslation: CGFloat,
        viewportHeight: CGFloat
    ) -> Double {
        let travel = max(1, viewportHeight * verticalDragTravelRatio)
        return startingLevel - Double(verticalTranslation / travel)
    }

    static func fixedEdge(
        startingAt startingLevel: Double,
        verticalTranslation: CGFloat,
        viewportHeight: CGFloat
    ) -> BrightnessFixedEdge? {
        let raw = rawLevel(
            startingAt: startingLevel,
            verticalTranslation: verticalTranslation,
            viewportHeight: viewportHeight
        )
        if raw >= 1 { return .object }
        if raw <= 0 { return .mate }
        return nil
    }

    static func preference(for level: Double) -> StandModePreference {
        let value = clamped(level)
        if value >= 1 { return .object }
        if value <= 0 { return .mate }
        return .automatic
    }

    static func mode(
        for level: Double,
        preference: StandModePreference
    ) -> EnvironmentDisplayMode {
        switch preference {
        case .object: .stand
        case .mate: .sleeping
        case .automatic: clamped(level) <= mateUpperBound ? .sleeping : .stand
        }
    }

    static func tapLevel(from mode: EnvironmentDisplayMode) -> Double {
        mode == .stand ? mateTapLevel : objectTapLevel
    }
}

enum BrightnessFixedEdge: Equatable {
    case mate
    case object

    var level: Double {
        switch self {
        case .mate: 0
        case .object: 1
        }
    }
}

enum StandExperienceMode: String, Equatable {
    case object
    case mate
    case startled

    var title: String {
        switch self {
        case .object: "오브제 모드"
        case .mate: "매이트 모드"
        case .startled: "화들짝 모드"
        }
    }

    var systemImage: String {
        switch self {
        case .object: "lamp.table.fill"
        case .mate: "moon.stars.fill"
        case .startled: "bolt.fill"
        }
    }
}

enum AmbientCameraState: Equatable {
    case disabled
    case permissionNeeded
    case denied
    case measuring
    case ready
    case unavailable
}

struct AmbientBrightnessReading: Equatable {
    let value: Double
    let measuredAt: Date
    let cameraPosition: AVCaptureDevice.Position

    var isDark: Bool { value < AutomaticModeTransitionPolicy.cameraDarkThreshold }
}

enum AmbientCameraModePolicy {
    static let darkThreshold = 0.16
    static let brightThreshold = 0.28
    static let maximumReadingAge: TimeInterval = 20
    static let minimumObservationDuration: TimeInterval = 2

    static func target(
        current: EnvironmentDisplayMode,
        fallback: EnvironmentDisplayMode,
        reading: AmbientBrightnessReading?,
        now: Date = Date()
    ) -> EnvironmentDisplayMode {
        guard let reading,
              now.timeIntervalSince(reading.measuredAt) <= maximumReadingAge
        else { return fallback }
        if reading.value >= brightThreshold { return .stand }
        if reading.value <= darkThreshold { return .sleeping }
        return current
    }
}

enum AutomaticModeTransitionPolicy {
    static let cameraDarkThreshold = 0.16
    static let objectToMateDelay: TimeInterval = 20
    static let mateToObjectDelay: TimeInterval = 35
    static let maximumDecisionDelay: TimeInterval = 60

    static func target(
        preference: StandModePreference,
        screenBrightness: Double,
        threshold: Double,
        cameraReading: AmbientBrightnessReading?,
        now: Date = Date()
    ) -> EnvironmentDisplayMode {
        switch preference {
        case .object:
            return .stand
        case .mate:
            return .sleeping
        case .automatic:
            if let cameraReading,
               now.timeIntervalSince(cameraReading.measuredAt) < 90 {
                return cameraReading.isDark ? .sleeping : .stand
            }
            return EnvironmentDisplayMode.resolve(
                brightness: screenBrightness,
                threshold: threshold
            )
        }
    }

    static func confirmationDelay(
        from current: EnvironmentDisplayMode,
        to target: EnvironmentDisplayMode,
        hasCameraReading: Bool
    ) -> TimeInterval {
        guard current != target else { return 0 }
        if hasCameraReading { return 4 }
        return switch (current, target) {
        case (.stand, .sleeping): objectToMateDelay
        case (.sleeping, .stand): mateToObjectDelay
        default: maximumDecisionDelay
        }
    }
}

enum StandAutomaticDimmingPolicy {
    static func shouldFade(
        automaticDimmingEnabled: Bool,
        environmentDisplayMode: EnvironmentDisplayMode
    ) -> Bool {
        automaticDimmingEnabled && environmentDisplayMode == .sleeping
    }
}

enum SleepCareMonitoringPolicy {
    static func shouldMonitor(
        isNightSessionActive: Bool,
        environmentDisplayMode: EnvironmentDisplayMode
    ) -> Bool {
        isNightSessionActive && environmentDisplayMode == .sleeping
    }

    static func shouldCaptureAudio(
        isNightSessionActive: Bool,
        environmentDisplayMode: EnvironmentDisplayMode,
        isSuspended: Bool
    ) -> Bool {
        shouldMonitor(
            isNightSessionActive: isNightSessionActive,
            environmentDisplayMode: environmentDisplayMode
        ) && !isSuspended
    }
}

enum SleepMovementLightingPolicy {
    static func torchLevel(
        torchEnabled: Bool,
        environmentDisplayMode: EnvironmentDisplayMode
    ) -> Double {
        guard environmentDisplayMode == .sleeping else { return 0 }
        return torchEnabled ? 1 : 0.1
    }
}

enum LampTorchLightingPolicy {
    static func maximumLevel(
        torchEnabled: Bool,
        isMovementTriggered: Bool,
        environmentDisplayMode: EnvironmentDisplayMode
    ) -> Double {
        guard environmentDisplayMode == .sleeping, isMovementTriggered else { return 0 }
        return SleepMovementLightingPolicy.torchLevel(
            torchEnabled: torchEnabled,
            environmentDisplayMode: environmentDisplayMode
        )
    }
}

@MainActor
final class StandViewModel: ObservableObject {
    @Published private(set) var isNightSessionActive = false
    @Published private(set) var lampIntensity = 0.0
    @Published private(set) var lampPhase: LampPhase = .off
    @Published private(set) var orientationPreference: OrientationPreference = .automatic
    @Published private(set) var batteryStatus = DeviceBatteryStatus(
        level: nil,
        powerState: .unknown
    )
    @Published private(set) var batteryProtectionActive = false
    /// 앱 안의 조명 밝기입니다. 시스템 밝기는 자동 모드의 참고값으로만 읽습니다.
    @Published private(set) var displayBrightness = Double(UIScreen.main.brightness)
    @Published private(set) var automaticDimmingPaused = false
    @Published private(set) var manualDimmingHoldActive = false
    @Published private(set) var environmentDisplayMode: EnvironmentDisplayMode = .stand
    @Published private(set) var ambientCameraState: AmbientCameraState = .disabled
    @Published private(set) var lastAmbientBrightnessReading: AmbientBrightnessReading?
    @Published private(set) var isFaceDown = false
    @Published private(set) var sharedInternetRadioDraft: InternetRadioConfiguration?
    @Published var controlsVisible = true

    var experienceMode: StandExperienceMode {
        if isMovementTriggeredLamp, lampPhase != .off { return .startled }
        return environmentDisplayMode == .stand ? .object : .mate
    }

    var isDisplayDark: Bool {
        isNightSessionActive && lampPhase == .off && !controlsVisible
    }

    let settings: SettingsStore
    let library: RecordingLibrary
    let audio: AudioCaptureService
    let radio: InternetRadioPlayer
    let weather: WeatherService

    private var lampTask: Task<Void, Never>?
    private var movementTorchSyncTask: Task<Void, Never>?
    private var controlsTask: Task<Void, Never>?
    private var modeTransitionTask: Task<Void, Never>?
    private var ambientSamplingTask: Task<Void, Never>?
    private var pendingModeTarget: EnvironmentDisplayMode?
    private var settingsSubscription: AnyCancellable?
    private var screenBrightnessSubscription: AnyCancellable?
    private var batterySubscriptions: Set<AnyCancellable> = []
    private let torch = TorchController()
    private let motionMonitor = WakeMotionMonitor()
    private let postureMonitor = DevicePostureMonitor()
    private let ambientCamera = AmbientCameraBrightnessService()
    private var activeLampMaximumIntensity = 1.0
    private var isMovementTriggeredLamp = false
    private enum MonitoringSuspensionReason: Hashable {
        case recordingPlayback
        case internetRadio
    }

    private var monitoringSuspensions: Set<MonitoringSuspensionReason> = []
    private var appIsActive = true
    private var isAdjustingBrightness = false
    private var activeRecordingSessionID: UUID?
    private var activeStartleEventID: UUID?

    init() {
        let settings = SettingsStore()
        let library = RecordingLibrary()
        self.settings = settings
        self.library = library
        weather = WeatherService()
        audio = AudioCaptureService(recordingsDirectory: library.directory)
        radio = InternetRadioPlayer()

        audio.onClap = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.wakeForSleepMovement()
        }
        audio.onRelativeSoundRise = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.wakeForSleepMovement()
        }
        audio.onClipSaved = { [weak self] url in
            guard let self else { return }
            // 저장 완료 콜백은 잠자기→스탠드 전환 뒤에 늦게 도착할 수 있다.
            // 파일명에 기록된 실제 녹음 시작 시각으로 올바른 잠자기 구간을 찾는다.
            self.library.add(url)
        }
        audio.configure(settings: settings.value)
        radio.onPlaybackBecameInactive = { [weak self] in
            guard let self else { return }
            self.monitoringSuspensions.remove(.internetRadio)
            self.syncSleepCareMonitoring()
        }
        motionMonitor.onMovement = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.wakeForSleepMovement()
        }
        postureMonitor.onFaceDownChanged = { [weak self] isFaceDown in
            self?.applyFaceDownState(isFaceDown)
        }
        orientationPreference = settings.value.orientationPreference
        OrientationController.shared.setPreference(settings.value.orientationPreference)
        ambientCameraState = settings.value.cameraAmbientSensingEnabled
            ? ambientCamera.currentState
            : .disabled

        settingsSubscription = settings.$value
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                audio.configure(settings: value)
                if value.internetRadio == nil, radio.state.isActive {
                    stopInternetRadioPlayback()
                }
                orientationPreference = value.orientationPreference
                OrientationController.shared.setPreference(value.orientationPreference)
                syncTorch(using: value)
                refreshEnvironmentDisplayMode(
                    preference: value.modePreference,
                    performTransition: isNightSessionActive
                )
                if !value.cameraAmbientSensingEnabled {
                    ambientCamera.cancel()
                    ambientSamplingTask?.cancel()
                    ambientSamplingTask = nil
                    ambientCameraState = .disabled
                    lastAmbientBrightnessReading = nil
                } else if ambientCameraState == .disabled {
                    ambientCameraState = ambientCamera.currentState
                    startAmbientSamplingIfNeeded()
                }
            }

        screenBrightnessSubscription = NotificationCenter.default
            .publisher(for: UIScreen.brightnessDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let screen = notification.object as? UIScreen else { return }
                guard let self else { return }
                guard !isFaceDown else { return }
                let newBrightness = Double(screen.brightness)
                displayBrightness = newBrightness
                guard !isAdjustingBrightness else { return }
                guard settings.value.modePreference == .automatic else { return }
                applyBaseBrightness(newBrightness, animated: false)
                refreshEnvironmentDisplayMode(
                    preference: .automatic,
                    performTransition: true
                )
            }

        startBatteryMonitoring()
    }

    func startNightSession() {
        guard !isNightSessionActive else { return }
        batteryStatus = .current()
        guard !batteryStatus.shouldProtectBattery else {
            batteryProtectionActive = true
            UIApplication.shared.isIdleTimerDisabled = false
            controlsVisible = true
            return
        }
        batteryProtectionActive = false
        isNightSessionActive = true
        displayBrightness = Double(UIScreen.main.brightness)
        var initialSettings = settings.value
        initialSettings.modePreference = .automatic
        initialSettings.lampIntensity = displayBrightness
        initialSettings.brightnessModeThreshold = SimplifiedBrightnessModePolicy.mateUpperBound
        initialSettings.automaticDimmingEnabled = false
        settings.value = initialSettings
        applyEnvironmentDisplayMode(.stand, performTransition: false)
        UIApplication.shared.isIdleTimerDisabled = true
        audio.configure(settings: settings.value)
        syncSleepCareMonitoring()
        postureMonitor.start()
        weather.refreshIfNeeded()
        controlsTask?.cancel()
        controlsVisible = true
        applyBaseBrightness(displayBrightness, animated: false)
        if settings.value.cameraAmbientSensingEnabled {
            measureAmbientBrightnessIfNeeded()
            startAmbientSamplingIfNeeded()
        }
    }

    func stopNightSession() {
        guard isNightSessionActive else { return }
        isNightSessionActive = false
        stopInternetRadioPlayback()
        audio.stop()
        motionMonitor.stop()
        postureMonitor.stop()
        applyFaceDownState(false)
        finishStartleEvent()
        library.endSleepSession(id: activeRecordingSessionID)
        activeRecordingSessionID = nil
        turnOffLamp(animated: true)
        controlsTask?.cancel()
        controlsVisible = true
        modeTransitionTask?.cancel()
        pendingModeTarget = nil
        ambientSamplingTask?.cancel()
        ambientSamplingTask = nil
        ambientCamera.cancel()
    }

    func appDidBecomeActive() {
        appIsActive = true
        importSharedInternetRadioIfNeeded()
        manualDimmingHoldActive = false
        displayBrightness = Double(UIScreen.main.brightness)
        if isNightSessionActive, settings.value.modePreference == .automatic {
            applyBaseBrightness(displayBrightness, animated: false)
            refreshEnvironmentDisplayMode(
                preference: .automatic,
                performTransition: false
            )
        }
        batteryStatus = .current()
        if batteryStatus.shouldProtectBattery {
            pauseForLowBattery()
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        OrientationController.shared.reapply()
        guard isNightSessionActive else { return }
        postureMonitor.start()
        syncSleepCareMonitoring()
        weather.refreshIfNeeded()
        controlsTask?.cancel()
        controlsVisible = true
        applyBaseBrightness(displayBrightness, animated: false)
        if settings.value.cameraAmbientSensingEnabled {
            measureAmbientBrightnessIfNeeded()
            startAmbientSamplingIfNeeded()
        }
    }

    func appWillResignActive() {
        appIsActive = false
        isAdjustingBrightness = false
        stopInternetRadioPlayback()
        manualDimmingHoldActive = false
        automaticDimmingPaused = false
        UIApplication.shared.isIdleTimerDisabled = false
        postureMonitor.stop()
        isFaceDown = false
        movementTorchSyncTask?.cancel()
        movementTorchSyncTask = nil
        torch.turnOff()
        ambientCamera.cancel()
        ambientSamplingTask?.cancel()
        ambientSamplingTask = nil
        ambientCameraState = settings.value.cameraAmbientSensingEnabled
            ? ambientCamera.currentState
            : .disabled
        guard isNightSessionActive else { return }
        audio.stop()
        motionMonitor.stop()
        // 앱이 화면을 떠난 동안에는 실제 감시가 중단되므로 잠자기 모드 구간도
        // 여기서 닫는다. 다시 30분 이내 돌아오면 같은 잠자리로 재개된다.
        finishStartleEvent()
        library.endSleepSession(id: activeRecordingSessionID)
        activeRecordingSessionID = nil
    }

    func activateLamp() {
        applyBaseBrightness(displayBrightness, animated: true)
    }

    private func activateLamp(triggeredBySleepMovement: Bool) {
        guard isNightSessionActive else { return }
        guard triggeredBySleepMovement else {
            applyBaseBrightness(displayBrightness, animated: true)
            return
        }
        lampTask?.cancel()

        let now = ProcessInfo.processInfo.systemUptime
        let holdDuration = settings.value.holdDuration
        let fadeDuration = max(0.1, settings.value.fadeDuration)
        let baseIntensity = SimplifiedBrightnessModePolicy.clamped(displayBrightness)
        let maximumIntensity = max(0.7, baseIntensity)
        activeLampMaximumIntensity = maximumIntensity
        isMovementTriggeredLamp = true
        automaticDimmingPaused = false

        lampPhase = .holding
        withAnimation(.easeOut(duration: 0.3)) {
            lampIntensity = maximumIntensity
        }
        syncTorch()

        lampTask = Task { [weak self] in
            var fadeStartedAt: TimeInterval?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }

                let currentTime = ProcessInfo.processInfo.systemUptime
                if currentTime <= now + holdDuration {
                    lampPhase = .holding
                    lampIntensity = maximumIntensity
                    continue
                }

                let start = fadeStartedAt ?? currentTime
                fadeStartedAt = start
                let progress = min(1, max(0, (currentTime - start) / fadeDuration))
                lampPhase = .fading
                lampIntensity = baseIntensity + (maximumIntensity - baseIntensity) * (1 - progress)
                syncTorch()

                if progress >= 1 {
                    lampIntensity = baseIntensity
                    lampPhase = .holding
                    torch.turnOff()
                    isMovementTriggeredLamp = false
                    finishStartleEvent()
                    return
                }
            }
        }
    }

    private func applyBaseBrightness(_ level: Double, animated: Bool) {
        guard isNightSessionActive else { return }
        let value = SimplifiedBrightnessModePolicy.clamped(level)
        lampTask?.cancel()
        movementTorchSyncTask?.cancel()
        movementTorchSyncTask = nil
        isMovementTriggeredLamp = false
        finishStartleEvent()
        automaticDimmingPaused = false
        manualDimmingHoldActive = false
        activeLampMaximumIntensity = max(value, 0.01)
        lampPhase = .holding
        torch.turnOff()
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { lampIntensity = value }
        } else {
            lampIntensity = value
        }
    }

    private func wakeForSleepMovement() {
        guard isNightSessionActive, environmentDisplayMode == .sleeping else { return }
        if activeRecordingSessionID == nil {
            syncRecordingSessionForDisplayMode()
        }
        if activeStartleEventID == nil {
            activeStartleEventID = library.beginStartleEvent(
                sessionID: activeRecordingSessionID
            )
        }
        activateLamp(triggeredBySleepMovement: true)
        let torchLevel = SleepMovementLightingPolicy.torchLevel(
            torchEnabled: settings.value.torchEnabled,
            environmentDisplayMode: environmentDisplayMode
        )
        guard torchLevel > 0 else { return }

        // 점등 순간 카메라 장치가 잠시 바쁘더라도 뒤척임 보조 불빛이 빠지지 않도록
        // 짧은 간격으로 다시 동기화한다. TorchController가 이미 켜진 경우에는 no-op이다.
        movementTorchSyncTask?.cancel()
        movementTorchSyncTask = Task { [weak self] in
            for delay in [150, 450] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self,
                      !Task.isCancelled,
                      self.isNightSessionActive,
                      self.lampPhase != .off,
                      SleepMovementLightingPolicy.torchLevel(
                        torchEnabled: self.settings.value.torchEnabled,
                        environmentDisplayMode: self.environmentDisplayMode
                      ) > 0
                else { return }
                self.syncTorch()
            }
        }
    }

    func turnOffLamp(animated: Bool) {
        lampTask?.cancel()
        movementTorchSyncTask?.cancel()
        movementTorchSyncTask = nil
        manualDimmingHoldActive = false
        automaticDimmingPaused = false
        isMovementTriggeredLamp = false
        finishStartleEvent()
        lampPhase = .off
        torch.turnOff()
        if animated {
            withAnimation(.easeOut(duration: 0.8)) { lampIntensity = 0 }
        } else {
            lampIntensity = 0
        }
    }

    func dimLampNow() {
        guard isNightSessionActive, lampPhase != .off else { return }
        lampTask?.cancel()
        manualDimmingHoldActive = false
        automaticDimmingPaused = false
        let startedAt = ProcessInfo.processInfo.systemUptime
        let startingIntensity = lampIntensity
        let duration = 1.5
        lampPhase = .fading

        lampTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                let progress = min(
                    1,
                    (ProcessInfo.processInfo.systemUptime - startedAt) / duration
                )
                lampIntensity = startingIntensity * (1 - progress)
                syncTorch()
                if progress >= 1 {
                    lampIntensity = 0
                    lampPhase = .off
                    torch.turnOff()
                    isMovementTriggeredLamp = false
                    finishStartleEvent()
                    return
                }
            }
        }
    }

    func pauseMonitoringForPlayback() {
        monitoringSuspensions.insert(.recordingPlayback)
        stopInternetRadioPlayback()
        audio.stop()
    }

    func resumeMonitoringAfterPlayback() {
        guard monitoringSuspensions.remove(.recordingPlayback) != nil else { return }
        guard isNightSessionActive else { return }
        syncSleepCareMonitoring()
        startAmbientSamplingIfNeeded()
    }

    func toggleInternetRadioPlayback() {
        if radio.state.isActive {
            stopInternetRadioPlayback()
        } else {
            startInternetRadioPlayback()
        }
    }

    func stopInternetRadioPlayback() {
        radio.stop()
    }

    func saveInternetRadioConfiguration(_ configuration: InternetRadioConfiguration) {
        stopInternetRadioPlayback()
        sharedInternetRadioDraft = nil
        SharedInternetRadioImportStore().clearPendingConfiguration()
        var value = settings.value
        value.internetRadio = configuration
        settings.value = value
    }

    func removeInternetRadioConfiguration() {
        stopInternetRadioPlayback()
        var value = settings.value
        value.internetRadio = nil
        settings.value = value
    }

    func discardSharedInternetRadioDraft() {
        sharedInternetRadioDraft = nil
        SharedInternetRadioImportStore().clearPendingConfiguration()
    }

    private func importSharedInternetRadioIfNeeded() {
        guard let configuration = SharedInternetRadioImportStore().pendingConfiguration() else { return }
        sharedInternetRadioDraft = InternetRadioImportPolicy.draft(
            shared: configuration,
            existing: settings.value.internetRadio
        )
    }

    private func startInternetRadioPlayback() {
        guard let configuration = settings.value.internetRadio else { return }
        monitoringSuspensions.insert(.internetRadio)
        audio.stop()
        radio.play(url: configuration.streamURL)
    }

    private func refreshEnvironmentDisplayMode(
        preference: StandModePreference? = nil,
        performTransition: Bool
    ) {
        let resolvedPreference = preference ?? settings.value.modePreference
        let fallbackMode = SimplifiedBrightnessModePolicy.mode(
            for: displayBrightness,
            preference: resolvedPreference
        )
        let newMode = resolvedPreference == .automatic
            && settings.value.cameraAmbientSensingEnabled
            ? AmbientCameraModePolicy.target(
                current: environmentDisplayMode,
                fallback: fallbackMode,
                reading: lastAmbientBrightnessReading
            )
            : fallbackMode
        guard newMode != environmentDisplayMode else {
            modeTransitionTask?.cancel()
            modeTransitionTask = nil
            pendingModeTarget = nil
            return
        }
        modeTransitionTask?.cancel()
        modeTransitionTask = nil
        pendingModeTarget = nil
        applyEnvironmentDisplayMode(newMode, performTransition: performTransition)
    }

    private func applyEnvironmentDisplayMode(
        _ newMode: EnvironmentDisplayMode,
        performTransition: Bool
    ) {
        let changed = newMode != environmentDisplayMode
        if newMode == .stand { finishStartleEvent() }
        environmentDisplayMode = newMode
        if isNightSessionActive { syncRecordingSessionForDisplayMode() }
        guard performTransition, changed, isNightSessionActive else { return }
        syncSleepCareMonitoring()
        applyBaseBrightness(displayBrightness, animated: true)
    }

    func setModePreference(_ preference: StandModePreference) {
        settings.value.modePreference = preference
        refreshEnvironmentDisplayMode(
            preference: preference,
            performTransition: true
        )
    }

    func setAmbientCameraSensingEnabled(_ enabled: Bool) {
        settings.value.cameraAmbientSensingEnabled = enabled
        guard enabled else {
            ambientCamera.cancel()
            ambientCameraState = .disabled
            lastAmbientBrightnessReading = nil
            ambientSamplingTask?.cancel()
            ambientSamplingTask = nil
            return
        }
        ambientCamera.requestPermission { [weak self] state in
            guard let self else { return }
            self.ambientCameraState = state
            if state == .ready {
                self.measureAmbientBrightness()
                self.startAmbientSamplingIfNeeded()
            }
        }
    }

    func measureAmbientBrightness() {
        guard settings.value.cameraAmbientSensingEnabled else {
            ambientCameraState = .disabled
            return
        }
        guard !isAdjustingBrightness else { return }
        guard experienceMode != .startled else { return }
        torch.turnOff()
        ambientCameraState = .measuring
        ambientCamera.measureOnce { [weak self] result, state in
            guard let self else { return }
            self.ambientCameraState = state
            guard let result else { return }
            self.lastAmbientBrightnessReading = result
            self.modeTransitionTask?.cancel()
            self.pendingModeTarget = nil
            self.refreshEnvironmentDisplayMode(performTransition: true)
            self.syncTorch()
        }
    }

    private func measureAmbientBrightnessIfNeeded() {
        if let lastAmbientBrightnessReading,
           Date().timeIntervalSince(lastAmbientBrightnessReading.measuredAt) < 45 {
            return
        }
        measureAmbientBrightness()
    }

    private func startAmbientSamplingIfNeeded() {
        ambientSamplingTask?.cancel()
        guard isNightSessionActive,
              settings.value.modePreference == .automatic,
              settings.value.cameraAmbientSensingEnabled
        else {
            ambientSamplingTask = nil
            return
        }
        ambientSamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                if !self.isAdjustingBrightness,
                   self.ambientCameraState != .measuring,
                   self.experienceMode != .startled {
                    self.measureAmbientBrightness()
                }
            }
        }
    }

    /// 녹음 묶음은 감지 세션 전체가 아니라 실제 잠자기 모드 구간을 기준으로 한다.
    /// 잠자기 모드 사이의 짧은 깨어남은 RecordingLibrary가 30분까지 같은 세션으로 잇는다.
    private func syncRecordingSessionForDisplayMode(at date: Date = Date()) {
        switch environmentDisplayMode {
        case .sleeping:
            if activeRecordingSessionID == nil {
                activeRecordingSessionID = library.beginSleepSession(at: date)
            }
        case .stand:
            guard activeRecordingSessionID != nil else { return }
            library.endSleepSession(id: activeRecordingSessionID, at: date)
            activeRecordingSessionID = nil
        }
    }

    private func finishStartleEvent(at date: Date = Date()) {
        guard activeStartleEventID != nil else { return }
        library.endStartleEvent(id: activeStartleEventID, at: date)
        activeStartleEventID = nil
    }

    private func syncSleepCareMonitoring() {
        guard appIsActive, SleepCareMonitoringPolicy.shouldMonitor(
            isNightSessionActive: isNightSessionActive,
            environmentDisplayMode: environmentDisplayMode
        ) else {
            audio.stop()
            motionMonitor.stop()
            return
        }

        motionMonitor.start()
        guard SleepCareMonitoringPolicy.shouldCaptureAudio(
            isNightSessionActive: isNightSessionActive,
            environmentDisplayMode: environmentDisplayMode,
            isSuspended: !monitoringSuspensions.isEmpty
        ) else {
            audio.stop()
            return
        }
        audio.requestAccessAndStart()
    }

    private func applyFaceDownState(_ faceDown: Bool) {
        guard faceDown != isFaceDown else { return }

        if faceDown {
            guard isNightSessionActive else { return }
            isFaceDown = true
            return
        }

        isFaceDown = false
        if isNightSessionActive {
            refreshEnvironmentDisplayMode(performTransition: true)
        }
    }

    func beginBrightnessAdjustment() {
        isAdjustingBrightness = true
        if settings.value.cameraAmbientSensingEnabled {
            ambientCamera.cancel()
        }
        lampTask?.cancel()
        movementTorchSyncTask?.cancel()
        movementTorchSyncTask = nil
        isMovementTriggeredLamp = false
        finishStartleEvent()
        torch.turnOff()
    }

    func previewBrightnessLevel(_ level: Double) {
        let value = SimplifiedBrightnessModePolicy.clamped(level)
        displayBrightness = value
        applyBaseBrightness(value, animated: false)
    }

    func updateBrightnessLevel(_ level: Double) {
        let value = SimplifiedBrightnessModePolicy.clamped(level)
        let preference = SimplifiedBrightnessModePolicy.preference(for: value)
        displayBrightness = value

        var updatedSettings = settings.value
        updatedSettings.modePreference = preference
        updatedSettings.lampIntensity = value
        settings.value = updatedSettings

        applyBaseBrightness(value, animated: false)
        refreshEnvironmentDisplayMode(
            preference: preference,
            performTransition: true
        )
    }

    func endBrightnessAdjustment() {
        isAdjustingBrightness = false
        updateBrightnessLevel(displayBrightness)
    }

    func toggleObjectMateMode() {
        guard isNightSessionActive else { return }
        let target = SimplifiedBrightnessModePolicy.tapLevel(from: environmentDisplayMode)
        updateBrightnessLevel(target)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func syncTorch(using settingsOverride: AppSettings? = nil) {
        let currentSettings = settingsOverride ?? settings.value
        guard isNightSessionActive, lampPhase != .off else {
            torch.turnOff()
            return
        }
        let maximumTorchLevel = LampTorchLightingPolicy.maximumLevel(
            torchEnabled: currentSettings.torchEnabled,
            isMovementTriggered: isMovementTriggeredLamp,
            environmentDisplayMode: environmentDisplayMode
        )
        guard maximumTorchLevel > 0 else {
            torch.turnOff()
            return
        }
        let progress = activeLampMaximumIntensity > 0
            ? lampIntensity / activeLampMaximumIntensity
            : 0
        torch.setLevel(progress * maximumTorchLevel)
    }

    func revealControls() {
        controlsVisible = true
    }

    private func startBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryStatus = .current()

        Publishers.Merge(
            NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification),
            NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.handleBatteryChange()
        }
        .store(in: &batterySubscriptions)
    }

    private func handleBatteryChange() {
        batteryStatus = .current()
        if batteryStatus.shouldProtectBattery {
            pauseForLowBattery()
        }
    }

    private func pauseForLowBattery() {
        batteryProtectionActive = true
        UIApplication.shared.isIdleTimerDisabled = false
        let wasNightSessionActive = isNightSessionActive
        isNightSessionActive = false
        stopInternetRadioPlayback()
        guard wasNightSessionActive else { return }
        audio.stop()
        motionMonitor.stop()
        finishStartleEvent()
        library.endSleepSession(id: activeRecordingSessionID)
        activeRecordingSessionID = nil
        turnOffLamp(animated: true)
        controlsTask?.cancel()
        controlsVisible = true
        ambientSamplingTask?.cancel()
        ambientSamplingTask = nil
        ambientCamera.cancel()
    }

    private func scheduleControlsHide() {
        controlsTask?.cancel()
        controlsTask = nil
        controlsVisible = true
    }
}

private final class AmbientCameraBrightnessService: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.armsone.stand.ambient-camera")
    private var session: AVCaptureSession?
    private var activeDevice: AVCaptureDevice?
    private var completion: ((AmbientBrightnessReading?, AmbientCameraState) -> Void)?
    private var samples: [Double] = []
    private var receivedFrameCount = 0
    private var measurementStartedAt: TimeInterval?
    private var timeoutWorkItem: DispatchWorkItem?

    var currentState: AmbientCameraState {
        #if targetEnvironment(simulator)
        return .unavailable
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .ready
        case .notDetermined: .permissionNeeded
        case .denied, .restricted: .denied
        @unknown default: .unavailable
        }
        #endif
    }

    func requestPermission(completion: @escaping (AmbientCameraState) -> Void) {
        #if targetEnvironment(simulator)
        completion(.unavailable)
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(.ready)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted ? .ready : .denied) }
            }
        case .denied, .restricted:
            completion(.denied)
        @unknown default:
            completion(.unavailable)
        }
        #endif
    }

    func measureOnce(
        completion: @escaping (AmbientBrightnessReading?, AmbientCameraState) -> Void
    ) {
        #if targetEnvironment(simulator)
        completion(nil, .unavailable)
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            completion(nil, currentState)
            return
        }
        queue.async { [weak self] in
            self?.startMeasurement(completion: completion)
        }
        #endif
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.finish(reading: nil, state: self.currentState)
        }
    }

    private func startMeasurement(
        completion: @escaping (AmbientBrightnessReading?, AmbientCameraState) -> Void
    ) {
        finish(reading: nil, state: currentState, notify: false)
        self.completion = completion
        samples = []
        receivedFrameCount = 0
        measurementStartedAt = ProcessInfo.processInfo.systemUptime

        let position = preferredCameraPosition()
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        ) else {
            finish(reading: nil, state: .unavailable)
            return
        }

        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw AmbientCameraError.configuration }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            guard session.canAddOutput(output) else { throw AmbientCameraError.configuration }
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: queue)
            session.commitConfiguration()

            self.session = session
            activeDevice = device
            session.startRunning()

            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let reading = self.makeReading() {
                    self.finish(reading: reading, state: .ready)
                } else {
                    self.finish(reading: nil, state: .unavailable)
                }
            }
            timeoutWorkItem = timeout
            queue.asyncAfter(deadline: .now() + 3, execute: timeout)
        } catch {
            finish(reading: nil, state: .unavailable)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        receivedFrameCount += 1
        guard receivedFrameCount >= 8,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        if activeDevice?.isAdjustingExposure == true, receivedFrameCount < 20 { return }
        samples.append(sceneBrightness(pixelBuffer: buffer))
        let observedDuration = ProcessInfo.processInfo.systemUptime
            - (measurementStartedAt ?? ProcessInfo.processInfo.systemUptime)
        guard observedDuration >= AmbientCameraModePolicy.minimumObservationDuration,
              samples.count >= 5,
              let reading = makeReading()
        else { return }
        finish(reading: reading, state: .ready)
    }

    private func preferredCameraPosition() -> AVCaptureDevice.Position {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        return UIDevice.current.orientation == .faceDown ? .back : .front
    }

    private func sceneBrightness(pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        let step = 16
        var total = 0.0
        var count = 0
        for y in stride(from: 0, to: height, by: step) {
            let row = pointer.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: step) {
                let pixel = row.advanced(by: x * 4)
                let blue = Double(pixel[0])
                let green = Double(pixel[1])
                let red = Double(pixel[2])
                total += (0.0722 * blue + 0.7152 * green + 0.2126 * red) / 255
                count += 1
            }
        }
        let luminance = count > 0 ? total / Double(count) : 0
        guard let device = activeDevice else { return luminance }
        let isoFactor = max(0.5, Double(device.iso) / 100)
        let exposureSeconds = max(1.0 / 4_000, CMTimeGetSeconds(device.exposureDuration))
        let exposureFactor = max(0.25, exposureSeconds * 60)
        let compensation = sqrt(isoFactor * exposureFactor)
        return min(1, max(0, luminance / max(0.5, compensation)))
    }

    private func makeReading() -> AmbientBrightnessReading? {
        guard !samples.isEmpty, let device = activeDevice else { return nil }
        let sorted = samples.sorted()
        return AmbientBrightnessReading(
            value: sorted[sorted.count / 2],
            measuredAt: Date(),
            cameraPosition: device.position
        )
    }

    private func finish(
        reading: AmbientBrightnessReading?,
        state: AmbientCameraState,
        notify: Bool = true
    ) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        session?.stopRunning()
        session = nil
        activeDevice = nil
        samples = []
        receivedFrameCount = 0
        measurementStartedAt = nil
        let callback = completion
        completion = nil
        guard notify, let callback else { return }
        DispatchQueue.main.async { callback(reading, state) }
    }

    private enum AmbientCameraError: Error {
        case configuration
    }
}

@MainActor
private final class TorchController {
    private lazy var device = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
    )
    private var lastLevel: Float = 0

    func setLevel(_ requestedLevel: Double) {
        guard let device, device.hasTorch, device.isTorchAvailable else {
            lastLevel = 0
            return
        }

        let level = Float(min(1, max(0, requestedLevel)))
        guard level > 0 else {
            turnOff()
            return
        }
        guard abs(level - lastLevel) >= 0.01 || device.torchMode != .on else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            try device.setTorchModeOn(level: max(0.01, level))
            lastLevel = level
        } catch {
            lastLevel = 0
        }
    }

    func turnOff() {
        guard let device, device.hasTorch, device.torchMode != .off else {
            lastLevel = 0
            return
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            // The torch can be temporarily unavailable while the camera or system owns it.
        }
        lastLevel = 0
    }
}
