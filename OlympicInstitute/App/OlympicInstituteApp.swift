import SwiftUI

/// Everything screens talk to, created once.
@MainActor
final class AppModel: ObservableObject {
    let session = Session()
    let http: HTTP
    let api: AppAPI
    let site: SiteAPI

    /// Last course list, so links from the site or the assistant can open the course screen.
    @Published var knownCourses: [Course] = []
    /// The assistant conversation lives for the app session, like the website keeps it per tab.
    @Published var chat: [ChatMessage] = []
    @Published var knownPosts: [Post] = []

    init() {
        var siteURL = "https://olympic-institute.com"
        #if DEBUG
        // UI tests point the app at their local stand-in for the website.
        if let override = ProcessInfo.processInfo.environment["OI_SITE_URL"], !override.isEmpty { siteURL = override }
        if ProcessInfo.processInfo.arguments.contains("-reset") {
            Keychain.set("token", nil)
            UserDefaults.standard.removeObject(forKey: "user")
        }
        #endif
        http = HTTP(siteURL: siteURL, session: session)
        api = AppAPI(http: http, session: session)
        site = SiteAPI(http: http)
    }

    func courses() async throws -> [Course] {
        let list = try await api.courses()
        knownCourses = list
        return list
    }

    func courseId(forLink url: String) -> Int? {
        func norm(_ u: String) -> String {
            String(u.split(separator: "?").first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        return knownCourses.first { norm($0.link) == norm(url) }?.id
    }
}

enum Tab: Hashable { case home, courses, learning, assistant, more }

/// Screens pushed on top of a tab.
enum Route: Hashable {
    case course(Int)
    case lesson(Int)
    case quiz(Int)
    case web(url: String, title: String, signedIn: Bool)
    case login, register, verify, instructors, testimonials, gallery, library, articles
    case article(Int)
}

/// Every way a screen moves to another one.
@MainActor
final class Router: ObservableObject {
    @Published var tab: Tab = .home
    @Published var paths: [Tab: NavigationPath] = [.home: NavigationPath(), .courses: NavigationPath(), .learning: NavigationPath(), .assistant: NavigationPath(), .more: NavigationPath()]
    /// The track the courses tab is filtered by (set when a track card or category link is opened).
    @Published var coursesCategory: Int?

    weak var model: AppModel?

    func push(_ route: Route) { paths[tab, default: NavigationPath()].append(route) }

    func back() {
        if !(paths[tab]?.isEmpty ?? true) { paths[tab]?.removeLast() }
    }

    /// Leaves the sign-in screens, back to whatever asked for an account.
    func afterSignIn() {
        var path = paths[tab] ?? NavigationPath()
        if path.count > 0 { path.removeLast() }
        paths[tab] = path
    }

    func showCourses(category: Int? = nil) {
        coursesCategory = category
        tab = .courses
        paths[.courses] = NavigationPath()
    }

    func open(item: CurriculumItem) {
        switch item.type {
        case "lesson": push(.lesson(item.id))
        case "quiz": push(.quiz(item.id))
        default: push(.web(url: item.link, title: item.title, signedIn: true))
        }
    }

    func open(ref: ItemRef) {
        switch ref.type {
        case "lesson": push(.lesson(ref.id))
        case "quiz": push(.quiz(ref.id))
        default: push(.web(url: ref.link, title: ref.title, signedIn: true))
        }
    }

    /// Follows a link taken from the website: pages the app draws natively open their screen, other site
    /// pages open inside the app, anything else (WhatsApp, phone, other sites) leaves the app.
    func site(_ url: String, label: String) {
        guard let model else { return }
        let base = model.http.siteURL
        let full = url.hasPrefix("/") ? base + url : url
        guard full.hasPrefix(base), let comps = URLComponents(string: full) else {
            if let u = URL(string: full) { UIApplication.shared.open(u) }
            return
        }
        let path = comps.percentEncodedPath.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let slash = "/" + path + (path.isEmpty ? "" : "/")
        let query = comps.queryItems ?? []
        if let cat = query.first(where: { $0.name == "tutor-course-filter-category" })?.value.flatMap(Int.init) {
            showCourses(category: cat)
            return
        }
        let pages: [(SitePage, Route)] = [(.instructors, .instructors), (.testimonials, .testimonials), (.gallery, .gallery), (.library, .library), (.verify, .verify)]
        if slash == "/courses/" || slash == "/en-courses/" {
            showCourses()
        } else if slash == "/login/" {
            push(query.contains { $0.name == "tab" && $0.value == "register" } ? .register : .login)
        } else if let hit = pages.first(where: { slash == $0.0.paths.ar.lowercased() || slash == $0.0.paths.en.lowercased() }) {
            push(hit.1)
        } else if let id = model.courseId(forLink: full) {
            push(.course(id))
        } else {
            push(.web(url: full, title: label, signedIn: false))
        }
    }
}

@main
struct OlympicInstituteApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environmentObject(model)
                .environmentObject(model.session)
                .environmentObject(router)
                .onAppear { router.model = model }
        }
    }
}

/// Applies the student's theme (dark by default, like the website) and language around the whole app.
struct ThemedRoot: View {
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("lang") private var lang = "ar"
    @Environment(\.colorScheme) private var system

    var body: some View {
        let dark = theme == "dark" || (theme == "system" && system == .dark)
        RootView()
            .environment(\.palette, dark ? .dark : .light)
            .environment(\.layoutDirection, lang == "ar" ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: lang))
            .preferredColorScheme(theme == "system" ? nil : (dark ? .dark : .light))
            .tint(dark ? Brand.cyan : Brand.navy)
            .id(lang)
    }
}

struct RootView: View {
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        TabView(selection: $router.tab) {
            stack(.home) { HomeView() }
                .tabItem { Label(L.t("الرئيسية", "Home"), systemImage: "house") }
                .tag(Tab.home)
            stack(.courses) { CoursesView() }
                .tabItem { Label(L.t("الدورات", "Courses"), systemImage: "graduationcap") }
                .tag(Tab.courses)
            stack(.learning) { LearningView() }
                .tabItem { Label(L.t("دوراتي", "My learning"), systemImage: "books.vertical") }
                .tag(Tab.learning)
            stack(.assistant) { AssistantView() }
                .tabItem { Label(L.t("المساعد", "Assistant"), systemImage: "message") }
                .tag(Tab.assistant)
            stack(.more) { MoreView() }
                .tabItem { Label(L.t("المزيد", "More"), systemImage: "square.grid.2x2") }
                .tag(Tab.more)
        }
    }

    private func stack<Content: View>(_ tab: Tab, @ViewBuilder _ root: () -> Content) -> some View {
        NavigationStack(path: Binding(get: { router.paths[tab] ?? NavigationPath() }, set: { router.paths[tab] = $0 })) {
            root()
                .navigationDestination(for: Route.self) { route in destination(route) }
        }
        .background(p.page.ignoresSafeArea())
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .course(let id): CourseView(id: id)
        case .lesson(let id): LessonView(id: id)
        case .quiz(let id): QuizView(id: id)
        case .web(let url, let title, let signed): WebPageView(url: url, title: title, signedIn: signed)
        case .login: LoginView()
        case .register: RegisterView()
        case .verify: VerifyView()
        case .instructors: InstructorsView()
        case .testimonials: TestimonialsView()
        case .gallery: GalleryView()
        case .library: LibraryView()
        case .articles: ArticlesView()
        case .article(let id): ArticleView(id: id)
        }
    }
}
