import SwiftUI

struct SignInView: View {
    @Environment(Session.self) private var session

    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var mode: Mode = .signIn

    enum Mode { case signIn, signUp }

    private var canSubmit: Bool {
        guard !session.isWorking, !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return !firstName.isEmpty && !lastName.isEmpty && password.count >= 8
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 60)

                VStack(spacing: 8) {
                    Text("Trove")
                        .font(.troveSerif(44, .regular))
                        .foregroundStyle(Theme.ink)
                    Text("Show up for what matters")
                        .font(.troveMono(13))
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.bottom, 12)

                VStack(spacing: 12) {
                    if mode == .signUp {
                        HStack(spacing: 12) {
                            field("First name", text: $firstName)
                            field("Last name", text: $lastName)
                        }
                    }
                    field("Email", text: $email, keyboard: .emailAddress)
                    field("Password", text: $password, secure: true)
                    if mode == .signUp {
                        Text("At least 8 characters")
                            .font(.troveMono(11))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let error = session.authError {
                    Text(error)
                        .font(.troveMono(12))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(mode == .signIn ? "Sign in" : "Create account") {
                    Task {
                        if mode == .signIn {
                            await session.signIn(email: email, password: password)
                        } else {
                            await session.signUp(email: email, password: password, firstName: firstName, lastName: lastName)
                        }
                    }
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(!canSubmit)

                Button(mode == .signIn ? "Create an account" : "I already have an account") {
                    mode = mode == .signIn ? .signUp : .signIn
                    session.authError = nil
                }
                .font(.troveMono(13))
                .foregroundStyle(Theme.ink2)

                HStack {
                    line; Text("or").font(.troveMono(11)).foregroundStyle(Theme.muted); line
                }
                .padding(.vertical, 4)

                Button("Explore the demo") {
                    Task { await session.signInDemo() }
                }
                .buttonStyle(PillButtonStyle(filled: false))
                .disabled(session.isWorking)

                if session.isWorking {
                    ProgressView().tint(Theme.ink).padding(.top, 4)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }

    private var line: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.troveMono(15))
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1)
        )
    }
}
