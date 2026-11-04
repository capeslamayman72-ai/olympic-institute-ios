import SwiftSoup
import XCTest
@testable import OlympicInstitute

/// Reads replies recorded from the plugin and pages saved from the live site.
final class ParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let parts = name.split(separator: ".")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: String(parts[0]), withExtension: String(parts[1])), "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    private func page(_ name: String) throws -> Document {
        try SwiftSoup.parse(String(decoding: try fixture(name), as: UTF8.self), "https://olympic-institute.com/")
    }

    private struct CoursesReply: Decodable { let courses: [Course] }
    private struct CourseReply: Decodable { let course: Course }
    private struct LessonReply: Decodable { let lesson: Lesson }
    private struct QuizReply: Decodable { let quiz: QuizInfo }
    private struct AttemptReply: Decodable { let attempt: Attempt }

    func testCourseList() throws {
        let c = try HTTP.decoder.decode(CoursesReply.self, from: try fixture("courses.json")).courses[0]
        XCTAssertEqual(c.title, "المعد البدني و مخطط الاحمال")
        XCTAssertEqual(c.lessons, 3)
        XCTAssertEqual(c.quizzes, 2)
        XCTAssertEqual(c.duration?.hours, 40)
        XCTAssertEqual(c.category?.name, "اللياقة البدنية")
        XCTAssertTrue(c.enrolled)
        XCTAssertEqual(c.progress?.percent, 20)
        XCTAssertEqual(c.price?.current, 3500)
        XCTAssertEqual(c.price?.intl, 200)
        XCTAssertEqual(c.price?.discountPercent, 13)
        XCTAssertEqual(c.price?.saving, 500)
    }

    func testCoursePage() throws {
        let c = try HTTP.decoder.decode(CourseReply.self, from: try fixture("course.json")).course
        XCTAssertEqual(c.curriculum?.count, 2)
        XCTAssertEqual(c.curriculum?[0].items.map(\.type), ["lesson", "lesson", "quiz"])
        XCTAssertTrue(c.curriculum?[0].items[0].done ?? false)
        XCTAssertEqual(c.curriculum?[0].items[0].durationSeconds, 2520)
        XCTAssertEqual(c.introVideo?.kind, "youtube")
        XCTAssertEqual(c.reviews?.map(\.name), ["محمد عماد", "علي عبدالمجيد"])
        // The first lesson is done, so "continue" points at the second.
        XCTAssertEqual(c.nextItem?.id, c.curriculum?[0].items[1].id)
    }

    func testLessonQuizAndResult() throws {
        let l = try HTTP.decoder.decode(LessonReply.self, from: try fixture("lesson.json")).lesson
        XCTAssertEqual(l.video?.url, "https://youtu.be/aqz-KE-bpKQ")
        XCTAssertNil(l.previous)
        XCTAssertEqual(l.next?.type, "lesson")

        let q = try HTTP.decoder.decode(QuizReply.self, from: try fixture("quiz.json")).quiz
        XCTAssertEqual(q.timeLimitSeconds, 600)
        XCTAssertEqual(q.attemptsLeft, 2)
        XCTAssertTrue(q.drawnInApp)

        let a = try HTTP.decoder.decode(AttemptReply.self, from: try fixture("attempt.json")).attempt
        XCTAssertEqual(a.questions.map(\.type), ["single_choice", "multiple_choice", "true_false", "fill_in_the_blank"])
        XCTAssertEqual(a.questions[3].blanks, 2)
        XCTAssertFalse(String(decoding: try fixture("attempt.json"), as: UTF8.self).contains("is_correct"), "answer keys must not reach the app")

        let r = try HTTP.decoder.decode(QuizResult.self, from: try fixture("result.json"))
        XCTAssertEqual(r.result.percent, 50)
        XCTAssertEqual(r.result.passed, true)
        XCTAssertEqual(r.result.review.map(\.isCorrect), [true, false])
        XCTAssertEqual(r.result.review[1].correctAnswerIds, [4, 5])
    }

    func testErrorBody() throws {
        let e = HTTP.error(status: 404, body: try fixture("error.json"))
        XCTAssertEqual(e.code, "oi_app_not_found")
        XCTAssertEqual(e.message, "الدرس غير موجود.")
        XCTAssertEqual(HTTP.error(status: 502, body: Data("<html>bad gateway</html>".utf8)).code, "http_502")
    }

    func testThemePages() throws {
        let staff = Parse.instructors(try page("instructors.html"))
        XCTAssertGreaterThanOrEqual(staff.count, 10)
        XCTAssertEqual(staff[0].name, "ا.د/ ماجد مصطفى")
        XCTAssertEqual(staff[0].role, "المستشار العلمي")

        let reviews = Parse.reviews(try page("testimonials.html"))
        XCTAssertGreaterThanOrEqual(reviews.count, 20)
        XCTAssertEqual(reviews[0].name, "muhamademad")

        let photos = Parse.gallery(try page("gallery.html"))
        XCTAssertGreaterThanOrEqual(photos.count, 20)
        XCTAssertTrue(photos[0].full.hasSuffix("1-1-1.jpg"))

        let books = Parse.library(try page("library.html"))
        XCTAssertEqual(books.map(\.title), ["كتاب تاريخ تاكتيكات كرة القدم"])
        XCTAssertTrue(books[0].featured)

        let stats = Parse.stats(try page("home.html"))
        XCTAssertEqual(stats.count, 4)
        XCTAssertEqual(stats[3].value, "96%")
    }

    func testHomeSectionsInTheSiteOrder() throws {
        let sections = Parse.home(try page("home.html"))
        let kinds = sections.map { s -> String in
            switch s {
            case .hero: return "hero"
            case .stats: return "stats"
            case .courses: return "courses"
            case .tracks: return "tracks"
            case .features: return "features"
            case .album: return "album"
            case .library: return "library"
            case .instructors: return "instructors"
            case .testimonials: return "testimonials"
            case .cta: return "cta"
            }
        }
        XCTAssertEqual(kinds, ["hero", "stats", "courses", "tracks", "features", "album", "library", "instructors", "testimonials", "cta"])
        guard case let .hero(title, badge, _, primary, _, pills, images, _) = sections[0] else { return XCTFail("no hero") }
        XCTAssertEqual(title, "المعهد الاوليمبي الدولي لعلوم الرياضة")
        XCTAssertEqual(badge, "أول وأقوى منصة رخص تدريبية بالوطن العربي")
        XCTAssertEqual(primary?.url, "https://olympic-institute.com/courses/")
        XCTAssertEqual(pills.count, 3)
        XCTAssertGreaterThanOrEqual(images.count, 4)
        guard case let .courses(heading, _, links) = sections[2] else { return XCTFail("no courses") }
        XCTAssertEqual(heading.parts, [HeadingPart(text: "دبلومات وبرامج", accent: 0), HeadingPart(text: "متكاملة", accent: 1)])
        XCTAssertEqual(links.count, 9)
        guard case let .tracks(_, tracks) = sections[3] else { return XCTFail("no tracks") }
        XCTAssertEqual(tracks.map(\.categoryId), [83, 81, 82])
    }

    func testCertificateAndAssistant() throws {
        XCTAssertEqual(Parse.certificateNonce(String(decoding: try fixture("verify.html"), as: UTF8.self)), "b56be1847f")
        guard case .notFound = Parse.certificate(Data(#"{"success":false,"data":{"message":"x"}}"#.utf8)) else { return XCTFail() }
        guard case .found(let c) = Parse.certificate(Data(#"{"success":true,"data":{"certificate_number":"A-1","name_ar":"س"}}"#.utf8)) else { return XCTFail() }
        XCTAssertEqual(c.number, "A-1")

        let reply = Parse.chat(try fixture("chat.json"))
        XCTAssertTrue(reply.text.hasPrefix("عندنا 15 دورة"))
        XCTAssertEqual(reply.links.map(\.label), ["كل الدورات"])
    }

    func testArticles() throws {
        let posts = Parse.posts(try fixture("posts.json"))
        XCTAssertEqual(posts.count, 7)
        XCTAssertNotNil(posts[0].image)
        XCTAssertFalse(posts[0].title.contains("&#"))
    }

    func testFormattingAndVideoLinks() {
        XCTAssertEqual(Format.rating(4.85), "4.9")
        XCTAssertEqual(Format.rating(5), "5")
        XCTAssertEqual(Format.clock(3723), "1:02:03")
        XCTAssertEqual(Format.amount(2000), "2,000")
        for url in ["https://youtu.be/aqz-KE-bpKQ", "https://www.youtube.com/watch?feature=share&v=aqz-KE-bpKQ", "https://youtube.com/shorts/aqz-KE-bpKQ"] {
            XCTAssertEqual(VideoLinks.youtubeId(url), "aqz-KE-bpKQ", url)
        }
        XCTAssertEqual(VideoLinks.vimeoEmbed("https://vimeo.com/76979871/abc123"), "https://player.vimeo.com/video/76979871?h=abc123")
        XCTAssertNil(VideoLinks.vimeoEmbed("https://youtu.be/x"))
    }
}
