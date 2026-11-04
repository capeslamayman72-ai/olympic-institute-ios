import SwiftUI

/// Used when the home page cannot be read: the site's own hero and course section, in the same words.
private func fallbackHome() -> [HomeSection] {
    [
        .hero(
            title: L.t("المعهد الاوليمبي الدولي لعلوم الرياضة", "International Olympic Institute for Sports Sciences"),
            badge: L.t("أول وأقوى منصة رخص تدريبية بالوطن العربي", "The Arab world's first coaching-licence platform"),
            sub: L.t("منصتك لعالم الاحتراف", "Your gateway to the professional world"),
            primary: SiteLink(label: L.t("استعرض الدورات", "Browse courses"), url: "/courses/"),
            secondary: SiteLink(label: L.t("سجّل كدارس جديد", "Register as a student"), url: "/login/?tab=register"),
            pills: [], images: [], emblem: nil
        ),
        .courses(
            Heading(eyebrow: L.t("الأكثر طلباً", "Most requested"), parts: [HeadingPart(text: L.t("دبلومات وبرامج", "Diplomas and"), accent: 0), HeadingPart(text: L.t("متكاملة", "programmes"), accent: 1)], intro: ""),
            more: SiteLink(label: L.t("كل الدورات", "All courses"), url: "/courses/"),
            links: []
        ),
    ]
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @AppStorage("theme") private var theme = "dark"
    @State private var sections: [HomeSection]?
    @State private var courses: [Course] = []
    @State private var coursesError: Error?

    var body: some View {
        GeometryReader { geo in
            let width = WidthClass(geo.size.width)
            ZStack(alignment: .bottomLeading) {
                if let sections {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                                block(section, width)
                                if case .stats = section, session.user != nil,
                                   let active = courses.first(where: { $0.enrolled && $0.progress?.isCompleted == false }) {
                                    ContinueCard(course: active).padding(.horizontal, 20).padding(.top, 24).centered()
                                }
                            }
                        }
                        .padding(.bottom, 96)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button {
                    UIApplication.shared.open(Contact.whatsapp(L.t("السلام عليكم، أريد الاستفسار عن دورات المعهد.", "Hello, I'd like to ask about the institute's courses.")))
                } label: {
                    Image("WhatsApp").renderingMode(.template).resizable().frame(width: 28, height: 28).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(Circle().fill(Brand.whatsapp))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .accessibilityLabel(L.t("واتساب", "WhatsApp"))
                .padding(18)
            }
        }
        .background(p.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(p.page, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Image("Logo").resizable().scaledToFit().frame(width: 34, height: 34)
                    Text(L.t("المعهد الأوليمبي الدولي", "International Olympic Institute")).font(AppFont.head(16)).foregroundStyle(p.text)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { theme = p.isDark ? "light" : "dark" } label: {
                    Image(systemName: p.isDark ? "sun.max" : "moon")
                }
                .accessibilityLabel(L.t("تبديل المظهر", "Switch theme"))
            }
        }
        .task(id: session.changes) {
            do {
                courses = try await model.courses()
                coursesError = nil
            } catch {
                coursesError = error
            }
        }
        .task {
            let read = (try? await model.site.home(L.lang)) ?? []
            sections = read.isEmpty ? fallbackHome() : read
        }
    }

    @ViewBuilder
    private func block(_ section: HomeSection, _ width: WidthClass) -> some View {
        switch section {
        case let .hero(title, badge, sub, primary, secondary, pills, images, emblem):
            HeroBlock(title: title, badge: badge, sub: sub, primary: primary, secondary: secondary, pills: pills, images: images, emblem: emblem, wide: width != .phone)
        case .stats(let stats):
            StatsBlock(stats: stats, columns: width == .phone ? 2 : 4)
        case let .courses(heading, more, links):
            Block {
                SectionHead(heading: heading, action: more?.label ?? L.t("كل الدورات", "All courses")) { router.showCourses() }
                coursesGrid(links)
            }
        case let .tracks(heading, tracks):
            Block(band: true) {
                SectionHead(heading: heading)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in TrackCard(track: t, index: i) }
                }
            }
        case let .features(heading, items):
            Block {
                SectionHead(heading: heading)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, f in FeatureCard(feature: f, index: i) }
                }
            }
        case let .album(title, more, photos):
            AlbumBlock(title: title, more: more, photos: photos)
        case let .library(title, text, button):
            Block { LibraryDoor(title: title, text: text, button: button) }
        case let .instructors(heading, more, people):
            Block(band: true) {
                SectionHead(heading: heading, action: more?.label) { router.push(.instructors) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) { ForEach(people) { InstructorCard(member: $0).frame(width: width == .phone ? 200 : 220) } }
                }
            }
        case let .testimonials(heading, items):
            Block(band: true) { TestimonialsBlock(heading: heading, items: items) }
        case let .cta(heading, primary, secondary):
            Block { CtaBlock(heading: heading, primary: primary, secondary: secondary) }
        }
    }

    @ViewBuilder
    private func coursesGrid(_ links: [String]) -> some View {
        // The same courses, in the same order, as the site's home page; the first nine if the page gave none.
        let norm: (String) -> String = { String($0.split(separator: "?").first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() }
        let picked = links.compactMap { l in courses.first { norm($0.link) == norm(l) } }
        let shown = picked.isEmpty ? Array(courses.prefix(9)) : picked
        if !shown.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                ForEach(shown) { c in CourseCard(course: c) { router.push(.course(c.id)) } }
            }
        } else if let coursesError {
            Text(ApiError.describe(coursesError)).font(AppFont.body(15)).foregroundStyle(p.muted)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

/// A full-width section with the site's vertical rhythm; `band` gives it the alternate background.
private struct Block<Content: View>: View {
    var band = false
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 22) { content() }
            .padding(.horizontal, 20)
            .centered()
            .padding(.vertical, 36)
            .background(band ? p.band : Color.clear)
    }
}

