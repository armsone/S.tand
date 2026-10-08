import Combine
import SwiftUI
import UIKit
import WebKit

/// 빠방(ppabang.net)이 현재 제공하는 채널. 실제 목록은 서버 상태에서 받아오므로,
/// 웹사이트에 카테고리가 추가·삭제되면 앱을 다시 올리지 않아도 선택 목록에 반영된다.
struct PpabangCategory: Hashable, Identifiable {
    let rawValue: String

    static let `default` = PpabangCategory(rawValue: "ccm")
    // 빠방 웹사이트의 재생목록 탭 순서.
    static let fallbackCategories = [
        "ccm", "ballad", "girlgroup", "legends", "crossEdit", "hiphop", "golfHorizontal",
        "golfVertical", "game", "mukbang", "camping", "travel", "lounge", "bedroom", "amv"
    ].map(PpabangCategory.init(rawValue:))

    var id: String { rawValue }

    var displayName: String {
        switch rawValue {
        case "golfVertical": "세로 골프"
        case "golfHorizontal": "가로 골프"
        case "camping": "캠핑"
        case "girlgroup": "아이돌 뮤비"
        case "legends": "경연"
        case "ballad": "가요톱텐"
        case "game": "게임"
        case "mukbang": "먹방"
        case "travel": "여행"
        case "ccm": "CCM"
        case "lounge": "라운지"
        case "bedroom": "베드룸"
        case "amv": "AMV"
        case "crossEdit", "cross-edit", "cross_edit": "교차편집"
        case "hiphop": "힙합"
        default:
            rawValue
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
                .capitalized
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = PpabangPlayerSession.allowedHost
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "category", value: rawValue),
            // WebKit의 이전 문서 캐시가 첫 항목을 되살리지 않도록 매번 새 목록을 요청한다.
            URLQueryItem(name: "standSession", value: UUID().uuidString)
        ]
        // 호스트·경로·쿼리가 모두 고정 문자열이므로 URL 생성은 실패하지 않는다.
        return components.url ?? URL(string: "https://ppabang.net/?category=\(rawValue)")!
    }
}

/// YouTube IFrame 플레이어가 실제로 보고한 상태만 재생 중으로 표시한다.
enum PpabangPlaybackState: Equatable {
    /// 플레이어가 닫혀 있다.
    case idle
    /// 페이지를 불러오는 중이다.
    case loading
    /// 페이지는 준비됐지만 아직 재생되지 않았다.
    case ready
    /// 재생 명령을 보냈지만 플레이어가 아직 응답하지 않았다.
    case requested
    case playing
    case paused
    case buffering
    /// 재생 명령이 확인되지 않았다. 웹뷰 안의 영상을 직접 탭해야 한다.
    case blocked
    case failed(String)

    var isPlaying: Bool { self == .playing }

    var statusText: String {
        switch self {
        case .idle: "대기 중"
        case .loading: "불러오는 중"
        case .ready: "재생 준비됨"
        case .requested: "재생 요청 중"
        case .playing: "재생 중"
        case .paused: "일시 정지"
        case .buffering: "버퍼링 중"
        case .blocked: "영상을 탭해 시작"
        case .failed: "연결 실패"
        }
    }

    /// 플레이어 패널에 표시하는 안내 문구. 재생 중일 때는 비어 있다.
    var instructionText: String? {
        switch self {
        case .blocked:
            "자동 재생이 막혔습니다. 영상 화면을 한 번 탭해 시작해 주세요."
        case .failed(let message):
            message
        case .idle, .loading, .ready, .requested, .playing, .paused, .buffering:
            nil
        }
    }
}

/// 빠방 웹 플레이어 하나를 소유하는 세션. 웹뷰는 패널이 보이는 동안만 존재하고,
/// 패널이 사라지면 `detach`가 명령 브리지와 재생을 함께 끝낸다.
@MainActor
final class PpabangPlayerSession: NSObject, ObservableObject {
    nonisolated static let allowedHost = "ppabang.net"
    nonisolated static let bridgeMessageName = "standPpabang"
    private static let categoryDefaultsKey = "ppabang.selectedCategory"
    /// 재생 명령 뒤 플레이어 응답을 기다리는 최대 시간(초). 한 번만 확인하고 재시도하지 않는다.
    private static let playbackConfirmationTimeout: TimeInterval = 4
    /// 앱이 비활성·배경으로 갔을 때 플레이어(웹뷰·영상·재생 위치)를 붙잡아 두는 시간은 두지 않는다.
    /// 화면을 벗어나면 즉시 멈추고, 복귀 시각과 관계없이 같은 미니플레이어·곡을 그대로 유지한다.

