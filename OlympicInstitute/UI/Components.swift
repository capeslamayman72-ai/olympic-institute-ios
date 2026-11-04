import SwiftUI

/* ---------- formatting ---------- */

enum Format {
    static func amount(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? (NumberFormatter.grouped.string(from: NSNumber(value: Int(v))) ?? "\(Int(v))")
            : String(format: "%.2f", locale: Locale(identifier: "en_US"), v)
    }

    static func money(_ v: Double, _ currency: String?) -> String {
        let unit: String
        switch currency {
        case nil, "EGP": unit = L.t("ج.م", "EGP")
        case "USD": unit = "$"
        default: unit = currency ?? ""
        }
        return "\(amount(v)) \(unit)"
    }

    static func hours(_ d: Duration?) -> String {
        let h = d?.hours ?? 0, m = d?.minutes ?? 0
        if h > 0 && m > 0 { return L.t("\(h) س \(m) د", "\(h)h \(m)m") }
        if h > 0 { return L.t("\(h) ساعة", "\(h) hours") }
        if m > 0 { return L.t("\(m) دقيقة", "\(m) min") }
        return ""
    }

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Rating as the site prints it: one decimal, rounded half-up ("4.85" shows as 4.9).
    static func rating(_ v: Double) -> String {
        let n = NSDecimalNumber(value: v).rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 1, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
        ))
        let s = n.stringValue
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

/* ---------- loading ---------- */

enum Loadable<T> {
    case loading, ready(T), failed(Error)

    var value: T? { if case .ready(let v) = self { return v } else { return nil } }
}

private struct LoadKey: Equatable {
    let key: AnyHashable
    let attempt: Int
}

/// Runs `load` when shown and whenever `key` changes; a reload keeps showing the previous result.
struct Loader<T, Content: View>: View {
    let key: AnyHashable
    let load: () async throws -> T
    @ViewBuilder let content: (T, _ reload: @escaping () -> Void) -> Content
    @State private var state: Loadable<T> = .loading
    @State private var attempt = 0

    var body: some View {
        Group {
            switch state {
            case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error): ErrorView(error: error) { attempt += 1 }
            case .ready(let value): content(value) { attempt += 1 }
            }
        }
        .task(id: LoadKey(key: key, attempt: attempt)) {
            if state.value == nil { state = .loading }
            do {
                state = .ready(try await load())
            } catch is CancellationError {
            } catch {
                if state.value == nil { state = .failed(error) }
            }
        }
    }
}

struct ErrorView: View {
    let error: Error
    let retry: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash").font(.system(size: 44)).foregroundStyle(p.muted)
            Text(ApiError.describe(error)).font(AppFont.body(16)).multilineTextAlignment(.center).foregroundStyle(p.text)
            Button(L.t("حاول تاني", "Try again"), action: retry).buttonStyle(PrimaryStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView<Action: View>: View {
    let icon: String
    let text: String
    @ViewBuilder var action: () -> Action
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(p.cyanText)
            Text(text).font(AppFont.body(16)).multilineTextAlignment(.center).foregroundStyle(p.text)
            action()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/* ---------- images ---------- */

struct RemoteImage: View {
    let url: String?
    var mode: ContentMode = .fill
    @Environment(\.palette) private var p

    var body: some View {
        // The plain fill sets the size; the photo is drawn over it, so a filling photo can never widen the layout.
        p.glass
            .overlay {
                if let url, let u = URL(string: url) {
                    AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: mode)
                        }
                    }
                }
            }
            .clipped()
    }
}

/* ---------- the site's building blocks ---------- */

/// .card: card surface, 1pt border, the theme's large radius.
struct SiteCardModifier: ViewModifier {
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        content
            .background(p.card)
            .clipShape(RoundedRectangle(cornerRadius: p.radiusLg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: p.radiusLg, style: .continuous).stroke(p.line, lineWidth: 1))
    }
}

extension View {
    func siteCard() -> some View { modifier(SiteCardModifier()) }

    /// Content at a readable width on iPad, centred like the site's .container.
    func centered(_ max: CGFloat = 1180) -> some View {
        frame(maxWidth: max).frame(maxWidth: .infinity)
    }

    func navBar(_ title: String) -> some View { modifier(NavBar(title: title)) }
}

struct NavBar: ViewModifier {
    let title: String
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // Back is just the arrow, so no system "Back" in English shows on an Arabic screen.
            .toolbarRole(.editor)
            .toolbarBackground(p.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(p.page.ignoresSafeArea())
    }
}

/// .eyebrow: a short cyan rule followed by the label.
struct Eyebrow: View {
    let text: String
    @Environment(\.palette) private var p

    var body: some View {
        if !text.isEmpty {
            HStack(spacing: 10) {
                Rectangle().fill(p.cyanText).frame(width: 22, height: 2)
                Text(text).font(AppFont.head(13)).foregroundStyle(p.cyanText)
            }
        }
    }
}

