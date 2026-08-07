import SwiftUI
import UIKit

struct HoldDurationAdjustment {
    static func value(startingAt startingValue: Double, translation: CGFloat) -> Double {
        let rawValue = startingValue + Double(translation / 300) * 290
        let steppedValue = (rawValue / 5).rounded() * 5
        return min(300, max(10, steppedValue))
    }
}

enum ScreenTapLampAction: Equatable {
    case brighten
    case dim
}

struct ScreenTapPolicy {
    static func action(for phase: LampPhase) -> ScreenTapLampAction {
        phase == .holding ? .dim : .brighten
    }
}

struct BurnInProtection {
    private static let path: [CGSize] = [
        .init(width: 0, height: 0),
        .init(width: 3, height: -2),
        .init(width: 5, height: 1),
        .init(width: 2, height: 3),
        .init(width: -2, height: 3),
        .init(width: -5, height: 1),
        .init(width: -3, height: -2),
        .init(width: 0, height: -3)
    ]

    static func offset(at date: Date) -> CGSize {
        let step = Int(date.timeIntervalSinceReferenceDate / 60)
        return path[((step % path.count) + path.count) % path.count]
    }
}

private enum PresentedSheet: String, Identifiable {
    case recordings
    case settings

    var id: String { rawValue }
}

private enum BrightnessTarget: Equatable {
    case lamp
    case silhouette
}

private struct BrightnessDragState {
    let target: BrightnessTarget
    let startingValue: Double
}

private struct BrightnessFeedback: Equatable {
    let target: BrightnessTarget
    let value: Double
}

private enum ScreenAdjustmentAxis {
    case vertical
    case horizontal
}

struct RootView: View {
    @ObservedObject private var model: StandViewModel
    @ObservedObject private var audio: AudioCaptureService
    @ObservedObject private var library: RecordingLibrary
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var weather: WeatherService
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedSheet: PresentedSheet?
    @State private var didInitialize = false
    @State private var brightnessDragState: BrightnessDragState?
    @State private var brightnessFeedback: BrightnessFeedback?
    @State private var brightnessFeedbackTask: Task<Void, Never>?
    @State private var screenAdjustmentAxis: ScreenAdjustmentAxis?
    @State private var holdDurationGestureStart: Double?
    @State private var holdDurationFeedback: Double?
    @State private var holdDurationFeedbackTask: Task<Void, Never>?
    @State private var clockScaleGestureStart: Double?
    @State private var clockScaleFeedback: Double?
    @State private var clockScaleFeedbackTask: Task<Void, Never>?

    init(model: StandViewModel) {
        _model = ObservedObject(wrappedValue: model)
        _audio = ObservedObject(wrappedValue: model.audio)
        _library = ObservedObject(wrappedValue: model.library)
        _settings = ObservedObject(wrappedValue: model.settings)
        _weather = ObservedObject(wrappedValue: model.weather)
    }

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width

