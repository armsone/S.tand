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
        if isMovementTriggered {
            return SleepMovementLightingPolicy.torchLevel(
                torchEnabled: torchEnabled,
                environmentDisplayMode: environmentDisplayMode
            )
        }
        return torchEnabled ? 1 : 0
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
    @Published private(set) var displayBrightness = Double(UIScreen.main.brightness)
    @Published private(set) var automaticDimmingPaused = false
    @Published private(set) var manualDimmingHoldActive = false
    @Published private(set) var environmentDisplayMode: EnvironmentDisplayMode = .stand
    @Published var controlsVisible = true

    var isDisplayDark: Bool {
        isNightSessionActive && lampPhase == .off && !controlsVisible
    }

    let settings: SettingsStore
    let library: RecordingLibrary
    let audio: AudioCaptureService
    let weather: WeatherService

    private var lampTask: Task<Void, Never>?
    private var movementTorchSyncTask: Task<Void, Never>?
    private var controlsTask: Task<Void, Never>?
    private var settingsSubscription: AnyCancellable?
    private var screenBrightnessSubscription: AnyCancellable?
    private var batterySubscriptions: Set<AnyCancellable> = []
    private let torch = TorchController()
    private let motionMonitor = WakeMotionMonitor()
    private var activeLampMaximumIntensity = 1.0
    private var isMovementTriggeredLamp = false
    private var monitoringPausedForPlayback = false
    private var brightnessBeforeSession: CGFloat?
    private var activeRecordingSessionID: UUID?

    init() {
        let settings = SettingsStore()
        let library = RecordingLibrary()
        self.settings = settings
        self.library = library
        weather = WeatherService()
        audio = AudioCaptureService(recordingsDirectory: library.directory)

        audio.onClap = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.activateLamp()
        }
        audio.onSoundClassified = { [weak self] classification in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  SleepSoundWakePolicy.shouldWake(classification),
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
        motionMonitor.onMovement = { [weak self] in
            guard let self,
                  self.environmentDisplayMode == .sleeping,
                  self.settings.value.multiStimulusWakeEnabled
            else { return }
            self.wakeForSleepMovement()
        }
        orientationPreference = settings.value.orientationPreference
        OrientationController.shared.setPreference(settings.value.orientationPreference)

        settingsSubscription = settings.$value
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                audio.configure(settings: value)
                orientationPreference = value.orientationPreference
                OrientationController.shared.setPreference(value.orientationPreference)
                syncTorch(using: value)
                refreshEnvironmentDisplayMode(
                    threshold: value.brightnessModeThreshold,
                    performTransition: isNightSessionActive
                )
            }

        screenBrightnessSubscription = NotificationCenter.default
            .publisher(for: UIScreen.brightnessDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let screen = notification.object as? UIScreen else { return }
                guard let self else { return }
                let newBrightness = Double(screen.brightness)
                displayBrightness = newBrightness
                refreshEnvironmentDisplayMode(performTransition: true)
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
        rememberScreenBrightnessIfNeeded()
        refreshEnvironmentDisplayMode(performTransition: false)
        monitoringPausedForPlayback = false
        UIApplication.shared.isIdleTimerDisabled = true
        audio.configure(settings: settings.value)
        syncSleepCareMonitoring()
        weather.refreshIfNeeded()
        controlsTask?.cancel()
        controlsVisible = false
        activateLamp()
    }

    func stopNightSession() {
        guard isNightSessionActive else { return }
        isNightSessionActive = false
        audio.stop()
        motionMonitor.stop()
        library.endSleepSession(id: activeRecordingSessionID)
        activeRecordingSessionID = nil
        turnOffLamp(animated: true)
        controlsTask?.cancel()
        controlsVisible = true
    }

    func appDidBecomeActive() {
        manualDimmingHoldActive = false
        rememberScreenBrightnessIfNeeded()
        displayBrightness = Double(UIScreen.main.brightness)
        refreshEnvironmentDisplayMode(performTransition: false)
        batteryStatus = .current()
        if batteryStatus.shouldProtectBattery {
            pauseForLowBattery()
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        OrientationController.shared.reapply()
        guard isNightSessionActive else { return }
        syncSleepCareMonitoring()
        weather.refreshIfNeeded()
        controlsTask?.cancel()
        controlsVisible = false
        activateLamp()
    }

    func appWillResignActive() {
        manualDimmingHoldActive = false
        automaticDimmingPaused = false
        UIApplication.shared.isIdleTimerDisabled = false
        restoreScreenBrightness()
        movementTorchSyncTask?.cancel()
        movementTorchSyncTask = nil
        torch.turnOff()
        guard isNightSessionActive else { return }
        audio.stop()
        motionMonitor.stop()
        // 앱이 화면을 떠난 동안에는 실제 감시가 중단되므로 잠자기 모드 구간도
        // 여기서 닫는다. 다시 30분 이내 돌아오면 같은 잠자리로 재개된다.
        library.endSleepSession(id: activeRecordingSessionID)
        activeRecordingSessionID = nil
    }

    func activateLamp() {
        activateLamp(triggeredBySleepMovement: false)
    }

    private func activateLamp(triggeredBySleepMovement: Bool) {
        guard isNightSessionActive else { return }
        lampTask?.cancel()

        let now = ProcessInfo.processInfo.systemUptime
        let holdDuration = settings.value.holdDuration
        let fadeDuration = max(0.1, settings.value.fadeDuration)
        let maximumIntensity = settings.value.lampIntensity
        activeLampMaximumIntensity = maximumIntensity
        isMovementTriggeredLamp = triggeredBySleepMovement
        automaticDimmingPaused = false

        lampPhase = .holding
        withAnimation(.easeOut(duration: 0.3)) {
            lampIntensity = maximumIntensity
        }
        syncTorch()

        if manualDimmingHoldActive {
            automaticDimmingPaused = true
            return
        }

        // 스탠드 모드는 사용자가 직접 어둡게 할 때까지 밝은 화면을 유지한다.
        // 타이머를 만들지 않아 이전 잠자기 모드의 감광 작업이 다시 이어지지 않는다.
        if environmentDisplayMode == .stand {
            automaticDimmingPaused = settings.value.automaticDimmingEnabled
            return
        }

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

                if !StandAutomaticDimmingPolicy.shouldFade(
                    automaticDimmingEnabled: settings.value.automaticDimmingEnabled,
                    environmentDisplayMode: environmentDisplayMode
                ) {
                    fadeStartedAt = nil
                    automaticDimmingPaused = settings.value.automaticDimmingEnabled
                        && environmentDisplayMode == .stand
                    lampPhase = .holding
                    lampIntensity = maximumIntensity
                    syncTorch()
                    continue
                }

                automaticDimmingPaused = false
                let start = fadeStartedAt ?? currentTime
                fadeStartedAt = start
                let progress = min(1, max(0, (currentTime - start) / fadeDuration))
                lampPhase = .fading
                lampIntensity = maximumIntensity * (1 - progress)
                syncTorch()

                if progress >= 1 {
                    lampIntensity = 0
                    lampPhase = .off
                    torch.turnOff()
                    return
                }
            }
        }
    }

    private func wakeForSleepMovement() {
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
                    return
                }
            }
        }
    }

    func pauseMonitoringForPlayback() {
        guard isNightSessionActive else { return }
        monitoringPausedForPlayback = true
        audio.stop()
    }

    func resumeMonitoringAfterPlayback() {
        guard monitoringPausedForPlayback else { return }
        monitoringPausedForPlayback = false
        guard isNightSessionActive else { return }
        syncSleepCareMonitoring()
    }

    private func refreshEnvironmentDisplayMode(
        threshold: Double? = nil,
        performTransition: Bool
    ) {
        let newMode = EnvironmentDisplayMode.resolve(
            brightness: displayBrightness,
            threshold: threshold ?? settings.value.brightnessModeThreshold
        )
        let changed = newMode != environmentDisplayMode
        environmentDisplayMode = newMode
        if isNightSessionActive {
            syncRecordingSessionForDisplayMode()
        }
        guard performTransition, changed, isNightSessionActive else { return }
        syncSleepCareMonitoring()
        switch newMode {
        case .sleeping:
            if lampPhase == .holding { activateLamp() }
        case .stand:
            activateLamp()
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

    private func syncSleepCareMonitoring() {
        guard SleepCareMonitoringPolicy.shouldMonitor(
            isNightSessionActive: isNightSessionActive,
            environmentDisplayMode: environmentDisplayMode
        ) else {
            audio.stop()
            motionMonitor.stop()
            return
        }

        motionMonitor.start()
        guard !monitoringPausedForPlayback else {
            audio.stop()
            return
        }
        audio.requestAccessAndStart()
    }

    private func rememberScreenBrightnessIfNeeded() {
        if brightnessBeforeSession == nil {
            brightnessBeforeSession = UIScreen.main.brightness
        }
    }

    private func restoreScreenBrightness() {
        guard let brightnessBeforeSession else { return }
        UIScreen.main.brightness = brightnessBeforeSession
        self.brightnessBeforeSession = nil
    }

    func toggleManualDimmingHold() {
        guard isNightSessionActive else { return }
        if manualDimmingHoldActive {
            manualDimmingHoldActive = false
            automaticDimmingPaused = false
            activateLamp()
            return
        }

        lampTask?.cancel()
        manualDimmingHoldActive = true
        automaticDimmingPaused = true
        activeLampMaximumIntensity = settings.value.lampIntensity
        lampPhase = .holding
        withAnimation(.easeOut(duration: 0.3)) {
            lampIntensity = settings.value.lampIntensity
        }
        syncTorch()
    }

    func beginManualLampAdjustment() {
        guard isNightSessionActive else { return }
        lampTask?.cancel()
        lampPhase = .holding
        activeLampMaximumIntensity = settings.value.lampIntensity
        lampIntensity = settings.value.lampIntensity
        syncTorch()
    }

    func updateManualLampBrightness(_ value: Double) {
        guard isNightSessionActive else { return }
        let intensity = min(1, max(0.15, value))
        settings.value.lampIntensity = intensity
        activeLampMaximumIntensity = intensity
        lampPhase = .holding
        lampIntensity = intensity
        syncTorch()
    }

    func endManualLampAdjustment() {
        guard isNightSessionActive else { return }
        activateLamp()
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
        scheduleControlsHide()
    }

    var orientationControlTitle: String {
        switch orientationPreference {
        case .automatic: "현재 방향 고정하기"
        case .portrait, .landscape: "기기 회전 따르기"
        }
    }

    var orientationControlImage: String {
        orientationPreference == .automatic ? "lock.rotation" : "lock.open.fill"
    }

    func toggleOrientationLock() {
        if orientationPreference == .automatic {
            settings.value.orientationPreference = OrientationController.shared
                .preferenceForCurrentOrientation()
        } else {
            settings.value.orientationPreference = .automatic
        }
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
        guard isNightSessionActive else { return }
        isNightSessionActive = false
        audio.stop()
        motionMonitor.stop()
        library.endSleepSession(id: activeRecordingSessionID)
        activeRecordingSessionID = nil
        turnOffLamp(animated: true)
        controlsTask?.cancel()
        controlsVisible = true
    }

    private func scheduleControlsHide() {
        controlsTask?.cancel()
        guard isNightSessionActive else { return }
        controlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                self?.controlsVisible = false
            }
        }
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
