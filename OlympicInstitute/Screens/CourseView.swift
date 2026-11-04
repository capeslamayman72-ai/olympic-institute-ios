import SwiftUI

/// The course page in the site's order: header with facts, what you'll learn, overview, curriculum,
/// who it's for, reviews, the buy card, related courses. On wide iPads the buy card sits beside the content.
///
/// The iPhone app takes no payments (App Store rules for digital courses): paid courses show their price and
/// are bought on the institute's website or over WhatsApp, then appear here under «دوراتي».
struct CourseView: View {
    let id: Int
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var message: String?

    var body: some View {
        GeometryReader { geo in
            let width = WidthClass(geo.size.width)
            Loader(key: session.changes, load: { try await model.api.course(id) }) { c, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if width == .wide {
                            HStack(alignment: .top, spacing: 28) {
                                VStack(alignment: .leading, spacing: 0) { CourseHeader(course: c, width: width); CourseBody(course: c, message: $message) }
                                    .frame(maxWidth: .infinity)
                                BuyCard(course: c, message: $message).frame(width: 340).padding(.top, 8)
                            }
                        } else {
                            CourseHeader(course: c, width: width)
                            CourseBody(course: c, message: $message)
                            BuyCard(course: c, message: $message).padding(.top, 28)
                        }
                        Related(course: c)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .centered()
                }
                .safeAreaInset(edge: .bottom) { if width != .wide { StickyBar(course: c, message: $message) } }
                .navBar(c.title)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if let u = URL(string: c.link) { ShareLink(item: u, subject: Text(c.title)) { Image(systemName: "square.and.arrow.up") } }
                    }
                }
            }
        }
        .background(p.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L.t("تمام", "OK"), role: .cancel) {}
        }
    }
}

/// The main action for this student and this course.
private struct CourseAction {
    let label: String
    let icon: String?
    let run: () async throws -> Void
}

@MainActor
private func action(for c: Course, user: User?, model: AppModel, router: Router) -> CourseAction? {
    if c.enrolled, c.progress?.isCompleted == true {
        return CourseAction(label: L.t("شهادتي", "My certificate"), icon: "rosette") {
            router.push(.web(url: c.certificateUrl ?? c.link, title: L.t("شهادتي", "My certificate"), signedIn: true))
        }
    }
    if c.enrolled, c.canComplete == true, (c.progress?.percent ?? 0) >= 100 {
        return CourseAction(label: L.t("إنهاء الدورة", "Finish course"), icon: "checkmark.seal") { try await model.api.completeCourse(c.id) }
    }
    if c.enrolled, let next = c.nextItem {
        return CourseAction(label: (c.progress?.percent ?? 0) == 0 ? L.t("ابدأ التعلّم", "Start learning") : L.t("كمّل التعلّم", "Continue learning"), icon: "play.fill") {
            router.open(item: next)
        }
    }
    if c.enrolled { return nil }
    if user == nil { return CourseAction(label: L.t("سجّل الدخول", "Sign in"), icon: nil) { router.push(.login) } }
    if c.price?.free ?? true {
        return CourseAction(label: L.t("سجّل في الدورة مجاناً", "Enroll for free"), icon: nil) { try await model.api.enroll(c.id) }
    }
    return nil
}

private func askURL(_ title: String) -> URL {
    Contact.whatsapp(L.t("السلام عليكم، أرغب في الاستفسار عن: \(title)", "Hello, I'd like to ask about: \(title)"))
}

/* ---------- header ---------- */

private struct CourseHeader: View {
    let course: Course
    let width: WidthClass
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var playIntro = false

    var body: some View {
        let c = course
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Button(L.t("الرئيسية", "Home")) { router.tab = .home }
                Text("  /  ")
                Button(L.t("الدورات", "Courses")) { router.showCourses() }
                if let cat = c.category {
                    Text("  /  ")
                    Button(cat.name) { router.showCourses(category: cat.id) }.foregroundStyle(p.cyanText)
                }
            }
            .font(AppFont.body(13)).foregroundStyle(p.muted).buttonStyle(.plain)

            FlowLayout(spacing: 8) {
                if let cat = c.category { Pill(text: cat.name, tone: .accent) }
                if let off = c.price?.discountPercent { Pill(text: L.t("خصم \(off)%", "\(off)% off"), tone: .sale) }
            }
            Text(c.title).font(AppFont.head(30)).foregroundStyle(p.text)
            if let ex = c.excerpt, !ex.isEmpty { Text(ex).font(AppFont.body(16)).foregroundStyle(p.textSoft) }

