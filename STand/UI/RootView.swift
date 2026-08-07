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
    @Environment(\.openURL) private var openURL
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
    @State private var isEditingScreen = false
    @State private var editingLayout = StandScreenLayout.portrait
    @State private var editingIsPortrait = true
    @State private var currentIsPortrait = true
    @State private var currentCanvasSize = CGSize.zero
    @State private var currentProtectedInsets = EdgeInsets()

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

                if !isEditingScreen {
                    if model.isDisplayDark, didInitialize {
                        silhouetteInfo(isPortrait: isPortrait, canvasSize: proxy.size)
                            .transition(.opacity)
                    }

                    VStack(spacing: 0) {
                        topBar(isPortrait: isPortrait)
                        Spacer(minLength: 0)
                        bottomControls(isPortrait: isPortrait)
                    }
                    .padding(.horizontal, isPortrait ? 20 : 32)
                    .padding(.top, isPortrait ? 18 : 20)
                    .padding(.bottom, isPortrait ? 18 : 6)
                    .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                    centerContent(isPortrait: isPortrait, canvasSize: proxy.size)
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

                if isEditingScreen {
                    ScreenEditorView(
                        layout: $editingLayout,
                        isPortrait: editingIsPortrait,
                        weather: weather,
                        clockFont: Binding(
                            get: { settings.value.clockFont },
                            set: { settings.value.clockFont = $0 }
                        ),
                        hourMode: Binding(
                            get: { settings.value.clockHourMode },
                            set: { settings.value.clockHourMode = $0 }
                        ),
                        threshold: Binding(
                            get: { settings.value.brightnessModeThreshold },
                            set: { settings.value.brightnessModeThreshold = $0 }
                        ),
                        screenScale: settings.value.clockScale,
                        currentBrightness: model.displayBrightness,
                        batteryText: silhouetteBatteryText,
                        onReset: {
                            editingLayout = editingIsPortrait ? .portrait : .landscape
                        },
                        onSave: saveScreenLayout
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .onAppear {
                currentIsPortrait = isPortrait
                updateCanvasMetrics(proxy: proxy, isPortrait: isPortrait)
            }
            .onChange(of: proxy.size) { _, _ in
                updateCanvasMetrics(proxy: proxy, isPortrait: isPortrait)
            }
            .onChange(of: isPortrait) { _, value in currentIsPortrait = value }
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
    private func centerContent(isPortrait: Bool, canvasSize: CGSize) -> some View {
        if model.isNightSessionActive {
            clockAndWeather(isPortrait: isPortrait, isDimmed: false, canvasSize: canvasSize)
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

    private func silhouetteInfo(isPortrait: Bool, canvasSize: CGSize) -> some View {
        clockAndWeather(isPortrait: isPortrait, isDimmed: true, canvasSize: canvasSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var silhouetteBatteryText: String {
        guard let level = model.batteryStatus.level else { return "배터리 --%" }
        return "배터리 \(Int((level * 100).rounded()))%"
    }

    private func clockAndWeather(
        isPortrait: Bool,
        isDimmed: Bool,
        canvasSize: CGSize
    ) -> some View {
        DashboardCanvas(
            service: weather,
            layout: isPortrait ? settings.value.portraitLayout : settings.value.landscapeLayout,
            canvasSize: canvasSize,
            isPortrait: isPortrait,
            isDimmed: isDimmed,
            dimmedIntensity: settings.value.silhouetteIntensity,
            intensity: isDimmed ? 0 : model.lampIntensity,
            clockScale: settings.value.clockScale,
            clockFont: settings.value.clockFont,
            hourMode: settings.value.clockHourMode,
            statusText: dashboardStatusText,
            batteryText: silhouetteBatteryText,
            batterySystemImage: model.batteryStatus.isCharging
                ? "battery.100percent.bolt"
                : "battery.50percent",
            currentBrightness: model.displayBrightness,
            brightnessThreshold: Binding(
                get: { settings.value.brightnessModeThreshold },
                set: { settings.value.brightnessModeThreshold = $0 }
            )
        )
    }

    private var dashboardStatusText: String {
        if model.displayBrightness < settings.value.brightnessModeThreshold {
            return "현재 상태 · 슬리핑 모드"
        }
        return switch model.lampPhase {
        case .off: "현재 상태 · 잠자기 모드"
        case .holding: "현재 상태 · 스탠드 모드"
        case .fading: "현재 상태 · 스탠드 감광 중"
        }
    }

    private func enterScreenEditing(isPortrait: Bool) {
        editingIsPortrait = isPortrait
        editingLayout = isPortrait ? settings.value.portraitLayout : settings.value.landscapeLayout
        model.revealControls()
        withAnimation(.easeOut(duration: 0.25)) { isEditingScreen = true }
    }

    private func saveScreenLayout() {
        if editingIsPortrait {
            settings.value.portraitLayout = editingLayout
        } else {
            settings.value.landscapeLayout = editingLayout
        }
        withAnimation(.easeOut(duration: 0.25)) { isEditingScreen = false }
    }

    private var screenAdjustmentGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isEditingScreen else { return }
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
                guard !isEditingScreen else { return }
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
                    guard !isEditingScreen else { return }
                    enterScreenEditing(isPortrait: currentIsPortrait)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                case .second:
                    handleScreenTap()
                default:
                    break
                }
            }
    }

    private func handleScreenTap() {
                guard !isEditingScreen else { return }
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
                guard !isEditingScreen else { return }
                let startingScale: Double
                if let clockScaleGestureStart {
                    startingScale = clockScaleGestureStart
                } else {
                    startingScale = settings.value.clockScale
                    clockScaleGestureStart = startingScale
                }

                let requestedScale = max(0.7, startingScale * Double(magnification))
                let layout = currentIsPortrait
                    ? settings.value.portraitLayout
                    : settings.value.landscapeLayout
                let maximumScale = PanelEditingPolicy.maximumScreenScale(
                    layout: layout,
                    isPortrait: currentIsPortrait,
                    canvasSize: currentCanvasSize,
                    insets: currentProtectedInsets,
                    hardLimit: 1.35
                )
                let scale = min(max(maximumScale, startingScale), requestedScale)
                settings.value.clockScale = scale
                clockScaleFeedbackTask?.cancel()
                withAnimation(.easeOut(duration: 0.12)) {
                    clockScaleFeedback = scale
                }
            }
            .onEnded { _ in
                guard !isEditingScreen else { return }
                clockScaleGestureStart = nil
                scheduleClockScaleFeedbackHide()
            }
    }

    private func updateCanvasMetrics(proxy: GeometryProxy, isPortrait: Bool) {
        currentCanvasSize = proxy.size
        currentProtectedInsets = PanelEditingPolicy.protectedInsets(
            safeAreaInsets: proxy.safeAreaInsets,
            isPortrait: isPortrait
        )
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
            title: "플래시 연동",
            systemImage: settings.value.torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
            status: settings.value.torchEnabled ? "화면 점등과 함께 켜짐" : "사용 안 함",
            hint: "화면이 켜질 때 후면 플래시를 함께 켤지 바꿉니다"
        ) {
            settings.value.torchEnabled.toggle()
            if settings.value.torchEnabled { model.activateLamp() }
        }
        ControlButton(
            title: "AiShot 실행",
            systemImage: "camera.aperture",
            hint: "HanClip의 AiShot 촬영 화면을 엽니다"
        ) {
            if let url = URL(string: "hanclip://aishot") { openURL(url) }
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

            Text(feedback.target == .lamp ? "화면 조명 밝기" : "슬리핑 모드 밝기")
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

private enum WeatherPiece: Int, CaseIterable, Identifiable {
    case icon
    case temperature
    case condition

    var id: Int { rawValue }
}

private extension StandScreenLayout {
    func weatherTransform(at index: Int) -> PanelTransform {
        switch index {
        case 0: weatherIcon
        case 1: weatherTemperature
        default: weatherCondition
        }
    }

    mutating func setWeatherTransform(_ transform: PanelTransform, at index: Int) {
        switch index {
        case 0: weatherIcon = transform
        case 1: weatherTemperature = transform
        default: weatherCondition = transform
        }
    }
}

private struct DashboardCanvas: View {
    @ObservedObject var service: WeatherService
    let layout: StandScreenLayout
    let canvasSize: CGSize
    let isPortrait: Bool
    let isDimmed: Bool
    let dimmedIntensity: Double
    let intensity: Double
    let clockScale: Double
    let clockFont: ClockFontChoice
    let hourMode: ClockHourMode
    let statusText: String
    let batteryText: String
    let batterySystemImage: String
    let currentBrightness: Double
    @Binding var brightnessThreshold: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let drift = BurnInProtection.offset(at: context.date)
            ZStack {
                FlipClockFace(
                    date: context.date,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockScale: 1,
                    clockFont: clockFont,
                    hourMode: hourMode
                )

                Text(context.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .panelTransform(layout.date, canvasSize: canvasSize)

                Text(statusText)
                    .font(.caption.weight(.medium))
                    .panelTransform(layout.status, canvasSize: canvasSize)

                BrightnessRuleBar(
                    currentBrightness: currentBrightness,
                    threshold: $brightnessThreshold,
                    isDimmed: isDimmed
                )
                .panelTransform(layout.brightnessRule, canvasSize: canvasSize)
                .allowsHitTesting(!isDimmed)

                if isDimmed {
                    Label(batteryText, systemImage: batterySystemImage)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.04), in: Capsule())
                        .panelTransform(layout.battery, canvasSize: canvasSize)
                }

                WeatherPanelCollection(
                    service: service,
                    layout: layout,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    globalScale: 1,
                    canvasSize: canvasSize
                )
            }
            .scaleEffect(clockScale, anchor: .center)
            .foregroundStyle(
                .white.opacity(isDimmed ? dimmedIntensity : max(0.12, min(0.88, 0.22 + intensity)))
            )
            .offset(drift)
            .animation(.easeInOut(duration: 4), value: drift)
        }
    }
}

private extension View {
    func panelTransform(
        _ transform: PanelTransform,
        canvasSize: CGSize,
        globalScale: Double = 1
    ) -> some View {
        scaleEffect(transform.scale * globalScale)
            .offset(
                x: transform.x * canvasSize.width,
                y: transform.y * canvasSize.height
            )
    }
}

private struct WeatherPanelCollection: View {
    @ObservedObject var service: WeatherService
    let layout: StandScreenLayout
    let isPortrait: Bool
    let isDimmed: Bool
    let globalScale: Double
    let canvasSize: CGSize

    var body: some View {
        let groupIDs = Array(Set(layout.weatherGroupIDs)).sorted()
        ForEach(groupIDs, id: \.self) { groupID in
            let pieces = WeatherPiece.allCases.filter {
                layout.weatherGroupIDs[$0.rawValue] == groupID
            }
            if let first = pieces.first {
                WeatherGroupPanel(
                    service: service,
                    pieces: pieces,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed
                )
                .panelTransform(
                    layout.weatherTransform(at: first.rawValue),
                    canvasSize: canvasSize,
                    globalScale: globalScale
                )
            }
        }
    }
}

private struct WeatherGroupPanel: View {
    @ObservedObject var service: WeatherService
    let pieces: [WeatherPiece]
    let isPortrait: Bool
    let isDimmed: Bool

    var body: some View {
        let totalWidth: CGFloat = isPortrait ? 282 : 370
        let cell = totalWidth / 3
        HStack(spacing: 0) {
            ForEach(pieces) { piece in
                WeatherPieceContent(service: service, piece: piece, isPortrait: isPortrait)
                    .frame(width: cell, height: cell)
            }
        }
        .frame(width: cell * CGFloat(pieces.count), height: cell)
        .background(
            FlipPanelSurface(
                isDimmed: isDimmed,
                cornerRadius: isPortrait ? 18 : 20,
                splitGap: isPortrait ? 4 : 3
            )
        )
    }
}

private struct WeatherPieceContent: View {
    @ObservedObject var service: WeatherService
    let piece: WeatherPiece
    let isPortrait: Bool

    var body: some View {
        Group {
            switch piece {
            case .icon:
                Image(systemName: service.weather?.systemImage ?? "location.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: isPortrait ? 34 : 40, weight: .medium))
            case .temperature:
                VStack(spacing: isPortrait ? 2 : 3) {
                    Text(service.weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--°")
                        .font(.system(size: isPortrait ? 28 : 34, weight: .semibold, design: .rounded))
                    Text(service.weather.map { "체감 \(Int($0.apparentTemperature.rounded()))°" } ?? "체감 --°")
                        .font(.system(size: isPortrait ? 11 : 13, weight: .medium, design: .rounded))
                        .opacity(0.72)
                }
            case .condition:
                Text(service.weather?.summary ?? "날씨")
                    .font(.system(size: isPortrait ? 17 : 20, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
    }
}

private struct BrightnessRuleBar: View {
    let currentBrightness: Double
    @Binding var threshold: Double
    let isDimmed: Bool

    var body: some View {
        VStack(spacing: 1) {
            HStack {
                Text("슬리핑")
                    .foregroundStyle(currentBrightness < threshold ? Color.orange : Color.white.opacity(0.42))
                Spacer()
                Text("현재 \(Int((currentBrightness * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("스탠드")
                    .foregroundStyle(currentBrightness >= threshold ? Color.orange : Color.white.opacity(0.42))
            }
            .font(.system(size: 8, weight: .medium))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14)).frame(height: 2)
                    Circle()
                        .fill(Color.orange.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .offset(x: max(0, proxy.size.width - 6) * currentBrightness)
                }
            }
            .frame(height: 6)

            Slider(value: $threshold, in: 0...1)
                .tint(.white.opacity(0.48))
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 38)
        .background(.black.opacity(isDimmed ? 0.06 : 0.12), in: Capsule())
        .opacity(isDimmed ? 0.5 : 0.8)
        .accessibilityLabel("밝기 기준, 현재 \(Int(currentBrightness * 100))퍼센트, 기준 \(Int(threshold * 100))퍼센트")
    }
}

private struct ScreenEditorView: View {
    @Binding var layout: StandScreenLayout
    let isPortrait: Bool
    @ObservedObject var weather: WeatherService
    @Binding var clockFont: ClockFontChoice
    @Binding var hourMode: ClockHourMode
    @Binding var threshold: Double
    let screenScale: Double
    let currentBrightness: Double
    let batteryText: String
    let onReset: () -> Void
    let onSave: () -> Void
    @State private var showFontPalette = false

    var body: some View {
        GeometryReader { proxy in
            let protectedInsets = PanelEditingPolicy.protectedInsets(
                safeAreaInsets: proxy.safeAreaInsets,
                isPortrait: isPortrait,
                fontPaletteVisible: showFontPalette
            )

            ZStack {
                Color.black.opacity(0.32).ignoresSafeArea()

                Rectangle().fill(.white.opacity(0.16)).frame(width: 0.5)
                Rectangle().fill(.white.opacity(0.16)).frame(height: 0.5)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    FlipClockFace(
                        date: context.date,
                        isPortrait: isPortrait,
                        isDimmed: false,
                        clockScale: 1,
                        clockFont: clockFont,
                        hourMode: hourMode
                    )
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture(count: 2).onEnded {
                            hourMode.toggle()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    )
                    .onTapGesture { showFontPalette.toggle() }
                }

                editableWeatherPanels(
                    canvasSize: proxy.size,
                    protectedInsets: protectedInsets
                )

                EditablePanel(
                    transform: $layout.date,
                    canvasSize: proxy.size,
                    protectedInsets: protectedInsets,
                    screenScale: screenScale
                ) {
                    Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                EditablePanel(
                    transform: $layout.status,
                    canvasSize: proxy.size,
                    protectedInsets: protectedInsets,
                    screenScale: screenScale
                ) {
                    Text("현재 상태 · 스탠드 모드")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                EditablePanel(
                    transform: $layout.brightnessRule,
                    canvasSize: proxy.size,
                    protectedInsets: protectedInsets,
                    screenScale: screenScale
                ) {
                    BrightnessRuleBar(
                        currentBrightness: currentBrightness,
                        threshold: $threshold,
                        isDimmed: false
                    )
                }

                EditablePanel(
                    transform: $layout.battery,
                    canvasSize: proxy.size,
                    protectedInsets: protectedInsets,
                    screenScale: screenScale
                ) {
                    Label(batteryText, systemImage: "battery.100percent.bolt")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                if showFontPalette {
                    VStack {
                        Spacer()
                        fontPalette
                    }
                    .padding(.horizontal, isPortrait ? 14 : 28)
                    .padding(.bottom, isPortrait ? 22 : 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
                }

                VStack {
                    HStack {
                        Button("초기화", action: onReset)
                        Spacer()
                        Text(isPortrait ? "세로 화면 편집" : "가로 화면 편집")
                            .font(.headline)
                        Spacer()
                        Button("저장", action: onSave)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(isPortrait ? 18 : 14)
                .zIndex(10)
            }
            .foregroundStyle(.white.opacity(0.86))
        }
    }

    @ViewBuilder
    private func editableWeatherPanels(
        canvasSize: CGSize,
        protectedInsets: EdgeInsets
    ) -> some View {
        let groupIDs = Array(Set(layout.weatherGroupIDs)).sorted()
        ForEach(groupIDs, id: \.self) { groupID in
            let pieces = WeatherPiece.allCases.filter {
                layout.weatherGroupIDs[$0.rawValue] == groupID
            }
            EditablePanel(
                transform: weatherBinding(for: groupID),
                canvasSize: canvasSize,
                protectedInsets: protectedInsets,
                screenScale: screenScale,
                onEnded: { mergeWeatherGroup(groupID, canvasSize: canvasSize) }
            ) {
                WeatherGroupPanel(
                    service: weather,
                    pieces: pieces,
                    isPortrait: isPortrait,
                    isDimmed: false
                )
            }
            .onTapGesture(count: 2) {
                if pieces.count > 1 { splitWeatherGroup(groupID) }
            }
        }
    }

    private func weatherBinding(for groupID: Int) -> Binding<PanelTransform> {
        Binding(
            get: {
                let index = layout.weatherGroupIDs.firstIndex(of: groupID) ?? 0
                return layout.weatherTransform(at: index)
            },
            set: { newValue in
                for index in layout.weatherGroupIDs.indices where layout.weatherGroupIDs[index] == groupID {
                    layout.setWeatherTransform(newValue, at: index)
                }
            }
        )
    }

    private func mergeWeatherGroup(_ groupID: Int, canvasSize: CGSize) {
        let sourceIndices = layout.weatherGroupIDs.indices.filter { layout.weatherGroupIDs[$0] == groupID }
        guard let sourceIndex = sourceIndices.first else { return }
        let source = layout.weatherTransform(at: sourceIndex)
        let candidates = Array(Set(layout.weatherGroupIDs)).filter { $0 != groupID }
        let sourceBounds = weatherBounds(for: groupID, canvasSize: canvasSize)
        guard let targetID = candidates.max(by: {
            PanelEditingPolicy.overlapFraction(
                sourceBounds,
                weatherBounds(for: $0, canvasSize: canvasSize)
            ) < PanelEditingPolicy.overlapFraction(
                sourceBounds,
                weatherBounds(for: $1, canvasSize: canvasSize)
            )
        }) else { return }
        let target = weatherBinding(for: targetID).wrappedValue
        let overlap = PanelEditingPolicy.overlapFraction(
            sourceBounds,
            weatherBounds(for: targetID, canvasSize: canvasSize)
        )
        guard overlap >= 0.10 else { return }

        let targetIndices = layout.weatherGroupIDs.indices.filter { layout.weatherGroupIDs[$0] == targetID }
        let leftIndex = (sourceIndices + targetIndices).min {
            layout.weatherTransform(at: $0).x < layout.weatherTransform(at: $1).x
        } ?? sourceIndex
        var merged = layout.weatherTransform(at: leftIndex)
        merged.x = (source.x + target.x) / 2
        merged.y = (source.y + target.y) / 2
        for index in sourceIndices + targetIndices {
            layout.weatherGroupIDs[index] = targetID
            layout.setWeatherTransform(merged, at: index)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func splitWeatherGroup(_ groupID: Int) {
        let indices = layout.weatherGroupIDs.indices.filter { layout.weatherGroupIDs[$0] == groupID }
        guard indices.count > 1, let first = indices.first else { return }
        let center = layout.weatherTransform(at: first)
        for (position, index) in indices.enumerated() {
            layout.weatherGroupIDs[index] = index
            var transform = center
            transform.x += Double(position) * 0.16 - Double(indices.count - 1) * 0.08
            layout.setWeatherTransform(transform, at: index)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func weatherBounds(for groupID: Int, canvasSize: CGSize) -> CGRect {
        let piecesCount = layout.weatherGroupIDs.filter { $0 == groupID }.count
        let transform = weatherBinding(for: groupID).wrappedValue
        let totalWidth: CGFloat = isPortrait ? 282 : 370
        let cell = totalWidth / 3
        let width = cell * CGFloat(piecesCount) * transform.scale
        let height = cell * transform.scale
        let center = CGPoint(
            x: canvasSize.width / 2 + transform.x * canvasSize.width,
            y: canvasSize.height / 2 + transform.y * canvasSize.height
        )
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    private var fontPalette: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(ClockFontChoice.allCases) { choice in
                    Button {
                        clockFont = choice
                    } label: {
                        FontMiniClock(choice: choice, selected: choice == clockFont)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: isPortrait ? 390 : 650, maxHeight: isPortrait ? 190 : 126)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

enum PanelEditingPolicy {
    static func protectedInsets(
        safeAreaInsets: EdgeInsets,
        isPortrait: Bool,
        fontPaletteVisible: Bool = false
    ) -> EdgeInsets {
        let controlBoundary = safeAreaInsets.bottom + (isPortrait ? 184 : 84)
        let fontPaletteBoundary = safeAreaInsets.bottom + (isPortrait ? 250 : 148)
        return EdgeInsets(
            top: safeAreaInsets.top + (isPortrait ? 76 : 66),
            leading: isPortrait ? 14 : 24,
            bottom: fontPaletteVisible
                ? max(controlBoundary, fontPaletteBoundary)
                : controlBoundary,
            trailing: isPortrait ? 14 : 24
        )
    }

    static func shouldSnapToVerticalCenter(centerOffset: CGFloat, panelWidth: CGFloat) -> Bool {
        panelWidth > 0 && abs(centerOffset) <= panelWidth * 0.05
    }

    static func overlapFraction(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smallerArea > 0 else { return 0 }
        return intersection.width * intersection.height / smallerArea
    }

    static func clampedCenter(
        _ proposed: CGPoint,
        panelSize: CGSize,
        canvasSize: CGSize,
        insets: EdgeInsets
    ) -> CGPoint {
        let halfWidth = panelSize.width / 2
        let halfHeight = panelSize.height / 2
        let minimumX = insets.leading + halfWidth
        let maximumX = max(minimumX, canvasSize.width - insets.trailing - halfWidth)
        let minimumY = insets.top + halfHeight
        let maximumY = max(minimumY, canvasSize.height - insets.bottom - halfHeight)
        return CGPoint(
            x: min(maximumX, max(minimumX, proposed.x)),
            y: min(maximumY, max(minimumY, proposed.y))
        )
    }

    static func clampedTransform(
        _ transform: PanelTransform,
        panelSize: CGSize,
        canvasSize: CGSize,
        insets: EdgeInsets,
        screenScale: Double
    ) -> PanelTransform {
        guard canvasSize.width > 0, canvasSize.height > 0, panelSize != .zero else {
            return transform
        }

        // 편집 화면 자체와 저장 후 전체 확대 화면 중 더 큰 쪽을 기준으로 제한한다.
        // 전체 화면이 축소된 상태에서도 편집 패널이 버튼 경계를 넘어가지 않는다.
        let groupScale = max(1, screenScale)
        let renderedSize = CGSize(
            width: panelSize.width * transform.scale * groupScale,
            height: panelSize.height * transform.scale * groupScale
        )
        let proposedCenter = CGPoint(
            x: canvasSize.width / 2 + transform.x * canvasSize.width * groupScale,
            y: canvasSize.height / 2 + transform.y * canvasSize.height * groupScale
        )
        let center = clampedCenter(
            proposedCenter,
            panelSize: renderedSize,
            canvasSize: canvasSize,
            insets: insets
        )
        var result = transform
        result.x = (center.x - canvasSize.width / 2) / (canvasSize.width * groupScale)
        result.y = (center.y - canvasSize.height / 2) / (canvasSize.height * groupScale)
        return result
    }

    static func maximumScreenScale(
        layout: StandScreenLayout,
        isPortrait: Bool,
        canvasSize: CGSize,
        insets: EdgeInsets,
        hardLimit: Double
    ) -> Double {
        guard canvasSize.height > 0 else { return hardLimit }
        let canvasCenterY = canvasSize.height / 2
        let topRoom = max(0, canvasCenterY - insets.top)
        let bottomRoom = max(0, canvasSize.height - insets.bottom - canvasCenterY)
        let weatherHeight: CGFloat = (isPortrait ? 282 : 370) / 3
        let panels: [(PanelTransform, CGFloat)] = [
            (layout.weatherIcon, weatherHeight),
            (layout.weatherTemperature, weatherHeight),
            (layout.weatherCondition, weatherHeight),
            (layout.date, 36),
            (layout.status, 36),
            (layout.brightnessRule, 38),
            (layout.battery, 36),
            (.init(x: 0, y: 0), isPortrait ? 92 : 116)
        ]

        var maximum = hardLimit
        for (transform, baseHeight) in panels {
            let centerOffset = CGFloat(transform.y) * canvasSize.height
            let halfHeight = baseHeight * transform.scale / 2
            let topReach = halfHeight - centerOffset
            let bottomReach = halfHeight + centerOffset
            if topReach > 0 { maximum = min(maximum, Double(topRoom / topReach)) }
            if bottomReach > 0 { maximum = min(maximum, Double(bottomRoom / bottomReach)) }
        }
        return max(0.7, maximum)
    }
}

private struct EditablePanelSizeKey: PreferenceKey {
    static var defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct EditablePanel<Content: View>: View {
    @Binding var transform: PanelTransform
    let canvasSize: CGSize
    let protectedInsets: EdgeInsets
    let screenScale: Double
    var onEnded: () -> Void = {}
    @ViewBuilder let content: () -> Content
    @State private var dragStart: PanelTransform?
    @State private var scaleStart: Double?
    @State private var panelSize = CGSize.zero

    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: EditablePanelSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(EditablePanelSizeKey.self) { measuredSize in
                panelSize = measuredSize
                constrainToEditableArea(panelSize: measuredSize)
            }
            .onChange(of: protectedInsets.bottom) { _, _ in
                constrainToEditableArea()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .panelTransform(transform, canvasSize: canvasSize)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let start = dragStart ?? transform
                        dragStart = start
                        transform.x = min(0.46, max(-0.46, start.x + value.translation.width / canvasSize.width))
                        transform.y = min(0.44, max(-0.44, start.y + value.translation.height / canvasSize.height))
                        constrainToEditableArea()
                    }
                    .onEnded { _ in
                        let centerOffset = CGFloat(transform.x) * canvasSize.width
                        let renderedWidth = panelSize.width * transform.scale
                        if PanelEditingPolicy.shouldSnapToVerticalCenter(
                            centerOffset: centerOffset,
                            panelWidth: renderedWidth
                        ) {
                            transform.x = 0
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        if abs(transform.y) < 0.045 { transform.y = 0 }
                        dragStart = nil
                        onEnded()
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let start = scaleStart ?? transform.scale
                        scaleStart = start
                        transform.scale = min(1.6, max(0.65, start * Double(value)))
                        constrainToEditableArea()
                    }
                    .onEnded { _ in scaleStart = nil }
            )
    }


    private func constrainToEditableArea(panelSize measuredSize: CGSize? = nil) {
        transform = PanelEditingPolicy.clampedTransform(
            transform,
            panelSize: measuredSize ?? panelSize,
            canvasSize: canvasSize,
            insets: protectedInsets,
            screenScale: screenScale
        )
    }
}

private struct FontMiniClock: View {
    let choice: ClockFontChoice
    let selected: Bool

    var body: some View {
        HStack(spacing: 3) {
            miniCard("12")
            Text(":").font(choice.font(size: 16))
            miniCard("34")
        }
        .padding(5)
        .background(selected ? Color.orange.opacity(0.24) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func miniCard(_ value: String) -> some View {
        Text(value)
            .font(choice.font(size: 20))
            .offset(y: choice.clockVerticalOffset(size: 20))
            .mask(FlipTextSplitMask(gap: 2))
            .frame(width: 38, height: 30)
            .background(FlipPanelSurface(isDimmed: false, cornerRadius: 7, splitGap: 2))
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
        case .off: "잠자기 모드 · 박수 또는 화면 탭을 기다리는 중"
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
    var hourMode: ClockHourMode = .twentyFour

    var body: some View {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let rawHour = components.hour ?? 0
        let displayHour = hourMode == .twelve ? (rawHour % 12 == 0 ? 12 : rawHour % 12) : rawHour
        HStack(spacing: isPortrait ? 8 : 12) {
                FlipClockCard(
                    value: String(format: "%02d", displayHour),
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
                .mask(FlipTextSplitMask(gap: isPortrait ? 4 : 3))
        }
        .frame(
            width: isPortrait ? 126 : 164,
            height: isPortrait ? 92 : 116
        )
    }
}

struct FlipTextSplitMask: View {
    let gap: CGFloat

    var body: some View {
        VStack(spacing: gap) {
            Rectangle()
            Rectangle()
        }
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
