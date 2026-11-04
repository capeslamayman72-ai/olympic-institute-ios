import SwiftUI

/// The site's /courses/ page: catalogue header, track filters with counts, the result count, cards, and the help band.
struct CoursesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var categories: [Category] = []

    var body: some View {
        Loader(key: session.changes, load: { try await model.courses() }) { list, reload in
            let selected = router.coursesCategory
            let needle = query.trimmingCharacters(in: .whitespaces)
            let shown = list.filter { c in
                (selected == nil || (c.categories ?? []).contains { $0.id == selected })
                    && (needle.isEmpty || c.title.localizedCaseInsensitiveContains(needle) || (c.excerpt ?? "").localizedCaseInsensitiveContains(needle))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHead(heading: Heading(
                        eyebrow: L.t("الكتالوج الكامل", "The full catalogue"),
                        parts: [HeadingPart(text: L.t("الدورات", "Courses &"), accent: 0), HeadingPart(text: L.t("والدبلومات", "Diplomas"), accent: 1)],
                        intro: L.t(
                            "اختر المسار الذي يناسب تخصصك — الطب الرياضي، أو تدريب كرة القدم، أو اللياقة البدنية والإعداد البدني. كل دورة تنتهي بشهادة من المعهد يمكن التحقق من صحتها إلكترونياً.",
                            "Programmes across sports medicine, football coaching and analysis, and physical preparation. Each ends in a certificate from the institute that can be verified online."
                        )
                    ))
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(p.muted)
                        TextField(L.t("ابحث باسم الدورة", "Search by course name"), text: $query).font(AppFont.body(16))
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(p.muted) }
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 50)
                    .background(Capsule().fill(p.glass)).overlay(Capsule().stroke(p.line, lineWidth: 1))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            FilterPill(label: L.t("كل الدورات", "All courses"), count: list.count, active: selected == nil) { router.coursesCategory = nil }
                            ForEach(categories) { c in
                                FilterPill(label: c.name, count: c.count ?? 0, active: selected == c.id) {
                                    router.coursesCategory = selected == c.id ? nil : c.id
                                }
                            }
                        }
                    }

                    (Text(L.t("عرض ", "Showing ")) + Text("\(shown.count)").foregroundColor(p.cyanText).bold()
                        + Text(L.t(" من إجمالي ", " of ")) + Text("\(list.count)").bold() + Text(L.t(" دورة", " courses")))
                        .font(AppFont.body(15)).foregroundStyle(p.muted)

                    if shown.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", text: L.t("مفيش دورات بالشكل ده.", "No courses match.")) { EmptyView() }
                            .frame(height: 260)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            ForEach(shown) { c in CourseCard(course: c) { router.push(.course(c.id)) } }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .centered()

                HelpBand()
                    .padding(.top, 36)
            }
            .refreshable { reload() }
        }
        .navBar(L.t("الدورات والدبلومات", "Courses & diplomas"))
        .task { categories = (try? await model.api.categories()) ?? [] }
    }
}

/// .filter: a pill with the track name and its course count; the active one is filled cyan.
private struct FilterPill: View {
    let label: String
    let count: Int
    let active: Bool
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(AppFont.head(14)).foregroundStyle(active ? Brand.darkPage : p.text)
                Text("\(count)").font(AppFont.head(12, .semibold)).foregroundStyle(active ? Brand.darkPage : p.muted)
                    .padding(.horizontal, 8).background(Capsule().fill(active ? Brand.darkPage.opacity(0.12) : p.card))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(active ? Brand.cyan : p.glass))
            .overlay(Capsule().stroke(active ? Brand.cyan : p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The catalogue's closing band: help choosing a track over WhatsApp or the contact page.
private struct HelpBand: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHead(heading: Heading(
                eyebrow: L.t("لم تجد ما تبحث عنه؟", "Not sure which one fits you?"),
                parts: [HeadingPart(text: L.t("نساعدك في اختيار", "We'll help you pick"), accent: 0), HeadingPart(text: L.t("المسار المناسب", "the right track"), accent: 1)],
                intro: L.t(
                    "راسلنا على واتساب أو اتصل بنا، وسنرشدك إلى الدورة الأنسب لمستواك وهدفك المهني، ومواعيد أقرب مجموعة.",
                    "Tell us your background and what you want to do, and we will point you at the right track and the next group's dates."
                )
            ))
            VStack(spacing: 12) {
                Button(L.t("استفسر على واتساب", "Ask on WhatsApp")) {
                    UIApplication.shared.open(Contact.whatsapp(L.t("السلام عليكم، محتاج مساعدة في اختيار الدورة المناسبة.", "Hello, I need help choosing a course.")))
                }
                .buttonStyle(WhatsAppStyle(full: true))
                Button(L.t("صفحة التواصل", "Contact page")) {
                    router.push(.web(url: model.site.url(.contact), title: L.t("تواصل معنا", "Contact us"), signedIn: false))
                }
                .buttonStyle(GhostStyle(full: true))
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 20)
        .centered()
        .padding(.vertical, 32)
        .background(p.band)
    }
}