            ZStack {
                LampBackground(intensity: model.lampIntensity)

                if model.isDisplayDark, didInitialize {
                    silhouetteInfo(isPortrait: isPortrait)
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    topBar(isPortrait: isPortrait)
                    Spacer(minLength: 0)
                    bottomControls(isPortrait: isPortrait)
                }
                .padding(.horizontal, isPortrait ? 20 : 32)
                .padding(.vertical, isPortrait ? 18 : 20)
                .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                centerContent(isPortrait: isPortrait)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, isPortrait ? 20 : 32)
                    .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                statusBanners
                    .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                if let brightnessFeedback {
                    BrightnessFeedbackView(feedback: brightnessFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if let clockScaleFeedback {
                    ClockScaleFeedbackView(scale: clockScaleFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }


                if let holdDurationFeedback {
                    HoldDurationFeedbackView(duration: holdDurationFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(screenAdjustmentGesture.exclusively(before: screenPressGesture))
        .simultaneousGesture(clockMagnificationGesture)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $presentedSheet, onDismiss: {
            model.resumeMonitoringAfterPlayback()
        }) { sheet in
            switch sheet {
            case .recordings:
                RecordingsView(
                    library: library,
                    playbackDisabled: false
                )
            case .settings:
                SettingsView(store: model.settings)
            }
        }
        .onAppear {
            resetTransientInterface()
            model.appDidBecomeActive()
            model.startNightSession()
            didInitialize = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                resetTransientInterface()
                model.appDidBecomeActive()
                didInitialize = true
            case .inactive, .background:
                resetTransientInterface()
                didInitialize = false
                model.appWillResignActive()
            @unknown default:
                break
            }
        }
    }

    private func resetTransientInterface() {
        brightnessFeedbackTask?.cancel()
        clockScaleFeedbackTask?.cancel()
        holdDurationFeedbackTask?.cancel()

        brightnessFeedbackTask = nil
        clockScaleFeedbackTask = nil
        holdDurationFeedbackTask = nil

        brightnessDragState = nil
        brightnessFeedback = nil
        screenAdjustmentAxis = nil
        holdDurationGestureStart = nil
        holdDurationFeedback = nil
        clockScaleGestureStart = nil
        clockScaleFeedback = nil
    }

    private func topBar(isPortrait: Bool) -> some View {
        HStack(spacing: 16) {
            Text("S.tand")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .tracking(0.8)

            if model.isNightSessionActive {
                AudioStatusPill(audio: audio, compact: isPortrait)
            }

            Spacer()

            if model.isNightSessionActive, !isPortrait {
                Label(
                    audio.isWritingClip ? "수면 소리 저장 중" : "기기에서 소리 분석 중",
                    systemImage: audio.isWritingClip ? "waveform.badge.mic" : "ear"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(audio.isWritingClip ? Color.red.opacity(0.9) : Color.white.opacity(0.55))
            } else if !model.isNightSessionActive {
                Text("버전 \(AppVersion.display)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            }

            BatteryStatusPill(status: model.batteryStatus)
        }
        .foregroundStyle(.white.opacity(0.82))
        .opacity(model.controlsVisible || !model.isNightSessionActive ? 1 : 0.18)
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
    }

    @ViewBuilder
    private func centerContent(isPortrait: Bool) -> some View {
        if model.isNightSessionActive {
            clockAndWeather(isPortrait: isPortrait, isDimmed: false)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.orange.opacity(0.8))

                Text("오늘 밤도 편안하게")
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                Text("취침을 시작하면 자동 잠금을 막고 박수와 수면 소리를 감지합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))

                Button {
                    model.startNightSession()
                } label: {
                    Label("취침 시작", systemImage: "bed.double.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityHint("자동 잠금을 막고 소리 감지를 시작합니다")
            }
            .padding(.horizontal, isPortrait ? 8 : 0)
        }
    }

    private func silhouetteInfo(isPortrait: Bool) -> some View {
        ZStack {
            clockAndWeather(isPortrait: isPortrait, isDimmed: true)

            Label(
                silhouetteBatteryText,
                systemImage: model.batteryStatus.isCharging
                    ? "battery.100percent.bolt"
                    : "battery.50percent"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(settings.value.silhouetteIntensity * 0.72))
            .offset(y: (isPortrait ? 92 : 116) * settings.value.clockScale / 2 + 52)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var silhouetteBatteryText: String {
        guard let level = model.batteryStatus.level else { return "배터리 --%" }
        return "배터리 \(Int((level * 100).rounded()))%"
    }

    private func clockAndWeather(isPortrait: Bool, isDimmed: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let burnInOffset = BurnInProtection.offset(at: context.date)
            let sharedVerticalOffset = CGFloat(isPortrait ? -36 : 0) + burnInOffset.height

            ZStack {
                NightClock(
                    phase: isDimmed ? .off : model.lampPhase,
                    intensity: isDimmed ? 0 : model.lampIntensity,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    dimmedIntensity: settings.value.silhouetteIntensity,
                    clockScale: settings.value.clockScale,
                    clockFont: settings.value.clockFont,
                    automaticDimmingEnabled: settings.value.automaticDimmingEnabled,
                    automaticDimmingPaused: model.automaticDimmingPaused,
                    manualDimmingHoldActive: model.manualDimmingHoldActive
                )
                .offset(x: burnInOffset.width, y: sharedVerticalOffset)
                .animation(.easeInOut(duration: 4), value: burnInOffset)

                WeatherBadge(
                    service: weather,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    dimmedIntensity: settings.value.silhouetteIntensity,
                    clockScale: settings.value.clockScale
                )
                .offset(
                    x: burnInOffset.width,
                    y: isPortrait
                        ? -178 - max(0, settings.value.clockScale - 1) * 62 + sharedVerticalOffset
                        : -124 - max(0, settings.value.clockScale - 1) * 40 + sharedVerticalOffset
                )
                .animation(.easeInOut(duration: 4), value: burnInOffset)
            }
        }
    }

    private var screenAdjustmentGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if screenAdjustmentAxis == nil {
                    screenAdjustmentAxis = abs(value.translation.height) > abs(value.translation.width)
                        ? .vertical
                        : .horizontal
                }

                guard screenAdjustmentAxis == .vertical else {
                    updateHoldDuration(with: value.translation.width)
                    return
                }

                let state: BrightnessDragState
                if let brightnessDragState {
                    state = brightnessDragState
                } else {
                    let target: BrightnessTarget = model.isDisplayDark ? .silhouette : .lamp
                    let startingValue = target == .silhouette
                        ? settings.value.silhouetteIntensity
                        : settings.value.lampIntensity
                    state = BrightnessDragState(target: target, startingValue: startingValue)
                    brightnessDragState = state
                    if target == .lamp {
                        model.beginManualLampAdjustment()
                    }
                }

                let change = -value.translation.height / 280
                let adjustedValue: Double
                switch state.target {
                case .lamp:
                    adjustedValue = min(1, max(0.15, state.startingValue + change))
                    model.updateManualLampBrightness(adjustedValue)
                case .silhouette:
                    adjustedValue = min(0.2, max(0.005, state.startingValue + change * 0.2))
                    settings.value.silhouetteIntensity = adjustedValue
                }

                brightnessFeedbackTask?.cancel()
                withAnimation(.easeOut(duration: 0.12)) {
                    brightnessFeedback = BrightnessFeedback(
                        target: state.target,
                        value: adjustedValue
                    )
                }
            }
            .onEnded { _ in
                switch screenAdjustmentAxis {
                case .vertical:
                    if brightnessDragState?.target == .lamp {
                        model.endManualLampAdjustment()
                    }
                    brightnessDragState = nil
                    scheduleBrightnessFeedbackHide()
                case .horizontal:
                    holdDurationGestureStart = nil
                    model.activateLamp()
                    scheduleHoldDurationFeedbackHide()
                case nil:
                    break
                }
                screenAdjustmentAxis = nil
            }
    }

    private var screenPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.8, maximumDistance: 12)
            .exclusively(before: TapGesture())
            .onEnded { result in
                switch result {
                case .first(true):
                    model.toggleManualDimmingHold()
                    model.revealControls()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                case .second:
                    handleScreenTap()
                default:
                    break
                }
            }
    }

    private func handleScreenTap() {
                if model.isNightSessionActive {
                    if ScreenTapPolicy.action(for: model.lampPhase) == .brighten {
                        model.activateLamp()
                        model.revealControls()
                    } else {
                        model.dimLampNow()
                    }
                }
    }

    private func updateHoldDuration(with horizontalTranslation: CGFloat) {
        let startingValue: Double
        if let holdDurationGestureStart {
            startingValue = holdDurationGestureStart
        } else {
            startingValue = settings.value.holdDuration
            holdDurationGestureStart = startingValue
        }

        let duration = HoldDurationAdjustment.value(
            startingAt: startingValue,
            translation: horizontalTranslation
        )
        settings.value.holdDuration = duration
        holdDurationFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            holdDurationFeedback = duration
        }
    }

    private var clockMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                let startingScale: Double
                if let clockScaleGestureStart {
                    startingScale = clockScaleGestureStart
                } else {
                    startingScale = settings.value.clockScale
                    clockScaleGestureStart = startingScale
                }

                let scale = min(1.35, max(0.7, startingScale * Double(magnification)))
                settings.value.clockScale = scale
                clockScaleFeedbackTask?.cancel()
                withAnimation(.easeOut(duration: 0.12)) {
                    clockScaleFeedback = scale
                }
            }
            .onEnded { _ in
                clockScaleGestureStart = nil
                scheduleClockScaleFeedbackHide()
            }
    }

