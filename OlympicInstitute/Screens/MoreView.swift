import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("lang") private var lang = "ar"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                profile.padding(16)

                section(L.t("خدمات", "Services"))
                row("checkmark.seal", L.t("التحقق من الشهادات", "Verify a certificate")) { router.push(.verify) }
                row("books.vertical", L.t("المكتبة", "Library"), L.t("كتب ومراجع للتحميل", "Books and references to download")) { router.push(.library) }
                row("newspaper", L.t("المقالات", "Articles")) { router.push(.articles) }
                row("person.wave.2", L.t("انضم كمحاضر", "Join as a lecturer")) { web(.becomeInstructor, L.t("انضم كمحاضر", "Join as a lecturer")) }

                section(L.t("عن المعهد", "About the institute"))
                row("person.3", L.t("المدربون والمحاضرون", "Instructors")) { router.push(.instructors) }
                row("star.bubble", L.t("آراء الدارسين", "Testimonials")) { router.push(.testimonials) }
                row("photo.on.rectangle", L.t("ألبوم الصور", "Photo album")) { router.push(.gallery) }
                row("info.circle", L.t("من نحن", "About us")) { web(.about, L.t("من نحن", "About us")) }
                row("building.columns", L.t("مجلس الإدارة", "Board of directors")) { web(.board, L.t("مجلس الإدارة", "Board of directors")) }
                row("hands.sparkles", L.t("الشراكات والاعتمادات", "Partnerships")) { web(.partnership, L.t("الشراكات", "Partnerships")) }
                row("wrench.and.screwdriver", L.t("خدماتنا", "Our services")) { web(.services, L.t("خدماتنا", "Our services")) }

                section(L.t("تواصل معنا", "Contact us"))
                row("message", L.t("واتساب", "WhatsApp"), "+\(Contact.whatsappNumber)") {
                    UIApplication.shared.open(Contact.whatsapp(L.t("السلام عليكم، أريد الاستفسار عن دورات المعهد.", "Hello, I'd like to ask about the institute's courses.")))
                }
                row("phone", L.t("اتصل بنا", "Call us"), Contact.phone) { open("tel:\(Contact.phone)") }
                row("envelope", L.t("البريد الإلكتروني", "Email"), Contact.email) { open("mailto:\(Contact.email)") }
                row("globe", "Facebook") { open(Contact.facebook) }
                row("bubble.left.and.bubble.right", "Messenger") { open(Contact.messenger) }
                row("camera", "Instagram") { open(Contact.instagram) }
                row("music.note", "TikTok") { open(Contact.tiktok) }

                section(L.t("الإعدادات", "Settings"))
                Menu {
                    Button("العربية") { lang = "ar" }
                    Button("English") { lang = "en" }
                } label: {
                    rowLabel("globe", L.t("اللغة", "Language"), lang == "ar" ? "العربية" : "English")
                }
                Menu {
                    Button(L.t("داكن (زي الموقع)", "Dark (like the website)")) { theme = "dark" }
                    Button(L.t("فاتح", "Light")) { theme = "light" }
                    Button(L.t("حسب الموبايل", "Follow system")) { theme = "system" }
                } label: {
                    rowLabel("circle.lefthalf.filled", L.t("المظهر", "Appearance"),
                             theme == "dark" ? L.t("داكن", "Dark") : theme == "light" ? L.t("فاتح", "Light") : L.t("حسب الموبايل", "Follow system"))
                }
                row("hand.raised", L.t("سياسة الخصوصية", "Privacy policy")) { web(.privacy, L.t("سياسة الخصوصية", "Privacy policy")) }
                row("arrow.uturn.backward.circle", L.t("سياسة الاسترداد", "Refund policy")) { web(.refund, L.t("سياسة الاسترداد", "Refund policy")) }
                if session.user != nil {
                    row("rectangle.portrait.and.arrow.right", L.t("تسجيل الخروج", "Sign out")) { Task { await model.api.logout() } }
                }
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                Text(L.t("المعهد الأوليمبي الدولي لعلوم الرياضة · الإصدار \(version)", "International Olympic Institute · version \(version)"))
                    .font(AppFont.body(12)).foregroundStyle(p.muted).padding(16)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navBar(L.t("المزيد", "More"))
    }

    @ViewBuilder
    private var profile: some View {
        if let u = session.user {
            HStack(spacing: 12) {
                RemoteImage(url: u.avatar).frame(width: 56, height: 56).clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(u.name).font(AppFont.head(17)).foregroundStyle(p.text)
                    Text(u.email).font(AppFont.body(13)).foregroundStyle(p.muted)
                }
                Spacer()
                Button(L.t("خروج", "Sign out")) { Task { await model.api.logout() } }.font(AppFont.head(14)).foregroundStyle(p.cyanText)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: p.radiusLg).fill(Brand.cyan.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(Brand.cyan.opacity(0.3), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("ادخل بحسابك", "Sign in to your account")).font(AppFont.head(17)).foregroundStyle(p.text)
                Text(L.t("علشان تتابع دروسك واختباراتك وشهاداتك.", "To follow your lessons, quizzes and certificates.")).font(AppFont.body(14)).foregroundStyle(p.textSoft)
                HStack(spacing: 8) {
                    Button(L.t("تسجيل الدخول", "Sign in")) { router.push(.login) }.buttonStyle(PrimaryStyle())
                    Button(L.t("حساب جديد", "New account")) { router.push(.register) }.buttonStyle(GhostStyle())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: p.radiusLg).fill(Brand.cyan.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: p.radiusLg).stroke(Brand.cyan.opacity(0.3), lineWidth: 1))
        }
    }

    private func section(_ title: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Brand.cyan).frame(width: 4, height: 20)
            Text(title).font(AppFont.head(17)).foregroundStyle(p.text)
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, title, subtitle) }.buttonStyle(.plain)
    }

    private func rowLabel(_ icon: String, _ title: String, _ subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(p.cyanText)
                .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12).fill(Brand.cyan.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AppFont.head(15, .semibold)).foregroundStyle(p.text)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(AppFont.body(13)).foregroundStyle(p.muted).environment(\.layoutDirection, .leftToRight) }
            }
            Spacer()
            Image(systemName: "chevron.forward").font(.system(size: 13)).foregroundStyle(p.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func web(_ page: SitePage, _ title: String) {
        router.push(.web(url: model.site.url(page), title: title, signedIn: false))
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { UIApplication.shared.open(u) }
    }
}
