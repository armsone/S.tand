import SwiftUI
import UIKit

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

struct RootView: View {
    @ObservedObject private var model: StandViewModel
    @ObservedObject private var audio: AudioCaptureService
    @ObservedObject private var library: RecordingLibrary
    @ObservedObject private var settings: SettingsStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedSheet: PresentedSheet?
    @State private var didInitialize = false
    @State private var brightnessDragState: BrightnessDragState?
    @State private var brightnessFeedback: BrightnessFeedback?
    @State private var brightnessFeedbackTask: Task<Void, Never>?

    init(model: StandViewModel) {
        _model = ObservedObject(wrappedValue: model)
        _audio = ObservedObject(wrappedValue: model.audio)
        _library = ObservedObject(wrappedValue: model.library)
        _settings = ObservedObject(wrappedValue: model.settings)
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
                    Spacer(minLength: 12)
                    centerContent(isPortrait: isPortrait)
                    Spacer(minLength: 12)
                    bottomControls(isPortrait: isPortrait)
                }
                .padding(.horizontal, isPortrait ? 20 : 32)
                .padding(.vertical, isPortrait ? 18 : 20)
                .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                statusBanners
                    .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                if let brightnessFeedback {
                    BrightnessFeedbackView(feedback: brightnessFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(verticalBrightnessGesture.exclusively(before: tapToWakeGesture))
        .persistentSystemOverlays(.hidden)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .recordings:
                RecordingsView(
                    library: library,
                    playbackDisabled: model.isNightSessionActive
                )
            case .settings:
                SettingsView(store: model.settings)
            }
        }
        .onAppear {
            model.appDidBecomeActive()
            model.startNightSession()
            didInitialize = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                model.appDidBecomeActive()
            case .inactive, .background:
                model.appWillResignActive()
            @unknown default:
                break
            }
        }
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
            NightClock(
                phase: model.lampPhase,
                intensity: model.lampIntensity,
                isPortrait: isPortrait,
                isDimmed: false
            )
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
        VStack(spacing: 14) {
            NightClock(
                phase: .off,
                intensity: 0,
                isPortrait: isPortrait,
                isDimmed: true
            )
            .opacity(settings.value.silhouetteIntensity / 0.035)

            Label(
                silhouetteBatteryText,
                systemImage: model.batteryStatus.isCharging
                    ? "battery.100percent.bolt"
                    : "battery.50percent"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(settings.value.silhouetteIntensity * 0.72))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var silhouetteBatteryText: String {
        guard let level = model.batteryStatus.level else { return "배터리 --%" }
        return "배터리 \(Int((level * 100).rounded()))%"
    }

    private var verticalBrightnessGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }

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
                    adjustedValue = min(0.12, max(0.005, state.startingValue + change * 0.12))
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
                if brightnessDragState?.target == .lamp {
                    model.endManualLampAdjustment()
                }
                brightnessDragState = nil
                scheduleBrightnessFeedbackHide()
            }
    }

    private var tapToWakeGesture: some Gesture {
        TapGesture()
            .onEnded {
                if model.isNightSessionActive {
                    model.activateLamp()
                    model.revealControls()
                }
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
            title: "화면 어둡게",
            systemImage: "moon.fill",
            hint: "화면 조명과 플래시를 지금 끕니다"
        ) {
            model.turnOffLamp(animated: true)
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
        Text("화면을 탭해 제어")
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
            if audio.microphoneAccess == .denied, model.isNightSessionActive {
                microphoneDeniedBanner
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

    private var microphoneDeniedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
            Text("마이크 권한이 없어 수동 스탠드만 동작합니다.")
                .font(.subheadline.weight(.medium))
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("설정 열기", destination: settingsURL)
                    .font(.subheadline.weight(.semibold))
            }
        }
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
        case .silhouette: (feedback.value - 0.005) / 0.115
        }
    }

    private var displayPercent: Int {
        Int((normalizedValue * 100).rounded())
    }
}

private struct NightClock: View {
    let phase: LampPhase
    let intensity: Double
    let isPortrait: Bool
    let isDimmed: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 5) {
                FlipClockFace(
                    date: context.date,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed
                )

                Text(context.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(isDimmed ? 0.035 : 0.48))

                if !isDimmed {
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.36))
                        .padding(.top, 6)
                }
            }
            .foregroundStyle(
                .white.opacity(isDimmed ? 0.035 : max(0.12, min(0.88, 0.22 + intensity)))
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        switch phase {
        case .off: "대기 상태 · 박수 또는 화면 탭을 기다리는 중"
        case .holding: "현재 상태 · 화면 조명 켜짐"
        case .fading: "현재 상태 · 화면 조명이 서서히 어두워지는 중"
        }
    }
}

private struct FlipClockFace: View {
    let date: Date
    let isPortrait: Bool
    let isDimmed: Bool

    var body: some View {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        HStack(spacing: isPortrait ? 8 : 12) {
            FlipClockCard(
                value: String(format: "%02d", components.hour ?? 0),
                isPortrait: isPortrait,
                isDimmed: isDimmed
            )
            Text(":")
                .font(.system(size: isPortrait ? 48 : 62, weight: .ultraLight, design: .rounded))
                .opacity(isDimmed ? 0.5 : 0.8)
            FlipClockCard(
                value: String(format: "%02d", components.minute ?? 0),
                isPortrait: isPortrait,
                isDimmed: isDimmed
            )
        }
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.35), value: components.minute)
    }
}

private struct FlipClockCard: View {
    let value: String
    let isPortrait: Bool
    let isDimmed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isPortrait ? 18 : 22, style: .continuous)
                .fill(.white.opacity(isDimmed ? 0.012 : 0.075))
                .overlay {
                    RoundedRectangle(cornerRadius: isPortrait ? 18 : 22, style: .continuous)
                        .stroke(.white.opacity(isDimmed ? 0.018 : 0.08), lineWidth: 1)
                }

            Rectangle()
                .fill(.black.opacity(isDimmed ? 0.35 : 0.42))
                .frame(height: 1)

            Text(value)
                .font(.system(
                    size: isPortrait ? 64 : 82,
                    weight: .thin,
                    design: .rounded
                ))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .frame(
            width: isPortrait ? 126 : 164,
            height: isPortrait ? 92 : 116
        )
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

            if !compact {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(statusColor.opacity(0.9))
                                .frame(width: max(3, proxy.size.width * audio.normalizedLevel))
                        }
                }
                .frame(width: 44, height: 5)
            }

            Text(statusText)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.07), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
    }

    private var statusColor: Color {
        if audio.isWritingClip { return .red }
        if audio.state == .monitoring { return .green }
        return .orange
    }

    private var statusText: String {
        if audio.isWritingClip { return compact ? "저장" : "저장 중" }
        switch audio.state {
        case .monitoring: return compact ? "감지" : "감지 중"
        case .starting: return compact ? "준비" : "준비 중"
        case .failed: return "확인 필요"
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
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 24, height: 22)

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
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 68)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : .white.opacity(0.78))
        .accessibilityHint(hint ?? "")
    }
}