    @Published private(set) var category: PpabangCategory
    @Published private(set) var categories = PpabangCategory.fallbackCategories
    @Published private(set) var isPresented = false
    /// 홈 카드의 열고/닫기 버튼이 다루는 미니플레이어 패널 표시 여부. 재생 시작·정지와는
    /// 독립적으로 바뀌므로, 패널을 닫아도 재생은 멈추지 않고 열어도 재생이 시작되지 않는다.
    @Published private(set) var isPanelOpen = false
    @Published private(set) var state: PpabangPlaybackState = .idle
    @Published private(set) var trackTitle: String?

    /// 세로/가로 전환처럼 같은 화면 안에서 다른 SwiftUI 분기로 옮겨질 때도 웹뷰(영상·재생 위치)를
    /// 그대로 이어 쓰도록 강한 참조로 붙잡는다. 진짜로 패널을 닫을 때만 `teardown`에서 놓아 준다.
    private var webView: WKWebView?
    /// 재부착(회전 등으로 잠깐 뒤 같은 웹뷰가 다시 붙는 경우) 여부를 구분하기 위한 세대 값.
    /// `detach`가 예약한 정리 작업이 실행될 때 이 값이 바뀌어 있으면 그사이 다시 붙은 것이므로 건너뛴다.
    private var attachToken = 0
    private var pendingTeardown: Task<Void, Never>?
    private var hasLoadedPage = false
    /// 사이트가 YouTube 플레이어 준비와 재생 목록 표시를 모두 마쳐 재생 명령을 받을 수 있는 상태.
    /// 페이지 로드 직후에는 목록 요청이 끝나지 않아 플레이어에 영상이 없으므로 이 신호를 기다린다.
    private var isSiteReady = false
    private var pendingAutoplay = false
    private var confirmationTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    /// 페이지 로드 뒤 사이트 준비 신호를 기다리는 최대 시간(초).
    private static let siteReadinessTimeout: TimeInterval = 20
    static let emptyListMessage = "재생할 수 있는 영상이 없습니다. 영상 화면을 탭하면 목록을 다시 불러옵니다."
    static let playerUnavailableMessage = "플레이어를 준비하지 못했습니다. 정지 후 다시 재생해 주세요."
    private var generation = 0
    private var isBackgroundSuspended = false

    /// 화면을 벗어나 배경 정지 중이면 참. 이 동안에는 어떤 경로로도 재생을 시작하지 않는다.
    var isSuspendedForBackground: Bool { isBackgroundSuspended }

    override init() {
        let stored = UserDefaults.standard.string(forKey: Self.categoryDefaultsKey)
        category = stored.map(PpabangCategory.init(rawValue:)) ?? .default
        super.init()
        refreshCategories()
    }

    /// 빠방 서버의 현재 카테고리를 가져온다. 서버에 영상이 있는 항목만 표시해
    /// 아직 준비되지 않은 카테고리를 선택하는 일을 막는다.
    func refreshCategories() {
        let statusURL = URL(string: "https://\(Self.allowedHost)/api/catalog/status")!
        URLSession.shared.dataTask(with: statusURL) { [weak self] data, response, _ in
            guard let data,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  let status = try? JSONDecoder().decode(PpabangCatalogStatus.self, from: data)
            else { return }

            let current = status.categories.compactMap { rawValue, state in
                state.count > 0 ? PpabangCategory(rawValue: rawValue) : nil
            }.sorted {
                let leftRank = PpabangCategory.fallbackCategories.firstIndex(of: $0) ?? Int.max
                let rightRank = PpabangCategory.fallbackCategories.firstIndex(of: $1) ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return $0.rawValue < $1.rawValue
            }
            guard !current.isEmpty else { return }
            DispatchQueue.main.async {
                self?.categories = current
            }
        }.resume()
    }

    // MARK: - 네이티브 명령

