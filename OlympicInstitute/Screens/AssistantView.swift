import SwiftUI

private func greeting() -> ChatMessage {
    ChatMessage(
        fromUser: false,
        text: L.t(
            "أهلاً بيك في المعهد الأوليمبي الدولي لعلوم الرياضة 👋 اسألني عن الدورات وأسعارها ومدتها، أو التسجيل والشهادات، أو اختار من تحت.",
            "Welcome to the International Olympic Institute for Sports Sciences 👋 Ask me about courses, prices, duration, enrolment or certificates — or pick a topic below."
        ),
        chips: [
            ("courses", L.t("الدورات والأسعار", "Courses & prices")),
            ("mode", L.t("أونلاين ولا حضوري؟", "Online or onsite?")),
            ("certificate", L.t("الشهادات والتحقق", "Certificates")),
            ("register", L.t("التسجيل والدفع", "Enrolment & payment")),
            ("contact", L.t("العنوان والتواصل", "Address & contact")),
            ("refund", L.t("سياسة الاسترداد", "Refund policy")),
            ("partnership", L.t("شراكات للأندية", "Club partnerships")),
        ].map { ChatChip(label: $0.1, intent: $0.0, q: "") }
    )
}

/// One direction for the whole message from its first strong letter, as the site's dir="auto" does.
private func isRightToLeft(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) { return true }
        if scalar.properties.isAlphabetic { return false }
    }
    return L.lang == .ar
}