private struct HeroBlock: View {
    let title: String, badge: String, sub: String
    let primary: SiteLink?, secondary: SiteLink?
    let pills: [String], images: [String]
    let emblem: String?
    let wide: Bool
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var shot = 0
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .center, spacing: 32) {
                content
                if wide { Emblem(url: emblem).frame(width: 280) }
            }
            if !wide { Emblem(url: emblem) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .centered()
        // The slideshow sits behind the content and takes its size from it.
        .background {
            if !images.isEmpty {
                ZStack {
                    RemoteImage(url: images[shot % images.count])
                        .opacity(p.isDark ? 0.35 : 0.22)
                        .animation(.easeInOut(duration: 1.2), value: shot)
                    p.heroVeil
                }
            }
        }
        .clipped()
        .onReceive(timer) { _ in if images.count > 1 { shot += 1 } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(AppFont.head(34)).foregroundStyle(p.text).lineSpacing(4)
            if !badge.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(Circle().fill(Brand.navy))
                    Text(badge).font(AppFont.head(14)).foregroundStyle(Brand.navyDeep)
                }
                .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient(colors: [Brand.turquoise, Brand.cyan], startPoint: .leading, endPoint: .trailing)))
            }
            if !sub.isEmpty { Text(sub).font(AppFont.body(17)).foregroundStyle(p.textSoft) }
            VStack(spacing: 12) {
                if let primary {
                    Button { router.site(primary.url, label: primary.label) } label: {
                        HStack(spacing: 10) { Text(primary.label); Image(systemName: "arrow.forward") }
                    }
                    .buttonStyle(PrimaryStyle(full: true))
                }
                if let secondary {
                    Button(secondary.label) { router.site(secondary.url, label: secondary.label) }.buttonStyle(GhostStyle(full: true))
                }
            }
            .frame(maxWidth: wide ? 420 : .infinity)
            if !pills.isEmpty {
                FlowLayout(spacing: 8) {
                    let icons = ["checkmark.shield", "globe", "mappin.and.ellipse"]
                    ForEach(Array(pills.enumerated()), id: \.offset) { i, pill in
                        Pill(text: pill, tone: i == 0 ? .accent : .plain, icon: i < icons.count ? icons[i] : nil)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// .hero__visual: the institute's emblem inside a soft glowing ring.
private struct Emblem: View {
    let url: String?

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Brand.cyan.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 120))
                .overlay(Circle().stroke(Brand.cyan.opacity(0.25), lineWidth: 1))
                .frame(width: 230, height: 230)
            if let url { RemoteImage(url: url, mode: .fit).background(Color.clear).frame(width: 190, height: 190) } else {
                Image("Logo").resizable().scaledToFit().frame(width: 190, height: 190)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatsBlock: View {
    let stats: [Stat]
    let columns: Int
    @Environment(\.palette) private var p

    var body: some View {
        let rows = stride(from: 0, to: stats.count, by: columns).map { Array(stats[$0..<min($0 + columns, stats.count)]) }
        VStack(spacing: 26) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, st in
                        VStack(spacing: 4) {
                            Text(st.value).font(AppFont.head(34)).foregroundStyle(p.turqText).environment(\.layoutDirection, .leftToRight)
                            Text(st.label).font(AppFont.body(15)).foregroundStyle(p.muted).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        if i < row.count - 1 { Rectangle().fill(p.line).frame(width: 1, height: 64) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .centered()
        .padding(.vertical, 30)
        .background(p.band)
    }
}

private struct ContinueCard: View {
    let course: Course
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        Button { router.push(.course(course.id)) } label: {
            HStack(spacing: 14) {
                RemoteImage(url: course.image).frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: p.radiusMd))
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: L.t("كمّل التعلّم", "Continue learning"))
                    Text(course.title).font(AppFont.head(15)).foregroundStyle(p.text).lineLimit(2).multilineTextAlignment(.leading)
                    ProgressLine(percent: course.progress?.percent ?? 0, completed: false)
                }
            }
            .padding(14)
            .siteCard()
        }
        .buttonStyle(.plain)
    }
}