    private func scheduleBrightnessFeedbackHide() {
        brightnessFeedbackTask?.cancel()
        brightnessFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    brightnessFeedback = nil
                }
            }
        }
    }

    private func scheduleClockScaleFeedbackHide() {
        clockScaleFeedbackTask?.cancel()
        clockScaleFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    clockScaleFeedback = nil
                }
            }
        }
    }

    private func scheduleHoldDurationFeedbackHide() {
        holdDurationFeedbackTask?.cancel()
        holdDurationFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    holdDurationFeedback = nil
                }
            }
        }
    }

    @ViewBuilder
    private func bottomControls(isPortrait: Bool) -> some View {
        if isPortrait {
            portraitBottomControls
        } else {
            landscapeBottomControls
        }
    }

    private var landscapeBottomControls: some View {
        HStack(spacing: 10) {
            if model.isNightSessionActive {
                if model.controlsVisible {
                    nightControlButtons(compact: true)
                } else {
                    tapToControlText
                }
            }

            if model.controlsVisible || !model.isNightSessionActive {
                secondaryControlButtons
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
    }

    private var portraitBottomControls: some View {
        VStack(spacing: 10) {
            if model.isNightSessionActive {
                if model.controlsVisible {
                    HStack(spacing: 8) {
                        nightControlButtons(compact: true)
                    }
                } else {
                    tapToControlText
                }
            }

            if model.controlsVisible || !model.isNightSessionActive {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    secondaryControlButtons
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
    }

    @ViewBuilder
    private func nightControlButtons(compact: Bool) -> some View {
        ControlButton(
            title: compact ? "조명 켜기" : "화면 조명 켜기",
            systemImage: "lightbulb.fill",
            hint: "화면을 밝히고 설정에 따라 플래시도 켭니다"
        ) {
            model.activateLamp()
        }
        ControlButton(
            title: "지금 어둡게",
            systemImage: "moon.fill",
            hint: "주변 밝기 보호와 관계없이 화면 조명과 플래시를 자연스럽게 어둡힙니다"
        ) {
            model.dimLampNow()
        }
        ControlButton(
            title: compact ? "감지 종료" : "취침 감지 종료",
            systemImage: "stop.circle.fill",
            role: .destructive,
            hint: "소리 감지와 자동 녹음을 종료합니다"
        ) {
            model.stopNightSession()
        }
    }

    @ViewBuilder
    private var secondaryControlButtons: some View {
        ControlButton(
            title: model.orientationControlTitle,
            systemImage: model.orientationControlImage,
            status: model.orientationControlStatus,
            hint: model.orientationPreference == .automatic
                ? "현재 화면 방향으로 고정합니다"
                : "화면 방향이 iPhone 회전을 따르도록 바꿉니다"
        ) {
            model.toggleOrientationLock()
        }
        ControlButton(
            title: "녹음 목록 보기",
            systemImage: "waveform",
            status: library.clips.isEmpty ? "저장된 녹음 없음" : "\(library.clips.count)개 저장됨",
            hint: "저장된 수면 소리 녹음 목록을 엽니다"
        ) {
            model.pauseMonitoringForPlayback()
            presentedSheet = .recordings
        }
        ControlButton(
            title: "설정 열기",
            systemImage: "slider.horizontal.3",
            hint: "밝기, 감지, 녹음 설정을 엽니다"
        ) {
            presentedSheet = .settings
        }
    }

    private var tapToControlText: some View {
        Label(
            model.lampPhase == .holding ? "탭하면 자연스럽게 어두워짐" : "탭하면 조명 켜짐",
            systemImage: model.lampPhase == .holding ? "moon.fill" : "lightbulb.fill"
        )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.24))
            .padding(.vertical, 12)
    }

    private var statusBanners: some View {
        VStack {
            if model.batteryProtectionActive {
                batteryProtectionBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let message = audio.recordingErrorMessage, model.isNightSessionActive {
                Label(message, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    private var batteryProtectionBanner: some View {
        Label(
            model.batteryStatus.isCharging
                ? "충전이 연결되었습니다. 취침 시작을 눌러 다시 시작하세요."
                : "배터리가 20% 이하라 보호를 위해 감지와 불빛을 중지했습니다.",
            systemImage: model.batteryStatus.isCharging ? "battery.100percent.bolt" : "battery.25percent"
        )
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

}

private struct LampBackground: View {
    let intensity: Double

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.62, blue: 0.28).opacity(intensity),
                    Color(red: 0.95, green: 0.27, blue: 0.06).opacity(intensity * 0.72),
                    Color.black.opacity(1 - intensity * 0.22)
                ],
                center: .center,
                startRadius: 20,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
        .animation(.linear(duration: 0.08), value: intensity)
    }
}

private struct BrightnessFeedbackView: View {
    let feedback: BrightnessFeedback

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: feedback.target == .lamp ? "sun.max.fill" : "moon.stars.fill")
                .font(.title2)

            Text(feedback.target == .lamp ? "화면 조명 밝기" : "실루엣 밝기")
                .font(.caption.weight(.semibold))

            ProgressView(value: normalizedValue)
                .tint(.white.opacity(0.82))
                .frame(width: 120)

            Text("\(displayPercent)%")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white.opacity(feedback.target == .lamp ? 0.86 : 0.34))
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var normalizedValue: Double {
        switch feedback.target {
        case .lamp: (feedback.value - 0.15) / 0.85
        case .silhouette: (feedback.value - 0.005) / 0.195
        }
    }

    private var displayPercent: Int {
        Int((normalizedValue * 100).rounded())
    }
}

private struct ClockScaleFeedbackView: View {
    let scale: Double

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.title2)
            Text("시계 크기")
                .font(.caption.weight(.semibold))
            Text("\(Int((scale * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct HoldDurationFeedbackView: View {
    let duration: Double

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.title2)
            Text("어두워지기까지")
                .font(.caption.weight(.semibold))
            ProgressView(value: (duration - 10) / 290)
                .tint(.white.opacity(0.82))
                .frame(width: 140)
            Text(durationText)
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        let seconds = Int(duration.rounded())
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}

private struct WeatherBadge: View {
    @ObservedObject var service: WeatherService
    let isPortrait: Bool
    let isDimmed: Bool
    let dimmedIntensity: Double
    var clockScale = 1.0

    var body: some View {
        Group {
            if isPortrait {
                HStack(spacing: 16) {
                    weatherIcon
                    weatherInformation
                }
                .padding(.horizontal, 24)
                .frame(width: 282, height: 92)
                .background(
                    FlipPanelSurface(isDimmed: isDimmed, cornerRadius: 18, splitGap: 4)
                )
            } else {
                HStack(spacing: 12) {
                    weatherIcon
                        .frame(width: 88, height: 72)
                        .background(
                            FlipPanelSurface(isDimmed: isDimmed, cornerRadius: 18, splitGap: 3)
                        )

                    weatherInformation
                        .padding(.leading, 20)
                        .frame(width: 270, height: 72, alignment: .leading)
                        .background(
                            FlipPanelSurface(isDimmed: isDimmed, cornerRadius: 18, splitGap: 3)
                        )
                }
                .frame(width: 370, height: 72)
            }
        }
        .foregroundStyle(.white.opacity(isDimmed ? dimmedIntensity : 0.62))
        .scaleEffect(clockScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var weatherIcon: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: isPortrait ? 34 : 30, weight: .medium))
    }

    private var weatherInformation: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(primaryText)
                .font(.title3.weight(.semibold))
            if let secondaryText {
                Text(secondaryText)
                    .font(.caption)
                    .opacity(0.72)
            }
        }
    }

    private var systemImage: String {
        if let weather = service.weather { return weather.systemImage }
        return switch service.availability {
        case .locationDenied: "location.slash.fill"
        case .failed: "exclamationmark.icloud.fill"
        default: "location.fill"
        }
    }

    private var primaryText: String {
        if let weather = service.weather {
            return "\(Int(weather.temperature.rounded()))°  \(weather.summary)"
        }
        return switch service.availability {
        case .idle, .requestingLocation: "현재 위치 확인 중"
        case .loading: "날씨 불러오는 중"
        case .locationDenied: "위치 권한 필요"
        case .failed: "날씨 확인 필요"
        case .available: "날씨 정보"
        }
    }

    private var secondaryText: String? {
        guard let weather = service.weather else {
            return service.availability == .locationDenied ? "설정에서 위치 접근을 허용해 주세요" : nil
        }
        var parts = ["체감 \(Int(weather.apparentTemperature.rounded()))°"]
        if weather.precipitation > 0 {
            parts.append("강수 \(weather.precipitation.formatted(.number.precision(.fractionLength(1))))mm")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        [primaryText, secondaryText].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct NightClock: View {
    let phase: LampPhase
    let intensity: Double
    let isPortrait: Bool
    let isDimmed: Bool
    let dimmedIntensity: Double
    let clockScale: Double
    let clockFont: ClockFontChoice
    let automaticDimmingEnabled: Bool
    let automaticDimmingPaused: Bool
    let manualDimmingHoldActive: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                FlipClockFace(
                    date: context.date,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockScale: clockScale,
                    clockFont: clockFont
                )

                VStack(spacing: 5) {
                Text(context.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(isDimmed ? dimmedIntensity : 0.48))

                if !isDimmed {
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.36))
                        .padding(.top, 6)
                }
                }
                .offset(
                    y: (isPortrait ? 92 : 116) * clockScale / 2
                        + (isDimmed ? 12 : 24)
                )
            }
            .foregroundStyle(
                .white.opacity(isDimmed ? dimmedIntensity : max(0.12, min(0.88, 0.22 + intensity)))
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        if manualDimmingHoldActive {
            return "현재 상태 · 롱 터치 밝기 고정 중"
        }
        if !automaticDimmingEnabled {
            return "현재 상태 · 자동 디밍 꺼짐 · 화면 밝기 유지 중"
        }
        if automaticDimmingPaused {
            return "현재 상태 · 밝은 환경으로 판단해 자동 감광 보류 중"
        }
        return switch phase {
        case .off: "대기 상태 · 박수 또는 화면 탭을 기다리는 중"
        case .holding: "현재 상태 · 조명 켜짐 · 탭하면 자연스럽게 어두워짐"
        case .fading: "현재 상태 · 화면 조명이 서서히 어두워지는 중"
        }
    }
}