/// The website's chat widget, natively: brand header, bubbles, course cards, link buttons, topic chips.
struct AssistantView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var input = ""
    @State private var typing = false

    private var userBubble: Color { p.isDark ? Color(hex: 0x0A5AB4) : Brand.navy }
    private var botBubble: Color { p.isDark ? Color(hex: 0x0C2C4E) : Color(hex: 0xF8FBFE) }
    private var brand: LinearGradient {
        LinearGradient(colors: [Brand.navy, p.isDark ? Color(hex: 0x0A5AB4) : Brand.navyLit], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            // .oi-chat__head
            HStack(spacing: 12) {
                Image("Logo").resizable().scaledToFit().padding(3).frame(width: 42, height: 42).background(Circle().fill(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t("مساعد المعهد", "Institute assistant")).font(AppFont.head(17)).foregroundStyle(.white)
                    Text(L.t("بيرد فوراً من بيانات موقع المعهد", "Answers instantly from the institute's website")).font(AppFont.body(13)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button { model.chat = [greeting()] } label: { Image(systemName: "arrow.counterclockwise").foregroundStyle(.white) }
                    .accessibilityLabel(L.t("ابدأ من جديد", "Start over"))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(brand.ignoresSafeArea(edges: .top))

            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.chat) { m in bubble(m).id(m.id) }
                        if typing { typingDots.id("typing") }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 16)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                // Like the site: a new answer opens at its first line.
                .onChange(of: model.chat.count) { _ in
                    if let last = model.chat.last { withAnimation { reader.scrollTo(last.id, anchor: .top) } }
                }
                .onChange(of: typing) { t in if t { withAnimation { reader.scrollTo("typing", anchor: .bottom) } } }
            }

            let chips = (!typing && model.chat.last?.fromUser == false) ? model.chat.last?.chips ?? [] : []
            if !chips.isEmpty {
                VStack(spacing: 0) {
                    Rectangle().fill(p.line).frame(height: 1)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(chips, id: \.self) { chip in
                                Button {
                                    ask(chip.q.isEmpty ? (chip.intent.isEmpty ? chip.label : "") : chip.q, intent: chip.intent, shown: chip.label)
                                } label: {
                                    Text(chip.label).font(AppFont.head(13)).foregroundStyle(p.isDark ? p.cyanText : Brand.navy)
                                        .padding(.horizontal, 14).frame(minHeight: 34)
                                        .background(Capsule().fill(p.elevated))
                                        .overlay(Capsule().stroke(p.isDark ? p.cyanText : Brand.navy, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
            }

            // .oi-chat__form
            VStack(spacing: 4) {
                Rectangle().fill(p.line).frame(height: 1)
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(L.t("اكتب سؤالك…", "Type your question…"), text: $input, axis: .vertical)
                        .lineLimit(1...5)
                        .font(AppFont.body(16))
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(p.page))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.line, lineWidth: 1))
                    Button(action: send) {
                        Image(systemName: "paperplane.fill").font(.system(size: 18)).foregroundStyle(.white)
                            .scaleEffect(x: L.lang == .ar ? -1 : 1, y: 1)
                            .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12).fill(brand))
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || typing)
                    .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || typing ? 0.55 : 1)
                    .accessibilityLabel(L.t("إرسال", "Send"))
                }
                .padding(.horizontal, 12).padding(.top, 10)
                .frame(maxWidth: 760)
                Text(L.t("الأسئلة بتتسجل من غير اسمك أو رقمك عشان نحسّن الردود.", "Questions are logged without your name or number to improve answers."))
                    .font(AppFont.body(11)).foregroundStyle(p.muted)
                    .padding(.horizontal, 14).padding(.bottom, 8)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(p.elevated)
        }
        .background(p.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if model.chat.isEmpty { model.chat = [greeting()] } }
        .task { if model.knownCourses.isEmpty { _ = try? await model.courses() } }
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        ask(q, intent: "", shown: q)
    }

    private func ask(_ question: String, intent: String, shown: String) {
        guard !typing, !(question.isEmpty && intent.isEmpty) else { return }
        // The turns before this one, as the website sends them (up to eight).
        let history = model.chat.suffix(8).map { ($0.fromUser ? "user" : "assistant", $0.text) }
        model.chat.append(ChatMessage(fromUser: true, text: shown))
        typing = true
        Task {
            do {
                model.chat.append(try await model.site.ask(question, intent: intent, history: history, lang: L.lang))
            } catch {
                model.chat.append(ChatMessage(
                    fromUser: false,
                    text: L.t("حصلت مشكلة. جرّب تاني، أو كلّمنا على واتساب.", "Something went wrong. Try again, or message us on WhatsApp."),
                    links: [ChatLink(label: L.t("واتساب", "WhatsApp"), url: Contact.whatsapp("").absoluteString, kind: "whatsapp")]
                ))
            }
            typing = false
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        let rtl = isRightToLeft(m.text)
        VStack(alignment: m.fromUser ? .trailing : .leading, spacing: 8) {
            Text(linkified(m.text, m.fromUser))
                .font(AppFont.body(14.5))
                .lineSpacing(4)
                .foregroundStyle(m.fromUser ? .white : p.text)
                .multilineTextAlignment(rtl ? .trailing : .leading)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                .environment(\.openURL, OpenURLAction { url in
                    router.site(url.absoluteString, label: url.absoluteString)
                    return .handled
                })
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(
                    UnevenCorners(sharpLeading: !m.fromUser, sharpTrailing: m.fromUser)
                        .fill(m.fromUser ? userBubble : botBubble)
                        .flipsForRightToLeftLayoutDirection(true)
                )
                .overlay(
                    UnevenCorners(sharpLeading: !m.fromUser, sharpTrailing: m.fromUser)
                        .stroke(m.fromUser ? Color.clear : p.line, lineWidth: 1)
                        .flipsForRightToLeftLayoutDirection(true)
                )
            ForEach(m.cards, id: \.self) { card in
                VStack(alignment: .leading, spacing: 3) {
                    Button(card.title) { router.site(card.url, label: card.title) }.font(AppFont.head(14, .heavy)).foregroundStyle(p.text).buttonStyle(.plain)
                    if !card.price.isEmpty { Text(card.price).font(AppFont.head(13.5)).foregroundStyle(p.cyanText) }
                    if !card.meta.isEmpty { Text(card.meta).font(AppFont.body(12.5)).foregroundStyle(p.muted) }
                    HStack(spacing: 6) {
                        chatButton(L.t("التفاصيل", "Details"), kind: "") { router.site(card.url, label: card.title) }
                        if !card.buy.isEmpty { chatButton(L.t("سجّل", "Enrol"), kind: "primary") { router.site(card.buy, label: card.title) } }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(p.elevated))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.line, lineWidth: 1))
            }
            if !m.links.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(m.links, id: \.self) { l in chatButton(l.label, kind: l.kind) { router.site(l.url, label: l.label) } }
                }
            }
        }
        .frame(maxWidth: 560, alignment: m.fromUser ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: m.fromUser ? .trailing : .leading)
    }

    /// Bot text with its web addresses made tappable, as the site's linkify does.
    private func linkified(_ text: String, _ fromUser: Bool) -> AttributedString {
        var out = AttributedString(text)
        guard !fromUser, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let r = Range(match.range, in: text), let ar = Range(r, in: out) else { continue }
            out[ar].link = url
            out[ar].foregroundColor = p.cyanText
            out[ar].underlineStyle = .single
        }
        return out
    }

    /// .oi-chat__btn and its primary / WhatsApp variants.
    private func chatButton(_ label: String, kind: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if kind == "whatsapp" { Image("WhatsApp").renderingMode(.template).resizable().frame(width: 15, height: 15) }
                Text(label).font(AppFont.head(13))
            }
            .foregroundStyle(kind == "whatsapp" ? (p.isDark ? Brand.darkPage : .white) : kind == "primary" ? .white : p.text)
            .padding(.horizontal, 14).frame(minHeight: 34)
            .background(
                Capsule().fill(kind == "whatsapp" ? AnyShapeStyle(Brand.whatsapp) : kind == "primary" ? AnyShapeStyle(brand) : AnyShapeStyle(p.elevated))
            )
            .overlay(Capsule().stroke(kind.isEmpty ? p.line : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// .oi-chat__typing: three pulsing dots in a bot bubble.
    private var typingDots: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(p.muted).frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * abs(sin(t * 3 + Double(i) * 0.5)))
                }
            }
            .padding(14)
            .background(UnevenCorners(sharpLeading: true, sharpTrailing: false).fill(botBubble).flipsForRightToLeftLayoutDirection(true))
            .overlay(UnevenCorners(sharpLeading: true, sharpTrailing: false).stroke(p.line, lineWidth: 1).flipsForRightToLeftLayoutDirection(true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A bubble with a 4pt corner at the top on the speaker's side and 14pt elsewhere, like the site's.
struct UnevenCorners: Shape {
    let sharpLeading: Bool
    let sharpTrailing: Bool

    func path(in rect: CGRect) -> Path {
        // Drawn left-to-right; callers flip it for right-to-left layouts so the sharp corner stays on the speaker's side.
        let big: CGFloat = 14, small: CGFloat = 4
        let tl = sharpLeading ? small : big, tr = sharpTrailing ? small : big
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - big))
        path.addArc(center: CGPoint(x: rect.maxX - big, y: rect.maxY - big), radius: big, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + big, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + big, y: rect.maxY - big), radius: big, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
