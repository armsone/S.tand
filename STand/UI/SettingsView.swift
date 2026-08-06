import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("불빛") {
                    SettingSlider(
                        title: "최대 밝기",
                        valueText: "\(Int(store.value.lampIntensity * 100))%",
                        value: $store.value.lampIntensity,
                        range: 0.15...1
                    )
                    SettingSlider(
                        title: "유지 시간",
                        valueText: "\(Int(store.value.holdDuration))초",
                        value: $store.value.holdDuration,
                        range: 5...180,
                        step: 5
                    )
                    SettingSlider(
                        title: "감광 시간",
                        valueText: "\(Int(store.value.fadeDuration))초",
                        value: $store.value.fadeDuration,
                        range: 5...120,
                        step: 5
                    )
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
                    Text("S.tand의 녹음은 수면 상태를 진단하는 의료 기능이 아닙니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("앱 정보") {
                    LabeledContent("버전", value: AppVersion.display)
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
