import SwiftUI

private struct FieldBox<Content: View>: View {
    let error: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
                .font(AppFont.body(16))
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(p.glass))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(error == nil ? p.line : p.sale, lineWidth: 1))
            if let error { Text(error).font(AppFont.body(13)).foregroundStyle(p.sale) }
        }
    }
}

private struct PasswordField: View {
    let title: String
    @Binding var text: String
    var error: String?
    @State private var shown = false
    @Environment(\.palette) private var p

    var body: some View {
        FieldBox(error: error) {
            HStack {
                Group {
                    if shown { TextField(title, text: $text) } else { SecureField(title, text: $text) }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { shown.toggle() } label: { Image(systemName: shown ? "eye.slash" : "eye").foregroundStyle(p.muted) }
                    .accessibilityLabel(L.t("إظهار كلمة المرور", "Show password"))
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var login = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96)
                Text(L.t("أهلاً بيك في المعهد الأوليمبي", "Welcome to the Olympic Institute")).font(AppFont.head(22)).foregroundStyle(p.text).multilineTextAlignment(.center)
                Text(L.t("ادخل بنفس حساب الموقع.", "Use your website account.")).font(AppFont.body(15)).foregroundStyle(p.muted)
                FieldBox(error: nil) {
                    TextField(L.t("البريد الإلكتروني أو اسم المستخدم", "Email or username"), text: $login)
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                PasswordField(title: L.t("كلمة المرور", "Password"), text: $password)
                if let error { Text(error).font(AppFont.body(15)).foregroundStyle(p.sale).multilineTextAlignment(.center) }
                Button(action: submit) {
                    if busy { ProgressView().tint(p.buttonText) } else { Text(L.t("دخول", "Sign in")) }
                }
                .buttonStyle(PrimaryStyle(full: true))
                .disabled(busy || login.isEmpty || password.isEmpty)
                Button(L.t("نسيت كلمة المرور؟", "Forgot your password?")) {
                    router.push(.web(url: model.site.url(.lostPassword), title: L.t("استعادة كلمة المرور", "Reset password"), signedIn: false))
                }
                .font(AppFont.head(14)).foregroundStyle(p.cyanText)
                HStack(spacing: 6) {
                    Text(L.t("معندكش حساب؟", "No account yet?")).font(AppFont.body(15)).foregroundStyle(p.text)
                    Button(L.t("سجّل دلوقتي", "Create one")) { router.push(.register) }.font(AppFont.head(15)).foregroundStyle(p.cyanText)
                }
                Text(L.t(
                    "لو كنت بتدخل الموقع بحساب جوجل أو فيسبوك: اعمل كلمة مرور من «نسيت كلمة المرور» بنفس بريدك، وادخل بيها هنا.",
                    "If you sign in to the website with Google or Facebook, set a password via “Forgot your password?” using the same email, then use it here."
                ))
                .font(AppFont.body(13)).foregroundStyle(p.muted).multilineTextAlignment(.center).padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navBar(L.t("تسجيل الدخول", "Sign in"))
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                _ = try await model.api.login(login, password)
                router.afterSignIn()
            } catch {
                self.error = ApiError.describe(error)
            }
            busy = false
        }
    }
}

struct RegisterView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var first = ""
    @State private var last = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var terms = false
    @State private var busy = false
    @State private var error: String?
    @State private var fields: [String: String] = [:]
    @State private var verify: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    FieldBox(error: fields["first_name"]) { TextField(L.t("الاسم الأول", "First name"), text: $first).textContentType(.givenName) }
                    FieldBox(error: fields["last_name"]) { TextField(L.t("الاسم الأخير", "Last name"), text: $last).textContentType(.familyName) }
                }
                FieldBox(error: fields["user_login"]) {
                    TextField(L.t("اسم المستخدم (بالإنجليزي)", "Username"), text: $username).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                FieldBox(error: fields["email"]) {
                    TextField(L.t("البريد الإلكتروني", "Email"), text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                PasswordField(title: L.t("كلمة المرور", "Password"), text: $password, error: fields["password"])
                PasswordField(title: L.t("تأكيد كلمة المرور", "Confirm password"), text: $confirm, error: fields["password_confirmation"])
                Toggle(isOn: $terms) {
                    HStack(spacing: 4) {
                        Text(L.t("أوافق على الشروط و", "I accept the terms and")).font(AppFont.body(15))
                        Button(L.t("سياسة الخصوصية", "privacy policy")) {
                            router.push(.web(url: model.site.url(.privacy), title: L.t("سياسة الخصوصية", "Privacy policy"), signedIn: false))
                        }
                        .font(AppFont.head(15)).foregroundStyle(p.cyanText)
                    }
                }
                .toggleStyle(.switch).tint(Brand.cyan)
                if let e = fields["accept_terms"] { Text(e).font(AppFont.body(13)).foregroundStyle(p.sale) }
                if let error { Text(error).font(AppFont.body(15)).foregroundStyle(p.sale) }
                Button(action: submit) {
                    if busy { ProgressView().tint(p.buttonText) } else { Text(L.t("إنشاء الحساب", "Create account")) }
                }
                .buttonStyle(PrimaryStyle(full: true))
                .disabled(busy)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navBar(L.t("إنشاء حساب", "Create account"))
        .alert(L.t("فعّل حسابك", "Activate your account"), isPresented: Binding(get: { verify != nil }, set: { if !$0 { verify = nil } })) {
            Button(L.t("تمام", "OK")) { router.back() }
        } message: { Text(verify ?? "") }
    }

    private func submit() {
        var local: [String: String] = [:]
        let required = L.t("مطلوب", "Required")
        if first.trimmingCharacters(in: .whitespaces).isEmpty { local["first_name"] = required }
        if last.trimmingCharacters(in: .whitespaces).isEmpty { local["last_name"] = required }
        if username.trimmingCharacters(in: .whitespaces).isEmpty { local["user_login"] = required }
        if email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil { local["email"] = L.t("بريد غير صحيح", "Invalid email") }
        if password.count < 6 { local["password"] = L.t("6 حروف على الأقل", "At least 6 characters") }
        if confirm != password { local["password_confirmation"] = L.t("كلمتا المرور مش متطابقتين", "Passwords don't match") }
        if !terms { local["accept_terms"] = L.t("لازم توافق على الشروط", "Please accept the terms") }
        fields = local
        guard local.isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                switch try await model.api.register(first: first, last: last, username: username, email: email, password: password, acceptTerms: terms) {
                case .signedIn:
                    // Back past the sign-in screen too, to whatever asked for an account.
                    router.afterSignIn()
                    router.afterSignIn()
                case .verifyEmail(let message):
                    verify = message
                }
            } catch let e as ApiError {
                fields = e.fields
                error = e.friendly
            } catch {
                self.error = ApiError.describe(error)
            }
            busy = false
        }
    }
}
