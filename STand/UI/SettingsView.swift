import Combine
import SwiftUI
import UIKit

struct SettingsView: View {
    private let model: StandViewModel
    @StateObject private var runtime: SettingsRuntimeState
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var library: RecordingLibrary
    @ObservedObject private var weather: WeatherService

    let onEditScreen: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsRecordings = false
    @State private var showsInternetRadioChannels = false
    @State private var confirmsRestore = false

    init(model: StandViewModel, onEditScreen: @escaping () -> Void) {
        self.model = model
        _runtime = StateObject(wrappedValue: SettingsRuntimeState(model: model))
        _store = ObservedObject(wrappedValue: model.settings)
        _library = ObservedObject(wrappedValue: model.library)
        _weather = ObservedObject(wrappedValue: model.weather)
        self.onEditScreen = onEditScreen
    }

    private var accent: Color {
        store.value.displayTheme.accentColor
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    StandSettingsBackground(accent: accent)

                    ScrollView {
                        LazyVStack(spacing: 14) {
                            SettingsHero(
                                isNightSessionActive: runtime.isNightSessionActive,
                                environmentDisplayMode: runtime.environmentDisplayMode,
                                accent: accent
                            )

                            quickControls

                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                                    count: proxy.size.width >= 720 ? 2 : 1
                                ),
                                spacing: 14
                            ) {
                                screenAndClockCard
                                lightingCard
                                detectionCard
                                internetRadioCard
                                weatherAndDeviceCard
                                informationCard
                            }
                        }
                        .padding(.horizontal, proxy.size.width >= 720 ? 24 : 14)
                        .padding(.top, 8)
                        .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 16))
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(accent)
        .sheet(isPresented: $showsRecordings, onDismiss: {
            model.resumeMonitoringAfterPlayback()
        }) {
            RecordingsView(
                library: library,
                playbackDisabled: false,
                theme: store.value.displayTheme
            )
        }
        .sheet(isPresented: $showsInternetRadioChannels) {
            InternetRadioChannelManagementView(model: model)
        }
        .confirmationDialog(
            "추천 설정으로 되돌릴까요?",
            isPresented: $confirmsRestore,
            titleVisibility: .visible
        ) {
            Button("모든 설정과 화면 배치 복원", role: .destructive) {
                store.restoreRecommendedValues()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장한 라디오 채널, 세로·가로 화면 배치와 하단 버튼 순서도 처음 모습으로 돌아갑니다.")
        }
        .onAppear {
            library.reload()
            weather.refreshIfNeeded()
        }
        .animation(.easeInOut(duration: 0.25), value: store.value.displayTheme)
    }

    private var quickControls: some View {
        StandSettingsCard(
            title: "바로 제어",
            subtitle: "돌봄, 화면과 녹음만 간단히 관리합니다",
            systemImage: "switch.2",
            accent: accent
        ) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
                ),
                spacing: 8
            ) {
                SettingsActionTile(
                    title: runtime.isNightSessionActive ? "자동 기능 끄기" : "자동 기능 켜기",
                    status: runtime.isNightSessionActive ? "전환·감지·녹음" : "시계·날씨만 표시",
                    systemImage: runtime.isNightSessionActive ? "stop.circle.fill" : "moon.stars.fill",
                    isActive: runtime.isNightSessionActive,
                    accent: accent
                ) {
                    if runtime.isNightSessionActive {
                        model.stopNightSession()
                    } else {
                        model.startNightSession()
                    }
                }

                SettingsActionTile(
                    title: "화면 꾸미기",
                    status: "위치·크기",
                    systemImage: "rectangle.3.group",
                    isActive: false,
                    accent: accent,
                    action: onEditScreen
                )

                SettingsActionTile(
                    title: "수면 소리",
                    status: library.clips.isEmpty ? "녹음 없음" : "\(library.clips.count)개",
                    systemImage: "waveform",
                    isActive: !library.clips.isEmpty,
                    accent: accent
                ) {
                    model.pauseMonitoringForPlayback()
                    showsRecordings = true
                }

            }
        }
    }

    private var screenAndClockCard: some View {
        StandSettingsCard(
            title: "화면과 시계",
            subtitle: "테마, 글꼴과 화면 배치를 바꿉니다",
            systemImage: "clock.fill",
            accent: accent
        ) {
            VStack(alignment: .leading, spacing: 3) {
                SettingsFieldLabel("테마")
                Text("시계를 더블 터치하면 테마가 바뀝니다.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
            ThemePalettePicker(
                selection: Binding(
                    get: { store.value.displayTheme },
                    set: { store.value.displayTheme = $0 }
                )
            )

            SettingsFieldLabel("시간 형식")
            Picker(
                "시간 표시",
                selection: Binding(
                    get: { store.value.clockHourMode },
                    set: { store.value.clockHourMode = $0 }
                )
            ) {
                Text("12시간").tag(ClockHourMode.twelve)
                Text("24시간").tag(ClockHourMode.twentyFour)
            }
            .pickerStyle(.segmented)

            SettingsFieldLabel("화면 방향")
            Picker(
                "화면 방향",
                selection: Binding(
                    get: { store.value.orientationPreference },
                    set: { store.value.orientationPreference = $0 }
                )
            ) {
                ForEach(OrientationPreference.allCases) { preference in
                    Text(orientationShortTitle(preference))
                        .accessibilityLabel(preference.title)
                        .tag(preference)
                }
            }
            .pickerStyle(.segmented)

            NavigationLink {
                ClockFontSelectionView(store: store, accent: accent)
            } label: {
                SettingsNavigationRow(
                    title: "시계 글꼴",
                    value: store.value.clockFont.displayName,
                    systemImage: "textformat",
                    accent: accent
                )
            }
            .buttonStyle(.plain)

            SettingsSliderRow(
                title: "전체 구성 크기",
                valueText: "\(Int((store.value.clockScale * 100).rounded()))%",
                value: $store.value.clockScale,
                range: 0.7...1.35,
                step: 0.05,
                accent: accent
            )

            HStack(spacing: 8) {
                SettingsInlineButton(
                    title: "화면 배치",
                    systemImage: "move.3d",
                    accent: accent,
                    action: onEditScreen
                )

                NavigationLink {
                    ControlOrderSettingsView(store: store, accent: accent)
                } label: {
                    SettingsInlineButtonLabel(
                        title: "버튼 배치",
                        systemImage: "arrow.up.arrow.down",
                        accent: accent
                    )
                }
                .buttonStyle(.plain)
            }

            SettingsHelpText(
                "홈 화면을 길게 누르면 정보 패널만 편집합니다. 하단 기능 버튼을 길게 누르면 버튼 순서만 바꿀 수 있으며, 세로와 가로는 따로 저장됩니다."
            )
        }
    }

    private var lightingCard: some View {
        StandSettingsCard(
            title: "밝기와 모드",
            subtitle: "한 번 누르거나 위아래로 밀어 조절합니다",
            systemImage: "sun.and.horizon.fill",
            accent: accent
        ) {
            HStack(spacing: 12) {
                Label("매이트 0–30%", systemImage: "moon.stars.fill")
                Spacer(minLength: 8)
                Label("오브제 31–100%", systemImage: "sun.max.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(12)
            .background(.white.opacity(0.095), in: RoundedRectangle(cornerRadius: 15))

            SettingsHelpText(
                "화면을 한 번 누르면 매이트 10%와 오브제 90%를 전환합니다. 위아래로 화면 높이의 1/4만큼 밀면 밝기 전체 범위를 조절하며, 0%는 매이트 고정, 100%는 오브제 고정입니다."
            )

            SettingsToggleRow(
                title: "화들짝 플래시",
                subtitle: store.value.torchEnabled
                    ? "화들짝 모드에서만 강하게 켜짐"
                    : "화들짝 모드에서만 은은하게 켜짐",
                systemImage: "flashlight.on.fill",
                isOn: $store.value.torchEnabled,
                accent: accent
            )

            SettingsToggleRow(
                title: "방 밝기 감지",
                subtitle: cameraAmbientStatusText,
                systemImage: runtime.ambientCameraState == .measuring
                    ? "camera.metering.center.weighted"
                    : "camera.fill",
                isOn: Binding(
                    get: { store.value.cameraAmbientSensingEnabled },
                    set: { model.setAmbientCameraSensingEnabled($0) }
                ),
                accent: accent
            )

            if runtime.ambientCameraState == .denied {
                SettingsInlineButton(
                    title: "카메라 권한 열기",
                    systemImage: "gear",
                    accent: accent
                ) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }

            SettingsHelpText(
                "플래시는 매이트에서 움직임을 감지한 화들짝 모드에서만 작동합니다. 방 밝기 감지는 사진이나 영상을 저장하지 않고 약 2초 동안 평균 밝기만 계산합니다. 밝은 상태가 유지되면 플래시 없이 오브제 모드로 전환합니다."
            )
        }
    }

    private var detectionCard: some View {
        StandSettingsCard(
            title: "소리 감지",
            subtitle: "매이트에서 뒤척임을 살피고 필요한 소리만 저장합니다",
            systemImage: "waveform.badge.mic",
            accent: accent
        ) {
            SettingsAudioStatusView(
                audio: model.audio,
                isNightSessionActive: runtime.isNightSessionActive,
                environmentDisplayMode: runtime.environmentDisplayMode,
                accent: accent
            ) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
            }

            SettingsToggleRow(
                title: "다시 밝혀주기",
                subtitle: "박수, 핑거스냅, 뒤척임과 기기 움직임에 반응",
                systemImage: "ear.badge.waveform",
                isOn: $store.value.multiStimulusWakeEnabled,
                accent: accent
            )

            SettingsToggleRow(
                title: "코골이·잠꼬대 저장",
                subtitle: "후보 소리가 날 때 필요한 구간만 저장",
                systemImage: "record.circle",
                isOn: $store.value.recordingEnabled,
                accent: accent
            )

            SettingsInlineButton(
                title: library.clips.isEmpty ? "수면 소리 열기" : "녹음 \(library.clips.count)개 보기",
                systemImage: "play.circle.fill",
                accent: accent
            ) {
                model.pauseMonitoringForPlayback()
                showsRecordings = true
            }

            SettingsHelpText(
                "처음 1분 동안 방의 평소 소리를 익힙니다. 이후 평균보다 커진 순간에는 바로 화들짝 반응하고, 녹음은 이 기기 안에서만 처리합니다."
            )
        }
    }

    private var internetRadioCard: some View {
        let channels = store.value.internetRadioChannels
        let selected = store.value.internetRadio

        return StandSettingsCard(
            title: "인터넷 라디오",
            subtitle: channels.isEmpty
                ? "합법적인 HTTPS 스트림 주소를 직접 관리합니다"
                : "\(channels.count)개 채널 · \(selected?.displayName ?? "선택 필요")",
            systemImage: "radio.fill",
            accent: accent
        ) {
            HStack(spacing: 13) {
                Image(systemName: channels.isEmpty ? "radio" : "dot.radiowaves.left.and.right")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(channels.isEmpty ? Color.white.opacity(0.56) : accent)
                    .frame(width: 48, height: 48)
                    .background(
                        (channels.isEmpty ? Color.white.opacity(0.07) : accent.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(selected?.displayName ?? "등록한 채널이 없습니다")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(selected.map { "홈에서 재생할 채널 · \($0.streamURL.host ?? $0.urlString)" }
                        ?? "채널 관리에서 주소를 추가해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            SettingsInlineButton(
                title: channels.isEmpty ? "첫 채널 추가" : "채널 관리",
                systemImage: channels.isEmpty ? "plus.circle.fill" : "list.bullet",
                accent: accent
            ) {
                showsInternetRadioChannels = true
            }

            SettingsHelpText(
                "여러 주소를 저장하고 홈에서 사용할 채널을 고를 수 있습니다. 라디오는 포그라운드에서만 재생되며 재생 중에는 소리 감지와 녹음이 잠시 멈춥니다."
            )
        }
    }

    private var weatherAndDeviceCard: some View {
        StandSettingsCard(
            title: "날씨와 기기",
            subtitle: "현재 위치 정보와 밤새 켜둘 기기의 상태입니다",
            systemImage: "cloud.moon.fill",
            accent: accent
        ) {
            HStack(spacing: 14) {
                Image(systemName: weather.weather?.systemImage ?? "location.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 52, height: 52)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.locationName ?? weatherStatusTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let current = weather.weather {
                        Text("\(Int(current.temperature.rounded()))° · \(current.summary) · 체감 \(Int(current.apparentTemperature.rounded()))°")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.58))
                    } else {
                        Text("위치 권한을 허용하면 홈 날씨 패널에 표시합니다.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                SettingsInlineButton(
                    title: "날씨 새로고침",
                    systemImage: "arrow.clockwise",
                    accent: accent
                ) {
                    weather.refreshIfNeeded(force: true)
                }

                if weather.availability == .locationDenied {
                    SettingsInlineButton(
                        title: "위치 권한",
                        systemImage: "location.fill",
                        accent: accent
                    ) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            }

            SettingsInfoRow(
                title: "배터리",
                value: batteryText,
                systemImage: batteryImage,
                accent: accent
            )

            if runtime.batteryProtectionActive || runtime.batteryStatus.shouldProtectBattery {
                Label(
                    "배터리가 20% 이하이고 충전 중이 아니어서 감지를 멈췄습니다.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.yellow)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var informationCard: some View {
        StandSettingsCard(
            title: "연결과 정보",
            subtitle: "개인정보, 저작권과 앱 정보를 확인합니다",
            systemImage: "info.circle.fill",
            accent: accent
        ) {
            SettingsInfoRow(
                title: "버전",
                value: AppVersion.display,
                systemImage: "app.badge",
                accent: accent
            )

            NavigationLink {
                ClockFontLicensesView(accent: accent)
            } label: {
                SettingsNavigationRow(
                    title: "내장 폰트 저작권",
                    value: "원문 포함",
                    systemImage: "doc.text",
                    accent: accent
                )
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "https://open-meteo.com/")!) {
                SettingsNavigationRow(
                    title: "날씨 데이터",
                    value: "Open-Meteo",
                    systemImage: "cloud",
                    accent: accent
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Label("오디오는 이 기기에서 처리하고 로컬에만 저장합니다.", systemImage: "lock.shield.fill")
                Label("함께 있는 사람에게 녹음 사실을 먼저 알려 주세요.", systemImage: "person.2.fill")
                Label("충전 중인 기기와 플래시를 침구로 덮지 마세요.", systemImage: "thermometer.medium")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.62))

            Button(role: .destructive) {
                confirmsRestore = true
            } label: {
                Label("추천 설정 복원", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.88))
        }
    }

    private var lampActionTitle: String {
        guard runtime.isNightSessionActive else { return "화면 밝히기" }
        return ScreenTapPolicy.action(for: runtime.lampPhase) == .dim ? "지금 어둡게" : "화면 밝히기"
    }

    private var lampActionStatus: String {
        guard runtime.isNightSessionActive else { return "감지도 시작" }
        return switch runtime.lampPhase {
        case .off: "매이트"
        case .holding: "밝은 화면"
        case .fading: "감광 중"
        }
    }

    private var lampActionImage: String {
        guard runtime.isNightSessionActive else { return "sun.max.fill" }
        return ScreenTapPolicy.action(for: runtime.lampPhase) == .dim ? "moon.fill" : "sun.max.fill"
    }

    private func toggleLamp() {
        if !runtime.isNightSessionActive {
            model.startNightSession()
            return
        }

        switch ScreenTapPolicy.action(for: runtime.lampPhase) {
        case .brighten: model.activateLamp()
        case .dim: model.dimLampNow()
        }
    }

    private var silhouettePercentText: String {
        let percent = store.value.silhouetteIntensity * 100
        return percent < 1 ? String(format: "%.1f%%", percent) : "\(Int(percent.rounded()))%"
    }

    private var holdDurationText: String {
        let seconds = Int(store.value.holdDuration.rounded())
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }

    private var weatherStatusTitle: String {
        switch weather.availability {
        case .idle: "날씨 대기"
        case .requestingLocation: "위치 확인 중"
        case .loading: "날씨 불러오는 중"
        case .available: "현재 위치"
        case .locationDenied: "위치 권한 필요"
        case .failed: "날씨를 불러오지 못함"
        }
    }

    private var cameraAmbientStatusText: String {
        switch runtime.ambientCameraState {
        case .disabled: return "사용 안 함"
        case .permissionNeeded: return "처음 켤 때 사용 이유를 설명하고 권한을 요청합니다"
        case .denied: return "카메라 권한이 꺼져 있어 다른 신호만 사용합니다"
        case .measuring: return "약 1초 동안 평균 밝기만 확인 중"
        case .ready:
            if let reading = runtime.lastAmbientBrightnessReading {
                return "최근 확인 · \(reading.isDark ? "어두움" : "밝음") · 사진 저장 안 함"
            }
            return "판단이 애매할 때만 잠깐 확인"
        case .unavailable: return "이 기기에서는 사용할 수 없어 다른 신호만 사용합니다"
        }
    }

    private var batteryText: String {
        let level = runtime.batteryStatus.level.map { "\(Int(($0 * 100).rounded()))%" } ?? "확인 불가"
        let state: String = switch runtime.batteryStatus.powerState {
        case .charging: "충전 중"
        case .full: "충전 완료"
        case .unplugged: "배터리 사용"
        case .unknown: "상태 확인 중"
        }
        return "\(level) · \(state)"
    }

    private var batteryImage: String {
        switch runtime.batteryStatus.powerState {
        case .charging: "battery.100percent.bolt"
        case .full: "battery.100percent"
        case .unplugged: "battery.50percent"
        case .unknown: "battery.0percent"
        }
    }

    private func orientationShortTitle(_ preference: OrientationPreference) -> String {
        switch preference {
        case .automatic: "자동"
        case .portrait: "세로"
        case .landscape: "가로"
        }
    }
}

@MainActor
private final class SettingsRuntimeState: ObservableObject {
    @Published private(set) var isNightSessionActive: Bool
    @Published private(set) var lampPhase: LampPhase
    @Published private(set) var environmentDisplayMode: EnvironmentDisplayMode
    @Published private(set) var batteryStatus: DeviceBatteryStatus
    @Published private(set) var batteryProtectionActive: Bool
    @Published private(set) var displayBrightness: Double
    @Published private(set) var ambientCameraState: AmbientCameraState
    @Published private(set) var lastAmbientBrightnessReading: AmbientBrightnessReading?

    init(model: StandViewModel) {
        isNightSessionActive = model.isNightSessionActive
        lampPhase = model.lampPhase
        environmentDisplayMode = model.environmentDisplayMode
        batteryStatus = model.batteryStatus
        batteryProtectionActive = model.batteryProtectionActive
        displayBrightness = model.displayBrightness
        ambientCameraState = model.ambientCameraState
        lastAmbientBrightnessReading = model.lastAmbientBrightnessReading

        model.$isNightSessionActive
            .removeDuplicates()
            .assign(to: &$isNightSessionActive)
        model.$lampPhase
            .removeDuplicates()
            .assign(to: &$lampPhase)
        model.$environmentDisplayMode
            .removeDuplicates()
            .assign(to: &$environmentDisplayMode)
        model.$batteryStatus
            .removeDuplicates()
            .assign(to: &$batteryStatus)
        model.$batteryProtectionActive
            .removeDuplicates()
            .assign(to: &$batteryProtectionActive)
        model.$displayBrightness
            .removeDuplicates()
            .assign(to: &$displayBrightness)
        model.$ambientCameraState
            .removeDuplicates()
            .assign(to: &$ambientCameraState)
        model.$lastAmbientBrightnessReading
            .removeDuplicates()
            .assign(to: &$lastAmbientBrightnessReading)
    }
}

private struct SettingsAudioStatusView: View {
    @ObservedObject var audio: AudioCaptureService
    let isNightSessionActive: Bool
    let environmentDisplayMode: EnvironmentDisplayMode
    let accent: Color
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AudioLevelMeter(level: audio.normalizedLevel, accent: accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if audio.microphoneAccess == .denied {
                SettingsInlineButton(
                    title: "마이크 권한 열기",
                    systemImage: "gear",
                    accent: accent,
                    action: openSettings
                )
            }
        }
    }

    private var statusTitle: String {
        if !isNightSessionActive { return "감지 멈춤" }
        if environmentDisplayMode == .stand { return "오브제 모드" }
        return switch audio.state {
        case .stopped: "마이크 대기"
        case .starting: "마이크 준비 중"
        case .monitoring: audio.isWritingClip ? "소리 저장 중" : "소리 감지 중"
        case .failed: "소리 감지 안 됨"
        }
    }

    private var statusDetail: String {
        if isNightSessionActive, environmentDisplayMode == .stand {
            return "소리와 뒤척임 감시는 매이트 모드에서만 작동합니다."
        }
        switch audio.state {
        case .failed(let message): return message
        default:
            if let classification = audio.lastClassifiedSound {
                return "최근 감지 · \(classification.kind.settingsDisplayName)"
            }
            if audio.state == .monitoring, audio.noiseCalibrationProgress < 1 {
                return "방 소리 익히는 중 · \(Int((audio.noiseCalibrationProgress * 100).rounded()))%"
            }
            if let floor = audio.adaptiveNoiseFloorDB {
                return "자동 적응 완료 · 평소 \(Int(floor.rounded())) dB"
            }
            return audio.microphoneAccess == .denied
                ? "설정에서 마이크 권한을 허용해 주세요."
                : "레벨 \(Int((audio.normalizedLevel * 100).rounded()))%"
        }
    }
}

private struct StandSettingsBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            Color(red: 0.115, green: 0.085, blue: 0.078)
            LinearGradient(
                colors: [
                    accent.opacity(0.20),
                    Color(red: 0.16, green: 0.115, blue: 0.10),
                    Color(red: 0.085, green: 0.075, blue: 0.075)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [accent.opacity(0.24), accent.opacity(0.06), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 640
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

private struct SettingsHero: View {
    let isNightSessionActive: Bool
    let environmentDisplayMode: EnvironmentDisplayMode
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            STandBrandIcon(size: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("S.tand")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("낮에는 오브제, 밤에는 매이트")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 5) {
                StatusPill(
                    title: isNightSessionActive ? environmentText : "S.tand 멈춤",
                    systemImage: isNightSessionActive ? "waveform" : "waveform.slash",
                    active: isNightSessionActive,
                    accent: accent
                )
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.18), accent.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var environmentText: String {
        switch environmentDisplayMode {
        case .sleeping: "매이트 모드"
        case .stand: "오브제 모드"
        }
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let active: Bool
    let accent: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? accent : .white.opacity(0.58))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                (active ? accent.opacity(0.15) : Color.white.opacity(0.07)),
                in: Capsule()
            )
    }
}

private struct ThemePalettePicker: View {
    @Binding var selection: StandDisplayTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(StandDisplayTheme.allCases, id: \.self) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { selection = theme }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(theme.accentColor)
                            Circle()
                                .fill(.white.opacity(theme == .grayscale ? 0.12 : 0.18))
                                .frame(width: 14, height: 14)
                                .offset(x: -7, y: -7)
                            if selection == theme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(theme == .grayscale ? .black : .white)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(selection == theme ? 0.9 : 0.18), lineWidth: selection == theme ? 2 : 1)
                        }

                        Text(theme.title)
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        selection == theme ? theme.accentColor.opacity(0.12) : .white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(theme.title) 테마")
                .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
    }
}

private struct StandSettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(15)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 15)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.16), .white.opacity(0.085)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct SettingsActionTile: View {
    let title: String
    let status: String
    let systemImage: String
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isActive ? accent : .white.opacity(0.78))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .foregroundStyle(.white.opacity(0.84))
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(.horizontal, 4)
            .background(
                LinearGradient(
                    colors: [
                        isActive ? accent.opacity(0.24) : .white.opacity(0.13),
                        .white.opacity(0.075)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isActive ? accent.opacity(0.40) : .white.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(status)")
    }
}

private struct SettingsFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.76))
            .padding(.top, 1)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool
    let accent: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? accent : .white.opacity(0.54))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(accent)
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    let accent: Color
    var leadingLabel: String?
    var trailingLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent.opacity(0.88))
            }

            Slider(value: $value, in: range, step: step)
                .tint(accent)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)

            if leadingLabel != nil || trailingLabel != nil {
                HStack {
                    Text(leadingLabel ?? "")
                    Spacer()
                    Text(trailingLabel ?? "")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
            }
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let value: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
                .frame(width: 28)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SettingsInlineButtonLabel: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct SettingsInlineButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsInlineButtonLabel(title: title, systemImage: systemImage, accent: accent)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsHelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.68))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsBrightnessRuleControl: View {
    let currentBrightness: Double
    @Binding var threshold: Double
    let accent: Color
    @State private var trackFrame = CGRect.zero
    @State private var interactionPhase: BrightnessRuleGesturePhase = .undecided

    private let coordinateSpaceName = "settingsBrightnessRule"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("매이트", systemImage: "moon.fill")
                    .foregroundStyle(threshold < currentBrightness ? accent : .white.opacity(0.42))
                Spacer()
                Text("밝기 기준")
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Label("오브제", systemImage: "sun.max.fill")
                    .foregroundStyle(threshold >= currentBrightness ? accent : .white.opacity(0.42))
            }
            .font(.caption.weight(.semibold))

            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let thresholdX = max(0, width - 2) * threshold
                let brightnessX = max(0, width - 8) * currentBrightness

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.09))
                        .frame(height: 8)
                    Capsule()
                        .fill(accent.opacity(0.42))
                        .frame(width: max(4, thresholdX), height: 8)
                    Rectangle()
                        .fill(.white.opacity(0.84))
                        .frame(width: 2, height: 22)
                        .offset(x: thresholdX)
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white.opacity(0.38), lineWidth: 1))
                        .offset(x: brightnessX)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .background {
                    GeometryReader { trackProxy in
                        Color.clear.preference(
                            key: BrightnessRuleTrackFramePreferenceKey.self,
                            value: trackProxy.frame(in: .named(coordinateSpaceName))
                        )
                    }
                }
            }
            .frame(height: 32)

            Text("현재 \(Int((currentBrightness * 100).rounded()))% · 기준 \(Int((threshold * 100).rounded()))% · \(modeText)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.54))
        }
        .padding(12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(BrightnessRuleTrackFramePreferenceKey.self) { trackFrame = $0 }
        .simultaneousGesture(interactionGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("밝기 기준")
        .accessibilityValue("현재 \(Int(currentBrightness * 100))퍼센트, 기준 \(Int(threshold * 100))퍼센트, \(modeText)")
        .accessibilityHint("좌우로 밀어 조절하거나 탭하여 매이트와 오브제를 전환합니다")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: threshold = min(1, threshold + 0.05)
            case .decrement: threshold = max(0, threshold - 0.05)
            @unknown default: break
            }
        }
    }

    private var modeText: String {
        threshold < currentBrightness ? "매이트 모드" : "오브제 모드"
    }

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                updateInteraction(
                    translation: value.translation,
                    startLocation: value.startLocation,
                    currentLocation: value.location
                )
            }
            .onEnded { value in
                finishInteraction(
                    translation: value.translation,
                    currentLocation: value.location
                )
            }
    }

    private func updateInteraction(
        translation: CGSize,
        startLocation: CGPoint,
        currentLocation: CGPoint
    ) {
        if interactionPhase == .undecided {
            guard BrightnessRuleInteractionPolicy.hasReachedDecisionDistance(translation) else {
                return
            }
            interactionPhase = BrightnessRuleInteractionPolicy.isDirectHorizontalDrag(
                translation: translation
            ) && trackFrame.contains(startLocation)
                ? .draggingTrack
                : .ignored
        }

        guard interactionPhase == .draggingTrack else { return }
        threshold = BrightnessThresholdPolicy.value(
            locationX: currentLocation.x - trackFrame.minX,
            width: trackFrame.width
        )
    }

    private func finishInteraction(translation: CGSize, currentLocation: CGPoint) {
        if interactionPhase == .draggingTrack {
            threshold = BrightnessThresholdPolicy.value(
                locationX: currentLocation.x - trackFrame.minX,
                width: trackFrame.width
            )
        } else if interactionPhase == .undecided,
                  BrightnessRuleInteractionPolicy.isTap(translation) {
            toggleMode()
        }
        interactionPhase = .undecided
    }

    private func toggleMode() {
        withAnimation(.easeInOut(duration: 0.22)) {
            threshold = BrightnessThresholdPolicy.valueAfterTap(
                currentBrightness: currentBrightness,
                threshold: threshold
            )
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct AudioLevelMeter: View {
    let level: Double
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(.white.opacity(0.08))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.42), accent],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: max(4, 58 * min(1, max(0, level))))
        }
        .frame(width: 12, height: 58)
        .animation(.linear(duration: 0.12), value: level)
        .accessibilityLabel("감지 레벨 \(Int(level * 100))퍼센트")
    }
}