    /// 플레이어를 보이게 하고 선택한 채널을 불러온다. 이미 열려 있으면 채널만 바꾼다.
    func start(category requested: PpabangCategory? = nil) {
        if let requested, requested != category {
            category = requested
            UserDefaults.standard.set(requested.rawValue, forKey: Self.categoryDefaultsKey)
        }
        // 채널 변경은 명시적 조작이므로 배경 정지 상태를 버리고 새로 시작한다.
        isBackgroundSuspended = false
        cancelConfirmation()
        cancelReadinessWait()
        generation += 1
        trackTitle = nil
        hasLoadedPage = false
        isSiteReady = false
        // 패널을 열 때 자동 재생을 요청하지 않는다. 첫 영상은 준비된 모습(일시정지)으로 보여 주고,
        // 실제 재생은 사용자가 재생 버튼을 눌렀을 때 `requestPlay()`로 시작한다. 사이트의 시작
        // 덮개(`#startCover`)는 재생이 시작돼야 숨겨지므로, `bridgeScript`가 큐 준비 신호를 볼 때
        // 덮개를 대신 숨겨 cue된 첫 영상이 보이게 한다(`evaluateSite` 참고).
        pendingAutoplay = false
        isPresented = true
        isPanelOpen = true
        state = .loading
        if let webView {
            webView.load(URLRequest(url: category.url, timeoutInterval: 30))
        }
    }

    /// 홈 카드의 열고/닫기 버튼: 열면 채널을 불러와 첫 영상을 일시정지 상태로 준비해 두고(`start()`),
    /// 닫으면 `stop()`으로 정리한다. 패널을 연 뒤 오른쪽 재생/일시정지 버튼(`toggleMiniPpabangPlayback`)을
    /// 눌러야 `requestPlay()`가 호출되어 실제 재생이 시작된다.
    func togglePanel() {
        if isPresented {
            stop()
        } else {
            start()
        }
    }

    /// 정지: 플레이어 재생을 초기화하고 패널을 닫는다. 패널이 사라지면 웹뷰도 해제된다.
    func stop() {
        isBackgroundSuspended = false
        cancelConfirmation()
        cancelReadinessWait()
        generation += 1
        if let webView {
            webView.evaluateJavaScript(Self.stopScript) { _, _ in }
            Task { await webView.pauseAllMediaPlayback() }
        }
        pendingAutoplay = false
        isPresented = false
        isPanelOpen = false
        state = .idle
        trackTitle = nil
    }

