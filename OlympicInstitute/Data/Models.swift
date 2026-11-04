import Foundation

// Shapes of the "Olympic App API" plugin replies (wp-json/oi-app/v1). Keys arrive in snake_case and are
// decoded with .convertFromSnakeCase. Fields the plugin may leave out are optional so older plugin
// versions still decode.

struct User: Codable, Equatable {
    let id: Int
    let username: String
    let email: String
    let displayName: String
    let firstName: String?
    let lastName: String?
    let avatar: String?

    var name: String {
        let full = [firstName ?? "", lastName ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? displayName : full
    }
}

struct Category: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let count: Int?
}

struct Price: Codable, Hashable {
    let isFree: Bool?
    let productId: Int?
    let regular: Double?
    let sale: Double?
    let current: Double?
    let currency: String?
    let buyUrl: String?
    /// USD price for students outside Egypt (the theme's "لغير المصريين").
    let intl: Double?
    let intlOld: Double?

    var free: Bool { isFree == true || current == nil }

    var onSale: Bool {
        guard let sale, let regular else { return false }
        return sale < regular
    }

    /// Whole-number discount as the site rounds it ("خصم 13%").
    var discountPercent: Int? {
        guard onSale, let sale, let regular, regular > 0 else { return nil }
        return Int(((1 - sale / regular) * 100).rounded())
    }

    var saving: Double? {
        guard onSale, let sale, let regular else { return nil }
        return regular - sale
    }
}

struct Progress: Codable, Hashable {
    let percent: Int
    let completedItems: Int?
    let totalItems: Int?
    let isCompleted: Bool
}

struct Duration: Codable, Hashable {
    let hours: Int?
    let minutes: Int?
}

struct Counts: Codable, Hashable {
    let lessons: Int?
    let quizzes: Int?
    let assignments: Int?
}

struct Rating: Codable, Hashable {
    let average: Double
    let count: Int
}

struct Video: Codable, Hashable {
    /// youtube | vimeo | file | embed | web
    let kind: String
    let source: String?
    let url: String?
    let html: String?
    let poster: String?
    let durationSeconds: Int?
}

struct CurriculumItem: Codable, Identifiable, Hashable {
    let id: Int
    /// lesson | quiz | assignment | live | other
    let type: String
    let title: String
    let durationSeconds: Int?
    let isPreview: Bool?
    let isCompleted: Bool?
    let isLocked: Bool?
    let link: String

    var done: Bool { isCompleted == true }
    var locked: Bool { isLocked == true }
}

struct Topic: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let summary: String?
    let items: [CurriculumItem]
}

struct Person: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let title: String?
    let avatar: String?
}

struct Announcement: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let text: String
    let date: String?
}

struct CourseReview: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let rating: Double
    let text: String
}

/// A course card (from /courses) or a full course page (from /courses/{id}); page-only fields are optional.
struct Course: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let link: String
    let excerpt: String?
    let image: String?
    let categories: [Category]?
    let duration: Duration?
    let topicsCount: Int?
    let counts: Counts?
    let studentsCount: Int?
    let rating: Rating?
    let price: Price?
    let isEnrolled: Bool?
    let progress: Progress?

    let contentHtml: String?
    let benefits: [String]?
    let requirements: [String]?
    let audience: [String]?
    let introVideo: Video?
    let instructors: [Person]?
    let curriculum: [Topic]?
    let canComplete: Bool?
    let certificateUrl: String?
    let announcements: [Announcement]?
    let reviews: [CourseReview]?

    var enrolled: Bool { isEnrolled == true }
    var lessons: Int { counts?.lessons ?? 0 }
    var quizzes: Int { counts?.quizzes ?? 0 }
    var category: Category? { categories?.first }
    var items: [CurriculumItem] { (curriculum ?? []).flatMap(\.items) }

    /// Where "continue learning" goes: the first open item not done yet, else the first open item.
    var nextItem: CurriculumItem? {
        items.first { !$0.locked && !$0.done } ?? items.first { !$0.locked }
    }
}

struct ItemRef: Codable, Hashable {
    let id: Int
    let type: String
    let title: String
    let link: String
}

struct Attachment: Codable, Hashable {
    let title: String
    let url: String
    let size: String?
    let ext: String?
}

struct Lesson: Codable, Identifiable {
    let id: Int
    let courseId: Int
    let title: String
    let contentHtml: String?
    let video: Video?
    let attachments: [Attachment]?
    let isCompleted: Bool?
    let link: String
    let previous: ItemRef?
    let next: ItemRef?
}

struct AttemptSummary: Codable, Identifiable, Hashable {
    let id: Int
    /// attempt_started | attempt_ended | review_required | attempt_timeout
    let status: String
    let startedAt: String?
    let earnedMarks: Double
    let totalMarks: Double
    let percent: Double
    /// nil while the instructor has not reviewed written answers.
    let passed: Bool?
}

struct QuizInfo: Codable, Identifiable {
    let id: Int
    let courseId: Int
    let title: String
    let descriptionHtml: String?
    let timeLimitSeconds: Int
    let attemptsAllowed: Int
    let attemptsUsed: Int
    let passingGrade: Double
    let questionsCount: Int
    let feedbackMode: String?
    let native: Bool?
    let openAttemptId: Int?
    let attempts: [AttemptSummary]
    let link: String