private struct FlipClockFace: View {
    let date: Date
    let isPortrait: Bool
    let isDimmed: Bool
    let clockScale: Double
    let clockFont: ClockFontChoice

    var body: some View {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        HStack(spacing: isPortrait ? 8 : 12) {
                FlipClockCard(
                    value: String(format: "%02d", components.hour ?? 0),
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockFont: clockFont
                )
                Text(":")
                    .font(clockFont.font(size: isPortrait ? 48 : 62))
                    .opacity(isDimmed ? 0.42 : 0.72)
                    .offset(y: clockFont.clockVerticalOffset(size: isPortrait ? 48 : 62))
                ZStack(alignment: .bottomTrailing) {
                    FlipClockCard(
                        value: String(format: "%02d", components.minute ?? 0),
                        isPortrait: isPortrait,
                        isDimmed: isDimmed,
                        clockFont: clockFont
                    )

                    Text(String(format: "%02d", components.second ?? 0))
                        .font(clockFont.font(size: isPortrait ? 13 : 16))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(isDimmed ? 0.04 : 0.10))
                        .contentTransition(.numericText())
                        .frame(width: isPortrait ? 24 : 30)
                        .padding(.trailing, isPortrait ? 20 : 26)
                        .padding(.bottom, isPortrait ? 7 : 9)
                }
        }
        .scaleEffect(clockScale)
        .frame(height: (isPortrait ? 92 : 116) * clockScale)
        .animation(.snappy(duration: 0.42), value: components.minute)
        .animation(.easeInOut(duration: 0.18), value: components.second)
    }
}

