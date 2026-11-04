import AVKit
import SwiftUI
import WebKit

/// Post HTML shown as native text, in the site's body font and colours.
struct HTMLText: View {
    let html: String
    @Environment(\.palette) private var p
    @State private var text: AttributedString?

    var body: some View {
        Group {
            if let text { Text(text).lineSpacing(5) } else { Color.clear.frame(height: 20) }
        }
        .task(id: html + (p.isDark ? "d" : "l")) { text = render() }
    }

    private func render() -> AttributedString? {
        let color = p.isDark ? "#b8d0e4" : "#2c4a6e"
        let link = p.isDark ? "#6fd3f7" : "#0b6788"
        let dir = L.lang == .ar ? "rtl" : "ltr"
        let page = """
        <style>body{font-family:'Tajawal-Regular';font-size:16px;color:\(color);direction:\(dir);text-align:start}
        a{color:\(link)}h1,h2,h3,h4{font-family:'Cairo-Bold';color:\(link)}img,iframe{display:none}</style>\(html)
        """
        guard let data = page.data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              )
        else { return nil }
        let trimmed = ns.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var out = AttributedString(ns)
        // HTML import leaves trailing paragraph breaks.
        while let last = out.characters.last, last.isNewline { out.characters.removeLast() }
        return out
    }
}

/* ---------- video ---------- */

enum VideoLinks {
    static func youtubeId(_ url: String?) -> String? {
        guard let url else { return nil }
        let pattern = #"(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/|live/|v/))([A-Za-z0-9_-]{11})"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let r = Range(m.range(at: 1), in: url) else { return nil }
        return String(url[r])
    }

    /// vimeo.com/123, vimeo.com/123/abcdef (unlisted hash) or player.vimeo.com/video/123?h=abcdef.
    static func vimeoEmbed(_ url: String?) -> String? {
        guard let url,
              let re = try? NSRegularExpression(pattern: #"vimeo\.com/(?:video/)?(\d+)(?:/([0-9a-f]+))?"#),
              let m = re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let idR = Range(m.range(at: 1), in: url) else { return nil }
        var hash = Range(m.range(at: 2), in: url).map { String(url[$0]) } ?? ""
        if hash.isEmpty, let h = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "h" })?.value { hash = h }
        return "https://player.vimeo.com/video/\(url[idR])" + (hash.isEmpty ? "" : "?h=\(hash)")
    }

    static func playable(_ v: Video) -> Bool {
        switch v.kind {
        case "youtube": return youtubeId(v.url) != nil
        case "vimeo": return vimeoEmbed(v.url) != nil
        case "embed": return !(v.html ?? "").isEmpty
        case "file": return !(v.url ?? "").isEmpty
        default: return false
        }
    }
}

/// Plays a Tutor lesson video: YouTube and Vimeo in their own players, files natively, raw embeds as given.
struct VideoBox: View {
    let video: Video
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch video.kind {
        case "file":
            if let u = video.url.flatMap(URL.init(string:)) { VideoPlayer(player: AVPlayer(url: u)) }
        case "youtube":
            if let id = VideoLinks.youtubeId(video.url) {
                EmbedView(html: Self.frame("https://www.youtube.com/embed/\(id)?playsinline=1&rel=0&modestbranding=1"), base: model.http.siteURL)
            }
        case "vimeo":
            if let src = VideoLinks.vimeoEmbed(video.url) { EmbedView(html: Self.frame(src), base: model.http.siteURL) }
        default:
            if let html = video.html { EmbedView(html: Self.page(html), base: model.http.siteURL) }
        }
    }

    static func frame(_ src: String) -> String {
        page(#"<iframe src="\#(src)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>"#)
    }

    static func page(_ body: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        iframe,video{position:absolute;inset:0;width:100%!important;height:100%!important;border:0}</style>
        </head><body>\(body)</body></html>
        """
    }
}

/// A player page loaded with the site as its base URL, so YouTube/Vimeo see the referrer their embed rules expect.
struct EmbedView: UIViewRepresentable {
    let html: String
    let base: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.loadHTMLString(html, baseURL: URL(string: base + "/"))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

/* ---------- in-app browser ---------- */

/// Hosts that belong in their own apps rather than inside the in-app browser.
private let externalHosts = ["whatsapp.com", "wa.me", "m.me", "facebook.com", "instagram.com", "tiktok.com", "youtube.com", "youtu.be", "t.me"]

struct BrowserView: UIViewRepresentable {
    let url: URL
    @Binding var progress: Double
    @Binding var reload: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        web.customUserAgent = nil
        web.evaluateJavaScript("navigator.userAgent") { ua, _ in
            // Keep the real Safari agent and add the app marker the plugin looks for.
            web.customUserAgent = ((ua as? String) ?? "") + " " + HTTP.appMarker + "1.0"
            web.load(URLRequest(url: url))
        }
        context.coordinator.observe(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastReload != reload {
            context.coordinator.lastReload = reload
            web.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: BrowserView
        var lastReload = 0
        private var token: NSKeyValueObservation?

        init(_ parent: BrowserView) { self.parent = parent }

        func observe(_ web: WKWebView) {
            token = web.observe(\.estimatedProgress) { [weak self] w, _ in
                DispatchQueue.main.async { self?.parent.progress = w.estimatedProgress }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = action.request.url else { return decisionHandler(.allow) }
            let scheme = u.scheme ?? ""
            let host = u.host ?? ""
            let leave = (scheme != "http" && scheme != "https" && scheme != "about")
                || externalHosts.contains { host == $0 || host.hasSuffix("." + $0) }
                || u.path.lowercased().hasSuffix(".pdf")
            if leave {
                UIApplication.shared.open(u)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

/// A website page inside the app: assignments, certificates, information pages.
/// With `signedIn` it opens already logged in through a one-time link from the app API.
struct WebPageView: View {
    let url: String
    let title: String
    let signedIn: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @State private var start: URL?
    @State private var failure: Error?
    @State private var progress = 0.0
    @State private var reload = 0

    var body: some View {
        VStack(spacing: 0) {
            if progress > 0 && progress < 1 { ProgressView(value: progress).tint(Brand.cyan) }
            if let failure {
                ErrorView(error: failure) { self.failure = nil; Task { await prepare() } }
            } else if let start {
                BrowserView(url: start, progress: $progress, reload: $reload)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navBar(title)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { reload += 1 } label: { Image(systemName: "arrow.clockwise") }
                Button { if let u = URL(string: url) { UIApplication.shared.open(u) } } label: { Image(systemName: "safari") }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        do {
            let target = signedIn && model.session.token != nil ? try await model.api.webSession(url) : url
            start = URL(string: target)
        } catch {
            failure = error
        }
    }
}