            // .cd-facts: figures separated by hairlines.
            let facts: [(String, String)] = [
                (Format.hours(c.duration), L.t("المدة", "Duration")),
                ("\(c.lessons + c.quizzes)", L.t("درساً واختباراً", "lessons & quizzes")),
                ("\(c.topicsCount ?? 0)", L.t("وحدة تدريبية", "units")),
                ((c.studentsCount ?? 0) > 0 ? "\(c.studentsCount ?? 0)" : "", L.t("دارس ملتحق", "students")),
                (L.t("شهادة دولية", "International"), L.t("قابلة للتحقق", "verifiable certificate")),
            ].filter { !$0.0.isEmpty }
            let columns = width == .phone ? 2 : facts.count
            let rows = stride(from: 0, to: facts.count, by: columns).map { Array(facts[$0..<min($0 + columns, facts.count)]) }
            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 1) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, f in
                            VStack(spacing: 3) {
                                Text(f.0).font(AppFont.head(16, .heavy)).foregroundStyle(p.text).lineLimit(1)
                                Text(f.1).font(AppFont.body(12)).foregroundStyle(p.muted).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14).background(p.elevated)
                        }
                    }
                }
            }
            .background(p.line)
            .clipShape(RoundedRectangle(cornerRadius: p.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: p.radiusMd).stroke(p.line, lineWidth: 1))

            ZStack {
                if playIntro, let intro = c.introVideo {
                    VideoBox(video: intro)
                } else {
                    RemoteImage(url: c.image)
                    if let intro = c.introVideo, VideoLinks.playable(intro) {
                        Button { playIntro = true } label: {
                            Image(systemName: "play.fill").font(.system(size: 26)).foregroundStyle(Brand.darkPage)
                                .frame(width: 68, height: 68).background(Circle().fill(Brand.cyan))
                        }
                        .accessibilityLabel(L.t("شاهد الفيديو التعريفي", "Watch the intro"))
                    }
                }
            }
            .aspectRatio(width == .phone ? 16 / 10 : 2.2, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: p.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(p.line, lineWidth: 1))
        }
    }
}

/* ---------- body ---------- */

private struct CourseBody: View {
    let course: Course
    @Binding var message: String?
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        let c = course
        VStack(alignment: .leading, spacing: 0) {
            ForEach(c.announcements ?? []) { a in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "megaphone").foregroundStyle(p.cyanText)
                    VStack(alignment: .leading) {
                        Text(a.title).font(AppFont.head(15)).foregroundStyle(p.text)
                        Text(a.text).font(AppFont.body(13)).foregroundStyle(p.textSoft)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: p.radiusMd).fill(Brand.cyan.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: p.radiusMd).stroke(Brand.cyan.opacity(0.35), lineWidth: 1))
                .padding(.top, 12)
            }

            if let benefits = c.benefits, !benefits.isEmpty {
                title(L.t("ماذا", "What you'll"), L.t("ستتعلّم", "learn"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(benefits, id: \.self) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle").foregroundStyle(p.turqText)
                            Text(line).font(AppFont.body(15)).foregroundStyle(p.textSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18).siteCard()
            }

            if let html = c.contentHtml, !html.isEmpty {
                title(L.t("نظرة عامة على", "Course"), L.t("الدورة", "overview"))
                HTMLText(html: html)
            }

            if let curriculum = c.curriculum, !curriculum.isEmpty {
                CurriculumSection(course: c, message: $message)
            }

            if let audience = c.audience, !audience.isEmpty {
                Text(L.t("لمن هذه الدورة", "Who it's for")).font(AppFont.head(23)).foregroundStyle(p.text).padding(.top, 32).padding(.bottom, 10)
                ForEach(audience, id: \.self) { line in
                    HStack(spacing: 10) {
                        Circle().fill(Brand.cyan).frame(width: 8, height: 8)
                        Text(line).font(AppFont.body(16)).foregroundStyle(p.textSoft)
                    }
                    .padding(.vertical, 3)
                }
            }

            if let reviews = c.reviews, !reviews.isEmpty {
                title(L.t("آراء", "Student"), L.t("الدارسين", "reviews"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(reviews) { r in ReviewCard(stars: Int(r.rating.rounded()), text: r.text, name: r.name) }
                }
            }
        }
    }

    private func title(_ plain: String, _ accent: String) -> some View {
        AccentText(parts: [HeadingPart(text: plain, accent: 0), HeadingPart(text: accent, accent: 1)])
            .padding(.top, 36).padding(.bottom, 16)
    }
}