    /// 재생 요청. 사이트의 시작·이어듣기 덮개를 누르거나 YouTube iframe에 playVideo를 보낸다.
    /// 플레이어가 재생 상태를 보고하기 전까지는 재생 중으로 표시하지 않는다.
    func requestPlay() {
        guard isPresented else { return }
        // 페이지 로드 전, 사이트 준비 전, 배경 유예 중에는 재생하지 않는다.
        // 의도만 남겨 두고 준비 신호·전면 복귀 때 처리한다.
        guard let webView, hasLoadedPage, isSiteReady, !isSuspendedForBackground else {
            pendingAutoplay = true
            return
        }
        pendingAutoplay = false
        if state == .playing { return }
        state = .requested
        let currentGeneration = generation
        webView.evaluateJavaScript(Self.playScript) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                if error != nil, self.state == .requested {
                    self.state = .blocked
                }
            }
        }
        scheduleConfirmation(generation: currentGeneration)
    }

    /// 재생 위치를 유지한 채 멈춘다. `stop()`과 달리 패널을 닫거나 웹뷰를 해제하지 않는다.
    func pause() {
        guard isPresented else { return }
        cancelConfirmation()
        pendingAutoplay = false
        if let webView {
            webView.evaluateJavaScript(Self.pauseScript) { _, _ in }
        }
        if state == .playing || state == .buffering || state == .requested {
            state = .paused
        }
    }

    /// 사이트의 다음 곡 버튼(#nextButton)을 눌러 사이트 자체 재생 목록 순서를 따른다.
    func skipToNext() {
        guard isPresented, let webView, hasLoadedPage, !isSuspendedForBackground else { return }
        webView.evaluateJavaScript(Self.nextScript) { _, _ in }
    }

    // MARK: - 배경 정지

    /// 앱이 비활성·배경으로 갈 때 호출한다. 영상은 즉시 멈추지만 미니플레이어와 선택한
    /// 곡·웹뷰는 그대로 유지한다. 시간이 얼마나 지나 돌아오든 패널을 닫거나 재생 정보를
    /// 비우지 않으며, 재생 재개는 사용자가 재생 버튼을 눌렀을 때만 이뤄진다.
    func suspendForBackground() {
        guard isPresented else { return }
        pauseMediaForBackground()
        if state == .playing || state == .buffering || state == .requested {
            state = .paused
        }
        cancelConfirmation()
        // 배경으로 물러나는 동안 남은 재생 의도를 지워, 복귀 후 준비 신호(`ready`)가
        // 뒤늦게 와도 사용자 조작 없이 자동 재생되지 않게 한다.
        pendingAutoplay = false
        isBackgroundSuspended = true
    }

    /// 앱이 전면 활성으로 돌아왔을 때 호출한다. 배경 정지 중이었다면 재생 요청을 다시
    /// 받을 수 있게 하되, 자동으로 재생을 시작하지는 않는다. 배경 중 `empty`·로드 실패
    /// 등 콜백이 재생 의도(`pendingAutoplay`)를 다시 세워 뒀을 수 있으므로 함께 지워,
    /// 복귀 뒤 뒤늦게 오는 `ready`·`didFinish` 콜백이 사용자 조작 없이 재생을 시작하지
    /// 않게 한다.
    func resumeAfterForegroundReturn() {
        isBackgroundSuspended = false
        pendingAutoplay = false
    }

    /// 배경에서 YouTube 재생이 이어지지 않도록 iframe 플레이어와 웹뷰 미디어를 모두 멈춘다.
    private func pauseMediaForBackground() {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.pauseScript) { _, _ in }
        Task { await webView.pauseAllMediaPlayback() }
    }

    // MARK: - 웹뷰 수명

    /// 현재 붙어 있는 웹뷰. `PpabangWebView.makeUIView`가 같은 인스턴스를 재사용할 수 있도록 노출한다.
    var currentWebView: WKWebView? { webView }

    func attach(_ webView: WKWebView) {
        pendingTeardown?.cancel()
        pendingTeardown = nil
        attachToken += 1
        if self.webView === webView {
            // 같은 웹뷰가 다른 SwiftUI 분기(세로↔가로 전환 등)로 옮겨 붙은 경우다.
            // 영상·재생 위치를 그대로 두고 델리게이트만 다시 연결한다.
            webView.navigationDelegate = self
            webView.uiDelegate = self
            return
        }
        if let previous = self.webView {
            teardown(previous)
        }
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(
            PpabangScriptMessageProxy(target: self),
            name: Self.bridgeMessageName
        )
        if isPresented {
            hasLoadedPage = false
            isSiteReady = false
            state = .loading
            webView.load(URLRequest(url: category.url, timeoutInterval: 30))
        }
    }

    /// SwiftUI가 웹뷰를 다른 분기로 옮기며 잠깐 떼어낼 때도 곧바로 정리하지 않는다.
    /// 다음 실행 루프 턴까지 기다려 같은 웹뷰가 다시 붙지 않았을 때만(진짜로 패널이 닫힌 경우) 정리한다.
    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        let tokenAtDetach = attachToken
        pendingTeardown?.cancel()
        pendingTeardown = Task { @MainActor [weak self] in
            // 회전으로 인한 레이아웃 재구성은 다음 화면 갱신에서 곧바로 끝나지 않을 수 있어
            // 한 프레임보다 넉넉한 여유를 두고 진짜로 재부착됐는지 확인한다.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self,
                  self.attachToken == tokenAtDetach, self.webView === webView
            else { return }
            self.teardown(webView)
        }
    }

    private func teardown(_ webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.bridgeMessageName
        )
        webView.configuration.userContentController.removeAllUserScripts()
        webView.stopLoading()
        webView.evaluateJavaScript(Self.stopScript) { _, _ in }
        webView.loadHTMLString("", baseURL: nil)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        if self.webView === webView {
            self.webView = nil
        }
        hasLoadedPage = false
        isSiteReady = false
        cancelConfirmation()
        cancelReadinessWait()
        isBackgroundSuspended = false
        if isPresented {
            // 패널이 화면에서 사라지면(편집 모드, 씬 전환 등) 재생도 함께 끝난다.
            isPresented = false
            isPanelOpen = false
            state = .idle
            trackTitle = nil
            pendingAutoplay = false
        }
    }

    // MARK: - 브리지 메시지

    fileprivate func handleBridgeMessage(_ message: WKScriptMessage) {
        guard isPresented, let webView, message.webView === webView,
              message.frameInfo.isMainFrame,
              Self.isAllowedOrigin(message.frameInfo.securityOrigin),
              let body = message.body as? [String: Any]
        else { return }

        if let title = body["title"] as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            trackTitle = trimmed.isEmpty ? nil : trimmed
        }
        if let siteEvent = body["site"] as? String {
            apply(siteEvent: siteEvent)
        }
        guard let rawState = body["state"] as? Int else { return }
        apply(playerState: rawState)
    }

    /// 브리지가 보고하는 사이트 상태.
    /// - `ready`: 플레이어와 재생 목록이 준비됐다. 남은 재생 의도가 있으면 지금 보낸다.
    /// - `empty`: 사이트가 재생할 영상이 없다고 표시했다(목록 소진·목록 요청 실패).
    /// - `emptyCleared`: 빈 목록 표시가 사라지고 새 영상 재생이 시작됐다.
    private func apply(siteEvent: String) {
        switch siteEvent {
        case "ready":
            isSiteReady = true
            cancelReadinessWait()
            if pendingAutoplay, state != .requested {
                requestPlay()
            }
        case "empty":
            cancelConfirmation()
            // 준비 신호가 아직 없으면 목록이 뒤늦게 도착할 때 자동으로 다시 시작하도록 의도를 남긴다.
            pendingAutoplay = pendingAutoplay || !isSiteReady
            state = .failed(Self.emptyListMessage)
        case "emptyCleared":
            if case .failed = state {
                state = .requested
                scheduleConfirmation(generation: generation)
            }
        default:
            break
        }
    }

    /// 페이지 로드 뒤 사이트 준비 신호가 오지 않으면 대기 중임을 숨기지 않고 실패로 표시한다.
    /// 늦게라도 준비 신호가 오면 남은 재생 의도로 정상 재개한다.
    private func scheduleReadinessWait(generation: Int) {
        cancelReadinessWait()
        readinessTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.siteReadinessTimeout))
            guard !Task.isCancelled, let self, self.generation == generation, self.isPresented else { return }
            if !self.isSiteReady, self.state == .ready {
                self.state = .failed(Self.playerUnavailableMessage)
            }
        }
    }

    private func cancelReadinessWait() {
        readinessTask?.cancel()
        readinessTask = nil
    }

    /// YouTube IFrame API의 플레이어 상태 코드.
    private func apply(playerState: Int) {
        if isSuspendedForBackground {
            // 배경 유예 중 플레이어가 재생 중이라고 보고하면 다시 멈춘다. 재생 표시는 하지 않는다.
            if playerState == 1 || playerState == 3 {
                pauseMediaForBackground()
            }
            return
        }
        switch playerState {
        case 1:
            cancelConfirmation()
            state = .playing
        case 2:
            cancelConfirmation()
            state = .paused
        case 3:
            state = .buffering
        case 0:
            // 곡이 끝나면 사이트가 다음 곡으로 넘어간다. 다음 상태 보고를 기다린다.
            if state == .playing { state = .buffering }
        case 5:
            if state == .playing || state == .paused || state == .buffering { state = .ready }
        case -1:
            if state == .playing || state == .paused { state = .ready }
        default:
            break
        }
    }

    private func scheduleConfirmation(generation: Int) {
        cancelConfirmation()
        confirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.playbackConfirmationTimeout))
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            if self.state == .requested {
                self.state = .blocked
            }
        }
    }

    private func cancelConfirmation() {
        confirmationTask?.cancel()
        confirmationTask = nil
    }

    // MARK: - 허용 범위

    static func isAllowedOrigin(_ origin: WKSecurityOrigin) -> Bool {
        origin.protocol == "https" && origin.host == allowedHost
    }

    static func isAllowedTopLevelURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == allowedHost
    }

    // MARK: - 스크립트

    /// 메인 프레임에만 주입한다. #player iframe의 src에서 유도한 YouTube origin에서 온
    /// IFrame API 상태 메시지만 네이티브로 전달한다. 사이트 준비·빈 목록 상태도 함께 보고하고,
    /// 로고 이미지는 모든 상태(시작 덮개·빈 목록 안내·상단 바)에서 숨긴다.
    static let bridgeScript = """
    (function () {
      if (window.location.origin !== 'https://ppabang.net') { return; }
      var style = document.createElement('style');
      style.textContent = `
        html,body{margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:transparent!important;}
        .brand-bar,.queue,.player-help{display:none!important;}
        .brand-mark img,.start-cover img,.empty-state img{display:none!important;}
        .empty-state{cursor:pointer!important;padding:16px!important;}
        .empty-state strong{font-size:17px!important;}
        .shorts-shell,.stage,#playerFrame,.video-surface{margin:0!important;padding:0!important;width:100%!important;height:100%!important;max-width:none!important;max-height:none!important;min-width:200px!important;min-height:200px!important;box-sizing:border-box!important;}
        .shorts-shell,.stage{display:block!important;}
        #playerFrame{border-radius:0!important;aspect-ratio:auto!important;}
        .stage{position:relative!important;top:0!important;inset:0!important;min-height:0!important;}
        #playerFrame{position:relative!important;inset:0!important;border:0!important;box-shadow:none!important;display:block!important;}
        .video-surface{position:absolute!important;inset:0!important;flex:none!important;aspect-ratio:auto!important;}
        .player-toolbar{display:none!important;}
        #playerFrame,.video-surface{background:transparent!important;}
        #player{width:100%!important;height:100%!important;min-width:200px!important;min-height:200px!important;}
      `;
      document.head.appendChild(style);
      if (window.__standPpabangBridge) { return; }
      var bridge = { playerReady: false, readySent: false, started: false };
      window.__standPpabangBridge = bridge;
      function post(payload) {
        try { window.webkit.messageHandlers.\(bridgeMessageName).postMessage(payload); } catch (error) {}
      }
      var queueList = document.getElementById('queueList');
      var tasteState = document.getElementById('tasteState');
      var emptyState = document.getElementById('emptyState');
      var startCover = document.getElementById('startCover');
      // 사이트는 목록 요청이 끝난 뒤에야 영상을 큐에 넣는다. 플레이어와 목록이 모두 준비됐을 때만
      // 준비 신호를 보내고, 목록 요청이 끝났는데도 영상이 없으면 사이트의 빈 목록 안내를 띄운다.
      // 사이트는 시작 덮개(`#startCover`)를 사용자가 직접 누르거나 영상이 재생될 때만 숨긴다.
      // 네이티브는 재생 요청을 사용자가 재생 버튼을 누를 때까지 미루므로, 그 사이 덮개가 "지금
      // 재생할 수 있는 쇼츠가 없어요" 문구를 그대로 띄운 채 있게 된다. 큐가 준비되면 이미 첫
      // 영상이 cue된 상태이므로 덮개만 숨겨 그 모습을 보여 준다.
      function evaluateSite() {
        if (!bridge.playerReady) { return; }
        var hasQueue = !!(queueList && queueList.querySelector('.queue-item'));
        if (hasQueue) {
          if (startCover && !bridge.started) { startCover.hidden = true; }
          if (!bridge.readySent) { bridge.readySent = true; post({ site: 'ready' }); }
          return;
        }
        var settled = !tasteState || tasteState.textContent.trim() !== '준비 중';
        if (settled) {
          if (emptyState && emptyState.hidden) { emptyState.hidden = false; }
          if (startCover && startCover.hidden && !bridge.started) { startCover.hidden = false; }
        }
      }
      if (emptyState) {
        new MutationObserver(function () {
          post({ site: emptyState.hidden ? 'emptyCleared' : 'empty' });
        }).observe(emptyState, { attributes: true, attributeFilter: ['hidden'] });
        // 빈 목록 안내를 탭하면 사이트의 시작 버튼 경로로 목록을 다시 불러온다.
        // 사이트 CSS가 시작 덮개를 숨겨도 click()은 동작한다.
        emptyState.setAttribute('role', 'button');
        emptyState.setAttribute('tabindex', '0');
        function retryFromEmpty() { if (startCover && !startCover.disabled) { startCover.click(); } }
        emptyState.addEventListener('click', retryFromEmpty);
        emptyState.addEventListener('keydown', function (event) {
          if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); retryFromEmpty(); }
        });
      }
      if (queueList) {
        new MutationObserver(evaluateSite).observe(queueList, { childList: true });
      }
      if (tasteState) {
        new MutationObserver(evaluateSite).observe(tasteState, { childList: true, characterData: true, subtree: true });
      }
      window.addEventListener('message', function (event) {
        var frame = document.getElementById('player');
        if (!frame || !frame.contentWindow || event.source !== frame.contentWindow) { return; }
        var expectedOrigin;
        try { expectedOrigin = new URL(frame.src, window.location.href).origin; } catch (error) { return; }
        if (event.origin !== expectedOrigin ||
            (expectedOrigin !== 'https://www.youtube.com' && expectedOrigin !== 'https://www.youtube-nocookie.com')) { return; }
        var data = event.data;
        if (typeof data === 'string') {
          try { data = JSON.parse(data); } catch (error) { return; }
        }
        if (!data || typeof data !== 'object') { return; }
        if (data.event === 'onReady' || data.event === 'infoDelivery' || data.event === 'onStateChange') {
          if (!bridge.playerReady) { bridge.playerReady = true; evaluateSite(); }
        }
        if (data.event === 'onStateChange' && typeof data.info === 'number') {
          if (data.info === 1) { bridge.started = true; }
          post({ state: data.info });
          return;
        }
        if (data.event === 'infoDelivery' && data.info && typeof data.info === 'object') {
          var payload = {};
          if (typeof data.info.playerState === 'number') {
            payload.state = data.info.playerState;
            if (data.info.playerState === 1) { bridge.started = true; }
          }
          if (data.info.videoData && typeof data.info.videoData.title === 'string') {
            payload.title = data.info.videoData.title;
          }
          if (payload.state !== undefined || payload.title !== undefined) { post(payload); }
        }
      }, false);
    })();
    """

    private static let playerCommandHelper = """
    function standPpabangCommand(name) {
      var frame = document.getElementById('player');
      if (!frame || !frame.contentWindow || !frame.src) { return false; }
      var origin;
      try { origin = new URL(frame.src, window.location.href).origin; } catch (error) { return false; }
      frame.contentWindow.postMessage(JSON.stringify({ event: 'command', func: name, args: [] }), origin);
      return true;
    }
    """

    /// 빈 목록 상태나 첫 시작은 사이트의 시작 버튼 경로(목록 재요청·playAt)를 그대로 쓴다.
    /// 사이트 CSS가 시작 덮개를 숨기고 있어 보이는지로 판단하지 않고 click()으로 호출한다.
    /// 이미 한 번 재생된 뒤에는 현재 영상에 playVideo만 보내 사이트 재생 순서를 방해하지 않는다.
    static let playScript = """
    (function () {
      \(playerCommandHelper)
      var bridge = window.__standPpabangBridge;
      var start = document.getElementById('startCover');
      var empty = document.getElementById('emptyState');
      var resume = document.getElementById('resumeCover');
      if (empty && !empty.hidden && start && !start.disabled) { start.click(); return 'reload'; }
      if (resume && !resume.hidden) { resume.click(); return 'resume'; }
      if (bridge && typeof bridge === 'object' && !bridge.started && start && !start.disabled) { start.click(); return 'start'; }
      return standPpabangCommand('playVideo') ? 'play' : 'none';
    })();
    """

    static let stopScript = """
    (function () {
      \(playerCommandHelper)
      return standPpabangCommand('stopVideo');
    })();
    """

    /// 재생 위치를 유지한 채 멈춘다. 배경 유예 중 전면 복귀 시 같은 지점에서 이어 간다.
    static let pauseScript = """
    (function () {
      \(playerCommandHelper)
      return standPpabangCommand('pauseVideo');
    })();
    """

    static let nextScript = """
    (function () {
      var button = document.getElementById('nextButton');
      if (!button) { return false; }
      button.click();
      return true;
    })();
    """
}

