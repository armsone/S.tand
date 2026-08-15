import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct BoyisoBabyFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - (side / 2),
            y: rect.midY - (side / 2)
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (side * x), y: origin.y + (side * y))
        }

        var path = Path()
        path.addEllipse(in: CGRect(
            x: origin.x + (side * 0.12),
            y: origin.y + (side * 0.12),
            width: side * 0.76,
            height: side * 0.76
        ))

        path.move(to: point(0.37, 0.17))
        path.addCurve(
            to: point(0.58, 0.30),
            control1: point(0.42, 0.05),
            control2: point(0.60, 0.10)
        )
        path.addCurve(
            to: point(0.68, 0.22),
            control1: point(0.62, 0.27),
            control2: point(0.66, 0.24)
        )

        let eyeSize = side * 0.045
        path.addEllipse(in: CGRect(
            x: point(0.36, 0.43).x - (eyeSize / 2),
            y: point(0.36, 0.43).y - (eyeSize / 2),
            width: eyeSize,
            height: eyeSize
        ))
        path.addEllipse(in: CGRect(
            x: point(0.64, 0.43).x - (eyeSize / 2),
            y: point(0.64, 0.43).y - (eyeSize / 2),
            width: eyeSize,
            height: eyeSize
        ))

        path.move(to: point(0.35, 0.60))
        path.addQuadCurve(
            to: point(0.65, 0.60),
            control: point(0.50, 0.77)
        )
        return path
    }
}

struct BoyisoBabyFaceIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        BoyisoBabyFaceShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

struct BoyisoView: View {
    @ObservedObject var service: BoyisoConnectivityService
    let accent: Color

