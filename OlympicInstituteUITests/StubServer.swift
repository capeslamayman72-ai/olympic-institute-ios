import Foundation
import Network

/// A local stand-in for olympic-institute.com built from recorded replies: the plugin's JSON (captured from a
/// local WordPress running the plugin) and saved copies of the theme's pages. Absolute links are rewritten here.
final class StubServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "stub-server")
    private(set) var base = ""
    private let lock = NSLock()
    private var log: [String] = []

    var requests: [String] { lock.lock(); defer { lock.unlock() }; return log }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() {
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            self.receive(conn, Data())
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 10)
        base = "http://localhost:\(listener.port?.rawValue ?? 0)"
    }

    func stop() { listener.cancel() }

    private func receive(_ conn: NWConnection, _ buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let (method, path) = Self.parse(buf) {
                self.lock.lock()
                self.log.append("\(method) \(path)")
                self.lock.unlock()
                let (type, body, status) = self.respond(path)
                let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
            } else if !done && error == nil {
                self.receive(conn, buf)
            } else {
                conn.cancel()
            }
        }
    }

    /// The request line, once headers and the whole body (per Content-Length) have arrived.
    private static func parse(_ data: Data) -> (String, String)? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let length = lines.first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        guard data.count - end.upperBound >= length else { return nil }
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private func fixture(_ name: String) -> Data {
        let parts = name.split(separator: ".")
        guard let url = Bundle(for: StubServer.self).url(forResource: String(parts[0]), withExtension: String(parts[1])),
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }

    private func rewrite(_ data: Data, courseImages: Bool = false) -> Data {
        var s = String(decoding: data, as: UTF8.self)
        let escaped = base.replacingOccurrences(of: "/", with: "\\/")
        s = s.replacingOccurrences(of: "https://olympic-institute.com", with: base)
            .replacingOccurrences(of: "https:\\/\\/olympic-institute.com", with: escaped)
            .replacingOccurrences(of: "http:\\/\\/localhost:8787", with: escaped)
            .replacingOccurrences(of: "http://localhost:8787", with: base)
        // The local test site had no course thumbnails; give course cards a picture.
        if courseImages { s = s.replacingOccurrences(of: "\"image\":null", with: "\"image\":\"\(escaped)\\/img\\/course.png\"") }
        return Data(s.utf8)
    }

    private func respond(_ path: String) -> (String, Data, Int) {
        let api = "/wp-json/oi-app/v1"
        let json = "application/json; charset=utf-8", html = "text/html; charset=utf-8"
        func j(_ name: String, images: Bool = false) -> (String, Data, Int) { (json, rewrite(fixture(name), courseImages: images), 200) }
        func h(_ name: String) -> (String, Data, Int) { (html, rewrite(fixture(name)), 200) }
        func raw(_ s: String) -> (String, Data, Int) { (json, Data(s.utf8), 200) }

        if path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") { return ("image/png", fixture("img.png"), 200) }
        if path.hasPrefix(api + "/courses/") && path.hasSuffix("/enroll") { return j("course.json", images: true) }
        if path.hasPrefix(api + "/courses/") { return j("course.json", images: true) }
        if path.hasPrefix(api + "/courses") { return j("courses.json", images: true) }
        if path.hasPrefix(api + "/categories") { return j("categories.json") }
        if path.hasPrefix(api + "/auth/login") { return j("login.json") }
        if path.hasPrefix(api + "/auth/logout") { return raw(#"{"ok":true}"#) }
        if path.hasPrefix(api + "/auth/web-session") { return raw(#"{"url":"\#(base)/?oi_app_sso=abc"}"#) }
        if path.hasPrefix(api + "/my/courses") { return j("courses.json", images: true) }
        if path.hasPrefix(api + "/lessons/") && path.hasSuffix("/complete") {
            return raw(#"{"progress":{"percent":40,"completed_items":2,"total_items":5,"is_completed":false}}"#)
        }
        if path.hasPrefix(api + "/lessons/") {
            let s = String(decoding: rewrite(fixture("lesson.json")), as: UTF8.self).replacingOccurrences(of: "\"is_completed\":true", with: "\"is_completed\":false")
            return (json, Data(s.utf8), 200)
        }
        if path.hasPrefix(api + "/quizzes/") && path.hasSuffix("/start") { return j("attempt.json") }
        if path.hasPrefix(api + "/quizzes/") { return j("quiz.json") }
        if path.hasPrefix(api + "/quiz-attempts/") { return j("result.json") }
        if path.hasPrefix("/wp-json/oi-chat/v1/ask") { return j("chat.json") }
        if path.hasPrefix("/wp-json/wp/v2/posts") { return j("posts.json") }
        if path.hasPrefix("/wp-admin/admin-ajax.php") {
            return raw(#"{"success":true,"data":{"certificate_number":"OI-2026-0412","name_ar":"أحمد محمود علي","name_en":"Ahmed Mahmoud Ali","specialization":"المعد البدني و مخطط الاحمال","statement":"اجتاز الدورة بتقدير ممتاز."}}"#)
        }
        if path == "/" || path == "/en/" { return h("home.html") }
        let p = path.lowercased()
        if p.contains("%d8%a7%d9%84%d9%85%d8%af%d8%b1%d8%a8%d9%88%d9%86") || p.contains("en-instructors") { return h("instructors.html") }
        if p.contains("%d8%a2%d8%b1%d8%a7%d8%a1") || p.contains("en-testimonials") { return h("testimonials.html") }
        if p.contains("%d8%a3%d9%84%d8%a8%d9%88%d9%85") || p.contains("en-gallery") { return h("gallery.html") }
        if p.contains("%d8%a7%d9%84%d9%85%d9%83%d8%aa%d8%a8%d8%a9") || p.contains("en-library") { return h("library.html") }
        if p.contains("%d8%a7%d9%84%d8%aa%d8%ad%d9%82%d9%82") || p.contains("en-verify") { return h("verify.html") }
        return (json, Data(#"{"code":"rest_no_route","message":"No route","data":{"status":404}}"#.utf8), 404)
    }
}