/// A heading with its accent-coloured words.
struct AccentText: View {
    let parts: [HeadingPart]
    var size: CGFloat = 27
    var color: Color?
    @Environment(\.palette) private var p

    var body: some View {
        var out = AttributedString()
        for (i, part) in parts.enumerated() {
            var piece = AttributedString((i > 0 ? " " : "") + part.text)
            switch part.accent {
            case 1: piece.foregroundColor = p.cyanText
            case 2: piece.foregroundColor = p.turqText
            default: piece.foregroundColor = color ?? p.text
            }
            out += piece
        }
        return Text(out).font(AppFont.head(size)).lineSpacing(2)
    }
}

/// .section-head: eyebrow, heading with its accent word, intro paragraph and an optional "link ←".
struct SectionHead: View {
    let heading: Heading
    var action: String?
    var onAction: (() -> Void)?
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: heading.eyebrow)
            if !heading.parts.isEmpty { AccentText(parts: heading.parts) }
            if !heading.intro.isEmpty {
                Text(heading.intro).font(AppFont.body(16)).foregroundStyle(p.muted).lineSpacing(5)
            }
            if let action, let onAction { LinkArrow(text: action, action: onAction) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// .link-arrow: cyan bold text with a forward arrow (points left in Arabic).
struct LinkArrow: View {
    let text: String
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text).font(AppFont.head(14))
                Image(systemName: "arrow.forward").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(p.cyanText)
        }
        .buttonStyle(.plain)
    }
}

enum PillTone { case plain, accent, turq, sale }

/// .pill and its accent / turquoise / sale variants.
struct Pill: View {
    let text: String
    var tone: PillTone = .plain
    var icon: String?
    @Environment(\.palette) private var p

    var body: some View {
        let (fg, bg, border): (Color, Color, Color) = {
            switch tone {
            case .plain: return (p.textSoft, p.glass, p.line)
            case .accent: return (p.cyanText, Brand.cyan.opacity(0.10), Brand.cyan.opacity(0.45))
            case .turq: return (p.turqText, Brand.turquoise.opacity(0.10), Brand.turquoise.opacity(0.42))
            case .sale: return (p.sale, p.sale.opacity(0.16), .clear)
            }
        }()
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
            Text(text).font(AppFont.head(13, .semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Capsule().fill(bg))
        .overlay(Capsule().stroke(border, lineWidth: 1))
    }
}

/// .btn--primary: cyan on dark, navy gradient on light.
struct PrimaryStyle: ButtonStyle {
    var full = false
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.head(15))
            .foregroundStyle(p.buttonText)
            .padding(.horizontal, 24)
            .frame(minHeight: 52)
            .frame(maxWidth: full ? .infinity : nil)
            .background(Capsule().fill(p.buttonFill))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
    }
}

/// .btn--ghost: glass fill with a strong border.
struct GhostStyle: ButtonStyle {
    var full = false
    @Environment(\.palette) private var p

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.head(15))
            .foregroundStyle(p.text)
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .frame(maxWidth: full ? .infinity : nil)
            .background(Capsule().fill(p.glass))
            .overlay(Capsule().stroke(p.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// .btn--wa: the turquoise "ask on WhatsApp" button.
struct WhatsAppStyle: ButtonStyle {
    var full = false
    @Environment(\.palette) private var p

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.head(15))
            .foregroundStyle(p.turqText)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .frame(maxWidth: full ? .infinity : nil)
            .background(Capsule().fill(Brand.turquoise.opacity(0.11)))
            .overlay(Capsule().stroke(Brand.turquoise.opacity(0.45), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// .stars: five turquoise stars, the value in cyan and the count.
struct Stars: View {
    let rating: Rating?
    @Environment(\.palette) private var p

    var body: some View {
        if let r = rating, r.count > 0 {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: r.average >= Double(i) + 0.75 ? "star.fill" : r.average >= Double(i) + 0.25 ? "star.leadinghalf.filled" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(p.turqText)
                }
                Text(Format.rating(r.average)).font(AppFont.head(13)).foregroundStyle(p.cyanText).padding(.leading, 4)
                Text("(\(r.count))").font(AppFont.body(13)).foregroundStyle(p.muted)
            }
        } else {
            Text(L.t("لا توجد تقييمات بعد", "No ratings yet")).font(AppFont.body(13)).foregroundStyle(p.muted)
        }
    }
}

struct Meta: View {
    let icon: String
    let text: String
    @Environment(\.palette) private var p

    var body: some View {
        if !text.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(p.cyanText)
                Text(text).font(AppFont.body(13)).foregroundStyle(p.muted)
            }
        }
    }
}

/// .price: the EGP price, the USD price for non-Egyptians, then the old price struck through.
struct PriceBlock: View {
    let price: Price?
    var big = false
    @Environment(\.palette) private var p