    @State private var selectedRole: BoyisoRole
    @State private var name: String
    @State private var scannerPresented = false
    @State private var pendingInvitation: URL?
    @State private var validationMessage: String?
    @State private var shareURL: URL?
    @State private var nameEditorExpanded = false
    @State private var confirmsLeavingRoom = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(service: BoyisoConnectivityService, accent: Color) {
        self.service = service
        self.accent = accent
        _selectedRole = State(initialValue: service.role)
        _name = State(initialValue: service.deviceName)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(BoyisoBranding.descriptor)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if service.invitation == nil { setupFlow } else { connectedFlow }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(BoyisoBranding.primaryName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scannerPresented) {
            BoyisoQRScanner { result in
                scannerPresented = false
                switch result {
                case .success(let url):
                    pendingInvitation = url
                    joinPendingInvitation()
                case .failure:
                    validationMessage = "보이소 초대 QR을 읽지 못했습니다."
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: service.invitation?.url) { _, _ in prepareShareImage() }
        .confirmationDialog(
            "같은 공간에서 나올까요?",
            isPresented: $confirmsLeavingRoom,
            titleVisibility: .visible
        ) {
            Button("공간에서 나오기", role: .destructive) {
                service.leaveRoom()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("연결된 사람들과의 보이소 연결이 종료됩니다.")
        }
    }

    private var setupFlow: some View {
        VStack(spacing: 14) {
            BoyisoCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. 나의 역할").font(.title3.bold())
                    HStack(spacing: 10) {
                        ForEach(BoyisoRole.allCases) { role in
                            if role == selectedRole {
                                Button(role.title) { selectedRole = role }
                                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                                    .buttonStyle(.borderedProminent).tint(accent)
                            } else {
                                Button(role.title) { selectedRole = role }
                                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                                    .buttonStyle(.bordered).tint(accent)
                            }
                        }
                    }
                    Text(selectedRole.description).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }

            BoyisoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("2. 내 이름").font(.title3.bold())
                    TextField("같은 공간에 표시할 이름", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12).frame(height: 46)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: name) { _, value in
                            if value.count > 32 { name = String(value.prefix(32)) }
                            validationMessage = nil
                        }
                }
            }

            BoyisoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("3. 공간 선택").font(.title3.bold())
                    Group {
                        if horizontalSizeClass == .regular {
                            HStack(spacing: 12) { roomCreationTile; roomJoinTile }
                        } else {
                            VStack(spacing: 12) { roomCreationTile; roomJoinTile }
                        }
                    }
                }
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var connectedFlow: some View {
        VStack(spacing: 14) {
            Button {
                _ = service.sendTokTok()
            } label: {
                HStack(spacing: 8) {
                    BoyisoBabyFaceIcon(lineWidth: 1.8)
                        .frame(width: 22, height: 22)
                    Text("톡톡 보내기")
                }
                .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent).tint(accent)
            .accessibilityLabel("톡톡 보내기")

            BoyisoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("공간에 연결됨", systemImage: "checkmark.circle.fill")
                        .font(.title3.bold()).foregroundStyle(.green)
                    if let connectionDetail {
                        Text(connectionDetail)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    }
                    if let issue = service.issueMessage {
                        Text(issue).font(.caption).foregroundStyle(.orange)
                    }
                    DisclosureGroup("내 이름 수정", isExpanded: $nameEditorExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("같은 공간에 표시할 이름", text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 12).frame(minHeight: 46)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                .onChange(of: name) { _, value in
                                    if value.count > 32 { name = String(value.prefix(32)) }
                                    validationMessage = nil
                                }
                            Button("이름 저장") {
                                if service.updateDisplayName(name) {
                                    name = service.deviceName
                                    validationMessage = nil
                                    nameEditorExpanded = false
                                } else {
                                    validationMessage = "내 이름을 입력해 주세요."
                                }
                            }
                            .buttonStyle(.borderedProminent).tint(accent)
                            if let validationMessage {
                                Text(validationMessage).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(.white.opacity(0.78))
                }
            }

            BoyisoParticipantSummaryHeader(totalCount: participantSections.totalCount)
            if participantSections.hasDuplicateNames {
                Label("같은 이름을 쓰는 기기가 있어요", systemImage: "person.2")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            participantGroupCard(role: .host, participants: participantSections.hosts)
            participantGroupCard(role: .guest, participants: participantSections.guests)

            if let invitation = service.invitation,
               let image = BoyisoQRCode.image(for: invitation.url.absoluteString) {
                BoyisoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("우리 공간 QR코드").font(.title3.bold())
                        Text("이 QR을 가진 사람은 같은 공간에 들어올 수 있습니다. 필요한 사람에게만 보내 주세요.")
                            .font(.caption).foregroundStyle(.white.opacity(0.58))
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("보이소 초대 QR코드")
                        if let shareURL {
                            ShareLink(item: shareURL, subject: Text("보이소 초대"),
                                      message: Text("보이소에서 이 QR 사진을 찍고 같은 공간에 들어오세요.")) {
                                Label("QR 사진 보내기", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Text("화면 잠금 중에도 iOS가 허용하는 범위에서 Bluetooth·오디오 연결과 수신 알림을 유지합니다. 다만 앱이 정지되거나 종료되면 Wi-Fi·Bluetooth 상시 연결은 보장되지 않으며, 앱을 다시 열면 자동으로 재탐색합니다. 무음 모드·집중 모드·알림 설정은 그대로 따릅니다.")
                .font(.caption).foregroundStyle(.white.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) { confirmsLeavingRoom = true } label: {
                Text("공간에서 나오기").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 720)
        .onAppear { prepareShareImage() }
    }

    private var participantSections: BoyisoParticipantSections {
        BoyisoParticipantSections(current: service.currentParticipant, peers: service.activePeers)
    }

    private var connectionDetail: String? {
        BoyisoConnectionStatusCopy.detail(
            hasPeers: !service.activePeers.isEmpty,
            hadConnectedPeer: service.hadConnectedPeer,
            hasIssue: service.issueMessage != nil
        )
    }

    private var roomCreationTile: some View {
        Button(action: createRoom) {
            BoyisoRoomChoiceLabel(
                title: "공간 만들기",
                description: "초대 QR을 만들고 사람들을 기다립니다.",
                systemImage: "qrcode"
            )
        }
        .buttonStyle(.borderedProminent).tint(accent)
    }

    private var roomJoinTile: some View {
        Button { scannerPresented = true } label: {
            BoyisoRoomChoiceLabel(
                title: "공간 입장",
                description: "카메라로 같은 공간의 QR을 찍습니다.",
                systemImage: "qrcode.viewfinder"
            )
        }
        .buttonStyle(.bordered)
    }

    private func participantGroupCard(
        role: BoyisoRole,
        participants: [BoyisoParticipantPresentation]
    ) -> some View {
        BoyisoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(role.tint).frame(width: 4, height: 24).accessibilityHidden(true)
                    Image(systemName: role.iconName)
                        .foregroundStyle(role.tint)
                        .accessibilityHidden(true)
                    Text("\(role.title) \(participants.count)명")
                }
                .font(.headline.bold())
                .foregroundStyle(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(role.title) \(participants.count)명")
                .accessibilityAddTraits(.isHeader)

                if participants.isEmpty {
                    Text("아직 없음")
                        .font(.body).foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                        BoyisoParticipantRow(participant: participant)
                        if index < participants.count - 1 {
                            Divider().overlay(.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private func createRoom() {
        do {
            try service.createRoom(role: selectedRole, name: name)
            validationMessage = nil
            prepareShareImage()
        } catch { validationMessage = "내 이름을 입력해 주세요." }
    }

    private func joinPendingInvitation() {
        guard let pendingInvitation else { return }
        do {
            try service.joinRoom(pendingInvitation, role: selectedRole, name: name)
            validationMessage = nil
            self.pendingInvitation = nil
        } catch { validationMessage = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "내 이름을 입력한 뒤 다시 QR을 찍어 주세요." : "보이소 V2 초대 QR이 아닙니다." }
    }

    private func prepareShareImage() {
        guard let invitation = service.invitation,
              let image = BoyisoQRCode.image(for: invitation.url.absoluteString),
              let data = image.pngData() else { shareURL = nil; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("boyiso-invitation.png")
        do { try data.write(to: url, options: .atomic); shareURL = url } catch { shareURL = nil }
    }
}

enum BoyisoConnectionStatusCopy {
    static func summary(hasPeers: Bool, hadConnectedPeer: Bool, hasIssue: Bool) -> String {
        if hasIssue || hadConnectedPeer && !hasPeers { return "다시 연결 중" }
        if !hasPeers { return "함께할 사람이 연결되기를 기다리고 있습니다." }
        return "함께 연결되어 있습니다."
    }

    static func detail(hasPeers: Bool, hadConnectedPeer: Bool, hasIssue: Bool) -> String? {
        hasPeers && !hasIssue ? nil : summary(
            hasPeers: hasPeers,
            hadConnectedPeer: hadConnectedPeer,
            hasIssue: hasIssue
        )
    }
}

struct BoyisoParticipantPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let role: BoyisoRole
    let isCurrentDevice: Bool
    let state: String
    let batteryPercent: Int?
    let transports: Set<BoyisoTransportKind>

    var connectionLabels: [String] {
        if isCurrentDevice { return ["이 기기"] }
        return BoyisoTransportKind.allCases.filter(transports.contains).map(\.title)
    }

    var accessibilityLabel: String {
        [name, isCurrentDevice ? "나" : nil, role.title, state,
         batteryPercent.map { "배터리 \($0)퍼센트" },
         connectionLabels.isEmpty ? nil : "연결 경로, \(connectionLabels.joined(separator: ", "))"]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

struct BoyisoParticipantSections: Equatable {
    let hosts: [BoyisoParticipantPresentation]
    let guests: [BoyisoParticipantPresentation]
    var totalCount: Int { hosts.count + guests.count }
    var hasDuplicateNames: Bool {
        let names = (hosts + guests).map(\.name)
        return Set(names).count != names.count
    }

    init(current: BoyisoPeerStatus, peers: [BoyisoPeerStatus]) {
        var uniquePeers: [UUID: BoyisoPeerStatus] = [:]
        for peer in peers where peer.id != current.id {
            if let existing = uniquePeers[peer.id] {
                var newest = peer.lastSeen >= existing.lastSeen ? peer : existing
                newest.transports.formUnion(existing.transports)
                newest.transports.formUnion(peer.transports)
                uniquePeers[peer.id] = newest
            } else {
                uniquePeers[peer.id] = peer
            }
        }
        let all = [(current, true)] + uniquePeers.values.map { ($0, false) }
        func presentations(for role: BoyisoRole) -> [BoyisoParticipantPresentation] {
            all.filter { $0.0.role == role }.map { peer, isCurrent in
                BoyisoParticipantPresentation(
                    id: peer.id,
                    name: peer.name,
                    role: peer.role,
                    isCurrentDevice: isCurrent,
                    state: peer.role == .host ? "연결됨" : Self.guestState(peer),
                    batteryPercent: peer.batteryPercent,
                    transports: peer.transports
                )
            }
            .sorted {
                if $0.isCurrentDevice != $1.isCurrentDevice { return $0.isCurrentDevice }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        hosts = presentations(for: .host)
        guests = presentations(for: .guest)
    }

    private static func guestState(_ peer: BoyisoPeerStatus) -> String {
        peer.sessionActive && peer.displayMode == .mate && peer.monitoring ? "감지 중" : "대기 중"
    }
}

private extension BoyisoRole {
    var iconName: String { self == .host ? "eye.fill" : "waveform" }
    var tint: Color { self == .host ? Color(red: 0.25, green: 0.78, blue: 0.84) : Color.orange }
}

private struct BoyisoParticipantSummaryHeader: View {
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("공간에 있는 사람").font(.title2.bold())
            Text("나를 포함해 총 \(totalCount)명")
                .font(.subheadline).foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("공간에 있는 사람, 나를 포함해 총 \(totalCount)명")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct BoyisoParticipantRow: View {
    let participant: BoyisoParticipantPresentation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var nameSize = 18.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { participantName; batteryLabel }
                VStack(alignment: .leading, spacing: 6) { stateLabel; connectionBadges }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) { participantName; batteryLabel }
                    VStack(alignment: .leading, spacing: 6) { participantName; batteryLabel }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { stateLabel; Spacer(minLength: 4); connectionBadges }
                    VStack(alignment: .leading, spacing: 6) { stateLabel; connectionBadges }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(participant.accessibilityLabel)
    }

    private var participantName: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(participant.name)
                .font(.system(size: nameSize, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if participant.isCurrentDevice {
                Text("나").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.14), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var batteryLabel: some View {
        if let battery = participant.batteryPercent {
            Text("배터리 \(battery)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var stateLabel: some View {
        Text(participant.state)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.68))
    }

    @ViewBuilder
    private var connectionBadges: some View {
        ForEach(participant.connectionLabels, id: \.self) { label in
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.1), in: Capsule())
        }
    }
}

private struct BoyisoRoomChoiceLabel: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).font(.title2).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private enum BoyisoQRCode {
    static func image(for value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: .init(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct BoyisoQRScanner: UIViewControllerRepresentable {
    let completion: (Result<URL, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let session = AVCaptureSession()
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            completion(.failure(ScannerError.unavailable)); return controller
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { completion(.failure(ScannerError.unavailable)); return controller }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        controller.view.layer.addSublayer(preview)
        context.coordinator.session = session
        context.coordinator.preview = preview
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.preview?.frame = controller.view.bounds
    }
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.session?.stopRunning()
    }
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let completion: (Result<URL, Error>) -> Void
        var session: AVCaptureSession?
        var preview: AVCaptureVideoPreviewLayer?
        private var completed = false
        init(completion: @escaping (Result<URL, Error>) -> Void) { self.completion = completion }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !completed, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  let url = URL(string: value) else { return }
            completed = true; session?.stopRunning(); completion(.success(url))
        }
    }
    enum ScannerError: Error { case unavailable }
}

private struct BoyisoCard<Content: View>: View {
    var tint: Color?
    @ViewBuilder let content: Content
    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(tint?.opacity(0.065) ?? .white.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(tint?.opacity(0.28) ?? .white.opacity(0.08), lineWidth: 0.8)
            }
    }
}