    var attemptsLeft: Int? { attemptsAllowed > 0 ? max(0, attemptsAllowed - attemptsUsed) : nil }
    var canStart: Bool { openAttemptId != nil || attemptsLeft != 0 }
    var drawnInApp: Bool { native ?? true }
}

struct AnswerOption: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let image: String?
}

struct Question: Codable, Identifiable, Hashable {
    let id: Int
    /// true_false | single_choice | multiple_choice | open_ended | short_answer | fill_in_the_blank
    let type: String
    let title: String
    let descriptionHtml: String?
    let mark: Double?
    let required: Bool?
    let answers: [AnswerOption]
    let blankText: String?
    let blanks: Int?
}

struct Attempt: Codable, Identifiable {
    let id: Int
    let quizId: Int
    let timeLimitSeconds: Int
    let remainingSeconds: Int?
    let questions: [Question]
}

struct ReviewItem: Codable, Hashable {
    let questionId: Int
    let answered: Bool
    let isCorrect: Bool?
    let correctAnswerIds: [Int]?
}

struct QuizResultBody: Codable {
    let id: Int
    let status: String
    let earnedMarks: Double
    let totalMarks: Double
    let percent: Double
    let passed: Bool?
    let passingGrade: Double
    let review: [ReviewItem]
}

struct QuizResult: Codable {
    let result: QuizResultBody
    let progress: Progress?
}

/// What a quiz answer looks like on the wire: an answer id, ids, text, or the blanks in order.
enum QuizAnswer: Hashable {
    case choice(Int)
    case choices([Int])
    case text(String)
    case blanks([String])

    var json: Any {
        switch self {
        case .choice(let id): return id
        case .choices(let ids): return ids
        case .text(let s): return s
        case .blanks(let b): return b
        }
    }

    var isAnswered: Bool {
        switch self {
        case .choice: return true
        case .choices(let ids): return !ids.isEmpty
        case .text(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .blanks(let b): return b.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }
}

enum SignUpOutcome {
    case signedIn(User)
    case verifyEmail(String)
}

/* ---------- content read from the website's pages ---------- */

struct StaffMember: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let role: String
    let photo: String?
}

struct Review: Hashable, Identifiable {
    let id = UUID()
    let stars: Int
    let text: String
    let name: String
    let course: String
}

struct GalleryPhoto: Hashable, Identifiable {
    var id: String { full }
    let full: String
    let thumb: String
    let caption: String
}

struct Book: Hashable, Identifiable {
    var id: String { url }
    let title: String
    let cover: String?
    let url: String
    let meta: String
    let featured: Bool
}

struct Stat: Hashable {
    let value: String
    let label: String
}

struct Post: Hashable, Identifiable {
    let id: Int
    let title: String
    let date: String
    let excerpt: String
    let image: String?
    let link: String
    let contentHtml: String
}

struct Certificate: Hashable {
    let number: String
    let nameAr: String
    let nameEn: String
    let specialization: String
    let statement: String
}

enum CertificateCheck {
    case found(Certificate)
    case notFound(String)
}

struct ChatLink: Hashable {
    let label: String
    let url: String
    let kind: String
}

struct ChatChip: Hashable {
    let label: String
    let intent: String
    let q: String
}

struct ChatCard: Hashable {
    let title: String
    let url: String
    let price: String
    let meta: String
    let buy: String
}

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let fromUser: Bool
    let text: String
    var links: [ChatLink] = []
    var cards: [ChatCard] = []
    var chips: [ChatChip] = []
}

/* ---------- the website's home page ---------- */

/// A heading as the site writes it: plain words and accent-coloured words (cyan = 1, turquoise = 2).
struct Heading: Hashable {
    let eyebrow: String
    let parts: [HeadingPart]
    let intro: String
}

struct HeadingPart: Hashable {
    let text: String
    let accent: Int
}

struct SiteLink: Hashable {
    let label: String
    let url: String
}

struct Track: Hashable, Identifiable {
    var id: String { url }
    let categoryId: Int?
    let title: String
    let count: String
    let blurb: String
    let image: String?
    let url: String
}

struct Feature: Hashable, Identifiable {
    var id: String { title }
    let title: String
    let text: String
    let image: String?
}

struct Testimonial: Hashable, Identifiable {
    var id: String { name + text.prefix(20) }
    let text: String
    let name: String
    let role: String
}

/// Sections of the home page, in the site's order so the app follows any reordering on the site.
enum HomeSection: Hashable {
    case hero(title: String, badge: String, sub: String, primary: SiteLink?, secondary: SiteLink?, pills: [String], images: [String], emblem: String?)
    case stats([Stat])
    case courses(Heading, more: SiteLink?, links: [String])
    case tracks(Heading, [Track])
    case features(Heading, [Feature])
    case album(title: String, more: SiteLink?, photos: [GalleryPhoto])
    case library(title: String, text: String, button: SiteLink?)
    case instructors(Heading, more: SiteLink?, people: [StaffMember])
    case testimonials(Heading, [Testimonial])
    case cta(Heading, primary: SiteLink?, secondary: SiteLink?)
}
