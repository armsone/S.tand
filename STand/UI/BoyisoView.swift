import SwiftUI

struct BoyisoView: View {
    @ObservedObject var service: BoyisoConnectivityService
    let accent: Color

    @State private var selectedRole: BoyisoRole
    @State private var roomCode: String
    @State private var validationMessage: String?

    init(service: BoyisoConnectivityService, accent: Color) {
        self.service = service
        self.accent = accent
        _selectedRole = State(initialValue: service.role)
        _roomCode = State(initialValue: service.roomCode)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                introductionCard
                configurationCard
                connectionCard
                safetyCard
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("보이소")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .tint(accent)
    }

    private var introductionCard: some View {
        BoyisoCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("보이는 소리", systemImage: "waveform.and.magnifyingglass")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                Text("아이 곁 기기가 감지한 큰소리와 움직임을 보호자 화면의 빛으로 전합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                Text("현재 단계에서는 아이의 울음을 진단하거나 단정하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private var configurationCard: some View {
        BoyisoCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("이 기기의 역할")
                    .font(.headline)

                Picker("역할", selection: $selectedRole) {
                    ForEach(BoyisoRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(service.isEnabled)

                Text(selectedRole.description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))

                HStack(spacing: 10) {
                    TextField("8자리 돌봄 공간 코드", text: $roomCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .disabled(service.isEnabled)
                        .onChange(of: roomCode) { _, value in
                            roomCode = BoyisoCodec.normalizedRoomCode(value)
                            validationMessage = nil
                        }

                    if selectedRole == .host, !service.isEnabled {
                        Button("새 코드") {
                            roomCode = BoyisoCodec.makeRoomCode()
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    service.isEnabled ? service.disable() : enable()
                } label: {
                    Label(
                        service.isEnabled ? "보이소 연결 끄기" : "보이소 연결 시작",
                        systemImage: service.isEnabled ? "stop.fill" : "antenna.radiowaves.left.and.right"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(service.isEnabled ? .red.opacity(0.78) : accent)
            }
        }
    }

    private var connectionCard: some View {
        BoyisoCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(service.statusText, systemImage: statusSystemImage)
                        .font(.headline)
                    Spacer()
                    Circle()
                        .fill(service.activePeers.isEmpty ? .orange : .green)
                        .frame(width: 9, height: 9)
                }

                HStack(spacing: 8) {
                    transportBadge(
                        title: "Wi-Fi",
                        systemImage: "wifi",
                        ready: service.localNetworkReady
                    )
                    transportBadge(
                        title: "Bluetooth",
                        systemImage: "antenna.radiowaves.left.and.right",
                        ready: service.bluetoothReady
                    )
                }

                if let issue = service.issueMessage {
                    Text(issue)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if service.role == .host {
                    ForEach(service.activePeers) { peer in
                        Divider().overlay(.white.opacity(0.08))
                        HStack(spacing: 10) {
                            Image(systemName: peer.monitoring ? "waveform" : "waveform.slash")
                                .foregroundStyle(peer.monitoring ? accent : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(peer.transports.map(\.title).sorted().joined(separator: " + "))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                            Spacer()
                            if let battery = peer.batteryPercent {
                                Text("\(battery)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                        }
                    }
                }
            }
        }
    }

    private var safetyCard: some View {
        BoyisoCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("연결 상태를 함께 확인해 주세요", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Text("Wi-Fi와 Bluetooth는 각각 독립적으로 연결되며 같은 사건은 한 번만 표시합니다. 두 경로가 모두 끊기거나 아이 곁 기기의 감시가 멈추면 정상 상태로 취급하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                Text("보이소는 보호자의 직접 돌봄이나 의료용 감시장치를 대신하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private var statusSystemImage: String {
        if !service.isEnabled { return "antenna.radiowaves.left.and.right.slash" }
        return service.activePeers.isEmpty ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill"
    }

    private func transportBadge(title: String, systemImage: String, ready: Bool) -> some View {
        Label(ready ? "\(title) 준비됨" : "\(title) 대기", systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ready ? .green : .white.opacity(0.46))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.06), in: Capsule())
    }

    private func enable() {
        do {
            try service.configure(role: selectedRole, roomCode: roomCode)
            validationMessage = nil
        } catch {
            validationMessage = "공백 없이 영문과 숫자 8자리 이상을 입력해 주세요."
        }
    }
}

private struct BoyisoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.08), lineWidth: 0.7)
            }
    }
}
