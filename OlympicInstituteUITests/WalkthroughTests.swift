import UIKit
import XCTest

/// Walks the app against `StubServer` and keeps a screenshot of each screen (exported by the CI build).
/// It also checks the main flows hold together: browse, sign in, a lesson, a quiz, the assistant, a certificate.
final class WalkthroughTests: XCTestCase {
    private var server: StubServer!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = try StubServer()
        server.start()
        app = XCUIApplication()
        app.launchEnvironment["OI_SITE_URL"] = server.base
        app.launchArguments = ["-reset"]
        app.launch()
    }

    override func tearDown() {
        server.stop()
    }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "\(device)-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @discardableResult
    private func waitFor(_ text: String, timeout: TimeInterval = 25) -> XCUIElement {
        let e = element(containing: text)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "never showed: \(text)")
        return e
    }

    /// Scrolls until the element can be tapped (lists only build what is on screen), then clear of the sticky
    /// bottom bar, and waits for the scrolling to stop: a tap while the page still glides only stops it.
    private func reveal(_ e: XCUIElement, clearBottom: Bool = true) {
        var tries = 0
        while (!e.exists || !e.isHittable) && tries < 12 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.0)
            tries += 1
        }
        tries = 0
        while clearBottom && e.exists && e.frame.maxY > app.frame.maxY - 220 && tries < 4 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            Thread.sleep(forTimeInterval: 1.0)
            tries += 1
        }
    }

    /// `clearBottom: false` for buttons that live in a bottom bar or a sheet, which a drag would move or dismiss.
    private func tapButton(_ text: String, exact: Bool = false, clearBottom: Bool = true) {
        let query = exact ? app.buttons.matching(NSPredicate(format: "label == %@", text)) : app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text))
        let b = query.firstMatch
        if !b.waitForExistence(timeout: 5) { reveal(b, clearBottom: clearBottom) }
        XCTAssertTrue(b.waitForExistence(timeout: 20), "no button: \(text)")
        reveal(b, clearBottom: clearBottom)
        b.tap()
    }

    private func tab(_ label: String) {
        let inBar = app.tabBars.buttons[label]
        if inBar.exists { inBar.tap() } else { tapButton(label, exact: true) }
    }

    func testHomeAndCourses() {
        waitFor("منصتك لعالم الاحتراف")
        shot("01-home")
        app.swipeUp()
        shot("02-home-stats-courses")
        app.swipeUp()
        app.swipeUp()
        shot("03-home-tracks")
        app.swipeUp()
        app.swipeUp()
        shot("04-home-why")

        tab("الدورات")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 20))
        waitFor("المعد البدني و مخطط الاحمال")
        shot("05-courses")

        tapButton("المعد البدني و مخطط الاحمال")
        waitFor("ستتعلّم")
        shot("06-course")
        app.swipeUp()
        app.swipeUp()
        shot("07-course-curriculum")
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        shot("08-course-buy")
    }

    func testStudentFlow() {
        waitFor("منصتك لعالم الاحتراف")
        tab("دوراتي")
        tapButton("تسجيل الدخول")
        let login = app.textFields.firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 20))
        shot("10-login")
        login.tap()
        login.typeText("student1")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("secret12")
        tapButton("دخول", exact: true)
        waitFor("تقدّمك")
        shot("11-my-learning")
        XCTAssertTrue(server.requests.contains { $0.hasPrefix("POST /wp-json/oi-app/v1/auth/login") })

        tapButton("المعد البدني و مخطط الاحمال")
        waitFor("كمّل التعلّم")
        shot("12-course-enrolled")
        tapButton("مكونات اللياقة البدنية جــ1")
        waitFor("خلّصت الدرس")
        shot("13-lesson")
        tapButton("خلّصت الدرس")
        waitFor("أنهيت الدرس ده")
        app.navigationBars.buttons.firstMatch.tap()

        tapButton("اختبار الاعداد البدني")
        waitFor("ابدأ الاختبار")
        shot("14-quiz-intro")
        tapButton("ابدأ الاختبار")
        waitFor("أجبت 0 من 4")
        tapButton("القوة", exact: true)
        tapButton("صح", exact: true)
        waitFor("أجبت 2 من 4")
        shot("15-quiz-taking")
        tapButton("سلّم الإجابات", clearBottom: false)
        tapButton("سلّم", exact: true, clearBottom: false)
        waitFor("مبروك! نجحت في الاختبار")
        shot("16-quiz-result")
        XCTAssertTrue(server.requests.contains { $0.hasPrefix("POST /wp-json/oi-app/v1/quiz-attempts/") })
    }

    func testAssistantAndMore() {
        waitFor("منصتك لعالم الاحتراف")
        tab("المساعد")
        waitFor("الدورات والأسعار")
        shot("20-assistant")
        tapButton("الدورات والأسعار")
        waitFor("عندنا 15 دورة")
        shot("21-assistant-answer")

        tab("المزيد")
        waitFor("التحقق من الشهادات")
        shot("22-more")
        tapButton("التحقق من الشهادات")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("OI-2026-0412")
        tapButton("تحقّق", exact: true)
        waitFor("شهادة موثّقة")
        shot("23-verify")
        app.navigationBars.buttons.firstMatch.tap()

        tapButton("المدربون والمحاضرون")
        waitFor("المستشار العلمي")
        shot("24-instructors")
        app.navigationBars.buttons.firstMatch.tap()
        tapButton("المكتبة", exact: false)
        waitFor("كتاب تاريخ تاكتيكات كرة القدم")
        shot("25-library")
    }
}
