import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("화면 방향") {
                    Picker(
                        "회전 방식",
                        selection: Binding(
                            get: { store.value.orientationPreference },
                            set: { store.value.orientationPreference = $0 }
                        )
                    ) {
                        ForEach(OrientationPreference.allCases) { preference in
                            Label(preference.title, systemImage: preference.systemImage)
                                .tag(preference)
                        }
                    }

                    Text("기기 설정 따르기는 iPhone의 회전 상태를 따릅니다. 고정을 선택하면 앱을 다시 열어도 선택한 방향을 유지합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("시계") {
                    Picker("시계 글꼴", selection: $store.value.clockFont) {
                        ForEach(ClockFontChoice.allCases) { choice in
                            HStack {
                                Text("12:34")
                                    .font(choice.font(size: 18))
                                Text(choice.displayName)
                            }
                            .tag(choice)
                        }
                    }

                    HStack {
                        Spacer()
                        Text("12:34")
                            .font(store.value.clockFont.font(size: 38))
                            .monospacedDigit()
                            .contentTransition(.opacity)
                            .padding(.vertical, 8)
                        Spacer()
                    }
                    .accessibilityLabel("선택한 시계 글꼴 미리보기 12시 34분")

                    HStack {
                        Text("시계 크기")
                        Slider(value: $store.value.clockScale, in: 0.7...1.35, step: 0.05)
                        Text("\(Int((store.value.clockScale * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 42, alignment: .trailing)
                    }

                    Button("시계 크기 기본값") {
                        store.value.clockScale = 1
                    }
                    .disabled(abs(store.value.clockScale - 1) < 0.001)

                    Text("첫 화면에서 두 손가락을 벌리거나 오므려도 시계 크기를 바꿀 수 있습니다. 선택한 크기와 글꼴은 다음 실행에도 유지됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("불빛") {
                    SettingSlider(
                        title: "최대 밝기",
                        valueText: "\(Int(store.value.lampIntensity * 100))%",
                        value: $store.value.lampIntensity,
                        range: 0.15...1
                    )
                    SettingSlider(
                        title: "유지 시간",
                        valueText: holdDurationText,
                        value: $store.value.holdDuration,
                        range: 10...300,
                        step: 5
                    )
                    SettingSlider(
                        title: "감광 시간",
                        valueText: "\(Int(store.value.fadeDuration))초",
                        value: $store.value.fadeDuration,
                        range: 5...120,
                        step: 5
                    )

                    Toggle("화면 점등 시 플래시 사용", isOn: $store.value.torchEnabled)

                    if store.value.torchEnabled {
                        SettingSlider(
                            title: "플래시 최대 밝기",
                            valueText: "\(Int(store.value.torchIntensity * 100))%",
                            value: $store.value.torchIntensity,
                            range: 0.05...1
                        )
                    }

                    Toggle(
                        "소리·움직임에 다시 점등",
                        isOn: $store.value.multiStimulusWakeEnabled
                    )

                    Toggle(
                        "밝은 환경에서 자동 감광 보류",
                        isOn: $store.value.preventAutoDimmingWhenScreenBright
                    )

                    Text("첫 화면에서 좌우로 밀면 어두워지기까지의 시간을 10초~5분으로 바로 조절합니다. iOS가 공개하는 화면 밝기 값이 높은 동안에는 밝은 환경으로 판단해 자동 감광을 보류합니다. 화면 탭과 ‘지금 어둡게’는 이 보호와 관계없이 동작합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("박수, 손뼉·찰싹 소리, 핑거스냅, 옷·침구 마찰음, 뒤척임과 iPhone 움직임을 기기에서 감지해 다시 점등합니다. 형광등처럼 주변이 갑자기 밝아져 시스템 화면 밝기가 오를 때도 점등합니다. 오분류될 수 있으며 플래시 사용도 켜져 있으면 함께 켜집니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("수면 소리") {
                    Toggle("소리 구간 자동 저장", isOn: $store.value.recordingEnabled)

                    SettingSlider(
                        title: "감지 민감도",
                        valueText: sensitivityText,
                        value: Binding(
                            get: { Double(store.value.soundThresholdDB) },
                            set: { store.value.soundThresholdDB = Float($0) }
                        ),
                        range: -50 ... -20,
                        step: 1
                    )

                    Text("민감도가 높을수록 작은 소리도 저장됩니다. 현재 버전은 코골이 분류가 아니라 음량 기반 수면 소리 감지입니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("개인정보와 안전") {
                    Label("오디오는 이 iPhone에서 처리하고 로컬에만 저장합니다.", systemImage: "iphone.and.arrow.forward.inward")
                    Label("함께 있는 사람에게 녹음 사실을 먼저 알려 주세요.", systemImage: "person.2.fill")
                    Label("충전 중인 기기를 침구 아래에 두지 마세요.", systemImage: "thermometer.medium")
                    Label("플래시는 열이 날 수 있으므로 기기를 가리지 마세요.", systemImage: "flashlight.on.fill")
                    Text("S.tand의 녹음은 수면 상태를 진단하는 의료 기능이 아닙니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("앱 정보") {
                    LabeledContent("버전", value: AppVersion.display)
                    Link("날씨 데이터 · Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                    NavigationLink("내장 폰트 저작권") {
                        ClockFontLicensesView()
                    }
                    Button("추천 설정 복원") {
                        store.restoreRecommendedValues()
                    }
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private var sensitivityText: String {
        switch store.value.soundThresholdDB {
        case ..<(-42): "높음"
        case (-42)...(-32): "보통"
        default: "낮음"
        }
    }

    private var holdDurationText: String {
        let seconds = Int(store.value.holdDuration.rounded())
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}

private struct ClockFontLicensesView: View {
    private let bundledFonts = ClockFontChoice.allCases.filter { $0 != .systemRounded }

    var body: some View {
        List {
            Section {
                Text("S.tand는 시계 표시를 위해 HanClip에서 검증해 보관한 프리텐다드, 카카오 Big Sans, 나눔고딕, 태나다, 검은고딕, 도현의 원본 서체 파일을 수정하지 않고 포함합니다.")
                Text("이 서체들은 SIL Open Font License 1.1에 따라 앱·소프트웨어 번들 및 임베딩이 허용됩니다. 서체 파일 자체를 단독 판매하지 않으며, 각 저작권 고지와 라이선스 전문을 앱 번들에 함께 보관합니다.")
            } header: {
                Text("내장 폰트 저작권")
            }

            Section("라이선스 전문") {
                ForEach(bundledFonts) { font in
                    NavigationLink(font.displayName) {
                        FontLicenseDetailView(font: font)
                    }
                }
            }

            Section {
                Text("시스템 둥근체는 iOS 시스템 서체이며 S.tand 앱 번들에 별도 서체 파일로 포함하지 않습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("폰트 저작권")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FontLicenseDetailView: View {
    let font: ClockFontChoice

    var body: some View {
        ScrollView {
            Text(licenseText)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
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

private struct SettingSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .accessibilityValue(valueText)
        }
        .padding(.vertical, 3)
    }
}
