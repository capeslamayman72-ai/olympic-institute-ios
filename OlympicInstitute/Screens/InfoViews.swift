import SwiftUI

struct VerifyView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @State private var number = ""
    @State private var busy = false
    @State private var result: CertificateCheck?
    @State private var error: String?

    private var valid: Bool { number.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("كل شهادة صادرة من المعهد ليها رقم. اكتبه هنا علشان تتأكد إنها أصلية وتشوف بياناتها.",
                         "Every certificate the institute issues has a number. Enter it to confirm it is genuine."))
                    .font(AppFont.body(15)).foregroundStyle(p.textSoft)
                TextField(L.t("رقم الشهادة", "Certificate number"), text: Binding(get: { number }, set: { number = $0.filter { $0.isLetter || $0.isNumber || $0 == "-" } }))
                    .font(AppFont.body(17)).environment(\.layoutDirection, .leftToRight)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(p.glass))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(p.line, lineWidth: 1))
                    .onSubmit(check)
                Text(L.t("حروف إنجليزية وأرقام وشرطة فقط", "Latin letters, digits and dashes only")).font(AppFont.body(12)).foregroundStyle(p.muted)
                Button(action: check) {
                    if busy { ProgressView().tint(p.buttonText) } else { Text(L.t("تحقّق", "Verify")) }
                }
                .buttonStyle(PrimaryStyle(full: true))
                .disabled(!valid || busy)
                if let error { Text(error).font(AppFont.body(15)).foregroundStyle(p.sale) }
                switch result {
                case .found(let c):
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L.t("شهادة موثّقة", "Verified certificate"), systemImage: "checkmark.seal.fill")
                            .font(AppFont.head(22)).foregroundStyle(p.turqText)
                        Rectangle().fill(p.line).frame(height: 1)
                        line(L.t("الاسم", "Name"), c.nameAr)
                        line(L.t("الاسم بالإنجليزية", "Name (English)"), c.nameEn)
                        line(L.t("رقم الشهادة", "Number"), c.number)
                        line(L.t("التخصص", "Specialization"), c.specialization)
                        if !c.statement.isEmpty { Text(c.statement).font(AppFont.body(15)).foregroundStyle(p.textSoft) }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: p.radiusLg).fill(Brand.turquoise.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(Brand.turquoise.opacity(0.4), lineWidth: 1))
                case .notFound(let message):
                    Label(message.isEmpty ? L.t("مفيش شهادة بالرقم ده.", "No certificate with this number.") : message, systemImage: "exclamationmark.circle")
                        .font(AppFont.body(15)).foregroundStyle(p.sale)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: p.radiusLg).fill(p.sale.opacity(0.12)))
                case nil:
                    EmptyView()
                }
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .navBar(L.t("التحقق من الشهادات", "Verify a certificate"))
    }

    @ViewBuilder
    private func line(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top) {
                Text(label).font(AppFont.body(15)).foregroundStyle(p.muted).frame(width: 130, alignment: .leading)
                Text(value).font(AppFont.head(16)).foregroundStyle(p.text)
            }
        }
    }

    private func check() {
        guard valid, !busy else { return }
        busy = true
        error = nil
        result = nil
        Task {
            do { result = try await model.site.verifyCertificate(number, L.lang) } catch { self.error = ApiError.describe(error) }
            busy = false
        }
    }
}

struct InstructorsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Loader(key: L.lang.rawValue, load: { try await model.site.instructors(L.lang) }) { people, _ in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(people) { InstructorCard(member: $0) }
                }
                .padding(16)
            }
        }
        .navBar(L.t("المدربون والمحاضرون", "Instructors"))
    }
}

struct TestimonialsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Loader(key: L.lang.rawValue, load: { try await model.site.testimonials(L.lang) }) { reviews, _ in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(reviews) { r in ReviewCard(stars: r.stars, text: r.text, name: r.name, course: r.course) }
                }
                .padding(16)
            }
        }
        .navBar(L.t("آراء الدارسين", "Testimonials"))
    }
}

