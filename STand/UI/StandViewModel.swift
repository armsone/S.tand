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
    static let mateUpperBound = 0.4
    static let mateTapLevel = 0.35
    static let objectTapLevel = 0.8
    static let verticalDragTravelRatio = 0.5
    static let objectLockDelay: Duration = .seconds(1)
    static let mateLockDelay: Duration = .seconds(1)
    static let objectLockReleaseLevel = 0.95

    static func clamped(_ level: Double) -> Double {
        min(1, max(0, level))
    }

    static func level(
        startingAt startingLevel: Double,
        verticalTranslation: CGFloat,
        viewportHeight: CGFloat
    ) -> Double {
        let travel = max(1, viewportHeight * verticalDragTravelRatio)
        return clamped(startingLevel - Double(verticalTranslation / travel))
    }

    static func preference(for level: Double) -> StandModePreference {
        let value = clamped(level)
        if value >= 1 { return .object }
        if value <= 0 { return .mate }
        return .automatic
    }

    static func preferenceDuringAdjustment(for level: Double) -> StandModePreference {
        let value = clamped(level)
        return (value >= 1 || value <= 0) ? .automatic : preference(for: value)
    }

    static func stabilizedAdjustment(
        requestedLevel: Double,
        currentPreference: StandModePreference
    ) -> (level: Double, preference: StandModePreference) {
        let requested = clamped(requestedLevel)
        if currentPreference == .object, requested >= objectLockReleaseLevel {
            return (1, .object)
        }
        return (requested, preferenceDuringAdjustment(for: requested))
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

enum AppBrightnessSystemSyncPolicy {
    static func shouldAdoptSystemBrightness(
        isAdjustingBrightness: Bool,
        modePreference: StandModePreference
    ) -> Bool {
        !isAdjustingBrightness && modePreference == .automatic
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
        case .object: "sun.max.fill"
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
    static let maximumReadingAge: TimeInterval = 60
    static let minimumObservationDuration: TimeInterval = 1
    static let samplingInterval: Duration = .seconds(45)

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

    static func isRecentlyDark(
        _ reading: AmbientBrightnessReading?,
        now: Date = Date()
    ) -> Bool {
        guard let reading,
              now.timeIntervalSince(reading.measuredAt) <= maximumReadingAge
        else { return false }
        return reading.value <= darkThreshold
    }
}

enum AmbientCameraSamplingPolicy {
    static func shouldSample(
        isSessionActive: Bool,
        displayMode: EnvironmentDisplayMode,
        modePreference: StandModePreference,
        isEnabled: Bool
    ) -> Bool {
        isSessionActive
            && displayMode == .sleeping
            && modePreference == .automatic
            && isEnabled
    }
}

enum StartleActivationPolicy {
    static let delay: TimeInterval = 60

    static func canActivate(
        mateModeEnteredAt: TimeInterval?,
        now: TimeInterval
    ) -> Bool {
        guard let mateModeEnteredAt else { return false }
        return now - mateModeEnteredAt >= delay
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
               now.timeIntervalSince(cameraReading.measuredAt)
                <= AmbientCameraModePolicy.maximumReadingAge {
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
        if hasCameraReading, current == .stand, target == .sleeping { return 4 }
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
        isSuspended: Bool,
        isEnabled: Bool = true
    ) -> Bool {
        isEnabled && shouldMonitor(
            isNightSessionActive: isNightSessionActive,
            environmentDisplayMode: environmentDisplayMode
        ) && !isSuspended
    }
}

enum StartleLightingProfile: Equatable {
    case gentle
    case urgent

    static let totalDuration: TimeInterval = 10

    var riseDuration: TimeInterval { self == .gentle ? 2 : 1 }
    var fadeDuration: TimeInterval { self == .gentle ? 2 : 1 }
    var peakDisplayIntensity: Double { self == .gentle ? 0.4 : 1 }
    var peakTorchLevel: Double { self == .gentle ? 0.1 : 1 }
    var fadeStart: TimeInterval { Self.totalDuration - fadeDuration }

    static func forEvent(_ event: BoyisoEvent) -> StartleLightingProfile {
        event.kind == .sound && ["big_sound", "continuous_sound"].contains(event.detail)
            ? .urgent
            : .gentle
    }

    func displayIntensity(elapsed: TimeInterval, baseIntensity: Double) -> Double {
        let base = SimplifiedBrightnessModePolicy.clamped(baseIntensity)
        let peak = max(base, peakDisplayIntensity)
        if elapsed <= 0 { return base }
        if elapsed < riseDuration {
            return base + (peak - base) * eased(elapsed / riseDuration)
        }
        if elapsed < fadeStart { return peak }
        if elapsed < Self.totalDuration {
            let progress = eased((elapsed - fadeStart) / fadeDuration)
            return peak + (base - peak) * progress
        }
        return base
    }

    private func eased(_ value: Double) -> Double {
        let progress = min(1, max(0, value))
        return progress * progress * (3 - 2 * progress)
    }
}

enum SleepMovementLightingPolicy {
    static func torchLevel(
        torchEnabled: Bool,
        profile: StartleLightingProfile,
        environmentDisplayMode: EnvironmentDisplayMode,
        roomIsDark: Bool
    ) -> Double {
        guard torchEnabled, environmentDisplayMode == .sleeping, roomIsDark else { return 0 }
        return profile.peakTorchLevel
    }
}

enum LampTorchLightingPolicy {
    static func maximumLevel(
        torchEnabled: Bool,
        isMovementTriggered: Bool,
        profile: StartleLightingProfile,
        environmentDisplayMode: EnvironmentDisplayMode,
        roomIsDark: Bool
    ) -> Double {
        guard environmentDisplayMode == .sleeping, isMovementTriggered else { return 0 }
        return SleepMovementLightingPolicy.torchLevel(
            torchEnabled: torchEnabled,
            profile: profile,
            environmentDisplayMode: environmentDisplayMode,
            roomIsDark: roomIsDark
        )
    }
}

enum InternetRadioPlaybackMutationPolicy {
    static func shouldStopForSelection(
        activeChannelID: UUID?,
        selectedChannelID: UUID?
    ) -> Bool {
        guard let activeChannelID else { return false }
        return activeChannelID != selectedChannelID
    }

    static func shouldStopForUpdate(
        activeChannelID: UUID?,
        previous: InternetRadioConfiguration,
        updated: InternetRadioConfiguration
    ) -> Bool {
        activeChannelID == previous.id && previous.urlString != updated.urlString
    }

    static func shouldStopForRemoval(
        activeChannelID: UUID?,
        removedChannelID: UUID
    ) -> Bool {
        activeChannelID == removedChannelID
    }
}

@MainActor
final class StandViewModel: ObservableObject {
    @Published private(set) var isNightSessionActive = false
    @Published private(set) var lampIntensity = 0.0
    @Published private(set) var lampPhase: LampPhase = .off
    @Published private(set) var batteryStatus = DeviceBatteryStatus(
        level: nil,
        powerState: .unknown
    )
    @Published private(set) var batteryProtectionActive = false
    /// S.tand 화면 안에만 적용하는 조명 밝기입니다.
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
    let boyiso: BoyisoConnectivityService
    let radio: InternetRadioPlayer
    let weather: WeatherService

    private var lampTask: Task<Void, Never>?
    private var movementTorchSyncTask: Task<Void, Never>?
    private var controlsTask: Task<Void, Never>?
    private var modeTransitionTask: Task<Void, Never>?
    private var tapBrightnessTransitionTask: Task<Void, Never>?
    private var brightnessEndpointLockTask: Task<Void, Never>?
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
    private var activeLampBaseIntensity = 0.0
    private var activeStartleLightingProfile = StartleLightingProfile.gentle
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
    private var mateModeEnteredAt: TimeInterval?

    init() {
        let settings = SettingsStore()
        let library = RecordingLibrary()
        self.settings = settings
        self.library = library
        weather = WeatherService()
        audio = AudioCaptureService(recordingsDirectory: library.directory)
        boyiso = BoyisoConnectivityService()
        radio = InternetRadioPlayer()
        weather.setLocationEnabled(settings.value.weatherLocationEnabled)

        audio.onClap = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.boyiso.sendSoundEvent(
                intensity: max(0.2, self.audio.normalizedLevel),
                detail: "finger_snap"
            )
            self.wakeForSleepMovement(profile: .gentle)
        }
        audio.onRelativeSoundRise = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.boyiso.sendSoundEvent(
                intensity: max(0.2, self.audio.normalizedLevel),
                detail: "big_sound"
            )
            self.wakeForSleepMovement(profile: .urgent)
        }
        audio.onContinuousSound = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.boyiso.sendSoundEvent(
                intensity: max(0.2, self.audio.normalizedLevel),
                detail: "continuous_sound"
            )
            self.wakeForSleepMovement(profile: .urgent)
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
            self.boyiso.sendMovementEvent()
            self.wakeForSleepMovement(profile: .gentle)
        }
        boyiso.onRemoteEvent = { [weak self] event in
            guard let self,
                  event.role == .guest,
                  event.kind == .sound || event.kind == .movement,
                  self.environmentDisplayMode == .sleeping,
                  self.isNightSessionActive,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            if event.kind == .sound {
                guard self.isNightSessionActive,
                      self.environmentDisplayMode == .sleeping else { return }
            }
            self.wakeForSleepMovement(
                profile: StartleLightingProfile.forEvent(event),
                respectsMateWarmup: false
            )
        }
        postureMonitor.onFaceDownChanged = { [weak self] isFaceDown in
            self?.applyFaceDownState(isFaceDown)
        }
        ambientCameraState = settings.value.cameraAmbientSensingEnabled
            ? ambientCamera.currentState
            : .disabled

        settingsSubscription = settings.$value
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                audio.configure(settings: value)
                weather.setLocationEnabled(value.weatherLocationEnabled)
                if let activeChannelID = radio.activeChannelID {
                    let activeConfiguration = value.internetRadioChannels.first(where: {
                        $0.id == activeChannelID
                    })
                    if activeConfiguration == nil
                        || activeConfiguration?.streamURL != radio.activeStreamURL {
                        stopInternetRadioPlayback()
                    }
                } else if value.internetRadio == nil, radio.state.isActive {
                    stopInternetRadioPlayback()
                }
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
                syncSleepCareMonitoring()
            }

        screenBrightnessSubscription = NotificationCenter.default
            .publisher(for: UIScreen.brightnessDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let screen = notification.object as? UIScreen else { return }
                guard let self else { return }
                guard !isFaceDown else { return }
                guard AppBrightnessSystemSyncPolicy.shouldAdoptSystemBrightness(
                    isAdjustingBrightness: isAdjustingBrightness,
                    modePreference: settings.value.modePreference
                ) else { return }
                let newBrightness = Double(screen.brightness)
                displayBrightness = newBrightness
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
        tapBrightnessTransitionTask?.cancel()
        brightnessEndpointLockTask?.cancel()
        brightnessEndpointLockTask = nil
        pendingModeTarget = nil
        ambientSamplingTask?.cancel()
        ambientSamplingTask = nil
        ambientCamera.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func appDidBecomeActive() {
        appIsActive = true
        importSharedInternetRadioIfNeeded()
        manualDimmingHoldActive = false
        if settings.value.modePreference == .automatic {
            displayBrightness = Double(UIScreen.main.brightness)
        } else {
            displayBrightness = SimplifiedBrightnessModePolicy.clamped(
                settings.value.lampIntensity
            )
        }
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
        OrientationController.shared.reapply()
        guard isNightSessionActive else {
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
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
        let keepsBoyisoMonitoring = boyiso.isEnabled
            && boyiso.role == .guest
            && isNightSessionActive
            && environmentDisplayMode == .sleeping
        updateBoyisoLocalState(monitoring: keepsBoyisoMonitoring)
        isAdjustingBrightness = false
        brightnessEndpointLockTask?.cancel()
        brightnessEndpointLockTask = nil
        stopInternetRadioPlayback()
        manualDimmingHoldActive = false
        automaticDimmingPaused = false
        UIApplication.shared.isIdleTimerDisabled = false
        postureMonitor.stop()
        isFaceDown = false
        lampTask?.cancel()
        lampTask = nil
        movementTorchSyncTask?.cancel()
        movementTorchSyncTask = nil
        torch.turnOff()
        if isMovementTriggeredLamp {
            lampIntensity = SimplifiedBrightnessModePolicy.clamped(displayBrightness)
            lampPhase = .holding
            isMovementTriggeredLamp = false
        }
        ambientCamera.cancel()
        ambientSamplingTask?.cancel()
        ambientSamplingTask = nil
        ambientCameraState = settings.value.cameraAmbientSensingEnabled
            ? ambientCamera.currentState
            : .disabled
        guard isNightSessionActive else { return }
        if !keepsBoyisoMonitoring {
            audio.stop()
            motionMonitor.stop()
        }
        // 앱이 화면을 떠난 동안에는 실제 감시가 중단되므로 잠자기 모드 구간도
        // 여기서 닫는다. 다시 30분 이내 돌아오면 같은 잠자리로 재개된다.
        finishStartleEvent()
        library.endSleepSession(id: activeRecordingSessionID)
        activeRecordingSessionID = nil
    }

    func activateLamp() {
        applyBaseBrightness(displayBrightness, animated: true)
    }

    private func activateLamp(
        triggeredBySleepMovement: Bool,
        profile: StartleLightingProfile = .gentle
    ) {
        guard isNightSessionActive else { return }
        guard triggeredBySleepMovement else {
            applyBaseBrightness(displayBrightness, animated: true)
            return
        }
        lampTask?.cancel()

        let now = ProcessInfo.processInfo.systemUptime
        let baseIntensity = SimplifiedBrightnessModePolicy.clamped(displayBrightness)
        let maximumIntensity = max(baseIntensity, profile.peakDisplayIntensity)
        activeLampBaseIntensity = baseIntensity
        activeLampMaximumIntensity = maximumIntensity
        activeStartleLightingProfile = profile
        isMovementTriggeredLamp = true
        automaticDimmingPaused = false

        lampPhase = .holding
        lampIntensity = baseIntensity
        syncTorch()

        lampTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }

                let elapsed = ProcessInfo.processInfo.systemUptime - now
                if elapsed >= StartleLightingProfile.totalDuration {
                    lampIntensity = baseIntensity
                    lampPhase = .holding
                    torch.turnOff()
                    isMovementTriggeredLamp = false
                    finishStartleEvent()
                    return
                }
                lampPhase = elapsed >= profile.fadeStart ? .fading : .holding
                lampIntensity = profile.displayIntensity(
                    elapsed: elapsed,
                    baseIntensity: baseIntensity
                )
                syncTorch()
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
        activeLampBaseIntensity = value
        lampPhase = .holding
        torch.turnOff()
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { lampIntensity = value }
        } else {
            lampIntensity = value
        }
    }

    private func wakeForSleepMovement(
        profile: StartleLightingProfile,
        respectsMateWarmup: Bool = true
    ) {
        guard isNightSessionActive, environmentDisplayMode == .sleeping else { return }
        if respectsMateWarmup {
            guard StartleActivationPolicy.canActivate(
                mateModeEnteredAt: mateModeEnteredAt,
                now: ProcessInfo.processInfo.systemUptime
            ) else { return }
        }
        if activeRecordingSessionID == nil {
            syncRecordingSessionForDisplayMode()
        }
        if activeStartleEventID == nil {
            activeStartleEventID = library.beginStartleEvent(
                sessionID: activeRecordingSessionID
            )
        }
        ambientCamera.cancel()
        activateLamp(triggeredBySleepMovement: true, profile: profile)
        let torchLevel = SleepMovementLightingPolicy.torchLevel(
            torchEnabled: settings.value.torchEnabled,
            profile: profile,
            environmentDisplayMode: environmentDisplayMode,
            roomIsDark: roomIsDarkForStartleTorch
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
                        profile: self.activeStartleLightingProfile,
                        environmentDisplayMode: self.environmentDisplayMode,
                        roomIsDark: self.roomIsDarkForStartleTorch
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

    func toggleInternetRadioPlayback(channelID: UUID) {
        guard let configuration = settings.value.internetRadioChannel(id: channelID) else { return }
        if radio.state.isActive, radio.activeChannelID == channelID {
            stopInternetRadioPlayback()
        } else {
            startInternetRadioPlayback(configuration)
        }
    }

    func stopInternetRadioPlayback() {
        radio.stop()
    }

    func addInternetRadioChannel(
        _ configuration: InternetRadioConfiguration,
        select: Bool = true
    ) {
        var value = settings.value
        let existing = value.internetRadioChannels.first(where: { $0.id == configuration.id })
        let willSelect = select || value.selectedInternetRadioID == nil
        let shouldStopForUpdate = existing.map {
            InternetRadioPlaybackMutationPolicy.shouldStopForUpdate(
                activeChannelID: radio.activeChannelID,
                previous: $0,
                updated: configuration
            )
        } ?? false
        let shouldStopForSelection = willSelect
            && InternetRadioPlaybackMutationPolicy.shouldStopForSelection(
                activeChannelID: radio.activeChannelID,
                selectedChannelID: configuration.id
            )
        if shouldStopForUpdate || shouldStopForSelection {
            stopInternetRadioPlayback()
        }

        value.addInternetRadioChannel(configuration, select: select)
        settings.value = value
    }

    @discardableResult
    func updateInternetRadioChannel(_ configuration: InternetRadioConfiguration) -> Bool {
        var value = settings.value
        guard let previous = value.internetRadioChannels.first(where: {
            $0.id == configuration.id
        }) else { return false }

        if InternetRadioPlaybackMutationPolicy.shouldStopForUpdate(
            activeChannelID: radio.activeChannelID,
            previous: previous,
            updated: configuration
        ) {
            stopInternetRadioPlayback()
        }
        guard value.updateInternetRadioChannel(configuration) else { return false }
        settings.value = value
        return true
    }

    @discardableResult
    func selectInternetRadioChannel(id: UUID) -> Bool {
        var value = settings.value
        guard value.internetRadioChannels.contains(where: { $0.id == id }) else {
            return false
        }
        if InternetRadioPlaybackMutationPolicy.shouldStopForSelection(
            activeChannelID: radio.activeChannelID,
            selectedChannelID: id
        ) {
            stopInternetRadioPlayback()
        }
        guard value.selectInternetRadioChannel(id: id) else { return false }
        settings.value = value
        return true
    }

    @discardableResult
    func selectSecondaryInternetRadioChannel(id: UUID?) -> Bool {
        var value = settings.value
        guard value.selectSecondaryInternetRadioChannel(id: id) else { return false }
        settings.value = value
        return true
    }

    @discardableResult
    func removeInternetRadioChannel(id: UUID) -> InternetRadioConfiguration? {
        var value = settings.value
        guard value.internetRadioChannels.contains(where: { $0.id == id }) else {
            return nil
        }
        if InternetRadioPlaybackMutationPolicy.shouldStopForRemoval(
            activeChannelID: radio.activeChannelID,
            removedChannelID: id
        ) {
            stopInternetRadioPlayback()
        }
        guard let removed = value.removeInternetRadioChannel(id: id) else { return nil }
        settings.value = value
        return removed
    }

    @discardableResult
    func moveInternetRadioChannel(id: UUID, to destinationIndex: Int) -> Bool {
        var value = settings.value
        guard value.moveInternetRadioChannel(id: id, to: destinationIndex) else {
            return false
        }
        settings.value = value
        return true
    }

    func saveInternetRadioConfiguration(_ configuration: InternetRadioConfiguration) {
        let identity = sharedInternetRadioDraft?.id
            ?? settings.value.internetRadio?.id
            ?? configuration.id
        let identifiedConfiguration = (try? InternetRadioConfiguration(
            id: identity,
            displayName: configuration.displayName,
            urlString: configuration.urlString
        )) ?? configuration

        if settings.value.internetRadioChannels.contains(where: {
            $0.id == identifiedConfiguration.id
        }) {
            _ = updateInternetRadioChannel(identifiedConfiguration)
            _ = selectInternetRadioChannel(id: identifiedConfiguration.id)
        } else {
            addInternetRadioChannel(identifiedConfiguration)
        }
        sharedInternetRadioDraft = nil
        SharedInternetRadioImportStore().clearPendingConfiguration()
    }

    func removeInternetRadioConfiguration() {
        guard let id = settings.value.selectedInternetRadioID else { return }
        _ = removeInternetRadioChannel(id: id)
    }

    func discardSharedInternetRadioDraft() {
        sharedInternetRadioDraft = nil
        SharedInternetRadioImportStore().clearPendingConfiguration()
    }

    private func importSharedInternetRadioIfNeeded() {
        guard let configuration = SharedInternetRadioImportStore().pendingConfiguration() else { return }
        sharedInternetRadioDraft = InternetRadioImportPolicy.draft(
            shared: configuration,
            existingChannels: settings.value.internetRadioChannels
        )
    }

    private func startInternetRadioPlayback(_ configuration: InternetRadioConfiguration) {
        monitoringSuspensions.insert(.internetRadio)
        audio.stop()
        radio.switchChannel(to: configuration)
    }

    private func refreshEnvironmentDisplayMode(
        preference: StandModePreference? = nil,
        performTransition: Bool
    ) {
        let resolvedPreference = preference ?? settings.value.modePreference
        let decision = environmentDisplayModeDecision(preference: resolvedPreference)
        let newMode = decision.mode
        guard newMode != environmentDisplayMode else {
            modeTransitionTask?.cancel()
            modeTransitionTask = nil
            pendingModeTarget = nil
            return
        }

        guard performTransition, resolvedPreference == .automatic else {
            modeTransitionTask?.cancel()
            modeTransitionTask = nil
            pendingModeTarget = nil
            applyEnvironmentDisplayMode(newMode, performTransition: performTransition)
            return
        }

        let delay = AutomaticModeTransitionPolicy.confirmationDelay(
            from: environmentDisplayMode,
            to: newMode,
            hasCameraReading: decision.hasFreshCameraReading
        )
        guard delay > 0 else {
            applyEnvironmentDisplayMode(newMode, performTransition: performTransition)
            return
        }
        if pendingModeTarget == newMode, modeTransitionTask != nil { return }

        modeTransitionTask?.cancel()
        pendingModeTarget = newMode
        modeTransitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.pendingModeTarget == newMode else { return }
            let confirmed = self.environmentDisplayModeDecision(preference: .automatic).mode
            guard confirmed == newMode else {
                self.pendingModeTarget = nil
                self.modeTransitionTask = nil
                return
            }
            self.pendingModeTarget = nil
            self.modeTransitionTask = nil
            self.applyEnvironmentDisplayMode(newMode, performTransition: true)
        }
    }

    private func environmentDisplayModeDecision(
        preference: StandModePreference
    ) -> (mode: EnvironmentDisplayMode, hasFreshCameraReading: Bool) {
        let fallbackMode = SimplifiedBrightnessModePolicy.mode(
            for: displayBrightness,
            preference: preference
        )
        let freshCameraReading = lastAmbientBrightnessReading.flatMap { reading in
            Date().timeIntervalSince(reading.measuredAt) <= AmbientCameraModePolicy.maximumReadingAge
                ? reading
                : nil
        }
        let usesCameraReading = preference == .automatic
            && settings.value.cameraAmbientSensingEnabled
            && freshCameraReading != nil
        let mode = preference == .automatic
            && settings.value.cameraAmbientSensingEnabled
            ? AmbientCameraModePolicy.target(
                current: environmentDisplayMode,
                fallback: fallbackMode,
                reading: freshCameraReading
            )
            : fallbackMode
        return (mode, usesCameraReading)
    }

    private func applyEnvironmentDisplayMode(
        _ newMode: EnvironmentDisplayMode,
        performTransition: Bool
    ) {
        let changed = newMode != environmentDisplayMode
        if changed {
            mateModeEnteredAt = newMode == .sleeping
                ? ProcessInfo.processInfo.systemUptime
                : nil
        }
        if newMode == .stand { finishStartleEvent() }
        environmentDisplayMode = newMode
        if newMode == .sleeping {
            startAmbientSamplingIfNeeded()
        } else {
            ambientSamplingTask?.cancel()
            ambientSamplingTask = nil
            ambientCamera.cancel()
            ambientCameraState = settings.value.cameraAmbientSensingEnabled
                ? ambientCamera.currentState
                : .disabled
        }
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
                self.startAmbientSamplingIfNeeded()
            }
        }
    }

    func setSoundSensingEnabled(_ enabled: Bool) {
        settings.value.soundSensingEnabled = enabled
        syncSleepCareMonitoring()
    }

    func setWeatherLocationEnabled(_ enabled: Bool) {
        settings.value.weatherLocationEnabled = enabled
        weather.setLocationEnabled(enabled, requestPermission: enabled)
    }

    func measureAmbientBrightness() {
        guard settings.value.cameraAmbientSensingEnabled else {
            ambientCameraState = .disabled
            return
        }
        guard environmentDisplayMode == .sleeping else { return }
        guard !isAdjustingBrightness else { return }
        guard experienceMode != .startled else { return }
        torch.turnOff()
        ambientCameraState = .measuring
        ambientCamera.measureOnce { [weak self] result, state in
            guard let self else { return }
            self.ambientCameraState = state
            guard let result else { return }
            self.lastAmbientBrightnessReading = result
            self.refreshEnvironmentDisplayMode(performTransition: true)
            self.syncTorch()
        }
    }

    private func measureAmbientBrightnessIfNeeded() {
        guard AmbientCameraSamplingPolicy.shouldSample(
            isSessionActive: isNightSessionActive,
            displayMode: environmentDisplayMode,
            modePreference: settings.value.modePreference,
            isEnabled: settings.value.cameraAmbientSensingEnabled
        ) else { return }
        if let lastAmbientBrightnessReading,
           Date().timeIntervalSince(lastAmbientBrightnessReading.measuredAt) < 45 {
            return
        }
        measureAmbientBrightness()
    }

    private func startAmbientSamplingIfNeeded() {
        ambientSamplingTask?.cancel()
        guard AmbientCameraSamplingPolicy.shouldSample(
            isSessionActive: isNightSessionActive,
            displayMode: environmentDisplayMode,
            modePreference: settings.value.modePreference,
            isEnabled: settings.value.cameraAmbientSensingEnabled
        ) else {
            ambientSamplingTask = nil
            return
        }
        ambientSamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AmbientCameraModePolicy.samplingInterval)
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
            updateBoyisoLocalState(monitoring: false)
            return
        }

        motionMonitor.start()
        updateBoyisoLocalState(monitoring: true)
        guard SleepCareMonitoringPolicy.shouldCaptureAudio(
            isNightSessionActive: isNightSessionActive,
            environmentDisplayMode: environmentDisplayMode,
            isSuspended: !monitoringSuspensions.isEmpty,
            isEnabled: settings.value.soundSensingEnabled
        ) else {
            audio.stop()
            return
        }
        audio.startIfAuthorized()
    }

    private var boyisoBatteryPercent: Int? {
        batteryStatus.level.map { Int(($0 * 100).rounded()) }
    }

    private func updateBoyisoLocalState(monitoring: Bool) {
        boyiso.updateLocalState(
            monitoring: monitoring,
            batteryPercent: boyisoBatteryPercent,
            displayMode: environmentDisplayMode == .sleeping ? .mate : .object,
            sessionActive: isNightSessionActive
        )
    }

    private func applyFaceDownState(_ faceDown: Bool) {
        guard faceDown != isFaceDown else { return }

        if faceDown {
            guard isNightSessionActive else { return }
            isFaceDown = true
            applyBaseBrightness(0, animated: false)
            return
        }

        isFaceDown = false
        if isNightSessionActive {
            applyBaseBrightness(displayBrightness, animated: false)
            refreshEnvironmentDisplayMode(performTransition: true)
        }
    }

    func beginBrightnessAdjustment() {
        guard isNightSessionActive else { return }
        tapBrightnessTransitionTask?.cancel()
        tapBrightnessTransitionTask = nil
        brightnessEndpointLockTask?.cancel()
        brightnessEndpointLockTask = nil
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

    func updateBrightnessLevel(_ level: Double) {
        guard isNightSessionActive else { return }
        let adjustment = SimplifiedBrightnessModePolicy.stabilizedAdjustment(
            requestedLevel: level,
            currentPreference: settings.value.modePreference
        )
        let value = adjustment.level
        let preference = adjustment.preference
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

        if preference == .object || preference == .mate {
            brightnessEndpointLockTask?.cancel()
            brightnessEndpointLockTask = nil
        } else if value >= 1 {
            scheduleObjectModeLock()
        } else if value <= 0 {
            scheduleMateModeLock()
        } else {
            brightnessEndpointLockTask?.cancel()
            brightnessEndpointLockTask = nil
        }
    }

    func endBrightnessAdjustment() {
        guard isNightSessionActive else { return }
        isAdjustingBrightness = false
        applyBaseBrightness(displayBrightness, animated: false)
    }

    func toggleObjectMateMode() {
        guard isNightSessionActive else { return }
        tapBrightnessTransitionTask?.cancel()
        let target = SimplifiedBrightnessModePolicy.tapLevel(from: environmentDisplayMode)
        let start = displayBrightness
        tapBrightnessTransitionTask = Task { [weak self] in
            guard let self else { return }
            let steps = 40
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                let value = start + (target - start) * progress
                displayBrightness = value
                applyBaseBrightness(value, animated: false)
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            var updated = settings.value
            updated.lampIntensity = target
            updated.modePreference = .automatic
            settings.value = updated
            refreshEnvironmentDisplayMode(preference: .automatic, performTransition: true)
            tapBrightnessTransitionTask = nil
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func scheduleObjectModeLock() {
        guard brightnessEndpointLockTask == nil else { return }
        brightnessEndpointLockTask = Task { [weak self] in
            try? await Task.sleep(for: SimplifiedBrightnessModePolicy.objectLockDelay)
            guard let self, !Task.isCancelled, displayBrightness >= 1 else { return }

            var updated = settings.value
            updated.lampIntensity = 1
            updated.modePreference = .object
            settings.value = updated
            refreshEnvironmentDisplayMode(preference: .object, performTransition: true)
            brightnessEndpointLockTask = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func scheduleMateModeLock() {
        guard brightnessEndpointLockTask == nil else { return }
        brightnessEndpointLockTask = Task { [weak self] in
            try? await Task.sleep(for: SimplifiedBrightnessModePolicy.mateLockDelay)
            guard let self, !Task.isCancelled, displayBrightness <= 0 else { return }
            var updated = settings.value
            updated.lampIntensity = 0
            updated.modePreference = .mate
            settings.value = updated
            refreshEnvironmentDisplayMode(preference: .mate, performTransition: true)
            brightnessEndpointLockTask = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
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
            profile: activeStartleLightingProfile,
            environmentDisplayMode: environmentDisplayMode,
            roomIsDark: roomIsDarkForStartleTorch
        )
        guard maximumTorchLevel > 0 else {
            torch.turnOff()
            return
        }
        let intensityRange = activeLampMaximumIntensity - activeLampBaseIntensity
        let progress = intensityRange > 0
            ? (lampIntensity - activeLampBaseIntensity) / intensityRange
            : 0
        torch.setLevel(min(1, max(0, progress)) * maximumTorchLevel)
    }

    private var roomIsDarkForStartleTorch: Bool {
        AmbientCameraModePolicy.isRecentlyDark(lastAmbientBrightnessReading)
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
            queue.asyncAfter(deadline: .now() + 1.5, execute: timeout)
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
