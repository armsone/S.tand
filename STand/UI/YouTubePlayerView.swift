import SwiftUI
import WebKit

struct YouTubePlayerView: View {
    let configuration: YouTubeConfiguration
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer(minLength: 18)

                    YouTubeWebPlayer(embedURL: configuration.embedURL)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(minWidth: 200, minHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }

                    VStack(spacing: 5) {
                        Text(configuration.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("공식 YouTube 플레이어에서 직접 재생합니다")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                    }

                    if let originalURL = configuration.originalURL {
                        Link(destination: originalURL) {
                            Label("YouTube에서 열기", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(accent.opacity(0.16), in: Capsule())
                        }
                        .foregroundStyle(accent)
                    }

                    Link(
                        "Google 개인정보처리방침",
                        destination: URL(string: "https://policies.google.com/privacy")!
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent.opacity(0.82))

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 18)
            }
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { dismiss() }
        }
    }
}

private struct YouTubeWebPlayer: UIViewRepresentable {
    let embedURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        loadPlayer(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedEmbedURL != embedURL else { return }
        loadPlayer(in: webView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    private func loadPlayer(in webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedEmbedURL = embedURL
        var request = URLRequest(url: embedURL)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedEmbedURL: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "https",
               let host = url.host?.lowercased(),
               host == "youtube.com" || host.hasSuffix(".youtube.com")
                    || host == "google.com" || host.hasSuffix(".google.com") {
                decisionHandler(.allow)
            } else if url.scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
