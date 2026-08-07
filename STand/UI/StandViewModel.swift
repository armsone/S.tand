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
    @Published var controlsVisible = true

    var isDisplayDark: Bool {
        isNightSessionActive && lampPhase == .off && !controlsVisible
    }

    let settings: SettingsStore
    let library: RecordingLibrary
    let audio: AudioCaptureService
    let weather: WeatherService

    private var lampTask: Task<Void, Never>?
    private var controlsTask: Task<Void, Never>?
    private var settingsSubscription: AnyCancellable?
    private var screenBrightnessSubscription: AnyCancellable?
    private var batterySubscriptions: Set<AnyCancellable> = []
    private let torch = TorchController()
    private var activeLampMaximumIntensity = 1.0

    init() {
        let settings = SettingsStore()
        let library = RecordingLibrary()
        self.settings = settings
        self.library = library
        weather = WeatherService()
        audio = AudioCaptureService(recordingsDirectory: library.directory)

        audio.onClap = { [weak self] in
            self?.activateLamp()
        }
        audio.onSoundClassified = { [weak self] classification in
            guard let self,
                  classification.kind == .movement,
                  self.settings.value.wakeOnSleepSound
            else { return }
            self.activateLamp()
        }
        audio.onClipSaved = { [weak self] url in
            guard let self else { return }
            self.library.add(url)
        }
        audio.configure(settings: settings.value)
        orientationPreference = settings.value.orientationPreference
        OrientationController.shared.setPreference(settings.value.orientationPreference)

        settingsSubscription = settings.$value
            .dropFirst()
            .sink { [weak self] value in
                self?.audio.configure(settings: value)
                self?.orientationPreference = value.orientationPreference
                OrientationController.shared.setPreference(value.orientationPreference)
                self?.syncTorch()
            }

        screenBrightnessSubscription = NotificationCenter.default
            .publisher(for: UIScreen.brightnessDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let screen = notification.object as? UIScreen else { return }
                self?.displayBrightness = Double(screen.brightness)
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
        UIApplication.shared.isIdleTimerDisabled = true
        audio.configure(settings: settings.value)
        audio.requestAccessAndStart()
        weather.refreshIfNeeded()
        controlsTask?.cancel()
        controlsVisible = false
        activateLamp()
    }

    func stopNightSession() {
        guard isNightSessionActive else { return }
        isNightSessionActive = false
        audio.stop()
        turnOffLamp(animated: true)
        controlsTask?.cancel()
        controlsVisible = true
    }

    func appDidBecomeActive() {
        batteryStatus = .current()
        if batteryStatus.shouldProtectBattery {
            pauseForLowBattery()
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        OrientationController.shared.reapply()
        guard isNightSessionActive else { return }
        audio.startIfAuthorized()
        weather.refreshIfNeeded()
        controlsTask?.cancel()
        controlsVisible = false
        activateLamp()
    }

    func appWillResignActive() {
        UIApplication.shared.isIdleTimerDisabled = false
        torch.turnOff()
        guard isNightSessionActive else { return }
        audio.stop()
    }

    func activateLamp() {
        guard isNightSessionActive else { return }
        lampTask?.cancel()

        let now = ProcessInfo.processInfo.systemUptime
        let holdDuration = settings.value.holdDuration
        let fadeDuration = max(0.1, settings.value.fadeDuration)
        let maximumIntensity = settings.value.lampIntensity
        activeLampMaximumIntensity = maximumIntensity
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

                if shouldPauseAutomaticDimming {
                    fadeStartedAt = nil
                    automaticDimmingPaused = true
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

    func turnOffLamp(animated: Bool) {
        lampTask?.cancel()
        automaticDimmingPaused = false
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

    private var shouldPauseAutomaticDimming: Bool {
        AmbientDimmingPolicy.shouldPause(
            screenBrightness: displayBrightness,
            enabled: settings.value.preventAutoDimmingWhenScreenBright
        )
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

    private func syncTorch() {
        guard settings.value.torchEnabled, isNightSessionActive, lampPhase != .off else {
            torch.turnOff()
            return
        }
        let progress = activeLampMaximumIntensity > 0
            ? lampIntensity / activeLampMaximumIntensity
            : 0
        torch.setLevel(progress * settings.value.torchIntensity)
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

    var orientationControlStatus: String {
        switch orientationPreference {
        case .automatic: "현재: 자동 회전"
        case .portrait: "현재: 세로 고정"
        case .landscape: "현재: 가로 고정"
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
