import AVFoundation
import Combine
import Foundation

enum InternetRadioPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case failed(String)

    var isActive: Bool {
        switch self {
        case .loading, .playing:
            true
        case .idle, .failed:
            false
        }
    }
}

@MainActor
final class InternetRadioPlayer: ObservableObject {
    @Published private(set) var state: InternetRadioPlaybackState = .idle
    @Published private(set) var activeChannelID: UUID?

    var activeStreamURL: URL? { activeURL }

    var onPlaybackBecameInactive: (() -> Void)?

    private let audioSession = AVAudioSession.sharedInstance()
    private var player: AVPlayer?
    private var playerCancellables: Set<AnyCancellable> = []
    private var notificationCancellables: Set<AnyCancellable> = []
    private var loadingTimeoutTask: Task<Void, Never>?
    private var pausedFailureTask: Task<Void, Never>?
    private var ownsAudioSession = false
    private var isWaitingForInterruptionToEnd = false
    private var activeURL: URL?

    init() {
        observeAudioSession()
    }

    func play(_ configuration: InternetRadioConfiguration) {
        startPlayback(url: configuration.streamURL, channelID: configuration.id)
    }

    func switchChannel(to configuration: InternetRadioConfiguration) {
        if state.isActive, activeURL == configuration.streamURL {
            activeChannelID = configuration.id
            return
        }
        startPlayback(url: configuration.streamURL, channelID: configuration.id)
    }

    func play(url: URL) {
        startPlayback(url: url, channelID: nil)
    }

    private func startPlayback(url: URL, channelID: UUID?) {
        guard !isWaitingForInterruptionToEnd else { return }
        tearDownPlayer()
        activeChannelID = channelID
        activeURL = url
        state = .loading

        do {
            if !ownsAudioSession {
                try audioSession.setCategory(.playback, mode: .default)
                try audioSession.setActive(true)
                ownsAudioSession = true
            }
        } catch {
            fail("오디오 출력을 시작할 수 없습니다.")
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        observe(player: player, item: item)
        scheduleLoadingTimeout()
        player.play()
    }

    func stop() {
        let shouldNotify = state.isActive && !isWaitingForInterruptionToEnd
        tearDownPlayer()
        deactivateAudioSessionIfOwned()
        activeChannelID = nil
        activeURL = nil
        state = .idle
        if shouldNotify { onPlaybackBecameInactive?() }
    }

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        item.publisher(for: \.status, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self, self.player?.currentItem === item else { return }
                switch status {
                case .failed:
                    self.fail(item.error?.localizedDescription ?? "스트림에 연결할 수 없습니다.")
                case .readyToPlay, .unknown:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &playerCancellables)

        player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self, self.player === player, self.state.isActive else { return }
                switch status {
                case .playing:
                    self.loadingTimeoutTask?.cancel()
                    self.loadingTimeoutTask = nil
                    self.pausedFailureTask?.cancel()
                    self.pausedFailureTask = nil
                    self.state = .playing
                case .waitingToPlayAtSpecifiedRate:
                    self.pausedFailureTask?.cancel()
                    self.pausedFailureTask = nil
                    self.state = .loading
                    self.scheduleLoadingTimeout()
                case .paused:
                    self.schedulePausedFailure()
                @unknown default:
                    break
                }
            }
            .store(in: &playerCancellables)

        NotificationCenter.default.publisher(
            for: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let self, self.player?.currentItem === item else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.fail(error?.localizedDescription ?? "라디오 재생이 중단되었습니다.")
        }
        .store(in: &playerCancellables)

        NotificationCenter.default.publisher(
            for: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self, self.player?.currentItem === item else { return }
            self.fail("라디오 재생이 종료되었습니다.")
        }
        .store(in: &playerCancellables)

        NotificationCenter.default.publisher(
            for: AVPlayerItem.playbackStalledNotification,
            object: item
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self,
                  self.player?.currentItem === item,
                  self.state.isActive
            else { return }
            self.state = .loading
            self.scheduleLoadingTimeout()
        }
        .store(in: &playerCancellables)
    }

    private func observeAudioSession() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawValue)
                else { return }
                switch type {
                case .began:
                    self?.stopForInterruption()
                case .ended:
                    self?.finishInterruption()
                @unknown default:
                    break
                }
            }
            .store(in: &notificationCancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: rawValue) == .oldDeviceUnavailable
                else { return }
                self?.fail("오디오 출력 기기가 분리되어 라디오를 멈췄습니다.")
            }
            .store(in: &notificationCancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.state.isActive || self.ownsAudioSession else { return }
                self.ownsAudioSession = false
                self.fail("오디오 서비스가 재설정되어 라디오를 멈췄습니다.")
            }
            .store(in: &notificationCancellables)
    }

    private func scheduleLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled, self.state == .loading else { return }
            self.fail("30초 안에 스트림에 연결하지 못했습니다.")
        }
    }

    private func schedulePausedFailure() {
        pausedFailureTask?.cancel()
        pausedFailureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self,
                  !Task.isCancelled,
                  self.state.isActive,
                  !self.isWaitingForInterruptionToEnd,
                  self.player?.timeControlStatus == .paused
            else { return }
            self.fail("라디오 재생이 중단되었습니다.")
        }
    }

    private func fail(_ message: String) {
        guard state.isActive || ownsAudioSession else { return }
        let shouldNotify = state.isActive
        tearDownPlayer()
        deactivateAudioSessionIfOwned()
        activeChannelID = nil
        activeURL = nil
        state = .failed(message)
        if shouldNotify { onPlaybackBecameInactive?() }
    }

    private func stopForInterruption() {
        guard !isWaitingForInterruptionToEnd,
              (state.isActive || ownsAudioSession)
        else { return }
        let shouldWaitToResumeMonitoring = state.isActive
        isWaitingForInterruptionToEnd = shouldWaitToResumeMonitoring
        tearDownPlayer()
        deactivateAudioSessionIfOwned()
        activeChannelID = nil
        activeURL = nil
        state = .failed("다른 오디오 사용으로 라디오가 중단되었습니다.")
    }

    private func finishInterruption() {
        guard isWaitingForInterruptionToEnd else { return }
        isWaitingForInterruptionToEnd = false
        onPlaybackBecameInactive?()
    }

    private func tearDownPlayer() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        pausedFailureTask?.cancel()
        pausedFailureTask = nil
        playerCancellables.removeAll()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func deactivateAudioSessionIfOwned() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
