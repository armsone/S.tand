import AVFoundation
import CoreLocation
import SwiftUI

struct FirstLaunchPermissionPromptSchedule: Equatable {
    var hasShownPrompt: Bool
    var launchesUntilNextPrompt: Int?
}

enum FirstLaunchPermissionPromptDecision: Equatable {
    case show
    case skip
    case reset
}

enum FirstLaunchPermissionPromptPolicy {
    static let reminderInterval = 3...7

    static func evaluateLaunch(
        allPermissionsGranted: Bool,
        schedule: FirstLaunchPermissionPromptSchedule
    ) -> (FirstLaunchPermissionPromptDecision, FirstLaunchPermissionPromptSchedule) {
        if allPermissionsGranted {
            return (.reset, FirstLaunchPermissionPromptSchedule(
                hasShownPrompt: false,
                launchesUntilNextPrompt: nil
            ))
        }
        guard schedule.hasShownPrompt else { return (.show, schedule) }

        let remaining = schedule.launchesUntilNextPrompt ?? reminderInterval.lowerBound
        guard remaining > 1 else { return (.show, schedule) }

        return (.skip, FirstLaunchPermissionPromptSchedule(
            hasShownPrompt: true,
            launchesUntilNextPrompt: remaining - 1
        ))
    }

    static func afterPrompt(interval: Int) -> FirstLaunchPermissionPromptSchedule {
        FirstLaunchPermissionPromptSchedule(
            hasShownPrompt: true,
            launchesUntilNextPrompt: min(
                reminderInterval.upperBound,
                max(reminderInterval.lowerBound, interval)
            )
        )
    }
}

@MainActor
final class FirstLaunchPermissionCoordinator: NSObject, ObservableObject {
    @Published private(set) var shouldPresentExplanation = false
    @Published private(set) var isRequesting = false

    private enum StorageKey {
        static let hasShownPrompt = "firstLaunchPermissionPromptHasShownV1"
        static let launchesUntilNextPrompt = "firstLaunchPermissionPromptLaunchesRemainingV1"
    }

    private let defaults: UserDefaults
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        locationManager.delegate = self
        evaluateThisProcessLaunch()
    }

    func requestNeededPermissions(completion: @escaping () -> Void) {
        guard !isRequesting else { return }
        isRequesting = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            await requestCameraIfNeeded()
            await requestMicrophoneIfNeeded()
            await requestLocationIfNeeded()
            finishPrompt()
            isRequesting = false
            shouldPresentExplanation = false
            completion()
        }
    }

    private var allPermissionsGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
            && [.authorizedAlways, .authorizedWhenInUse].contains(
                locationManager.authorizationStatus
            )
    }

    private func evaluateThisProcessLaunch() {
        let storedRemaining = defaults.object(forKey: StorageKey.launchesUntilNextPrompt) == nil
            ? nil
            : defaults.integer(forKey: StorageKey.launchesUntilNextPrompt)
        let schedule = FirstLaunchPermissionPromptSchedule(
            hasShownPrompt: defaults.bool(forKey: StorageKey.hasShownPrompt),
            launchesUntilNextPrompt: storedRemaining
        )
        let (decision, updatedSchedule) = FirstLaunchPermissionPromptPolicy.evaluateLaunch(
            allPermissionsGranted: allPermissionsGranted,
            schedule: schedule
        )

        switch decision {
        case .show:
            shouldPresentExplanation = true
        case .skip:
            persist(updatedSchedule)
        case .reset:
            clearSchedule()
        }
    }

    private func finishPrompt() {
        if allPermissionsGranted {
            clearSchedule()
        } else {
            persist(FirstLaunchPermissionPromptPolicy.afterPrompt(
                interval: Int.random(in: FirstLaunchPermissionPromptPolicy.reminderInterval)
            ))
        }
    }

    private func persist(_ schedule: FirstLaunchPermissionPromptSchedule) {
        defaults.set(schedule.hasShownPrompt, forKey: StorageKey.hasShownPrompt)
        if let remaining = schedule.launchesUntilNextPrompt {
            defaults.set(remaining, forKey: StorageKey.launchesUntilNextPrompt)
        } else {
            defaults.removeObject(forKey: StorageKey.launchesUntilNextPrompt)
        }
    }

    private func clearSchedule() {
        defaults.removeObject(forKey: StorageKey.hasShownPrompt)
        defaults.removeObject(forKey: StorageKey.launchesUntilNextPrompt)
    }

    private func requestCameraIfNeeded() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { _ in continuation.resume() }
        }
    }

    private func requestMicrophoneIfNeeded() async {
        guard AVAudioApplication.shared.recordPermission == .undetermined else { return }
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { _ in continuation.resume() }
        }
    }

    private func requestLocationIfNeeded() async {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }
}

extension FirstLaunchPermissionCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        Task { @MainActor [weak self] in
            guard let self, let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume()
        }
    }
}

struct FirstLaunchPermissionView: View {
    @ObservedObject var coordinator: FirstLaunchPermissionCoordinator
    let accent: Color
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.12, green: 0.075, blue: 0.055)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(accent)
                        Text("시작하기 전에")
                            .font(.title2.weight(.bold))
                        Text("S.tand가 필요한 이유를 먼저 알려드릴게요.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.60))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        permissionRow(
                            title: "카메라와 플래시",
                            detail: "방 밝기를 확인하고, 어두울 때 화들짝 모드에서만 잠깐 밝힙니다. 사진·영상은 저장하거나 전송하지 않습니다.",
                            systemImage: "camera.fill"
                        )
                        permissionRow(
                            title: "마이크",
                            detail: "잠꼬대·코골이를 감지하고 필요한 소리만 이 기기에 저장합니다.",
                            systemImage: "mic.fill"
                        )
                        permissionRow(
                            title: "위치 정보",
                            detail: "현재 날씨에만 사용하며 가능한 최소 정확도와 필요한 범위만 요청합니다.",
                            systemImage: "location.fill"
                        )
                    }

                    Text("허용하지 않아도 앱은 시작됩니다. 허용한 기능만 작동합니다.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)

                    Button {
                        coordinator.requestNeededPermissions(completion: onComplete)
                    } label: {
                        HStack(spacing: 9) {
                            if coordinator.isRequesting {
                                ProgressView().tint(.white)
                            }
                            Text(coordinator.isRequesting ? "권한 확인 중…" : "권한 확인하고 시작")
                                .font(.headline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator.isRequesting)
                    .accessibilityHint("결정하지 않은 권한만 차례로 확인한 뒤 앱을 시작합니다")
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 22)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }

    private func permissionRow(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