private struct TrackCard: View {
    let track: Track
    let index: Int
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    private let icons = ["cross.case", "soccerball", "figure.strengthtraining.traditional"]

    var body: some View {
        Button {
            if let id = track.categoryId { router.showCourses(category: id) } else { router.site(track.url, label: track.title) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: track.image)
                LinearGradient(stops: [
                    .init(color: p.page.opacity(0.2), location: 0),
                    .init(color: p.page.opacity(0.62), location: 0.45),
                    .init(color: p.page.opacity(0.97), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                VStack {
                    HStack {
                        Image(systemName: index < icons.count ? icons[index] : "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 22)).foregroundStyle(p.cyanText)
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: p.radiusMd).fill(Brand.cyan.opacity(0.13)))
                            .overlay(RoundedRectangle(cornerRadius: p.radiusMd).stroke(Brand.cyan.opacity(0.32), lineWidth: 1))
                        Spacer()
                        if !track.count.isEmpty {
                            Text(track.count).font(AppFont.head(13)).foregroundStyle(p.cyanText)
                                .padding(.horizontal, 13).padding(.vertical, 4)
                                .background(Capsule().fill(p.chip)).overlay(Capsule().stroke(p.lineStrong, lineWidth: 1))
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(track.title).font(AppFont.head(23)).foregroundStyle(p.text)
                        Text(track.blurb).font(AppFont.body(13)).foregroundStyle(p.textSoft).lineLimit(4).multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Text(L.t("استعرض المسار", "Explore the track")).font(AppFont.head(14))
                            Image(systemName: "arrow.forward").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(p.cyanText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(22)
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: p.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureCard: View {
    let feature: Feature
    let index: Int
    @Environment(\.palette) private var p
    private let icons = ["checkmark.seal", "person.3", "mappin.and.ellipse", "point.topleft.down.curvedto.point.bottomright.up"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = feature.image {
                RemoteImage(url: image).aspectRatio(5 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: p.radiusMd))
            }
            Image(systemName: index < icons.count ? icons[index] : "checkmark.seal")
                .font(.system(size: 24)).foregroundStyle(Brand.darkPage)
                .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: p.radiusMd).fill(Brand.cyan))
            Text(feature.title).font(AppFont.head(17)).foregroundStyle(p.text)
            Text(feature.text).font(AppFont.body(15)).foregroundStyle(p.muted).lineSpacing(4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [p.glass, p.page], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: p.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(p.line, lineWidth: 1))
    }
}

private struct AlbumBlock: View {
    let title: String
    let more: SiteLink?
    let photos: [GalleryPhoto]
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(AppFont.head(23)).foregroundStyle(p.text)
                Spacer()
                if let more { LinkArrow(text: more.label) { router.push(.gallery) } }
            }
            .padding(.horizontal, 20)
            .centered()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(photos) { photo in
                        Button { router.push(.gallery) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: photo.thumb).frame(width: 250, height: 188).clipShape(RoundedRectangle(cornerRadius: p.radiusMd))
                                Text(photo.caption).font(AppFont.body(13)).foregroundStyle(p.muted).lineLimit(1).frame(width: 250, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 30)
    }
}

private struct LibraryDoor: View {
    let title: String
    let text: String
    let button: SiteLink?
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book").font(.system(size: 28)).foregroundStyle(p.cyanText)
                .frame(width: 60, height: 60).background(RoundedRectangle(cornerRadius: p.radiusMd).fill(Brand.cyan.opacity(0.13)))
            Text(title).font(AppFont.head(27)).foregroundStyle(p.text)
            if !text.isEmpty { Text(text).font(AppFont.body(16)).foregroundStyle(p.muted).multilineTextAlignment(.center) }
            if let button { Button(button.label) { router.push(.library) }.buttonStyle(PrimaryStyle()) }
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(RadialGradient(colors: [Brand.cyan.opacity(0.16), p.card], center: .top, startRadius: 0, endRadius: 400))
        .clipShape(RoundedRectangle(cornerRadius: p.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(p.lineStrong, lineWidth: 1))
    }
}

/// .inst-card: portrait, name, role and the short cyan rule under them.
struct InstructorCard: View {
    let member: StaffMember
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            RemoteImage(url: member.photo).aspectRatio(4 / 5, contentMode: .fit)
            VStack(spacing: 4) {
                Text(member.name).font(AppFont.head(15)).foregroundStyle(p.text).lineLimit(2).multilineTextAlignment(.center)
                Text(member.role).font(AppFont.body(13)).foregroundStyle(p.muted).lineLimit(2).multilineTextAlignment(.center)
                Rectangle().fill(Brand.cyan).frame(width: 28, height: 2).padding(.top, 6)
            }
            .padding(14)
        }
        .siteCard()
    }
}

private struct TestimonialsBlock: View {
    let heading: Heading
    let items: [Testimonial]
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var page = 0
    private let timer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Eyebrow(text: heading.eyebrow)
                AccentText(parts: heading.parts).multilineTextAlignment(.center)
            }
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, q in
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "quote.opening").font(.system(size: 28)).foregroundStyle(p.cyanText)
                        Text(q.text).font(AppFont.body(16)).foregroundStyle(p.textSoft).lineSpacing(4)
                        HStack(spacing: 10) {
                            Text(String(q.name.prefix(1))).font(AppFont.head(17)).foregroundStyle(p.cyanText)
                                .frame(width: 42, height: 42).background(Circle().fill(Brand.cyan.opacity(0.15)))
                            VStack(alignment: .leading) {
                                Text(q.name).font(AppFont.head(15)).foregroundStyle(p.text)
                                if !q.role.isEmpty { Text(q.role).font(AppFont.body(13)).foregroundStyle(p.muted) }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .siteCard()
                    .padding(.horizontal, 2)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 280)
            HStack(spacing: 8) {
                ForEach(0..<items.count, id: \.self) { i in
                    Capsule().fill(i == page ? Brand.cyan : p.lineStrong).frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            LinkArrow(text: L.t("كل الآراء", "All testimonials")) { router.push(.testimonials) }
        }
        .onReceive(timer) { _ in
            guard items.count > 1 else { return }
            withAnimation { page = (page + 1) % items.count }
        }
    }
}

private struct CtaBlock: View {
    let heading: Heading
    let primary: SiteLink?
    let secondary: SiteLink?
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 14) {
            Eyebrow(text: heading.eyebrow)
            AccentText(parts: heading.parts, color: .white).multilineTextAlignment(.center)
            if !heading.intro.isEmpty {
                Text(heading.intro).font(AppFont.body(16)).foregroundStyle(Color(hex: 0xCFE0EE)).multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                if let primary {
                    Button(primary.label) { router.site(primary.url, label: primary.label) }
                        .font(AppFont.head(15)).foregroundStyle(Brand.darkPage)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(Brand.cyan))
                }
                if let secondary {
                    Button(secondary.label) { router.site(secondary.url, label: secondary.label) }
                        .font(AppFont.head(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52).overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                }
            }
            .frame(maxWidth: 420)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Brand.navy, Brand.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: p.radiusLg))
    }
}

/// Shared by the testimonials screen and the course page.
struct ReviewCard: View {
    let stars: Int
    let text: String
    let name: String
    var course: String = ""
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<min(max(stars, 0), 5), id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(p.turqText) }
            }
            Text(text).font(AppFont.body(15)).foregroundStyle(p.textSoft).lineLimit(6)
            HStack(spacing: 10) {
                Text(String(name.prefix(1))).font(AppFont.head(15)).foregroundStyle(p.cyanText)
                    .frame(width: 36, height: 36).background(Circle().fill(Brand.cyan.opacity(0.15)))
                VStack(alignment: .leading) {
                    Text(name).font(AppFont.head(15)).foregroundStyle(p.text)
                    if !course.isEmpty { Text(course).font(AppFont.body(13)).foregroundStyle(p.cyanText) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .siteCard()
    }
}