private struct ClockFontSelectionView: View {
    @ObservedObject var store: SettingsStore
    let accent: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ZStack {
            StandSettingsBackground(accent: accent)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ClockFontChoice.allCases) { choice in
                        Button {
                            store.value.clockFont = choice
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            ClockFontGridTile(
                                choice: choice,
                                selected: store.value.clockFont == choice,
                                accent: accent
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("시계 글꼴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.86), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct ClockFontGridTile: View {
    let choice: ClockFontChoice
    let selected: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.14), .white.opacity(0.065)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask {
                        VStack(spacing: 2) {
                            Rectangle()
                            Rectangle()
                        }
                    }

                Text("12:34")
                    .font(choice.font(size: 23))
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.88))
                    .offset(y: choice.clockVerticalOffset(size: 23))
                    .mask(FlipTextSplitMask(gap: 2))
            }
            .frame(height: 52)

            HStack(spacing: 4) {
                Text(choice.displayName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(8)
        .background(selected ? accent.opacity(0.15) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(selected ? accent.opacity(0.48) : .white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityLabel("\(choice.displayName) 플립시계 미리보기\(selected ? ", 선택됨" : "")")
    }
}

private struct ControlOrderSettingsView: View {
    @ObservedObject var store: SettingsStore
    let accent: Color
    @State private var editsPortrait = true

    var body: some View {
        ZStack {
            StandSettingsBackground(accent: accent)

            VStack(spacing: 12) {
                Picker("방향", selection: $editsPortrait) {
                    Text("세로 화면").tag(true)
                    Text("가로 화면").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)

                List {
                    Section {
                        ForEach(currentOrder) { kind in
                            HStack(spacing: 12) {
                                Image(systemName: kind.editorSystemImage)
                                    .foregroundStyle(accent)
                                    .frame(width: 28)
                                Text(kind.editorTitle)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.white.opacity(0.28))
                            }
                            .listRowBackground(Color.white.opacity(0.055))
                        }
                        .onMove(perform: moveControls)
                    } header: {
                        Text("위에서 아래, 왼쪽에서 오른쪽 순서")
                    } footer: {
                        Text("밝기 기준 타일은 일반 버튼보다 넓어서 순서에 따라 줄 수가 달라질 수 있습니다.")
                    }
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            .padding(.top, 8)
        }
        .navigationTitle("하단 버튼 순서")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.86), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("초기화") { setOrder(StandControlKind.defaultOrder) }
                    .foregroundStyle(accent)
            }
        }
    }

    private var currentOrder: [StandControlKind] {
        let layout = editsPortrait ? store.value.portraitLayout : store.value.landscapeLayout
        return StandControlKind.normalizedOrder(layout.controlOrder)
    }

    private func moveControls(from source: IndexSet, to destination: Int) {
        var order = currentOrder
        order.move(fromOffsets: source, toOffset: destination)
        setOrder(order)
    }

    private func setOrder(_ order: [StandControlKind]) {
        let normalized = StandControlKind.normalizedOrder(order)
        if editsPortrait {
            var layout = store.value.portraitLayout
            layout.controlOrder = normalized
            store.value.portraitLayout = layout
        } else {
            var layout = store.value.landscapeLayout
            layout.controlOrder = normalized
            store.value.landscapeLayout = layout
        }
    }
}

private extension SleepSoundKind {
    var settingsDisplayName: String {
        switch self {
        case .snore: "코골이"
        case .sleepTalk: "잠꼬대 후보"
        case .movement: "뒤척임"
        case .other: "기타 소리"
        }
    }
}

private struct ClockFontLicensesView: View {
    let accent: Color
    private let bundledFonts = ClockFontChoice.allCases.filter { $0 != .systemRounded }