struct GalleryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @State private var open: GalleryPhoto?

    var body: some View {
        Loader(key: L.lang.rawValue, load: { try await model.site.gallery(L.lang) }) { photos, _ in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                    ForEach(photos) { photo in
                        Button { open = photo } label: {
                            RemoteImage(url: photo.thumb).aspectRatio(1, contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.caption)
                    }
                }
                .padding(8)
            }
            .fullScreenCover(item: $open) { start in PhotoViewer(photos: photos, start: start) { open = nil } }
        }
        .navBar(L.t("ألبوم الصور", "Photo album"))
    }
}

private struct PhotoViewer: View {
    let photos: [GalleryPhoto]
    let start: GalleryPhoto
    let close: () -> Void
    @State private var current: GalleryPhoto?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: Binding(get: { current ?? start }, set: { current = $0 })) {
                ForEach(photos) { photo in
                    ZStack(alignment: .bottom) {
                        RemoteImage(url: photo.full, mode: .fit).background(Color.black)
                        if !photo.caption.isEmpty {
                            Text(photo.caption).font(AppFont.body(15)).foregroundStyle(.white).multilineTextAlignment(.center)
                                .padding(16).frame(maxWidth: .infinity).background(Color.black.opacity(0.5))
                        }
                    }
                    .tag(photo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(Color.black.opacity(0.4)))
            }
            .padding(16)
            .accessibilityLabel(L.t("إغلاق", "Close"))
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        Loader(key: L.lang.rawValue, load: { try await model.site.library(L.lang) }) { books, _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("كتاب جديد كل أسبوع، والتحميل مجاني ومن غير تسجيل.", "A new book every week, free to download."))
                        .font(AppFont.body(15)).foregroundStyle(p.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 12)], spacing: 12) {
                        ForEach(books) { b in
                            HStack(alignment: .top, spacing: 12) {
                                RemoteImage(url: b.cover).frame(width: 96, height: 128).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 6) {
                                    if b.featured { Text(L.t("كتاب الأسبوع", "Book of the week")).font(AppFont.head(13)).foregroundStyle(p.cyanText) }
                                    Text(b.title).font(AppFont.head(16)).foregroundStyle(p.text)
                                    if !b.meta.isEmpty { Text(b.meta).font(AppFont.body(12)).foregroundStyle(p.muted) }
                                    Button { if let u = URL(string: b.url) { UIApplication.shared.open(u) } } label: {
                                        Label(L.t("حمّل الكتاب", "Download"), systemImage: "arrow.down.circle")
                                    }
                                    .buttonStyle(GhostStyle())
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .siteCard()
                        }
                    }
                }
                .padding(16)
            }
        }
        .navBar(L.t("مكتبة المعهد", "Library"))
    }
}

struct ArticlesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        Loader(key: "posts", load: {
            let posts = try await model.site.posts()
            model.knownPosts = posts
            return posts
        }) { posts, _ in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(posts) { post in
                        Button { router.push(.article(post.id)) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                if post.image != nil { RemoteImage(url: post.image).aspectRatio(16 / 9, contentMode: .fit) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.date).font(AppFont.body(12)).foregroundStyle(p.muted)
                                    Text(post.title).font(AppFont.head(17)).foregroundStyle(p.text).multilineTextAlignment(.leading)
                                    if !post.excerpt.isEmpty {
                                        Text(post.excerpt).font(AppFont.body(14)).foregroundStyle(p.muted).lineLimit(3).multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .siteCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navBar(L.t("المقالات", "Articles"))
    }
}

struct ArticleView: View {
    let id: Int
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        Loader(key: id, load: {
            if let known = model.knownPosts.first(where: { $0.id == id }) { return known }
            let posts = try await model.site.posts()
            model.knownPosts = posts
            guard let post = posts.first(where: { $0.id == id }) else { throw ApiError(code: "not_found", message: L.t("المقال مش موجود.", "Article not found."), status: 404) }
            return post
        }) { post, _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if post.image != nil { RemoteImage(url: post.image).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: p.radiusMd)) }
                    Text(post.title).font(AppFont.head(23)).foregroundStyle(p.text)
                    Text(post.date).font(AppFont.body(13)).foregroundStyle(p.muted)
                    HTMLText(html: post.contentHtml)
                }
                .padding(16)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let u = URL(string: post.link) { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") } }
                }
            }
        }
        .navBar(L.t("المقالات", "Articles"))
    }
}