private struct CurriculumSection: View {
    let course: Course
    @Binding var message: String?
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var open: Set<Int> = []

    var body: some View {
        let topics = course.curriculum ?? []
        let allOpen = topics.allSatisfy { open.contains($0.id) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    AccentText(parts: [HeadingPart(text: L.t("محتوى", "Course"), accent: 0), HeadingPart(text: L.t("الدورة", "content"), accent: 1)])
                    let lessons = course.items.filter { $0.type == "lesson" }.count
                    Text(L.t("\(topics.count) وحدة · \(lessons) دروس", "\(topics.count) units · \(lessons) lessons")).font(AppFont.body(13)).foregroundStyle(p.muted)
                }
                Spacer()
                Button(allOpen ? L.t("اقفل الكل", "Collapse all") : L.t("افتح الكل", "Expand all")) {
                    open = allOpen ? [] : Set(topics.map(\.id))
                }
                .font(AppFont.head(14)).foregroundStyle(p.cyanText).buttonStyle(.plain)
            }
            .padding(.top, 36)

            ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if open.contains(topic.id) { open.remove(topic.id) } else { open.insert(topic.id) }
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Text("\(index + 1)").font(AppFont.head(14)).foregroundStyle(p.cyanText)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: p.radiusMd).fill(Brand.cyan.opacity(0.13)))
                                .overlay(RoundedRectangle(cornerRadius: p.radiusMd).stroke(Brand.cyan.opacity(0.28), lineWidth: 1))
                            Text(topic.title).font(AppFont.head(15)).foregroundStyle(p.text).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(topic.items.count)").font(AppFont.head(12, .semibold)).foregroundStyle(p.muted)
                                .padding(.horizontal, 9).background(Capsule().fill(p.glass))
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.muted)
                                .rotationEffect(.degrees(open.contains(topic.id) ? 180 : 0))
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open.contains(topic.id) {
                        VStack(spacing: 0) {
                            ForEach(topic.items) { item in LessonRow(item: item, enrolled: course.enrolled) { tap(item) } }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 10)
                    }
                }
                .background(LinearGradient(colors: [p.glass, p.page], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: p.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: p.radiusMd).stroke(p.line, lineWidth: 1))
            }
        }
        .onAppear {
            guard open.isEmpty else { return }
            let next = course.nextItem?.id
            open = Set(topics.enumerated().filter { $0.offset == 0 || $0.element.items.contains { $0.id == next } }.map(\.element.id))
        }
    }

    private func tap(_ item: CurriculumItem) {
        if item.locked {
            message = L.t("اشترك في الدورة علشان تفتح المحتوى ده.", "Enroll in the course to open this.")
        } else {
            router.open(item: item)
        }
    }
}

/// .cd-lesson: round icon, title, then the duration or a "اختبار" tag, with done / locked / preview marks.
private struct LessonRow: View {
    let item: CurriculumItem
    let enrolled: Bool
    let tap: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(p.cyanText)
                    .frame(width: 26, height: 26).background(Circle().fill(p.glass))
                Text(item.title).font(AppFont.body(15)).foregroundStyle(p.textSoft).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.type == "quiz" {
                    Text(L.t("اختبار", "Quiz")).font(AppFont.head(12)).foregroundStyle(p.turqText)
                        .padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(Brand.turquoise.opacity(0.18)))
                } else if let d = item.durationSeconds, d > 0 {
                    Text(Format.clock(d)).font(AppFont.body(13)).foregroundStyle(p.muted).environment(\.layoutDirection, .leftToRight)
                }
                if item.done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(p.turqText)
                } else if item.locked {
                    Image(systemName: "lock").font(.system(size: 13)).foregroundStyle(p.muted)
                } else if item.isPreview == true && !enrolled {
                    Pill(text: L.t("معاينة", "Preview"), tone: .accent)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch item.type {
        case "lesson": return "play.fill"
        case "quiz": return "questionmark"
        case "assignment": return "doc.text"
        case "live": return "video"
        default: return "book"
        }
    }
}

/* ---------- buying ---------- */

/// .buy-card: price (or progress), the main action, "ask about the course", what is included, the fine print.
private struct BuyCard: View {
    let course: Course
    @Binding var message: String?
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var busy = false