    var body: some View {
        List {
            Section {
                Text("S.tand는 시계 표시를 위해 HanClip에서 검증해 보관한 프리텐다드, 카카오 Big Sans, 나눔고딕, 태나다, 검은고딕, 도현, 페이퍼로지 Bold, 넥슨 Lv.1 고딕, Poppins의 원본 서체 파일을 수정하지 않고 포함합니다.")
                Text("프리텐다드, 카카오 Big Sans, 나눔고딕, 태나다, 검은고딕, 도현, 페이퍼로지와 Poppins는 SIL Open Font License 1.1에 따라 앱·소프트웨어 번들 및 임베딩이 허용됩니다. 서체 파일 자체를 단독 판매하지 않으며, 각 저작권 고지와 라이선스 전문을 앱 번들에 함께 보관합니다.")
                Text("페이퍼로지는 제작자의 공식 저장소에서 배포한 1.001 Bold 원본이며, Poppins는 Google Fonts 공식 저장소의 Regular 원본입니다. 넥슨 Lv.1 고딕의 저작권은 NEXON Korea에 있으며 공식 이용 조건에 따라 원본 파일과 저작권 안내를 함께 번들합니다.")
            } header: {
                Text("내장 폰트 저작권")
            }

            Section("라이선스 전문") {
                ForEach(bundledFonts) { font in
                    NavigationLink(font.displayName) {
                        FontLicenseDetailView(font: font, accent: accent)
                    }
                }
            }

            Section {
                Text("시스템 둥근체는 iOS 시스템 서체이며 S.tand 앱 번들에 별도 서체 파일로 포함하지 않습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(StandSettingsBackground(accent: accent))
        .navigationTitle("폰트 저작권")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FontLicenseDetailView: View {
    let font: ClockFontChoice
    let accent: Color

    var body: some View {
        ZStack {
            StandSettingsBackground(accent: accent)
            ScrollView {
                Text(licenseText)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle(font.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var licenseText: String {
        guard let filename = font.licenseFilename,
              let url = Bundle.main.url(forResource: filename, withExtension: "txt")
                ?? Bundle.main.url(
                    forResource: filename,
                    withExtension: "txt",
                    subdirectory: "FontLicenses"
                ),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "라이선스 전문을 불러올 수 없습니다."
        }
        return text
    }
}

private struct InternetRadioEditorRoute: Hashable {
    let routeID = UUID()
    let configuration: InternetRadioConfiguration?
    let initialAddress: String
    let suggestedName: String

    init(
        configuration: InternetRadioConfiguration? = nil,
        initialAddress: String = "",
        suggestedName: String = ""
    ) {
        self.configuration = configuration
        self.initialAddress = initialAddress
        self.suggestedName = suggestedName
    }
}

private enum InternetRadioManagementDestination: Hashable {
    case editor(InternetRadioEditorRoute)
}

@MainActor
struct InternetRadioChannelManagementView: View {
    private let model: StandViewModel
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var radio: InternetRadioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var path: [InternetRadioManagementDestination] = []
    @State private var showsBrowser = false

    init(model: StandViewModel) {
        self.model = model
        _store = ObservedObject(wrappedValue: model.settings)
        _radio = ObservedObject(wrappedValue: model.radio)
    }

    private var accent: Color {
        store.value.displayTheme.accentColor
    }

    private var channels: [InternetRadioConfiguration] {
        store.value.internetRadioChannels
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if channels.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("저장한 채널이 없습니다", systemImage: "radio")
                        } description: {
                            Text("직접 이용할 수 있는 HTTPS 스트림 주소를 추가해 주세요.")
                        } actions: {
                            Button {
                                addChannel()
                            } label: {
                                Label("첫 채널 추가", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(channels) { channel in
                            channelRow(channel)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        delete(channel)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }

                                    Button {
                                        edit(channel)
                                    } label: {
                                        Label("수정", systemImage: "pencil")
                                    }
                                    .tint(accent)
                                }
                        }
                        .onMove(perform: moveChannels)
                    } header: {
                        Text("홈에서 사용할 채널을 선택하세요")
                    } footer: {
                        Text("채널을 누르면 홈 라디오 패널에서 사용할 주소로 선택됩니다. 편집을 눌러 순서를 바꿀 수 있습니다.")
                    }
                }

                Section {
                    Button {
                        showsBrowser = true
                    } label: {
                        Label("웹에서 주소 찾기", systemImage: "safari.fill")
                    }
                    .accessibilityHint("앱 안의 브라우저에서 주소를 찾고 직접 복사합니다")
                } footer: {
                    Text("브라우저는 스트리밍 주소를 자동으로 감지하거나 채널에 입력하지 않습니다. 이용 권한이 있는 주소를 직접 복사한 뒤 채널 추가 화면에서 붙여넣어 주세요.")
                }

                Section("재생 안내") {
                    Label("라디오 재생 중에는 소리 감지와 녹음이 일시 중지됩니다.", systemImage: "waveform.slash")
                    Label("앱이 화면을 떠나면 라디오가 자동으로 멈춥니다.", systemImage: "iphone.slash")
                }
            }
            .scrollContentBackground(.hidden)
            .background(StandSettingsBackground(accent: accent))
            .navigationTitle("인터넷 라디오")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("완료") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if channels.count > 1 {
                        EditButton()
                    }
                    Button {
                        addChannel()
                    } label: {
                        Label("채널 추가", systemImage: "plus")
                    }
                    .accessibilityHint("이름과 HTTPS 스트림 주소를 직접 입력합니다")
                }
            }
            .navigationDestination(for: InternetRadioManagementDestination.self) { destination in
                switch destination {
                case .editor(let route):
                    InternetRadioChannelEditorView(
                        configuration: route.configuration,
                        initialAddress: route.initialAddress,
                        suggestedName: route.suggestedName,
                        accent: accent,
                        onSave: save,
                        onDelete: { channelID in
                            _ = model.removeInternetRadioChannel(id: channelID)
                        }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(accent)
        .grayscale(store.value.displayTheme == .grayscale ? 1 : 0)
        .fullScreenCover(isPresented: $showsBrowser) {
            InternetRadioBrowserView(accent: accent)
        }
    }

    private func channelRow(_ channel: InternetRadioConfiguration) -> some View {
        let isSelected = store.value.selectedInternetRadioID == channel.id
        let isActive = radio.activeChannelID == channel.id

        return HStack(spacing: 8) {
            Button {
                guard model.selectInternetRadioChannel(id: channel.id) else { return }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "antenna.radiowaves.left.and.right" : "radio.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : .secondary)
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel.displayName)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(channelStatus(channel, isActive: isActive))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                channelAccessibilityLabel(
                    channel,
                    isSelected: isSelected,
                    isActive: isActive
                )
            )
            .accessibilityHint(isSelected ? "현재 홈 채널입니다" : "두 번 탭하여 홈 채널로 선택합니다")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "채널 수정") {
                edit(channel)
            }

            Button {
                edit(channel)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(channel.displayName) 수정")
        }
        .contextMenu {
            Button {
                edit(channel)
            } label: {
                Label("채널 수정", systemImage: "pencil")
            }
            Button(role: .destructive) {
                delete(channel)
            } label: {
                Label("채널 삭제", systemImage: "trash")
            }
        }
    }

    private func channelStatus(
        _ channel: InternetRadioConfiguration,
        isActive: Bool
    ) -> String {
        if isActive {
            return radio.state == .loading ? "연결 중" : "재생 중"
        }
        return channel.streamURL.host ?? channel.urlString
    }

    private func channelAccessibilityLabel(
        _ channel: InternetRadioConfiguration,
        isSelected: Bool,
        isActive: Bool
    ) -> String {
        [
            channel.displayName,
            isSelected ? "홈 채널" : nil,
            isActive ? channelStatus(channel, isActive: true) : nil,
            channel.streamURL.host
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func addChannel() {
        path.append(.editor(InternetRadioEditorRoute()))
    }

    private func edit(_ channel: InternetRadioConfiguration) {
        path.append(.editor(InternetRadioEditorRoute(configuration: channel)))
    }

    private func save(_ configuration: InternetRadioConfiguration) {
        if store.value.internetRadioChannels.contains(where: { $0.id == configuration.id }) {
            if !model.updateInternetRadioChannel(configuration) {
                model.addInternetRadioChannel(configuration, select: true)
            }
        } else {
            model.addInternetRadioChannel(configuration, select: true)
        }
    }

    private func delete(_ channel: InternetRadioConfiguration) {
        guard model.removeInternetRadioChannel(id: channel.id) != nil else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func moveChannels(from offsets: IndexSet, to destination: Int) {
        guard offsets.count == 1, let source = offsets.first, channels.indices.contains(source) else {
            return
        }
        let channel = channels[source]
        let adjustedDestination = source < destination ? destination - 1 : destination
        guard model.moveInternetRadioChannel(id: channel.id, to: adjustedDestination) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

@MainActor
struct InternetRadioChannelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var address: String
    @State private var validationMessage: String?
    @State private var showsBrowser = false
    @State private var confirmsDeletion = false

    let configuration: InternetRadioConfiguration?
    let accent: Color
    let onSave: (InternetRadioConfiguration) -> Void
    let onDelete: (UUID) -> Void

    init(
        configuration: InternetRadioConfiguration? = nil,
        initialAddress: String = "",
        suggestedName: String = "",
        accent: Color = .orange,
        onSave: @escaping (InternetRadioConfiguration) -> Void,
        onDelete: @escaping (UUID) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.accent = accent
        self.onSave = onSave
        self.onDelete = onDelete
        _displayName = State(
            initialValue: configuration?.displayName
                ?? suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        _address = State(
            initialValue: initialAddress.isEmpty
                ? (configuration?.urlString ?? "")
                : initialAddress
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("이름 (선택)", text: $displayName)
                    .textInputAutocapitalization(.never)
                    .accessibilityHint("비워 두면 인터넷 라디오로 저장됩니다")

                TextField("https://…", text: $address, axis: .vertical)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("입력 오류, \(validationMessage)")
                }

                PasteButton(payloadType: String.self) { values in
                    guard let pasted = values.first else { return }
                    address = pasted
                    validationMessage = nil
                }
                .accessibilityLabel("복사한 주소 붙여넣기")
                .accessibilityHint("클립보드의 텍스트를 주소 입력란에 넣습니다")
            } header: {
                Text("채널 정보")
            } footer: {
                Text("직접 이용 권한을 확인한 합법적인 HTTPS 스트림 주소만 등록해 주세요. 이름은 최대 30자, 주소는 최대 2,048자로 저장됩니다.")
            }

            Section {
                Button {
                    showsBrowser = true
                } label: {
                    Label("웹에서 주소 찾기", systemImage: "safari.fill")
                }
                .accessibilityHint("브라우저에서 주소를 찾고 직접 복사합니다")
            } footer: {
                Text("브라우저에서 이용 권한이 있는 주소를 직접 복사한 뒤 이 화면으로 돌아와 붙여넣어 주세요. 웹페이지 주소는 자동으로 입력되지 않습니다.")
            }

            Section("재생 중 동작") {
                Label("소리 감지와 수면 녹음은 일시 중지됩니다.", systemImage: "waveform.slash")
                Label("기기 움직임 감지는 계속됩니다.", systemImage: "gyroscope")
            }

            if let configuration {
                Section {
                    Button("이 채널 삭제", role: .destructive) {
                        confirmsDeletion = true
                    }
                    .accessibilityHint("확인 후 \(configuration.displayName) 채널을 삭제합니다")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(StandSettingsBackground(accent: accent))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(configuration == nil ? "채널 추가" : "채널 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
                    .fontWeight(.semibold)
            }
        }
        .fullScreenCover(isPresented: $showsBrowser) {
            InternetRadioBrowserView(accent: accent)
        }
        .confirmationDialog(
            "\(configuration?.displayName ?? "이 채널")을 삭제할까요?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            if let configuration {
                Button("채널 삭제", role: .destructive) {
                    onDelete(configuration.id)
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 채널 주소는 되돌릴 수 없습니다.")
        }
        .onChange(of: displayName) { _, _ in validationMessage = nil }
        .onChange(of: address) { _, _ in validationMessage = nil }
    }

    private func save() {
        do {
            let saved = try configuration?.updated(
                displayName: displayName,
                urlString: address
            ) ?? InternetRadioConfiguration(
                displayName: displayName,
                urlString: address
            )
            validationMessage = nil
            onSave(saved)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