private struct PpabangCatalogStatus: Decodable {
    let categories: [String: CategoryState]

    struct CategoryState: Decodable {
        let count: Int
    }
}

extension PpabangPlayerSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let isTopLevel = navigationAction.targetFrame == nil
            || navigationAction.targetFrame?.isMainFrame == true
        if isTopLevel {
            // 최상위 문서는 빠방 HTTPS 페이지만 허용한다. 다른 곳으로 떠나는 이동은 막는다.
            guard Self.isAllowedTopLevelURL(url), !navigationAction.shouldPerformDownload else {
                decisionHandler(.cancel)
                return
            }
        } else if url.scheme?.lowercased() != "https" {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hasLoadedPage = false
        isSiteReady = false
        cancelReadinessWait()
        if isPresented { state = .loading }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isPresented else { return }
        hasLoadedPage = true
        if case .failed = state {} else { state = .ready }
        if pendingAutoplay {
            requestPlay()
        }
        if !isSiteReady {
            scheduleReadinessWait(generation: generation)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleLoadFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isPresented else { return }
        hasLoadedPage = false
        isSiteReady = false
        cancelConfirmation()
        cancelReadinessWait()
        state = .failed("플레이어가 종료되었습니다. 재생을 다시 눌러 주세요.")
        pendingAutoplay = true
    }

    private func handleLoadFailure(_ error: Error) {
        guard isPresented else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        hasLoadedPage = false
        isSiteReady = false
        cancelConfirmation()
        cancelReadinessWait()
        pendingAutoplay = true
        state = .failed("빠방을 열지 못했습니다. \(error.localizedDescription)")
    }
}

