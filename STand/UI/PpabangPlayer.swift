import Combine
import SwiftUI
import UIKit
import WebKit

/// 빠방(ppabang.net)이 제공하는 아홉 개 채널. 재생 목록과 자동 다음 곡은 웹사이트가 소유한다.
enum PpabangCategory: String, CaseIterable, Identifiable {
    case golfVertical
    case golfHorizontal
    case camping
    case girlgroup
    case legends
    case ballad
    case ccm
    case lounge
    case bedroom

    static let `default` = PpabangCategory.ccm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .golfVertical: "세로 골프"
        case .golfHorizontal: "가로 골프"
        case .camping: "캠핑"
        case .girlgroup: "아이돌 뮤비"
        case .legends: "경연"
        case .ballad: "가요톱텐"
        case .ccm: "CCM"
        case .lounge: "라운지"
        case .bedroom: "베드룸"
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = PpabangPlayerSession.allowedHost
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "category", value: rawValue)]
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

    @Published private(set) var category: PpabangCategory
    @Published private(set) var isPresented = false
    @Published private(set) var state: PpabangPlaybackState = .idle
    @Published private(set) var trackTitle: String?

    private weak var webView: WKWebView?
    private var hasLoadedPage = false
    private var pendingAutoplay = false
    private var confirmationTask: Task<Void, Never>?
    private var generation = 0

    override init() {
        let stored = UserDefaults.standard.string(forKey: Self.categoryDefaultsKey)
        category = stored.flatMap(PpabangCategory.init(rawValue:)) ?? .default
        super.init()
    }

    // MARK: - 네이티브 명령

    /// 플레이어를 보이게 하고 선택한 채널을 불러온다. 이미 열려 있으면 채널만 바꾼다.
    func start(category requested: PpabangCategory? = nil) {
        if let requested, requested != category {
            category = requested
            UserDefaults.standard.set(requested.rawValue, forKey: Self.categoryDefaultsKey)
        }
        cancelConfirmation()
        generation += 1
        trackTitle = nil
        hasLoadedPage = false
        pendingAutoplay = true
        isPresented = true
        state = .loading
        if let webView {
            webView.load(URLRequest(url: category.url, timeoutInterval: 30))
        }
    }

    /// 정지: 플레이어 재생을 초기화하고 패널을 닫는다. 패널이 사라지면 웹뷰도 해제된다.
    func stop() {
        cancelConfirmation()
        generation += 1
        if let webView {
            webView.evaluateJavaScript(Self.stopScript) { _, _ in }
            Task { await webView.pauseAllMediaPlayback() }
        }
        pendingAutoplay = false
        isPresented = false
        state = .idle
        trackTitle = nil
    }

    /// 재생 요청. 사이트의 시작·이어듣기 덮개를 누르거나 YouTube iframe에 playVideo를 보낸다.
    /// 플레이어가 재생 상태를 보고하기 전까지는 재생 중으로 표시하지 않는다.
    func requestPlay() {
        guard isPresented else { return }
        guard let webView, hasLoadedPage else {
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

    /// 사이트의 다음 곡 버튼(#nextButton)을 눌러 사이트 자체 재생 목록 순서를 따른다.
    func skipToNext() {
        guard isPresented, let webView, hasLoadedPage else { return }
        webView.evaluateJavaScript(Self.nextScript) { _, _ in }
    }

    // MARK: - 웹뷰 수명

    func attach(_ webView: WKWebView) {
        if let previous = self.webView, previous !== webView {
            detach(previous)
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
            state = .loading
            webView.load(URLRequest(url: category.url, timeoutInterval: 30))
        }
    }

    func detach(_ webView: WKWebView) {
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
        cancelConfirmation()
        if isPresented {
            // 패널이 화면에서 사라지면(편집 모드, 씬 전환 등) 재생도 함께 끝난다.
            isPresented = false
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
        guard let rawState = body["state"] as? Int else { return }
        apply(playerState: rawState)
    }

    /// YouTube IFrame API의 플레이어 상태 코드.
    private func apply(playerState: Int) {
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
    /// IFrame API 상태 메시지만 네이티브로 전달한다.
    static let bridgeScript = """
    (function () {
      if (window.location.origin !== 'https://ppabang.net') { return; }
      var style = document.createElement('style');
      style.textContent = `
        html,body{margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:transparent!important;}
        .brand-bar,.queue,.player-help{display:none!important;}
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
      window.__standPpabangBridge = true;
      function post(payload) {
        try { window.webkit.messageHandlers.\(bridgeMessageName).postMessage(payload); } catch (error) {}
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
        if (data.event === 'onStateChange' && typeof data.info === 'number') {
          post({ state: data.info });
          return;
        }
        if (data.event === 'infoDelivery' && data.info && typeof data.info === 'object') {
          var payload = {};
          if (typeof data.info.playerState === 'number') { payload.state = data.info.playerState; }
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

    static let playScript = """
    (function () {
      \(playerCommandHelper)
      function isVisible(element) {
        if (!element) { return false; }
        var style = window.getComputedStyle(element);
        if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity) === 0) { return false; }
        var rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      }
      var start = document.getElementById('startCover');
      if (isVisible(start)) { start.click(); return 'start'; }
      var resume = document.getElementById('resumeCover');
      if (isVisible(resume)) { resume.click(); return 'resume'; }
      return standPpabangCommand('playVideo') ? 'play' : 'none';
    })();
    """

    static let stopScript = """
    (function () {
      \(playerCommandHelper)
      return standPpabangCommand('stopVideo');
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
        if isPresented { state = .loading }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isPresented else { return }
        hasLoadedPage = true
        state = .ready
        if pendingAutoplay {
            requestPlay()
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
        cancelConfirmation()
        state = .failed("플레이어가 종료되었습니다. 재생을 다시 눌러 주세요.")
        pendingAutoplay = true
    }

    private func handleLoadFailure(_ error: Error) {
        guard isPresented else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        hasLoadedPage = false
        cancelConfirmation()
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
    static let maximumWidth: CGFloat = 272
    static let minimumVideoSide: CGFloat = 200
}

struct PpabangFloatingPlayer: View {
    @ObservedObject var session: PpabangPlayerSession
    let anchorFrame: CGRect
    let accent: Color
    let onSelectCategory: (PpabangCategory) -> Void
    let onPlay: () -> Void
    let onStop: () -> Void
    let onNext: () -> Void
    let onFrameChanged: (CGRect) -> Void
    @AppStorage("ppabang.panelOpacityPercent") private var backgroundPercent = 100
    @AppStorage("ppabang.panelPositionX") private var savedX = -1.0
    @AppStorage("ppabang.panelPositionY") private var savedY = -1.0
    @State private var origin: CGPoint?
    @GestureState private var translation = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let maxX = max(0, proxy.size.width - 272)
            let maxY = max(0, proxy.size.height - 216)
            let initialPosition = savedX >= 0 && savedY >= 0
                ? CGPoint(x: savedX * maxX, y: savedY * maxY)
                : CGPoint(x: anchorFrame.minX, y: anchorFrame.isEmpty ? 88 : anchorFrame.maxY + 8)
            let base = origin ?? CGPoint(
                x: min(maxX, max(0, initialPosition.x)),
                y: min(maxY, max(0, initialPosition.y))
            )
            let x = min(maxX, max(0, base.x + translation.width))
            let y = min(maxY, max(0, base.y + translation.height))
            PpabangPlayerPanel(
                session: session, accent: accent, onSelectCategory: onSelectCategory,
                onPlay: onPlay, onStop: onStop, onNext: onNext,
                backgroundOpacity: Double(min(100, max(10, backgroundPercent))) / 100,
                dragHandle: AnyView(
                    VStack(spacing: 0) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(backgroundPercent)%").font(.system(size: 8, weight: .medium))
                    }
                        .frame(width: 48, height: 32)
                        .contentShape(Rectangle())
                        .accessibilityLabel("플레이어 이동, 배경 진하기 \(backgroundPercent)퍼센트")
                        .accessibilityHint("누르면 배경 진하기 변경, 끌면 이동")
                        .onTapGesture {
                            backgroundPercent = [10, 35, 60, 85, 100].first { $0 > backgroundPercent } ?? 10
                        }
                        .gesture(
                            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                                .updating($translation) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    origin = CGPoint(
                                        x: min(maxX, max(0, base.x + value.translation.width)),
                                        y: min(maxY, max(0, base.y + value.translation.height))
                                    )
                                    if let origin {
                                        savedX = maxX > 0 ? origin.x / maxX : 0
                                        savedY = maxY > 0 ? origin.y / maxY : 0
                                    }
                                }
                        )
                )
            )
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .background {
                GeometryReader { panel in
                    Color.clear
                        .onAppear { onFrameChanged(panel.frame(in: .named("stand.root"))) }
                        .onChange(of: panel.frame(in: .named("stand.root"))) { _, frame in onFrameChanged(frame) }
                }
            }
            .offset(x: x, y: y)
            .transaction { $0.animation = nil }
        }
    }
}

struct PpabangPlayerPanel: View {
    @ObservedObject var session: PpabangPlayerSession
    let accent: Color
    let onSelectCategory: (PpabangCategory) -> Void
    let onPlay: () -> Void
    let onStop: () -> Void
    let onNext: () -> Void
    var backgroundOpacity: Double = 1
    var dragHandle: AnyView = AnyView(EmptyView())

    var body: some View {
        HStack(spacing: 8) {
            PpabangWebView(session: session)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel("빠방 영상 플레이어")
            VStack(spacing: 8) {
                dragHandle
                control("정지", action: onStop)
                control("다음", enabled: session.state != .loading, action: onNext)
                Button(action: onStop) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.14 * backgroundOpacity), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("플레이어 닫기 및 정지")
            }
            .frame(width: 48, height: 200)
            .help(session.state.instructionText ?? session.state.statusText)
        }
        .padding(8)
        .frame(width: 272, height: 216)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [accent.opacity(0.72), accent.opacity(0.50)], startPoint: .top, endPoint: .bottom))
                .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.6), lineWidth: 1) }
                .opacity(backgroundOpacity)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private func control(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.white.opacity((enabled ? 0.14 : 0.05) * backgroundOpacity), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("빠방 \(title)")
    }
}
