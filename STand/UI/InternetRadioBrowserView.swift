import Foundation
import SwiftUI
import UIKit
import WebKit

/// 스트리밍 사이트를 직접 탐색하기 위한 브라우저다.
/// 웹페이지를 분석하거나 발견한 주소를 라디오 채널에 자동으로 전달하지 않는다.
struct InternetRadioBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: InternetRadioBrowserSession
    @State private var addressText: String
    @State private var showsFavorites = false
    @FocusState private var addressFieldIsFocused: Bool
    @ScaledMetric(relativeTo: .body) private var scaledAddressBarHeight: CGFloat = 44

    let accent: Color

    private var addressBarHeight: CGFloat {
        min(56, max(44, scaledAddressBarHeight))
    }

    init(accent: Color = .orange) {
        let homepage = InternetRadioBrowserAddress.defaultHomepage
        self.accent = accent
        _session = StateObject(
            wrappedValue: InternetRadioBrowserSession(initialURL: homepage)
        )
        _addressText = State(initialValue: homepage.absoluteString)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                addressBar

                ZStack(alignment: .top) {
                    InternetRadioWebView(session: session)
                        .ignoresSafeArea(edges: .bottom)

                    if showsFavorites {
                        favoritesPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let errorMessage = session.errorMessage {
                        browserMessagePanel(errorMessage)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .background(browserBackground)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: session.currentURL) { _, newURL in
                guard !addressFieldIsFocused, let newURL else { return }
                addressText = newURL.absoluteString
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    session.resumePageMedia()
                } else {
                    session.pausePageMedia()
                }
            }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
    }

    private var addressBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                browserBackOrCloseButton
                browserAddressField.frame(minWidth: 88)
                browserPrimaryAddressButton
                browserReloadButton
                browserFavoritesButton
                browserCloseButton
            }

            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    browserBackOrCloseButton
                    browserAddressField
                    browserPrimaryAddressButton
                }

                HStack(spacing: 7) {
                    Spacer(minLength: 0)
                    browserReloadButton
                    browserFavoritesButton
                    browserCloseButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(browserBackground.opacity(0.96))
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(height: 1)
                pageLoadProgressBar
                    .frame(height: 2)
            }
        }
    }

    private var browserAddressField: some View {
        TextField("웹 주소 입력", text: $addressText)
            .font(.callout.weight(.semibold))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($addressFieldIsFocused)
            .onSubmit(loadAddress)
            .padding(.horizontal, 10)
            .frame(height: addressBarHeight)
            .background(browserPanelFill.opacity(0.72), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }

    private var browserReloadButton: some View {
        Button {
            session.reload()
        } label: {
            browserToolbarIcon("arrow.clockwise")
        }
        .buttonStyle(.plain)
        .disabled(!session.hasLoadedPage)
        .accessibilityLabel("새로고침")
    }

    private var browserCloseButton: some View {
        Button(action: closeBrowser) {
            browserToolbarIcon("xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("브라우저 닫기")
    }

    private var pageLoadProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                browserPanelFill.opacity(session.isLoading ? 0.80 : 0)
                accent
                    .frame(
                        width: proxy.size.width
                            * CGFloat(min(max(session.pageLoadProgress, 0), 1))
                    )
            }
        }
        .opacity(session.isLoading ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: session.pageLoadProgress)
        .animation(.easeInOut(duration: 0.16), value: session.isLoading)
        .accessibilityHidden(true)
    }

    private var browserBackOrCloseButton: some View {
        Image(
            systemName: session.isPopupOpen || !session.canGoBack
                ? "xmark"
                : "chevron.left"
        )
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white.opacity(0.68))
        .frame(width: 44, height: 44)
        .background(browserPanelFill.opacity(0.90), in: Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .contentShape(Circle())
        .gesture(browserBackOrCloseGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(backOrCloseAccessibilityLabel)
        .accessibilityHint(
            session.canGoBack && !session.isPopupOpen
                ? "길게 누르면 브라우저를 닫습니다"
                : ""
        )
        .accessibilityAction {
            handleBackOrCloseTap()
        }
        .accessibilityAction(named: Text("브라우저 닫기")) {
            closeBrowser()
        }
    }

    private var browserPrimaryAddressButton: some View {
        browserToolbarIcon(
            session.isLoading ? "xmark" : "arrow.turn.down.left",
            isPrimary: true
        )
        .contentShape(Circle())
        .gesture(primaryAddressButtonGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(session.isLoading ? "로딩 중지" : "주소로 이동")
        .accessibilityHint("길게 누르면 복사한 주소를 붙여넣고 바로 이동합니다")
        .accessibilityAction {
            primaryAddressAction()
        }
        .accessibilityAction(named: Text("복사한 주소로 이동")) {
            pasteCopiedAddressAndLoad()
        }
    }

    private var browserFavoritesButton: some View {
        Image(systemName: showsFavorites ? "star.fill" : "star")
            .font(.callout.weight(.semibold))
            .foregroundStyle(showsFavorites ? accent : .white.opacity(0.68))
            .frame(width: 44, height: 44)
            .background(browserPanelFill.opacity(0.90), in: Circle())
            .overlay {
                Circle().stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsFavorites.toggle()
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(showsFavorites ? "즐겨찾기 닫기" : "즐겨찾기 열기")
            .accessibilityAction {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsFavorites.toggle()
                }
            }
    }

    private func browserToolbarIcon(
        _ systemName: String,
        isPrimary: Bool = false
    ) -> some View {
        Image(systemName: systemName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(isPrimary ? Color.white : .white.opacity(0.68))
            .frame(width: 44, height: 44)
            .background(
                isPrimary ? accent : browserPanelFill.opacity(0.90),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        isPrimary ? accent.opacity(0.34) : .white.opacity(0.14),
                        lineWidth: 1
                    )
            }
    }

    private var primaryAddressButtonGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    pasteCopiedAddressAndLoad()
                case .second:
                    primaryAddressAction()
                }
            }
    }

    private var browserBackOrCloseGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    if session.isPopupOpen {
                        session.closePopup()
                    } else {
                        closeBrowser()
                    }
                case .second:
                    handleBackOrCloseTap()
                }
            }
    }

    private var backOrCloseAccessibilityLabel: String {
        if session.isPopupOpen { return "팝업 닫기" }
        return session.canGoBack ? "이전 페이지" : "브라우저 닫기"
    }

    private func handleBackOrCloseTap() {
        if session.isPopupOpen {
            session.closePopup()
        } else if session.canGoBack {
            session.goBack()
        } else {
            closeBrowser()
        }
    }

    private func closeBrowser() {
        session.pausePageMedia()
        dismiss()
    }

    private func loadAddress() {
        addressFieldIsFocused = false
        showsFavorites = false
        session.open(address: addressText)
    }

    private func primaryAddressAction() {
        if session.isLoading {
            session.stopLoading()
        } else {
            loadAddress()
        }
    }

    private func pasteCopiedAddressAndLoad() {
        guard let pastedAddress = copiedAddress else {
            session.showError("복사한 웹 주소가 없습니다.")
            return
        }
        addressText = pastedAddress
        loadAddress()
    }

    private var copiedAddress: String? {
        let value = UIPasteboard.general.string
            ?? UIPasteboard.general.url?.absoluteString
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var favoritesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("즐겨찾기", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsFavorites = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("즐겨찾기 닫기")
            }

            ForEach(InternetRadioBrowserFavorite.defaults) { favorite in
                Button {
                    addressText = favorite.url.absoluteString
                    showsFavorites = false
                    addressFieldIsFocused = false
                    session.open(url: favorite.url)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: favorite.isHomepage ? "house.fill" : "globe")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(favorite.isHomepage ? accent : .white.opacity(0.58))
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.88))
                            Text(favorite.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.36))
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 56)
                    .background(browserPanelFill.opacity(0.84), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(favorite.title), \(favorite.url.absoluteString)")
            }

            Text("웹사이트만 열며 스트리밍 주소를 자동으로 감지하거나 채널에 입력하지 않습니다.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.52))
                .padding(.horizontal, 4)
        }
        .padding(12)
        .background(browserBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func browserMessagePanel(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote.weight(.semibold))
                .lineLimit(3)
            Spacer(minLength: 4)
            Button {
                session.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("안내 닫기")
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.30), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var browserBackground: Color {
        Color(red: 0.105, green: 0.078, blue: 0.071)
    }

    private var browserPanelFill: Color {
        Color.white.opacity(0.09)
    }
}