private struct FlipClockCard: View {
    let value: String
    let isPortrait: Bool
    let isDimmed: Bool
    let clockFont: ClockFontChoice

    var body: some View {
        ZStack {
            FlipPanelSurface(
                isDimmed: isDimmed,
                cornerRadius: isPortrait ? 18 : 22
            )

            Text(value)
                .font(clockFont.font(size: isPortrait ? 64 : 82))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.42), value: value)
                .offset(y: clockFont.clockVerticalOffset(size: isPortrait ? 64 : 82))
        }
        .frame(
            width: isPortrait ? 126 : 164,
            height: isPortrait ? 92 : 116
        )
    }
}

private struct FlipPanelSurface: View {
    let isDimmed: Bool
    let cornerRadius: CGFloat
    var splitGap: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(isDimmed ? 0.014 : 0.095),
                        .white.opacity(isDimmed ? 0.008 : 0.052)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .mask {
                VStack(spacing: splitGap) {
                    Rectangle()
                    Rectangle()
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(isDimmed ? 0.018 : 0.08), lineWidth: 1)
            }
    }
}

private struct AudioStatusPill: View {
    @ObservedObject var audio: AudioCaptureService
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Group {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(statusColor.opacity(0.9))
                                .frame(width: max(3, proxy.size.width * audio.normalizedLevel))
                        }
                }
                .frame(width: compact ? 32 : 44, height: 5)
            }

            Text(statusText)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.07), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusText), 감지 레벨 \(Int((audio.normalizedLevel * 100).rounded()))퍼센트")
    }

    private var statusColor: Color {
        if audio.isWritingClip { return .red }
        if audio.state == .monitoring { return .green }
        return .orange
    }

    private var statusText: String {
        if audio.microphoneAccess == .denied {
            return compact ? "감지 안 됨" : "소리 감지 안 됨"
        }
        if audio.isWritingClip { return compact ? "저장" : "저장 중" }
        switch audio.state {
        case .monitoring: return compact ? "감지" : "감지 중"
        case .starting: return compact ? "준비" : "준비 중"
        case .failed: return compact ? "감지 안 됨" : "소리 감지 안 됨"
        case .stopped: return "정지됨"
        }
    }
}

private struct BatteryStatusPill: View {
    let status: DeviceBatteryStatus

    var body: some View {
        Label(levelText, systemImage: systemImage)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(status.shouldProtectBattery ? Color.orange : Color.white.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.white.opacity(0.07), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(accessibilityText)
    }

    private var levelText: String {
        guard let level = status.level else { return "--%" }
        return "\(Int((level * 100).rounded()))%"
    }

    private var systemImage: String {
        if status.isCharging { return "battery.100percent.bolt" }
        guard let level = status.level else { return "battery.0percent" }
        return switch level {
        case ...0.2: "battery.25percent"
        case ...0.5: "battery.50percent"
        case ...0.75: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private var accessibilityText: String {
        status.isCharging ? "배터리 \(levelText), 충전 중" : "배터리 \(levelText)"
    }
}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    var status: String? = nil
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24, height: 20)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if let status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(role == .destructive ? Color.red.opacity(0.9) : Color.white.opacity(0.78))
            .padding(.horizontal, 6)
            .frame(width: 102, height: 72)
            .background {
                FlipPanelSurface(isDimmed: false, cornerRadius: 15, splitGap: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint ?? "")
    }
}
