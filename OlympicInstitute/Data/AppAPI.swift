import Foundation

/// The site's "Olympic App API" plugin (wp-json/oi-app/v1): sign-in, courses, lessons, quizzes.
struct AppAPI {
    let http: HTTP
    let session: Session

    private var base: String { http.siteURL + "/wp-json/oi-app/v1" }

    private struct SignInReply: Decodable {
        let token: String?
        let user: User?
        let verificationRequired: Bool?
        let message: String?
    }

    private var device: String { "iOS " + ProcessInfo.processInfo.operatingSystemVersionString }

    /* ---------- account ---------- */

    func login(_ login: String, _ password: String) async throws -> User {
        let data = try await http.postJSON(
            base + "/auth/login",
            ["login": login.trimmingCharacters(in: .whitespaces), "password": password, "device": device],
            auth: false
        )
        let reply = try http.decode(SignInReply.self, data)
        guard let token = reply.token, let user = reply.user else { throw ApiError(code: "bad_reply", message: "", status: 0) }
        await session.signIn(token: token, user: user)
        return user
    }

    func register(first: String, last: String, username: String, email: String, password: String, acceptTerms: Bool) async throws -> SignUpOutcome {
        let data = try await http.postJSON(base + "/auth/register", [
            "first_name": first, "last_name": last, "username": username, "email": email,
            "password": password, "accept_terms": acceptTerms, "device": device,
        ], auth: false)
        let reply = try http.decode(SignInReply.self, data)
        if reply.verificationRequired == true { return .verifyEmail(reply.message ?? "") }
        guard let token = reply.token, let user = reply.user else { throw ApiError(code: "bad_reply", message: "", status: 0) }
        await session.signIn(token: token, user: user)
        return .signedIn(user)
    }

    func logout() async {
        _ = try? await http.postJSON(base + "/auth/logout")
        await session.signOut()
    }

    /// A one-time link that opens `redirect` in the in-app browser already signed in.
    func webSession(_ redirect: String) async throws -> String {
        let data = try await http.postJSON(base + "/auth/web-session", ["redirect": redirect])
        struct Reply: Decodable { let url: String }
        return try http.decode(Reply.self, data).url
    }

    /* ---------- catalog ---------- */

    func categories() async throws -> [Category] {
        struct Reply: Decodable { let categories: [Category] }
        return try http.decode(Reply.self, try await http.get(base + "/categories")).categories
    }

    func courses() async throws -> [Course] {
        struct Reply: Decodable { let courses: [Course] }
        return try http.decode(Reply.self, try await http.get(base + "/courses")).courses
    }

    func course(_ id: Int) async throws -> Course {
        struct Reply: Decodable { let course: Course }
        return try http.decode(Reply.self, try await http.get(base + "/courses/\(id)")).course
    }

    /* ---------- learning ---------- */

    func myCourses() async throws -> [Course] {
        struct Reply: Decodable { let courses: [Course] }
        return try http.decode(Reply.self, try await http.get(base + "/my/courses")).courses
    }

    func enroll(_ courseId: Int) async throws {
        _ = try await http.postJSON(base + "/courses/\(courseId)/enroll")
        await session.changed()
    }

    func completeCourse(_ courseId: Int) async throws {
        _ = try await http.postJSON(base + "/courses/\(courseId)/complete")
        await session.changed()
    }

    func lesson(_ id: Int) async throws -> Lesson {
        struct Reply: Decodable { let lesson: Lesson }
        return try http.decode(Reply.self, try await http.get(base + "/lessons/\(id)")).lesson
    }

    func completeLesson(_ id: Int) async throws {
        _ = try await http.postJSON(base + "/lessons/\(id)/complete")
        await session.changed()
    }

    func quiz(_ id: Int) async throws -> QuizInfo {
        struct Reply: Decodable { let quiz: QuizInfo }
        return try http.decode(Reply.self, try await http.get(base + "/quizzes/\(id)")).quiz
    }

    func startQuiz(_ id: Int) async throws -> Attempt {
        struct Reply: Decodable { let attempt: Attempt }
        return try http.decode(Reply.self, try await http.postJSON(base + "/quizzes/\(id)/start")).attempt
    }

    func submitQuiz(attempt: Int, questionIds: [Int], answers: [Int: QuizAnswer]) async throws -> QuizResult {
        var map: [String: Any] = [:]
        for (qid, answer) in answers { map[String(qid)] = answer.json }
        let data = try await http.postJSON(base + "/quiz-attempts/\(attempt)/submit", ["question_ids": questionIds, "answers": map])
        let result = try http.decode(QuizResult.self, data)
        await session.changed()
        return result
    }
}