extension PpabangPlayerSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // 새 창(YouTube 로고 등)은 열지 않는다. 플레이어 하나만 유지한다.
        nil
    }
}

/// `WKUserContentController`가 핸들러를 강하게 붙잡으므로 세션은 약하게 참조한다.
private final class PpabangScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: PpabangPlayerSession?

    init(target: PpabangPlayerSession) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // WebKit은 스크립트 메시지를 메인 스레드에서 전달한다.
        MainActor.assumeIsolated {
            target?.handleBridgeMessage(message)
        }
    }
}

struct PpabangWebView: UIViewRepresentable {
    @ObservedObject var session: PpabangPlayerSession

    final class Coordinator {
        let session: PpabangPlayerSession

        init(session: PpabangPlayerSession) {
            self.session = session
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> WKWebView {
        // 세로↔가로 전환처럼 같은 패널이 다른 SwiftUI 분기로 옮겨 붙을 때는 기존 웹뷰를
        // 그대로 재사용해 영상·재생 위치가 끊기지 않게 한다.
        if let existing = context.coordinator.session.currentWebView {
            context.coordinator.session.attach(existing)
            return existing
        }
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        // 네이티브 재생 버튼이 사이트 덮개를 눌러 재생을 시작할 수 있게 한다.
        // 실제 재생 여부는 플레이어 상태 보고로만 확정한다.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: PpabangPlayerSession.bridgeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        context.coordinator.session.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.session.detach(webView)
    }
}

enum PpabangPlayerPanelMetrics {
    static let width: CGFloat = 216
    static let height: CGFloat = 216
    static let minimumVideoSide: CGFloat = 200
}

struct PpabangFloatingPlayer: View {
    @ObservedObject var session: PpabangPlayerSession
    let accent: Color
    let controlSize: CGSize
    let onFrameChanged: (CGRect) -> Void
    let onToggle: () -> Void
    let onNext: () -> Void
    let onRefreshCategories: () -> Void
    let onSelectCategory: (PpabangCategory) -> Void