    var body: some View {
        let c = course
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if c.enrolled, let progress = c.progress {
                    Text(L.t("أنت مشترك في الدورة", "You're enrolled")).font(AppFont.head(17)).foregroundStyle(p.turqText)
                    ProgressLine(percent: progress.percent, completed: progress.isCompleted)
                } else {
                    PriceBlock(price: c.price, big: true)
                    if let save = c.price?.saving {
                        Text(L.t("وفّر ", "Save ") + Format.money(save, c.price?.currency)).font(AppFont.head(14)).foregroundStyle(p.turqText)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RadialGradient(colors: [Brand.cyan.opacity(0.14), .clear], center: .topTrailing, startRadius: 0, endRadius: 300))
            Rectangle().fill(p.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                if let a = action(for: c, user: session.user, model: model, router: router) {
                    Button {
                        busy = true
                        Task {
                            do { try await a.run() } catch { message = ApiError.describe(error) }
                            busy = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(p.buttonText) } else {
                                if let icon = a.icon { Image(systemName: icon) }
                                Text(a.label)
                            }
                        }
                    }
                    .buttonStyle(PrimaryStyle(full: true))
                    .disabled(busy)
                } else if !c.enrolled {
                    Text(L.t(
                        "الاشتراك والدفع في الدورة بيتم من موقع المعهد. بعد ما تشترك، الدورة هتظهر هنا في «دوراتي».",
                        "Enrollment and payment happen on the institute's website. Once enrolled, the course appears here under My learning."
                    ))
                    .font(AppFont.body(14)).foregroundStyle(p.textSoft)
                }
                Button(L.t("اسأل عن الدورة", "Ask about the course")) { UIApplication.shared.open(askURL(c.title)) }
                    .buttonStyle(WhatsAppStyle(full: true))
                VStack(alignment: .leading, spacing: 8) {
                    included("play.fill", L.t("\(c.lessons) دروس", "\(c.lessons) lessons"))
                    included("clock", Format.hours(c.duration))
                    included("rosette", L.t("شهادة معتمدة قابلة للتحقق", "Accredited, verifiable certificate"))
                    included("ipad.and.iphone", L.t("وصول من أي جهاز", "Access from any device"))
                }
                .padding(.top, 4)
                Text(L.t(
                    "للاستفسار عن مواعيد المجموعات القادمة تواصل معنا.",
                    "Contact us for the next groups' dates."
                ))
                .font(AppFont.body(12)).foregroundStyle(p.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(22)
        }
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: p.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(p.lineStrong, lineWidth: 1))
    }

    @ViewBuilder
    private func included(_ icon: String, _ text: String) -> some View {
        if !text.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(p.cyanText).frame(width: 20)
                Text(text).font(AppFont.body(15)).foregroundStyle(p.textSoft)
            }
        }
    }
}

/// On phones the main action stays reachable at the bottom while reading.
private struct StickyBar: View {
    let course: Course
    @Binding var message: String?
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var busy = false

    var body: some View {
        let c = course
        VStack(spacing: 0) {
            Rectangle().fill(p.line).frame(height: 1)
            HStack(spacing: 10) {
                if !c.enrolled { PriceBlock(price: c.price) } else { Spacer(minLength: 0) }
                Spacer(minLength: 0)
                Button { UIApplication.shared.open(askURL(c.title)) } label: {
                    Image("WhatsApp").renderingMode(.template).resizable().frame(width: 24, height: 24).foregroundStyle(p.turqText)
                }
                .accessibilityLabel(L.t("اسأل عن الدورة", "Ask about the course"))
                if let a = action(for: c, user: session.user, model: model, router: router) {
                    Button {
                        busy = true
                        Task {
                            do { try await a.run() } catch { message = ApiError.describe(error) }
                            busy = false
                        }
                    } label: { Text(a.label) }
                    .buttonStyle(PrimaryStyle(full: c.enrolled))
                    .disabled(busy)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(p.elevated.ignoresSafeArea(edges: .bottom))
    }
}

/* ---------- related ---------- */

/// .section--band "دورات ذات صلة": other courses from the same track.
private struct Related: View {
    let course: Course
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router

    var body: some View {
        let related = model.knownCourses.filter { other in
            other.id != course.id && (other.categories ?? []).contains { $0.id == course.category?.id }
        }.prefix(3)
        if let cat = course.category, !related.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                SectionHead(
                    heading: Heading(eyebrow: L.t("من نفس المسار", "From the same track"), parts: [HeadingPart(text: L.t("دورات", "Related"), accent: 0), HeadingPart(text: L.t("ذات صلة", "courses"), accent: 1)], intro: ""),
                    action: L.t("كل دورات المسار", "All courses in this track")
                ) { router.showCourses(category: cat.id) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(Array(related)) { r in CourseCard(course: r) { router.push(.course(r.id)) } }
                }
            }
            .padding(.top, 40)
        }
    }
}
