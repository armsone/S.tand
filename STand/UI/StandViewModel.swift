import Combine
import SwiftUI
import UIKit

enum LampPhase: Equatable {
    case off
    case holding
    case fading
}

@MainActor
final class StandViewModel: ObservableObject {
    @Published private(set) var isNightSessionActive = false
    @Published private(set) var lampIntensity = 0.0
    @Published private(set) var lampPhase: LampPhase = .off
    @Published var controlsVisible = true

    let settings: SettingsStore
    let library: RecordingLibrary
    let audio: AudioCaptureService

    private var lampTask: Task<Void, Never>?
    private var controlsTask: Task<Void, Never>?
    private var settingsSubscription: AnyCancellable?

    init() {
        let settings = SettingsStore()
        let library = RecordingLibrary()
        self.settings = settings
        self.library = library
        audio = AudioCaptureService(recordingsDirectory: library.directory)

        audio.onClap = { [weak self] in
            self?.activateLamp()
        }
        audio.onClipSaved = { [weak self] url in
            guard let self else { return }
            self.library.add(url)
        }
        audio.configure(settings: settings.value)

        settingsSubscription = settings.$value
            .dropFirst()
            .sink { [weak self] value in
                self?.audio.configure(settings: value)
            }
    }

    func startNightSession() {
        guard !isNightSessionActive else { return }
        isNightSessionActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        audio.configure(settings: settings.value)
        audio.requestAccessAndStart()
        activateLamp()
        scheduleControlsHide()
    }

    func stopNightSession() {
        guard isNightSessionActive else { return }
        isNightSessionActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        audio.stop()
        turnOffLamp(animated: true)
        controlsTask?.cancel()
        controlsVisible = true
    }

    func appDidBecomeActive() {
        guard isNightSessionActive else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        audio.startIfAuthorized()
    }

    func appWillResignActive() {
        guard isNightSessionActive else { return }
        audio.stop()
    }

    func activateLamp() {
        guard isNightSessionActive else { return }
        lampTask?.cancel()

        let now = ProcessInfo.processInfo.systemUptime
        let envelope = LampEnvelope(
            activatedAt: now,
            holdDuration: settings.value.holdDuration,
            fadeDuration: settings.value.fadeDuration,
            maximumIntensity: settings.value.lampIntensity
        )

        lampPhase = .holding
        withAnimation(.easeOut(duration: 0.3)) {
            lampIntensity = envelope.maximumIntensity
        }

        lampTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }

                let currentTime = ProcessInfo.processInfo.systemUptime
                let value = envelope.intensity(at: currentTime)
                lampPhase = currentTime <= envelope.activatedAt + envelope.holdDuration ? .holding : .fading
                lampIntensity = value

                if envelope.isFinished(at: currentTime) {
                    lampIntensity = 0
                    lampPhase = .off
                    return
                }
            }
        }
    }

    func turnOffLamp(animated: Bool) {
        lampTask?.cancel()
        lampPhase = .off
        if animated {
            withAnimation(.easeOut(duration: 0.8)) { lampIntensity = 0 }
        } else {
            lampIntensity = 0
        }
    }

    func revealControls() {
        controlsVisible = true
        scheduleControlsHide()
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
