import SwiftUI
import UIKit

private enum PresentedSheet: String, Identifiable {
    case recordings
    case settings

    var id: String { rawValue }
}

struct RootView: View {
    @ObservedObject private var model: StandViewModel
    @ObservedObject private var audio: AudioCaptureService
    @ObservedObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didCompleteWelcome") private var didCompleteWelcome = false
    @State private var presentedSheet: PresentedSheet?

    init(model: StandViewModel) {
        _model = ObservedObject(wrappedValue: model)
        _audio = ObservedObject(wrappedValue: model.audio)
        _library = ObservedObject(wrappedValue: model.library)
    }

    var body: some View {
        ZStack {
            LampBackground(intensity: model.lampIntensity)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                centerContent
                Spacer(minLength: 12)
                bottomControls
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            statusBanners
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.controlsVisible {
                model.activateLamp()
            } else {
                model.revealControls()
            }
        }
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

    private var topBar: some View {
        HStack(spacing: 16) {
            Text("S.tand")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .tracking(0.8)

            if model.isNightSessionActive {
                AudioStatusPill(audio: audio)
            }

            Spacer()

            if model.isNightSessionActive {
                Label(
                    audio.isWritingClip ? "수면 소리 저장 중" : "기기에서 소리 분석 중",
                    systemImage: audio.isWritingClip ? "waveform.badge.mic" : "ear"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(audio.isWritingClip ? Color.red.opacity(0.9) : Color.white.opacity(0.55))
            } else {
                Text("버전 \(AppVersion.display)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .foregroundStyle(.white.opacity(0.82))
        .opacity(model.controlsVisible || !model.isNightSessionActive ? 1 : 0.18)
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
    }

    @ViewBuilder
    private var centerContent: some View {
        if !didCompleteWelcome {
            WelcomePanel {
                didCompleteWelcome = true
                model.startNightSession()
            }
        } else if model.isNightSessionActive {
            NightClock(phase: model.lampPhase, intensity: model.lampIntensity)
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
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            if model.isNightSessionActive {
                if model.controlsVisible {
                    ControlButton(title: "불빛 켜기", systemImage: "lightbulb.fill") {
                        model.activateLamp()
                    }
                    ControlButton(title: "지금 끄기", systemImage: "moon.fill") {
                        model.turnOffLamp(animated: true)
                    }
                    ControlButton(title: "세션 종료", systemImage: "stop.circle.fill", role: .destructive) {
                        model.stopNightSession()
                    }
                } else {
                    Text("화면을 탭해 제어")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.24))
                        .padding(.vertical, 12)
                }
            }

            Spacer(minLength: 16)

            if model.controlsVisible || !model.isNightSessionActive {
                ControlButton(
                    title: library.clips.isEmpty ? "수면 소리" : "수면 소리 \(library.clips.count)",
                    systemImage: "waveform"
                ) {
                    presentedSheet = .recordings
                }
                ControlButton(title: "설정", systemImage: "slider.horizontal.3") {
                    presentedSheet = .settings
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
    }

    private var statusBanners: some View {
        VStack {
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

private struct NightClock: View {
    let phase: LampPhase
    let intensity: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 5) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 92, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)

                Text(context.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))

                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.36))
                    .padding(.top, 6)
            }
            .foregroundStyle(.white.opacity(max(0.12, min(0.88, 0.22 + intensity))))
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        switch phase {
        case .off: "박수 또는 화면 탭을 기다리는 중"
        case .holding: "불빛 켜짐"
        case .fading: "불빛이 서서히 어두워지는 중"
        }
    }
}

private struct WelcomePanel: View {
    let start: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 11) {
                Text("밤에는 은은한 불빛,")
                Text("잠든 동안에는 필요한 소리만.")
                    .foregroundStyle(.orange)
            }
            .font(.system(.title2, design: .rounded, weight: .semibold))

            Divider()
                .overlay(.white.opacity(0.12))
                .frame(height: 112)

            VStack(alignment: .leading, spacing: 9) {
                Label("박수형 소리를 감지해 앱 불빛을 켭니다.", systemImage: "hands.clap.fill")
                Label("지속되는 수면 소리 구간만 이 iPhone에 저장합니다.", systemImage: "waveform.badge.mic")
                Label("잠금 버튼을 누르거나 앱을 종료하면 감지가 멈춥니다.", systemImage: "lock.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.64))

            Button(action: start) {
                VStack(spacing: 5) {
                    Image(systemName: "bed.double.fill")
                        .font(.title2)
                    Text("추천 설정으로 시작")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(24)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct AudioStatusPill: View {
    @ObservedObject var audio: AudioCaptureService

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

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

            Text(statusText)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
    }

    private var statusColor: Color {
        if audio.isWritingClip { return .red }
        if audio.state == .monitoring { return .green }
        return .orange
    }

    private var statusText: String {
        if audio.isWritingClip { return "저장 중" }
        switch audio.state {
        case .monitoring: return "감지 중"
        case .starting: return "준비 중"
        case .failed: return "확인 필요"
        case .stopped: return "정지됨"
        }
    }
}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : .white.opacity(0.78))
    }
}
