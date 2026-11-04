import SwiftUI

/// Quizzes inside the app. The plugin creates and grades attempts with Tutor's own code, so results and
/// attempt limits match the website. Quizzes with ordering/matching/image questions open on the site.
struct QuizView: View {
    let id: Int
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var round = 0
    @State private var attempt: Attempt?
    @State private var result: QuizResult?
    @State private var starting = false
    @State private var note: String?

    var body: some View {
        Loader(key: "\(id)-\(round)", load: { try await model.api.quiz(id) }) { quiz, _ in
            Group {
                if let result, let attempt {
                    ResultView(result: result, attempt: attempt, quiz: quiz) {
                        self.result = nil
                        self.attempt = nil
                        round += 1
                    }
                } else if let attempt {
                    TakingView(attempt: attempt) { res in result = res }
                } else {
                    intro(quiz)
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .navBar(quiz.title)
            .navigationBarBackButtonHidden(attempt != nil && result == nil)
        }
        .background(p.page.ignoresSafeArea())
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button(L.t("تمام", "OK"), role: .cancel) {}
        }
    }

    private func intro(_ quiz: QuizInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(quiz.title).font(AppFont.head(23)).foregroundStyle(p.text)
                if let html = quiz.descriptionHtml, !html.isEmpty { HTMLText(html: html) }
                VStack(spacing: 10) {
                    fact(L.t("عدد الأسئلة", "Questions"), "\(quiz.questionsCount)")
                    fact(L.t("الوقت", "Time limit"), quiz.timeLimitSeconds > 0 ? Format.clock(quiz.timeLimitSeconds) : L.t("مفتوح", "No limit"))
                    fact(L.t("درجة النجاح", "Pass mark"), "\(Int(quiz.passingGrade))%")
                    fact(L.t("المحاولات", "Attempts"), quiz.attemptsAllowed > 0
                         ? L.t("\(quiz.attemptsUsed) من \(quiz.attemptsAllowed)", "\(quiz.attemptsUsed) of \(quiz.attemptsAllowed)")
                         : L.t("\(quiz.attemptsUsed) (غير محدودة)", "\(quiz.attemptsUsed) (unlimited)"))
                }
                .padding(16).siteCard()
                if !quiz.drawnInApp {
                    Text(L.t("الاختبار ده فيه أنواع أسئلة (ترتيب أو توصيل أو صور) بتتحل من صفحة الموقع جوه التطبيق.",
                             "This quiz has question types (ordering, matching, images) that are answered on the website page inside the app."))
                        .font(AppFont.body(14)).foregroundStyle(p.muted)
                }
                Button {
                    if !quiz.drawnInApp {
                        router.push(.web(url: quiz.link, title: quiz.title, signedIn: true))
                        return
                    }
                    starting = true
                    Task {
                        do { attempt = try await model.api.startQuiz(quiz.id) } catch { note = ApiError.describe(error) }
                        starting = false
                    }
                } label: {
                    if starting { ProgressView().tint(p.buttonText) } else { Text(Self.startLabel(quiz)) }
                }
                .buttonStyle(PrimaryStyle(full: true))
                .disabled(!quiz.canStart || starting)

                let finished = quiz.attempts.filter { $0.status != "attempt_started" }
                if !finished.isEmpty {
                    Text(L.t("محاولاتك السابقة", "Your previous attempts")).font(AppFont.head(17)).foregroundStyle(p.text).padding(.top, 8)
                    ForEach(Array(finished.enumerated()), id: \.element.id) { i, a in
                        HStack(spacing: 8) {
                            Text("\(finished.count - i).").font(AppFont.head(14)).foregroundStyle(p.text)
                            Text(String((a.startedAt ?? "").prefix(10))).font(AppFont.body(13)).foregroundStyle(p.muted)
                            Spacer()
                            Text("\(Self.fmt(a.percent))%").font(AppFont.head(14)).foregroundStyle(p.text)
                            StatusBadge(passed: a.passed, status: a.status)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(AppFont.body(15)).foregroundStyle(p.muted)
            Spacer()
            Text(value).font(AppFont.head(15)).foregroundStyle(p.text)
        }
    }

    static func startLabel(_ quiz: QuizInfo) -> String {
        if !quiz.drawnInApp { return L.t("افتح الاختبار", "Open the quiz") }
        if quiz.openAttemptId != nil { return L.t("كمّل المحاولة", "Resume attempt") }
        if !quiz.canStart { return L.t("خلصت المحاولات المسموحة", "No attempts left") }
        return L.t("ابدأ الاختبار", "Start the quiz")
    }

    static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

private struct StatusBadge: View {
    let passed: Bool?
    let status: String
    @Environment(\.palette) private var p

    var body: some View {
        let (text, color): (String, Color) = {
            if status == "attempt_timeout" { return (L.t("انتهى الوقت", "Timed out"), p.sale) }
            switch passed {
            case nil: return (L.t("قيد المراجعة", "In review"), p.cyanText)
            case true?: return (L.t("ناجح", "Passed"), p.turqText)
            case false?: return (L.t("لم ينجح", "Not passed"), p.sale)
            }
        }()
        Text(text).font(AppFont.head(12)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
    }
}

/// Tutor stores true/false options as the words "True"/"False".
private func optionTitle(_ title: String) -> String {
    switch title.trimmingCharacters(in: .whitespaces).lowercased() {
    case "true": return L.t("صح", "True")
    case "false": return L.t("خطأ", "False")
    default: return title
    }
}

private struct TakingView: View {
    let attempt: Attempt
    let finished: (QuizResult) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @State private var answers: [Int: QuizAnswer] = [:]
    @State private var remaining: Int?
    @State private var sending = false
    @State private var confirm = false
    @State private var note: String?

    var body: some View {
        let done = attempt.questions.filter { answers[$0.id]?.isAnswered == true }.count
        VStack(spacing: 0) {
            HStack {
                Text(L.t("أجبت \(done) من \(attempt.questions.count)", "Answered \(done) of \(attempt.questions.count)")).font(AppFont.head(14))
                Spacer()
                if let remaining {
                    Label(Format.clock(remaining), systemImage: "timer").font(AppFont.head(14))
                        .foregroundStyle(remaining < 60 ? p.sale : p.text)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .foregroundStyle(p.text)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Brand.cyan.opacity(0.14))

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(attempt.questions.enumerated()), id: \.element.id) { i, q in
                        QuestionCard(question: q, number: i + 1, answer: Binding(get: { answers[q.id] }, set: { answers[q.id] = $0 }))
                    }
                }
                .padding(16)
            }

            VStack(spacing: 0) {
                Rectangle().fill(p.line).frame(height: 1)
                Button {
                    if done < attempt.questions.count { confirm = true } else { submit() }
                } label: {
                    if sending { ProgressView().tint(p.buttonText) } else { Text(L.t("سلّم الإجابات", "Submit answers")) }
                }
                .buttonStyle(PrimaryStyle(full: true))
                .disabled(sending)
                .padding(16)
            }
            .background(p.elevated)
        }
        .onAppear { remaining = attempt.remainingSeconds }
        .task(id: attempt.id) {
            // The clock comes from the server, so reopening an attempt keeps the time already used.
            guard attempt.remainingSeconds != nil else { return }
            while let r = remaining, r > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining = r - 1
            }
            submit()
        }
        .confirmationDialog(L.t("فيه أسئلة من غير إجابة", "Some questions are unanswered"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L.t("سلّم", "Submit")) { submit() }
            Button(L.t("ارجع للأسئلة", "Back to questions"), role: .cancel) {}
        } message: {
            Text(L.t("لو سلّمت دلوقتي، الأسئلة دي هتتحسب غلط.", "Unanswered questions count as wrong."))
        }
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button(L.t("تمام", "OK"), role: .cancel) {}
        }
    }

    private func submit() {
        guard !sending else { return }
        sending = true
        Task {
            do {
                let picked = answers.filter { $0.value.isAnswered }
                finished(try await model.api.submitQuiz(attempt: attempt.id, questionIds: attempt.questions.map(\.id), answers: picked))
            } catch {
                note = ApiError.describe(error)
            }
            sending = false
        }
    }
}

private struct QuestionCard: View {
    let question: Question
    let number: Int
    @Binding var answer: QuizAnswer?
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)").font(AppFont.head(13)).foregroundStyle(p.buttonText)
                    .frame(width: 26, height: 26).background(Circle().fill(p.buttonFill))
                Text(question.title).font(AppFont.head(16)).foregroundStyle(p.text)
            }
            if let html = question.descriptionHtml, !html.isEmpty { HTMLText(html: html) }
            switch question.type {
            case "true_false", "single_choice":
                ForEach(question.answers) { a in
                    choice(optionTitle(a.title), selected: answer == .choice(a.id), multiple: false) { answer = .choice(a.id) }
                }
            case "multiple_choice":
                let chosen: [Int] = { if case .choices(let ids) = answer { return ids } else { return [] } }()
                ForEach(question.answers) { a in
                    choice(optionTitle(a.title), selected: chosen.contains(a.id), multiple: true) {
                        let next = chosen.contains(a.id) ? chosen.filter { $0 != a.id } : chosen + [a.id]
                        answer = next.isEmpty ? nil : .choices(next)
                    }
                }
            case "fill_in_the_blank":
                let count = max(question.blanks ?? 1, 1)
                let parts = (question.blankText ?? "").components(separatedBy: "{dash}")
                Text(parts.enumerated().map { i, s in i < parts.count - 1 ? s + " ____(\(i + 1)) " : s }.joined())
                    .font(AppFont.body(16)).foregroundStyle(p.textSoft)
                let blanks: [String] = { if case .blanks(let b) = answer { return b } else { return Array(repeating: "", count: count) } }()
                ForEach(0..<count, id: \.self) { i in
                    TextField(L.t("الفراغ \(i + 1)", "Blank \(i + 1)"), text: Binding(
                        get: { i < blanks.count ? blanks[i] : "" },
                        set: { v in
                            var next = blanks
                            while next.count < count { next.append("") }
                            next[i] = v
                            answer = .blanks(next)
                        }
                    ))
                    .font(AppFont.body(16))
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(p.page))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.line, lineWidth: 1))
                }
            default:
                let text: String = { if case .text(let s) = answer { return s } else { return "" } }()
                TextField(L.t("اكتب إجابتك", "Write your answer"), text: Binding(get: { text }, set: { answer = .text($0) }), axis: .vertical)
                    .lineLimit(question.type == "open_ended" ? 4...8 : 1...3)
                    .font(AppFont.body(16))
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(p.page))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.line, lineWidth: 1))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .siteCard()
    }

    private func choice(_ title: String, selected: Bool, multiple: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Image(systemName: multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 20)).foregroundStyle(selected ? p.cyanText : p.muted)
                    .accessibilityHidden(true)
                Text(title).font(AppFont.body(16)).foregroundStyle(p.text)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Brand.cyan.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ResultView: View {
    let result: QuizResult
    let attempt: Attempt
    let quiz: QuizInfo
    let again: () -> Void
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        let r = result.result
        let color: Color = r.passed == true ? p.turqText : r.passed == false ? p.sale : p.cyanText
        let left = quiz.attemptsLeft.map { $0 - 1 }
        let headline: String = Self.headline(r)
        ScrollView {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(p.glass, lineWidth: 10)
                    Circle().trim(from: 0, to: min(max(r.percent / 100, 0), 1)).stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(QuizView.fmt(r.percent))%").font(AppFont.head(30)).foregroundStyle(color)
                }
                .frame(width: 140, height: 140)
                Text(headline)
                    .font(AppFont.head(17)).foregroundStyle(p.text).multilineTextAlignment(.center)
                Text(L.t("الدرجة: \(QuizView.fmt(r.earnedMarks)) من \(QuizView.fmt(r.totalMarks))", "Score: \(QuizView.fmt(r.earnedMarks)) of \(QuizView.fmt(r.totalMarks))"))
                    .font(AppFont.body(15)).foregroundStyle(p.muted)
                HStack(spacing: 10) {
                    Button(L.t("رجوع للدورة", "Back to course")) { router.back() }.buttonStyle(PrimaryStyle(full: true))
                    if r.passed != true && left != 0 {
                        Button(L.t("محاولة تانية", "Try again"), action: again).buttonStyle(GhostStyle(full: true))
                    }
                }
                if !r.review.isEmpty {
                    Rectangle().fill(p.line).frame(height: 1)
                    Text(L.t("مراجعة الإجابات", "Answer review")).font(AppFont.head(17)).foregroundStyle(p.text).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(r.review.enumerated()), id: \.offset) { i, item in
                        if let q = attempt.questions.first(where: { $0.id == item.questionId }) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.isCorrect == true ? "checkmark.circle" : item.isCorrect == false ? "xmark.circle" : "hourglass")
                                    .foregroundStyle(item.isCorrect == true ? p.turqText : item.isCorrect == false ? p.sale : p.cyanText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(i + 1). \(q.title)").font(AppFont.body(15)).foregroundStyle(p.text)
                                    let correct = (item.correctAnswerIds ?? []).compactMap { id in q.answers.first { $0.id == id }.map { optionTitle($0.title) } }
                                    if item.isCorrect == false && !correct.isEmpty {
                                        Text(L.t("الصح: ", "Correct: ") + correct.joined(separator: L.t("، ", ", "))).font(AppFont.body(13)).foregroundStyle(p.turqText)
                                    }
                                    if !item.answered { Text(L.t("لم تُجب", "Not answered")).font(AppFont.body(13)).foregroundStyle(p.muted) }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    static func headline(_ r: QuizResultBody) -> String {
        switch r.passed {
        case true?: return L.t("مبروك! نجحت في الاختبار", "Well done! You passed")
        case false?:
            let mark = Int(r.passingGrade)
            return L.t("لم تصل لدرجة النجاح (\(mark)%)", "Below the pass mark (\(mark)%)")
        case nil: return L.t("إجاباتك المكتوبة هتتراجع من المحاضر وهتظهر النتيجة بعدها", "Your written answers will be reviewed by the instructor")
        }
    }
}
