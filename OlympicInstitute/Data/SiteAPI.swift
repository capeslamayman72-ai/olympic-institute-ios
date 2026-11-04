import Foundation
import SwiftSoup

/// Pages of the website. Arabic slugs stay percent-encoded exactly as WordPress links them.
enum SitePage {
    case home, instructors, testimonials, gallery, library, verify, about, board, partnership, services, contact, privacy, refund, lostPassword, becomeInstructor

    var paths: (ar: String, en: String) {
        switch self {
        case .home: return ("/", "/en/")
        case .instructors: return ("/%d8%a7%d9%84%d9%85%d8%af%d8%b1%d8%a8%d9%88%d9%86/", "/en-instructors/")
        case .testimonials: return ("/%d8%a2%d8%b1%d8%a7%d8%a1-%d8%a7%d9%84%d8%af%d8%a7%d8%b1%d8%b3%d9%8a%d9%86/", "/en-testimonials/")
        case .gallery: return ("/%d8%a3%d9%84%d8%a8%d9%88%d9%85-%d8%a7%d9%84%d8%b5%d9%88%d8%b1/", "/en-gallery/")
        case .library: return ("/%d8%a7%d9%84%d9%85%d9%83%d8%aa%d8%a8%d8%a9/", "/en-library/")
        case .verify: return ("/%d8%a7%d9%84%d8%aa%d8%ad%d9%82%d9%82-%d9%85%d9%86-%d8%a7%d9%84%d8%b4%d9%87%d8%a7%d8%af%d8%a7%d8%aa-2/", "/en-verify/")
        case .about: return ("/%d9%85%d9%86-%d9%86%d8%ad%d9%86/", "/en-about/")
        case .board: return ("/%d9%85%d8%ac%d9%84%d8%b3-%d8%a7%d9%84%d8%a5%d8%af%d8%a7%d8%b1%d8%a9/", "/en-board/")
        case .partnership: return ("/partnership/", "/en-partnership/")
        case .services: return ("/%d8%ae%d8%af%d9%85%d8%a7%d8%aa%d9%86%d8%a7/", "/en-services/")
        case .contact: return ("/%d8%aa%d9%88%d8%a7%d8%b5%d9%84-%d9%85%d8%b9%d9%86%d8%a7/", "/en-contact/")
        case .privacy: return ("/privacy-policy-olympic/", "/privacy-policy-olympic/")
        case .refund: return ("/refund-policy/", "/refund-policy/")
        case .lostPassword: return ("/wp-login.php?action=lostpassword", "/wp-login.php?action=lostpassword")
        case .becomeInstructor: return ("/instructor-registration-2/", "/instructor-registration-2/")
        }
    }

    func path(_ lang: Lang) -> String { lang == .ar ? paths.ar : paths.en }
}

/// Public website content: the theme's hand-built pages, articles, certificate check and the assistant.
struct SiteAPI {
    let http: HTTP

    func url(_ page: SitePage, _ lang: Lang = L.lang) -> String { http.siteURL + page.path(lang) }

    private func page(_ page: SitePage, _ lang: Lang) async throws -> Document {
        let address = url(page, lang)
        let data = try await http.get(address, auth: false)
        return try SwiftSoup.parse(String(decoding: data, as: UTF8.self), address)
    }

    func home(_ lang: Lang) async throws -> [HomeSection] { Parse.home(try await page(.home, lang)) }
    func instructors(_ lang: Lang) async throws -> [StaffMember] { Parse.instructors(try await page(.instructors, lang)) }
    func testimonials(_ lang: Lang) async throws -> [Review] { Parse.reviews(try await page(.testimonials, lang)) }
    func gallery(_ lang: Lang) async throws -> [GalleryPhoto] { Parse.gallery(try await page(.gallery, lang)) }
    func library(_ lang: Lang) async throws -> [Book] { Parse.library(try await page(.library, lang)) }

    func posts() async throws -> [Post] {
        Parse.posts(try await http.get(http.siteURL + "/wp-json/wp/v2/posts?per_page=30&_embed=wp:featuredmedia", auth: false))
    }