private struct InternetRadioWebView: UIViewRepresentable {
    @ObservedObject var session: InternetRadioBrowserSession

    final class Coordinator {
        let session: InternetRadioBrowserSession

        init(session: InternetRadioBrowserSession) {
            self.session = session
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView: WKWebView
        if let retainedWebView = InternetRadioBrowserSessionStore.shared.takeValidWebView() {
            webView = retainedWebView
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            configuration.preferences.isFraudulentWebsiteWarningEnabled = true
            configuration.preferences.isElementFullscreenEnabled = false
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.defaultWebpagePreferences.preferredContentMode = .mobile
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            configuration.allowsInlineMediaPlayback = true
            configuration.allowsAirPlayForMediaPlayback = false
            configuration.allowsPictureInPictureMediaPlayback = false
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: InternetRadioBrowserSession.fileUploadBlockingScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false,
                    in: .page
                )
            )
            webView = WKWebView(frame: .zero, configuration: configuration)
        }

        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .onDrag
        context.coordinator.session.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.session.detach(webView)
    }
}

@MainActor
private final class InternetRadioBrowserSessionStore {
    static let shared = InternetRadioBrowserSessionStore()

    private var retainedWebView: WKWebView?
    private var retainedAt: Date?
    private var resetTask: Task<Void, Never>?
    private var mediaPlaybackTask: Task<Void, Never>?
    private let retentionInterval: TimeInterval = 10

