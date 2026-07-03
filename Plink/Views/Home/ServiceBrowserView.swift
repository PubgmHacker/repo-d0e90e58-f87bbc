import SwiftUI
import WebKit

// MARK: - ServiceBrowserView
/// 🔧 NEW: Full-screen WebView for browsing a service's content.
///
/// Flow: User selects a service (e.g. Кинопоиск) → this screen opens with
/// the service's catalog page loaded in a WebView. User browses/searches for
/// a movie or video. When they find something to watch together, they tap
/// "Создать комнату" → opens RoomSetupView with the current URL pre-filled.
///
/// No manual URL entry — the user picks content naturally from the service's
/// own UI, then we capture the URL they landed on.
struct ServiceBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let service: VideoService
    /// Called when user taps "Создать комнату" — passes the current page URL.
    var onCreateRoom: (String) -> Void

    @State private var currentURL: URL?
    @State private var pageTitle: String = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var showCreateConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.raveBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // WebView
                    ServiceWebView(
                        initialURL: URL(string: service.browseURL)!,
                        currentURL: $currentURL,
                        pageTitle: $pageTitle,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward
                    )
                    .ignoresSafeArea(.all, edges: .bottom)

                    // Bottom bar with "Create Room" CTA
                    bottomBar
                }
            }
            .navigationTitle(service.brandName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.bioCyan)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        // Go back in WebView history
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14))
                            .foregroundColor(canGoBack ? .bioCyan : .raveTextTertiary)
                    }
                    .disabled(!canGoBack)

                    Button {
                        // Go forward in WebView history
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(canGoForward ? .bioCyan : .raveTextTertiary)
                    }
                    .disabled(!canGoForward)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("Создать комнату?", isPresented: $showCreateConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Создать") {
                    if let url = currentURL {
                        onCreateRoom(url.absoluteString)
                    }
                }
            } message: {
                if !pageTitle.isEmpty {
                    Text("Вы смотрите: \(pageTitle)\n\nСоздать комнату для совместного просмотра этого контента?")
                } else {
                    Text("Создать комнату для совместного просмотра этого контента?")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Current page info
            VStack(alignment: .leading, spacing: 2) {
                Text(pageTitle.isEmpty ? "Выберите контент" : pageTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)
                if let url = currentURL {
                    Text(url.host ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.raveTextTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Create Room button
            Button {
                HapticManager.impact(.medium)
                showCreateConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Создать комнату")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.raveGradient)
                .clipShape(Capsule())
                .shadow(color: .ravePrimary.opacity(0.4), radius: 8, y: 3)
            }
            .disabled(currentURL == nil)
            .opacity(currentURL == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - ServiceWebView (WKWebView wrapper)

struct ServiceWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURL: URL?
    @Binding var pageTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = WKWebsiteDataStore.default()  // persist login

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: initialURL))

        // Dark mode for web content
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Color.raveBackground)
        webView.scrollView.backgroundColor = UIColor(Color.raveBackground)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update navigation state bindings
        DispatchQueue.main.async {
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: ServiceWebView

        init(parent: ServiceWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Could show a loading indicator here
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.currentURL = webView.url
                self.parent.pageTitle = webView.title ?? ""
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }

            // Inject CSS for dark background (helps with services that don't have dark mode)
            let darkCSS = """
            :root { color-scheme: dark; }
            body { background-color: #0A0D14 !important; }
            """
            let js = """
            var style = document.createElement('style');
            style.textContent = '\(darkCSS)';
            document.head.appendChild(style);
            """
            webView.evaluateJavaScript(js)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.pageTitle = "Ошибка загрузки"
            }
        }

        // Open links in the same WebView (not external browser)
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
