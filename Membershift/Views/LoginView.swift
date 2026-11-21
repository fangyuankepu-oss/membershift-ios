import SwiftUI

/// Login screen, aligned with Android `MainActivity` / WebView `#loginView`:
/// username + password, language switcher, default-account hint.
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var selectedLanguage: AppLanguage

    init() {
        _selectedLanguage = State(initialValue: L10n.current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                // Logo: deep-green rounded square with a white M
                // (matches the Membershift logo: filled green square,
                // hollow white M cut-out).
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Brand.deepGreen)
                        .frame(width: 88, height: 88)
                    Text("M")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 40)

                Text(L10n.string("app_name"))
                    .font(.title2)
                    .bold()
                Text(L10n.string("login_title"))
                    .foregroundColor(.secondary)

                VStack(spacing: 12) {
                    TextField(L10n.string("login_username"), text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(L10n.string("login_password"), text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }

                Button(L10n.string("login_button")) { login() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.deepGreen)
                    .disabled(username.isEmpty || password.isEmpty)

                VStack(spacing: 4) {
                    Text(L10n.string("login_hint"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text(L10n.string("login_hint2"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Picker(L10n.string("login_language"), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedLanguage) { newValue in
                    appState.language = newValue
                }

                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func login() {
        if let user = Auth.verify(username: username, password: password, db: Database.shared) {
            errorMessage = nil
            appState.currentUser = user
        } else {
            errorMessage = L10n.string("login_error")
        }
    }
}