    func retain(_ webView: WKWebView) {
        suspendPlayback(in: webView)
        if retainedWebView !== webView {
            retainedWebView?.stopLoading()
        }
        retainedWebView = webView
        retainedAt = Date()
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.clearIfExpired()
        }
    }

    func takeValidWebView() -> WKWebView? {
        guard let retainedAt,
              Date().timeIntervalSince(retainedAt) <= retentionInterval,
              let retainedWebView
        else {
            clear()
            return nil
        }
        resetTask?.cancel()
        self.retainedWebView = nil
        self.retainedAt = nil
        resumePlayback(in: retainedWebView)
        return retainedWebView
    }

    func pausePlayback(in webView: WKWebView) {
        Task { @MainActor in
            await webView.pauseAllMediaPlayback()
        }
        webView.evaluateJavaScript(
            """
            document.querySelectorAll('video,audio').forEach((media) => {
              try { media.pause(); } catch (error) {}
            });
            """
        )
    }

    func suspendPlayback(in webView: WKWebView) {
        pausePlayback(in: webView)
        setMediaPlaybackSuspended(true, in: webView)
    }

    func resumePlayback(in webView: WKWebView) {
        setMediaPlaybackSuspended(false, in: webView)
    }

    private func setMediaPlaybackSuspended(_ suspended: Bool, in webView: WKWebView) {
        let previousTask = mediaPlaybackTask
        mediaPlaybackTask = Task { @MainActor [weak webView] in
            await previousTask?.value
            guard let webView else { return }
            await webView.setAllMediaPlaybackSuspended(suspended)
        }
    }

    private func clearIfExpired() {
        guard let retainedAt,
              Date().timeIntervalSince(retainedAt) > retentionInterval
        else { return }
        clear()
    }

    private func clear() {
        retainedWebView?.stopLoading()
        retainedWebView = nil
        retainedAt = nil
        resetTask?.cancel()
        resetTask = nil
    }
}

@MainActor
private final class InternetRadioBrowserSession: NSObject, ObservableObject {
    static let fileUploadBlockingScript = """
    (() => {
      const fileInput = (target) => {
        if (!(target instanceof Element)) return null;
        return target.closest('input[type="file"]');
      };
      const containsFiles = (event) => {
        const transferTypes = [
          ...Array.from(event.dataTransfer?.types || []),
          ...Array.from(event.clipboardData?.types || [])
        ];
        const clipboardHasFile = Array.from(
          event.clipboardData?.items || []
        ).some((item) => item.kind === 'file');
        return transferTypes.includes('Files') || clipboardHasFile;
      };
      const blockFileInput = (event) => {
        if (!fileInput(event.target) && !containsFiles(event)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
      };
      const disableFileInputs = (root) => {
        if (!(root instanceof Document || root instanceof Element)) return;
        if (root instanceof HTMLInputElement && root.type === 'file') {
          root.disabled = true;
        }
        root.querySelectorAll?.('input[type="file"]').forEach((input) => {
          input.disabled = true;
        });
      };
      const nativeClick = HTMLInputElement.prototype.click;
      HTMLInputElement.prototype.click = function() {
        if (this.type === 'file') return;
        return nativeClick.call(this);
      };
      if (HTMLInputElement.prototype.showPicker) {
        const nativeShowPicker = HTMLInputElement.prototype.showPicker;
        HTMLInputElement.prototype.showPicker = function() {
          if (this.type === 'file') return;
          return nativeShowPicker.call(this);
        };
      }
      document.addEventListener('click', blockFileInput, true);
      document.addEventListener('pointerdown', blockFileInput, true);
      document.addEventListener('touchstart', blockFileInput, true);
      document.addEventListener('dragenter', blockFileInput, true);
      document.addEventListener('dragover', blockFileInput, true);
      document.addEventListener('drop', blockFileInput, true);
      document.addEventListener('paste', blockFileInput, true);
      disableFileInputs(document);
      new MutationObserver((records) => {
        records.forEach((record) => {
          if (record.target) disableFileInputs(record.target);
          record.addedNodes.forEach((node) => disableFileInputs(node));
        });
      }).observe(document, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['type']
      });
    })();
    """

    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedPage = false
    @Published private(set) var pageLoadProgress = 0.0
    @Published private(set) var isPopupOpen = false
    @Published private(set) var errorMessage: String?