    var body: some View {
        if let price, !price.free, let current = price.current {
            FlowLayout(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.amount(current)).font(AppFont.head(big ? 26 : 21)).foregroundStyle(p.cyanText).environment(\.layoutDirection, .leftToRight)
                    Text(price.currency == nil || price.currency == "EGP" ? L.t("ج.م", "EGP") : price.currency!).font(AppFont.body(13)).foregroundStyle(p.muted)
                }
                if let usd = price.intl {
                    HStack(spacing: 6) {
                        Text("$" + Format.amount(usd)).font(AppFont.head(14)).foregroundStyle(p.turqText).environment(\.layoutDirection, .leftToRight)
                        Text(L.t("لغير المصريين", "outside Egypt")).font(AppFont.head(11, .semibold)).foregroundStyle(p.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(Capsule().fill(p.glass))
                    .overlay(Capsule().stroke(p.line, lineWidth: 1))
                }
                if price.onSale, let regular = price.regular {
                    Text(Format.money(regular, price.currency)).font(AppFont.body(14)).strikethrough(color: Color.red.opacity(0.7)).foregroundStyle(p.muted)
                }
            }
        } else {
            Text(L.t("مجاناً", "Free")).font(AppFont.head(big ? 26 : 21)).foregroundStyle(p.turqText)
        }
    }
}

struct ProgressLine: View {
    let percent: Int
    let completed: Bool
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(completed ? L.t("مكتملة ✓", "Completed ✓") : L.t("تقدّمك في الدورة", "Your progress"))
                    .font(AppFont.head(13, .semibold)).foregroundStyle(completed ? p.turqText : p.muted)
                Spacer()
                Text("\(percent)%").font(AppFont.head(14)).foregroundStyle(p.cyanText)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.glass).overlay(Capsule().stroke(p.line, lineWidth: 1))
                    Capsule().fill(completed ? Brand.turquoise : Brand.cyan).frame(width: g.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                }
            }
            .frame(height: 7)
        }
    }
}

/// The site's .course-card: photo with discount and track, title, blurb, hours and rating, then price and "التفاصيل".
struct CourseCard: View {
    let course: Course
    let open: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RemoteImage(url: course.image)
                    LinearGradient(colors: [.clear, Color(hex: 0x04182F, alpha: 0.7)], startPoint: .center, endPoint: .bottom)
                    VStack {
                        HStack {
                            Spacer()
                            if let off = course.price?.discountPercent {
                                Text(L.t("خصم \(off)%", "\(off)% off"))
                                    .font(AppFont.head(12)).foregroundStyle(p.cyanText)
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(Capsule().fill(p.chip))
                                    .overlay(Capsule().stroke(Brand.cyan.opacity(0.5), lineWidth: 1))
                            }
                        }
                        Spacer()
                        HStack(spacing: 7) {
                            if let cat = course.category {
                                Circle().fill(Brand.cyan).frame(width: 6, height: 6)
                                Text(cat.name).font(AppFont.head(13)).foregroundStyle(Color(hex: 0x6FD3F7))
                            }
                            Spacer()
                        }
                    }
                    .padding(14)
                }
                .aspectRatio(16 / 10, contentMode: .fit)

                VStack(alignment: .leading, spacing: 10) {
                    Text(course.title).font(AppFont.head(18)).foregroundStyle(p.text).lineLimit(2).multilineTextAlignment(.leading)
                    if let ex = course.excerpt, !ex.isEmpty {
                        Text(ex).font(AppFont.body(15)).foregroundStyle(p.muted).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 16) {
                        Meta(icon: "clock", text: Format.hours(course.duration))
                        Stars(rating: course.rating)
                    }
                    Rectangle().fill(p.line).frame(height: 1)
                    if course.enrolled, let progress = course.progress {
                        ProgressLine(percent: progress.percent, completed: progress.isCompleted)
                    } else {
                        HStack {
                            PriceBlock(price: course.price)
                            Spacer(minLength: 8)
                            HStack(spacing: 6) {
                                Text(L.t("التفاصيل", "Details")).font(AppFont.head(14))
                                Image(systemName: "arrow.forward").font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(p.cyanText)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .siteCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Lays children out left to right (right to left in Arabic) and wraps, like CSS flex-wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// Opens WhatsApp with a ready message, as the site's "ask about the course" buttons do.
enum Contact {
    static let whatsappNumber = "201277442824"
    static let phone = "+201044495999"
    static let email = "info@olympic-institute.com"
    static let facebook = "https://www.facebook.com/InternationalOlympicInstitute/"
    static let messenger = "https://m.me/InternationalOlympicInstitute"
    static let instagram = "https://www.instagram.com/olympic_institute/"
    static let tiktok = "https://www.tiktok.com/@olympic11111"

    static func whatsapp(_ message: String) -> URL {
        var c = URLComponents(string: "https://api.whatsapp.com/send/")!
        c.queryItems = [URLQueryItem(name: "phone", value: whatsappNumber), URLQueryItem(name: "text", value: message)]
        return c.url!
    }
}
