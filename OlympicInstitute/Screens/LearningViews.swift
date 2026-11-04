import SwiftUI

struct LearningView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            if session.user == nil {
                EmptyStateView(icon: "person.crop.circle.badge.questionmark", text: L.t("سجّل الدخول بحساب الموقع علشان تشوف دوراتك وتكمّل من مكان ما وقفت.", "Sign in with your website account to see your courses.")) {
                    Button(L.t("تسجيل الدخول", "Sign in")) { router.push(.login) }.buttonStyle(PrimaryStyle())
                }
            } else {
                Loader(key: session.changes, load: { try await model.api.myCourses() }) { list, reload in
                    if list.isEmpty {
                        EmptyStateView(icon: "books.vertical", text: L.t("لسه مشتركتش في أي دورة.", "You haven't enrolled in a course yet.")) {
                            Button(L.t("تصفّح الدورات", "Browse courses")) { router.showCourses() }.buttonStyle(PrimaryStyle())
                        }
                    } else {
                        ScrollView {
                            // Courses in progress first, finished ones after.
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                                ForEach(list.sorted { ($0.progress?.isCompleted == true ? 1 : 0) < ($1.progress?.isCompleted == true ? 1 : 0) }) { c in
                                    CourseCard(course: c) { router.push(.course(c.id)) }
                                }
                            }
                            .padding(16)
                            .centered()
                        }
                        .refreshable { reload() }
                    }
                }
            }
        }
        .navBar(L.t("دوراتي", "My learning"))
    }
}

struct LessonView: View {
    let id: Int
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var done: Bool?
    @State private var saving = false
    @State private var note: String?

    var body: some View {
        Loader(key: id, load: { try await model.api.lesson(id) }) { lesson, _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let video = lesson.video {
                        Group {
                            if VideoLinks.playable(video) {
                                VideoBox(video: video)
                            } else {
                                ZStack {
                                    Color.black
                                    Button(L.t("شاهد الدرس من الموقع", "Watch on the website")) {
                                        router.push(.web(url: lesson.link, title: lesson.title, signedIn: true))
                                    }
                                    .buttonStyle(PrimaryStyle())
                                }
                            }
                        }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: p.radiusMd))
                    }
                    Text(lesson.title).font(AppFont.head(23)).foregroundStyle(p.text)

                    if session.user != nil {
                        if done ?? (lesson.isCompleted == true) {
                            Label(L.t("أنهيت الدرس ده", "You finished this lesson"), systemImage: "checkmark.circle.fill")
                                .font(AppFont.head(14)).foregroundStyle(p.turqText)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(Brand.turquoise.opacity(0.14)))
                        } else {
                            Button {
                                saving = true
                                Task {
                                    do {
                                        try await model.api.completeLesson(lesson.id)
                                        done = true
                                    } catch {
                                        note = ApiError.describe(error)
                                    }
                                    saving = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if saving { ProgressView().tint(p.buttonText) } else { Image(systemName: "checkmark.circle") }
                                    Text(L.t("خلّصت الدرس", "Mark as complete"))
                                }
                            }
                            .buttonStyle(PrimaryStyle())
                            .disabled(saving)
                        }
                    }

                    if let html = lesson.contentHtml, !html.isEmpty { HTMLText(html: html) }

                    if let files = lesson.attachments, !files.isEmpty {
                        Rectangle().fill(p.line).frame(height: 1)
                        Text(L.t("ملفات الدرس", "Lesson files")).font(AppFont.head(17)).foregroundStyle(p.text)
                        ForEach(files, id: \.url) { f in
                            Button { if let u = URL(string: f.url) { UIApplication.shared.open(u) } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "paperclip").foregroundStyle(p.cyanText).frame(width: 40, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(p.glass))
                                    VStack(alignment: .leading) {
                                        Text(f.title.isEmpty ? (f.url as NSString).lastPathComponent : f.title).font(AppFont.head(15)).foregroundStyle(p.text)
                                        Text([f.ext?.uppercased() ?? "", f.size ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(AppFont.body(13)).foregroundStyle(p.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.down.circle").foregroundStyle(p.cyanText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if lesson.previous != nil || lesson.next != nil {
                        Rectangle().fill(p.line).frame(height: 1)
                        HStack {
                            if let prev = lesson.previous {
                                Button { router.back(); router.open(ref: prev) } label: {
                                    Label(L.t("السابق", "Previous"), systemImage: "arrow.backward")
                                }
                                .buttonStyle(GhostStyle())
                            }
                            Spacer()
                            if let next = lesson.next {
                                Button { router.back(); router.open(ref: next) } label: {
                                    HStack(spacing: 8) {
                                        Text(next.type == "quiz" ? L.t("الاختبار التالي", "Next quiz") : L.t("الدرس التالي", "Next lesson"))
                                        Image(systemName: "arrow.forward")
                                    }
                                }
                                .buttonStyle(PrimaryStyle())
                            }
                        }
                    }
                }
                .padding(16)
                .centered(960)
            }
            .navBar(lesson.title)
        }
        .background(p.page.ignoresSafeArea())
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button(L.t("تمام", "OK"), role: .cancel) {}
        }
    }
}