    /// Same two steps as the website's form: read the form's nonce, then ask admin-ajax.
    func verifyCertificate(_ number: String, _ lang: Lang) async throws -> CertificateCheck {
        let html = String(decoding: try await http.get(url(.verify, lang), auth: false), as: UTF8.self)
        guard let nonce = Parse.certificateNonce(html) else {
            throw ApiError(code: "certificate_form", message: L.t("صفحة التحقق مش متاحة دلوقتي.", "The verification page is unavailable."), status: 0)
        }
        let body = try await http.postForm(http.siteURL + "/wp-admin/admin-ajax.php", [
            "action": "verify_certificate", "certificate_number": number.trimmingCharacters(in: .whitespaces), "nonce": nonce,
        ])
        return Parse.certificate(body)
    }

    /// The website's assistant ("مساعد المعهد"); `history` is the last turns as (role, text).
    func ask(_ question: String, intent: String, history: [(String, String)], lang: Lang) async throws -> ChatMessage {
        let data = try await http.postJSON(http.siteURL + "/wp-json/oi-chat/v1/ask", [
            "q": question,
            "intent": intent,
            "lang": lang.rawValue,
            "history": history.map { ["role": $0.0, "text": $0.1] },
            "page_url": http.siteURL + "/?source=ios-app",
            "page_title": "iOS app",
            "course_id": 0,
            "hp": "",
        ], auth: false)
        return Parse.chat(data)
    }
}

/* ---------- parsing (static so tests can feed saved pages and recorded replies) ---------- */