    private let initialURL: URL
    private weak var webView: WKWebView?
    private var progressObservation: NSKeyValueObservation?
    private var popupReturnURL: URL?

    init(initialURL: URL) {
        self.initialURL = initialURL
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeProgress(in: webView)

        if webView.url == nil {
            webView.load(URLRequest(url: initialURL, timeoutInterval: 30))
        } else {
            updateNavigationState(from: webView)
        }
    }

    func detach(_ webView: WKWebView) {
        progressObservation?.invalidate()
        progressObservation = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        InternetRadioBrowserSessionStore.shared.retain(webView)
        if self.webView === webView {
            self.webView = nil
        }
    }

    func open(address: String) {
        do {
            let url = try InternetRadioBrowserAddress.browsingURL(from: address)
            errorMessage = nil
            pageTitle = ""
            webView?.load(URLRequest(url: url, timeoutInterval: 30))
        } catch {
            showError(error.localizedDescription)
        }
    }

    func open(url: URL) {
        guard InternetRadioBrowserAddress.isSecureWebURL(url) else {
            showError("https://로 시작하는 안전한 웹 주소만 열 수 있습니다.")
            return
        }
        errorMessage = nil
        pageTitle = ""
        webView?.load(URLRequest(url: url, timeoutInterval: 30))
    }

    func goBack() {
        webView?.goBack()
    }

    func reload() {
        errorMessage = nil
        webView?.reload()
    }

    func stopLoading() {
        webView?.stopLoading()
        isLoading = false
        pageLoadProgress = 0
    }

    func closePopup() {
        guard isPopupOpen, let webView else { return }
        isPopupOpen = false
        if let popupReturnURL {
            webView.load(URLRequest(url: popupReturnURL, timeoutInterval: 30))
            self.popupReturnURL = nil
        } else if webView.canGoBack {
            webView.goBack()
        }
    }

    func pausePageMedia() {
        guard let webView else { return }
        InternetRadioBrowserSessionStore.shared.suspendPlayback(in: webView)
    }

    func resumePageMedia() {
        guard let webView else { return }
        InternetRadioBrowserSessionStore.shared.resumePlayback(in: webView)
    }

    func showError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }

    private func observeProgress(in webView: WKWebView) {
        progressObservation?.invalidate()
        progressObservation = webView.observe(
            \.estimatedProgress,
            options: [.initial, .new]
        ) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.pageLoadProgress = webView.estimatedProgress
            }
        }
    }

    private func updateNavigationState(from webView: WKWebView) {
        if let url = webView.url,
           InternetRadioBrowserAddress.isSecureWebURL(url) {
            currentURL = url
        }
        pageTitle = webView.title ?? ""
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
        if webView.url != nil { hasLoadedPage = true }
    }

    private func rejectNavigation(_ message: String) {
        errorMessage = message
        isLoading = false
        pageLoadProgress = 0
    }

    private func handleLoadFailure(_ error: Error, webView: WKWebView) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            updateNavigationState(from: webView)
            return
        }
        errorMessage = "페이지를 열지 못했습니다. \(error.localizedDescription)"
        isLoading = false
        pageLoadProgress = 0
        updateNavigationState(from: webView)
    }
}