    var body: some View {
        GeometryReader { proxy in
            // 빠방을 시작하면 미니플레이어를 왼쪽 하단에 띄우고, 재생 조작은 오른쪽에 둔다.
            HStack(alignment: .bottom, spacing: HomeSharedControlMetrics.spacing) {
                PpabangPlayerPanel(
                    session: session,
                    accent: accent
                )

                PpabangMiniPlayerControls(
                    state: session.state,
                    category: session.category,
                    categories: session.categories,
                    size: controlSize,
                    onToggle: onToggle,
                    onNext: onNext,
                    onRefreshCategories: onRefreshCategories,
                    onSelectCategory: onSelectCategory
                )
            }
            // 미니플레이어(영상+재생 조작) 전체 영역을 모드 전환 탭/드래그 인식기에서 제외한다.
            .background {
                GeometryReader { frame in
                    Color.clear
                        .onAppear { onFrameChanged(frame.frame(in: .named("stand.root"))) }
                        .onChange(of: frame.frame(in: .named("stand.root"))) { _, rect in onFrameChanged(rect) }
                }
            }
            .offset(
                x: 0,
                y: max(0, proxy.size.height - PpabangPlayerPanelMetrics.height)
            )
            .transaction { $0.animation = nil }
        }
    }
}

struct PpabangPlayerPanel: View {
    @ObservedObject var session: PpabangPlayerSession
    let accent: Color

    var body: some View {
        PpabangWebView(session: session)
            .frame(width: PpabangPlayerPanelMetrics.minimumVideoSide, height: PpabangPlayerPanelMetrics.minimumVideoSide)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("빠방 영상 플레이어")
            .help(session.state.instructionText ?? session.state.statusText)
        .padding(8)
        .frame(width: PpabangPlayerPanelMetrics.width, height: PpabangPlayerPanelMetrics.height)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [accent.opacity(0.72), accent.opacity(0.50)], startPoint: .top, endPoint: .bottom))
                .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.6), lineWidth: 1) }
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}
