import Foundation
import Security

/// A failed call. `code` is the WordPress error code (oi_app_*, rest_no_route, …) or "network".
struct ApiError: LocalizedError {
    let code: String
    let message: String
    let status: Int
    var fields: [String: String] = [:]

    var errorDescription: String? { message }

    /// A sentence the student can act on. Server messages (already Arabic) pass through.
    var friendly: String {
        switch code {
        case "network": return L.t("مفيش اتصال بالإنترنت، أو الموقع مش بيرد.", "No connection, or the site is not responding.")
        case "rest_no_route": return L.t("خدمة التطبيق مش متفعّلة على الموقع لسه.", "The app service is not active on the website yet.")
        default:
            if code.hasPrefix("http_") { return L.t("الموقع رجّع خطأ (\(status)). حاول بعد شوية.", "The site returned an error (\(status)).") }
            return message
        }
    }

    static func describe(_ error: Error) -> String {
        (error as? ApiError)?.friendly ?? L.t("حصلت مشكلة غير متوقعة. حاول تاني.", "Something went wrong. Please try again.")
    }
}

/// The app token lives in the Keychain, never in plain preferences.
enum Keychain {
    private static let service = "com.olympicinstitute.app"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// The signed-in student. `changes` ticks whenever enrollment or progress may have changed.
@MainActor
final class Session: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var changes = 0

    nonisolated var token: String? { Keychain.get("token") }

    init() {
        if Keychain.get("token") != nil, let data = UserDefaults.standard.data(forKey: "user") {
            user = try? JSONDecoder().decode(User.self, from: data)
        }
    }

    func signIn(token: String, user: User) {
        Keychain.set("token", token)
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: "user")
        self.user = user
        changed()
    }

    func signOut() {
        Keychain.set("token", nil)
        UserDefaults.standard.removeObject(forKey: "user")
        if user != nil {
            user = nil
            changed()
        }
    }

    func changed() { changes += 1 }
}

struct HTTP {
    let siteURL: String
    let session: Session

    /// The plugin hides the site's header and footer for pages opened with this marker in the user agent.
    static let appMarker = "OlympicApp/"
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS like Mac OS X) \(appMarker)\(version)"
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func get(_ url: String, auth: Bool = true) async throws -> Data {
        try await send(url, auth: auth) { _ in }
    }

    func postJSON(_ url: String, _ body: [String: Any] = [:], auth: Bool = true) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(url, auth: auth) { r in
            r.httpMethod = "POST"
            r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = data
        }
    }

    func postForm(_ url: String, _ form: [String: String]) async throws -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
        return try await send(url, auth: false) { r in
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data(body.utf8)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw ApiError(code: "bad_reply", message: L.t("رد غير متوقع من الموقع.", "Unexpected reply from the site."), status: 0)
        }
    }

    private func send(_ url: String, auth: Bool, configure: (inout URLRequest) -> Void) async throws -> Data {
        let token = auth ? session.token : nil
        do {
            return try await execute(url, token: token, configure: configure)
        } catch let e as ApiError where token != nil && e.code == "oi_app_token_invalid" {
            // The site no longer knows this token (signed out elsewhere, expired): drop it and carry on as a guest.
            await session.signOut()
            return try await execute(url, token: nil, configure: configure)
        }
    }

    private func execute(_ url: String, token: String?, configure: (inout URLRequest) -> Void) async throws -> Data {
        guard let u = URL(string: url) else { throw ApiError(code: "bad_url", message: url, status: 0) }
        var r = URLRequest(url: u, timeoutInterval: 40)
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json, text/html;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        if let token {
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // Some hosts strip Authorization before PHP; the plugin reads this one too.
            r.setValue(token, forHTTPHeaderField: "X-OI-App-Token")
        }
        configure(&r)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: r)
        } catch {
            throw ApiError(code: "network", message: error.localizedDescription, status: 0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        throw Self.error(status: status, body: data)
    }

    static func error(status: Int, body: Data) -> ApiError {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return ApiError(code: "http_\(status)", message: "HTTP \(status)", status: status)
        }
        let data = json["data"] as? [String: Any]
        let fields = (data?["fields"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        let message = (json["message"] as? String).map(stripTags) ?? "HTTP \(status)"
        return ApiError(code: json["code"] as? String ?? "http_\(status)", message: message, status: status, fields: fields)
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