extension Element {
    func first(_ css: String) -> Element? { try? select(css).first() }
    func all(_ css: String) -> [Element] { (try? select(css).array()) ?? [] }
    var plain: String { ((try? text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    func abs(_ key: String) -> String { (try? absUrl(key)) ?? "" }
    func attribute(_ key: String) -> String { (try? attr(key)) ?? "" }

    func link(_ css: String) -> SiteLink? {
        guard let a = first(css) else { return nil }
        let url = a.abs("href")
        return url.isEmpty ? nil : SiteLink(label: a.plain, url: url)
    }
}

enum Parse {
    static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The theme writes counters as data-count="1895" data-suffix="+" and animates the text.
    static func stats(_ root: Element) -> [Stat] {
        root.all(".stat").compactMap { s in
            guard let num = s.first(".stat__num") else { return nil }
            let raw = num.attribute("data-count").isEmpty ? num.plain : num.attribute("data-count")
            let value = Int(raw).map { NumberFormatter.grouped.string(from: NSNumber(value: $0)) ?? raw } ?? raw
            return Stat(value: value + num.attribute("data-suffix"), label: s.first(".stat__label")?.plain ?? "")
        }
    }

    static func instructors(_ root: Element) -> [StaffMember] {
        root.all("article.inst-card").map { c in
            let photo = c.first(".inst-card__photo img")?.abs("src") ?? ""
            return StaffMember(name: c.first(".inst-card__name")?.plain ?? "", role: c.first(".inst-card__role")?.plain ?? "", photo: photo.isEmpty ? nil : photo)
        }.filter { !$0.name.isEmpty }
    }

    static func reviews(_ root: Element) -> [Review] {
        root.all("article.review-card").map { c in
            Review(
                stars: Int(c.first(".stars__val")?.plain ?? "") ?? 5,
                text: c.first("blockquote")?.plain ?? "",
                name: c.first(".review-card__name")?.plain ?? "",
                course: c.first(".review-card__course")?.plain ?? ""
            )
        }.filter { !$0.text.isEmpty }
    }

    static func gallery(_ root: Element) -> [GalleryPhoto] {
        var seen = Set<String>()
        return root.all("[data-lightbox]").compactMap { b in
            let thumb = b.first("img")?.abs("src") ?? ""
            let full = b.abs("data-lightbox").isEmpty ? thumb : b.abs("data-lightbox")
            guard !full.isEmpty, seen.insert(full).inserted else { return nil }
            let caption = b.attribute("data-alt").isEmpty ? (b.first("img")?.attribute("alt") ?? "") : b.attribute("data-alt")
            return GalleryPhoto(full: full, thumb: thumb.isEmpty ? full : thumb, caption: caption)
        }
    }

    /// Every PDF link on the library page, titled by the heading of the block it sits in.
    static func library(_ doc: Document) -> [Book] {
        let main: Element = doc.first("main") ?? (doc.body() ?? doc)
        var seen = Set<String>()
        return main.all("a[href]").compactMap { a in
            let href = a.attribute("href")
            guard href.components(separatedBy: "?")[0].lowercased().hasSuffix(".pdf") else { return nil }
            let url = a.abs("href")
            guard seen.insert(url).inserted else { return nil }
            let parents = (try? a.parents().array()) ?? []
            let up = parents.first
            let box = parents.first { $0.first("h1, h2, h3, h4") != nil && $0.first("img") != nil } ?? up ?? a
            let title = box.first("h2, h3, h4")?.plain ?? ""
            let meta = (box.first(".book__meta")?.plain ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let cover = box.first("img")?.abs("src") ?? ""
            let featured = box.hasClass("book-lead") || box.first(".book-lead") != nil || parents.contains { $0.hasClass("book-lead") }
            return Book(title: title.isEmpty ? a.plain : title, cover: cover.isEmpty ? nil : cover, url: url, meta: meta, featured: featured)
        }
    }

    static func posts(_ data: Data) -> [Post] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.map { o in
            let media = ((o["_embedded"] as? [String: Any])?["wp:featuredmedia"] as? [[String: Any]])?.first
            let sizes = (media?["media_details"] as? [String: Any])?["sizes"] as? [String: Any]
            let image = ((sizes?["medium_large"] as? [String: Any])?["source_url"] as? String)
                ?? ((sizes?["large"] as? [String: Any])?["source_url"] as? String)
                ?? (media?["source_url"] as? String)
            func rendered(_ key: String) -> String { ((o[key] as? [String: Any])?["rendered"] as? String) ?? "" }
            return Post(
                id: o["id"] as? Int ?? 0,
                title: plainText(rendered("title")),
                date: String((o["date"] as? String ?? "").prefix(10)),
                excerpt: plainText(rendered("excerpt")),
                image: image,
                link: o["link"] as? String ?? "",
                contentHtml: rendered("content")
            )
        }
    }

    static func plainText(_ html: String) -> String {
        ((try? SwiftSoup.parse(html).text()) ?? html).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func certificateNonce(_ html: String) -> String? {
        let patterns = [#"cvAjax\s*=\s*\{[^}]*"nonce"\s*:\s*"([A-Za-z0-9]+)""#, #"name="cv_nonce"\s+value="([A-Za-z0-9]+)""#]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html) {
                return String(html[r])
            }
        }
        return nil
    }

    static func certificate(_ data: Data) -> CertificateCheck {
        let o = json(data)
        let d = o["data"] as? [String: Any] ?? [:]
        guard o["success"] as? Bool == true, d["certificate_number"] != nil else {
            return .notFound(d["message"] as? String ?? "")
        }
        func s(_ k: String) -> String { d[k] as? String ?? "" }
        return .found(Certificate(number: s("certificate_number"), nameAr: s("name_ar"), nameEn: s("name_en"), specialization: s("specialization"), statement: s("statement")))
    }

    static func chat(_ data: Data) -> ChatMessage {
        let o = json(data)
        func list(_ k: String) -> [[String: Any]] { o[k] as? [[String: Any]] ?? [] }
        func s(_ d: [String: Any], _ k: String) -> String { d[k] as? String ?? "" }
        return ChatMessage(
            fromUser: false,
            text: o["text"] as? String ?? "",
            links: list("links").map { ChatLink(label: s($0, "label"), url: s($0, "url"), kind: s($0, "kind")) },
            cards: list("cards").map { ChatCard(title: s($0, "title"), url: s($0, "url"), price: s($0, "price"), meta: s($0, "meta"), buy: s($0, "buy")) },
            chips: list("chips").map { ChatChip(label: s($0, "label"), intent: s($0, "intent"), q: s($0, "q")) }
        )
    }

    /* ---------- home page ---------- */

    /// The section's eyebrow, its heading split into plain and accent-coloured words, and the paragraph under it.
    static func heading(_ section: Element) -> Heading {
        let h = section.first("h2, h1")
        var parts: [HeadingPart] = []
        for node in h?.getChildNodes() ?? [] {
            if let t = node as? TextNode {
                let s = t.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { parts.append(HeadingPart(text: s, accent: 0)) }
            } else if let e = node as? Element {
                let s = e.plain
                if !s.isEmpty { parts.append(HeadingPart(text: s, accent: e.hasClass("accent") ? 1 : e.hasClass("accent-2") ? 2 : 0)) }
            }
        }
        var intro = ""
        var next = try? h?.nextElementSibling()
        while let n = next {
            if n.tagName() == "p" { intro = n.plain; break }
            next = try? n.nextElementSibling()
        }
        return Heading(eyebrow: section.first(".eyebrow")?.plain ?? "", parts: parts, intro: intro)
    }

    private static func categoryId(_ url: String) -> Int? {
        guard let r = url.range(of: #"tutor-course-filter-category=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(url[r].split(separator: "=").last ?? "")
    }

    /// Reads the home page section by section, in the order the site shows them. Unknown sections are skipped.
    static func home(_ doc: Document) -> [HomeSection] {
        guard let main = doc.first("main") else { return [] }
        return main.children().array().compactMap { s -> HomeSection? in
            if s.hasClass("hero") {
                let lines = s.all("h1 .line").map(\.plain).joined(separator: " ")
                return .hero(
                    title: lines.isEmpty ? (s.first("h1")?.plain ?? "") : lines,
                    badge: s.first(".hero__seal")?.plain ?? "",
                    sub: s.first(".hero__sub")?.plain ?? "",
                    primary: s.link("a.btn--primary"),
                    secondary: s.link("a.btn--ghost"),
                    pills: s.all(".hero__trust .pill").map(\.plain),
                    images: s.all(".hero__bg img").map { $0.abs("src") }.filter { !$0.isEmpty },
                    emblem: s.first(".hero__emblem img").map { $0.abs("src") }
                )
            }
            if s.hasClass("stats") { return .stats(stats(s)) }
            if s.first(".course-card") != nil {
                let links = s.all(".course-card").compactMap { c -> String? in
                    let u = (c.first(".course-card__media") ?? c.first(".course-card__title a"))?.abs("href") ?? ""
                    return u.isEmpty ? nil : u
                }
                return .courses(heading(s), more: s.link(".section-head a.link-arrow, a.link-arrow"), links: links)
            }
            if s.first(".cat-card") != nil {
                let tracks = s.all("a.cat-card").map { c -> Track in
                    let url = c.abs("href")
                    let image = c.first("img.cat-card__bg")?.abs("src") ?? ""
                    return Track(
                        categoryId: categoryId(url),
                        title: c.first(".cat-card__title")?.plain ?? "",
                        count: c.first(".cat-card__count")?.plain ?? "",
                        blurb: c.first(".cat-card__blurb")?.plain ?? "",
                        image: image.isEmpty ? nil : image,
                        url: url
                    )
                }
                return .tracks(heading(s), tracks)
            }
            if s.first(".feature-card") != nil {
                let items = s.all(".feature-card").map { f -> Feature in
                    let img = f.first("img")?.abs("src") ?? ""
                    return Feature(title: f.first("h3")?.plain ?? "", text: f.first("p")?.plain ?? "", image: img.isEmpty ? nil : img)
                }
                return .features(heading(s), items)
            }
            if s.hasClass("album-band") {
                let photos = s.all(".shot").compactMap { shot -> GalleryPhoto? in
                    guard let img = shot.first("img") else { return nil }
                    let full = shot.first("[data-lightbox]")?.abs("data-lightbox") ?? ""
                    return GalleryPhoto(full: full.isEmpty ? img.abs("src") : full, thumb: img.abs("src"), caption: shot.first(".shot__cap, figcaption")?.plain ?? img.attribute("alt"))
                }
                return .album(title: s.first(".album-band__title, h2")?.plain ?? "", more: s.link("a.album-band__more"), photos: photos)
            }
            if s.first(".library-door") != nil {
                return .library(title: s.first("h2")?.plain ?? "", text: s.first("p")?.plain ?? "", button: s.link("a.btn"))
            }
            if s.first(".inst-card") != nil {
                return .instructors(heading(s), more: s.link(".section-head a.link-arrow, a.link-arrow"), people: instructors(s))
            }
            if s.first(".tst__slide") != nil {
                let items = s.all(".tst__slide").map {
                    Testimonial(text: $0.first(".tst__quote")?.plain ?? "", name: $0.first(".tst__name")?.plain ?? "", role: $0.first(".tst__role")?.plain ?? "")
                }.filter { !$0.text.isEmpty }
                return .testimonials(heading(s), items)
            }
            if s.first(".cta") != nil {
                return .cta(heading(s), primary: s.link("a.btn--primary"), secondary: s.link("a.btn--ghost"))
            }
            return nil
        }
    }
}

extension NumberFormatter {
    /// "1,895" with Western digits, as the site prints its figures.
    static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}