extension InternetRadioBrowserSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              InternetRadioBrowserAddress.isSecureWebURL(url)
        else {
            rejectNavigation("https://로 시작하는 안전한 웹 주소만 열 수 있습니다.")
            decisionHandler(.cancel)
            return
        }

        guard !navigationAction.shouldPerformDownload else {
            rejectNavigation("이 브라우저는 파일을 내려받지 않습니다.")
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let url = navigationResponse.response.url,
              InternetRadioBrowserAddress.isSecureWebURL(url)
        else {
            rejectNavigation("허용되지 않은 형식의 주소입니다.")
            decisionHandler(.cancel)
            return
        }

        if let response = navigationResponse.response as? HTTPURLResponse,
           let disposition = response.value(
               forHTTPHeaderField: "Content-Disposition"
           )?.lowercased(),
           disposition.contains("attachment") {
            rejectNavigation("이 브라우저는 파일을 내려받지 않습니다.")
            decisionHandler(.cancel)
            return
        }

        guard navigationResponse.canShowMIMEType else {
            rejectNavigation("이 브라우저에서 표시할 수 없는 파일 형식입니다.")
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        isLoading = true
        pageLoadProgress = max(webView.estimatedProgress, 0.08)
        updateNavigationState(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigationState(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorMessage = nil
        pageLoadProgress = 1
        isLoading = false
        updateNavigationState(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleLoadFailure(error, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleLoadFailure(error, webView: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        rejectNavigation("웹페이지가 종료되었습니다. 새로고침해 주세요.")
        updateNavigationState(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod
            == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

extension InternetRadioBrowserSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url,
              InternetRadioBrowserAddress.isSecureWebURL(url),
              !navigationAction.shouldPerformDownload
        else { return nil }

        if !isPopupOpen {
            popupReturnURL = webView.url
        }
        isPopupOpen = true
        webView.load(navigationAction.request)
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopup()
    }

    @available(iOS 18.4, *)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        completionHandler(nil)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    func webView(
        _ webView: WKWebView,
        requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }
}

struct InternetRadioBrowserFavorite: Identifiable, Equatable {
    let title: String
    let url: URL
    let isHomepage: Bool

    var id: String { url.absoluteString }

    static let defaults: [InternetRadioBrowserFavorite] = [
        InternetRadioBrowserFavorite(
            title: "Google",
            url: URL(string: "https://www.google.com/")!,
            isHomepage: true
        ),
        InternetRadioBrowserFavorite(
            title: "한국 라디오",
            url: URL(string: "https://radio.bsod.kr/")!,
            isHomepage: false
        ),
        InternetRadioBrowserFavorite(
            title: "FMSTREAM",
            url: URL(string: "https://fmstream.org/")!,
            isHomepage: false
        ),
        InternetRadioBrowserFavorite(
            title: "Radio Browser",
            url: URL(string: "https://www.radio-browser.info/")!,
            isHomepage: false
        )
    ]
}

enum InternetRadioBrowserAddress {
    static let defaultHomepage = InternetRadioBrowserFavorite.defaults[0].url

    /// 주소창 입력은 HTTPS 주소와 일반 검색어를 모두 받는다.
    static func browsingURL(from rawInput: String) throws -> URL {
        let input = try validatedInput(from: rawInput)

        if URLComponents(string: input)?.scheme?.isEmpty == false {
            return try secureURL(from: input)
        }

        let looksLikeWebAddress = !input.contains(where: \.isWhitespace)
            && input.contains(".")
        if looksLikeWebAddress {
            return try secureURL(from: input)
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: input)]
        guard let searchURL = components?.url,
              isSecureWebURL(searchURL)
        else { throw InternetRadioBrowserAddressError.unsupportedAddress }
        return searchURL
    }

    static func secureURL(from rawInput: String) throws -> URL {
        let input = try validatedInput(from: rawInput)

        let url: URL
        if let explicitScheme = URLComponents(string: input)?.scheme,
           !explicitScheme.isEmpty {
            guard let explicitURL = URL(string: input) else {
                throw InternetRadioBrowserAddressError.unsupportedAddress
            }
            url = explicitURL
        } else {
            guard let secureURL = URL(string: "https://\(input)") else {
                throw InternetRadioBrowserAddressError.unsupportedAddress
            }
            url = secureURL
        }

        guard isSecureWebURL(url) else {
            throw InternetRadioBrowserAddressError.unsupportedAddress
        }
        return url
    }

    private static func validatedInput(from rawInput: String) throws -> String {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw InternetRadioBrowserAddressError.emptyInput }
        guard input.count <= InternetRadioConfiguration.maximumAddressLength else {
            throw InternetRadioBrowserAddressError.addressTooLong
        }
        return input
    }

    static func isSecureWebURL(_ url: URL) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil
            && components.password == nil
    }
}

private enum InternetRadioBrowserAddressError: LocalizedError {
    case emptyInput
    case addressTooLong
    case unsupportedAddress

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "웹 주소를 입력해 주세요."
        case .addressTooLong:
            "주소가 너무 깁니다."
        case .unsupportedAddress:
            "아이디·비밀번호가 없는 https:// 주소만 열 수 있습니다."
        }
    }
}
