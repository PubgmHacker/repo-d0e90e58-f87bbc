import SwiftUI

// MARK: - Login View
struct LoginView: View {
    @State private var viewModel: AuthViewModel
    @State private var selectedAuthMethod: AuthMethod?
    @State private var showSignUp = false
    @ObservedObject private var loc = LocalizationManager.shared
    var onSignIn: () -> Void

    enum AuthMethod: String, CaseIterable, Identifiable {
        case google = "Google"
        case apple = "Apple"
        case email = "Email"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .google: return "globe"
            case .apple: return "apple.logo"
            case .email: return "envelope.fill"
            }
        }

        var color: Color {
            switch self {
            case .google: return Color(red: 0.85, green: 0.22, blue: 0.20)
            case .apple: return .white
            case .email: return Color.ravePrimary
            }
        }
    }

    init(viewModel: AuthViewModel, onSignIn: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSignIn = onSignIn
    }

    var body: some View {
        ZStack {
            // 🔧 FIX N7: Use BioluminescentBackground (was: opaque Color.raveBackground
            // + two static blurred circles). Now consistent with the rest of the app.
            BioluminescentBackground(energy: 0.5, dimming: 0)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Logo / Branding ───────────────────────────
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.ravePrimary, Color.raveAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.ravePrimary.opacity(0.5), radius: 20, y: 8)

                    Text(loc.string(.appName))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(loc.string(.appTagline))
                        .font(.subheadline)
                        .foregroundColor(.raveTextSecondary)
                }
                .padding(.bottom, 48)

                // ── Auth Method Selection ──────────────────────
                if selectedAuthMethod == nil {
                    VStack(spacing: 14) {
                        ForEach(AuthMethod.allCases) { method in
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedAuthMethod = method
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: method.icon)
                                        .font(.title3.bold())
                                        .foregroundColor(method == .apple ? .black : .white)
                                        .frame(width: 36, height: 36)
                                        .background(method == .apple ? Color.white : method.color.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text("Continue with \(method.rawValue)")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.white)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.raveTextSecondary)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(method == .google
                                    ? Color.white.opacity(0.08)
                                    : method == .apple
                                    ? Color.white.opacity(0.1)
                                    : Color.ravePrimary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                }

                // ── Email Form (when email selected) ───────────
                if selectedAuthMethod == .email {
                    VStack(spacing: 16) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedAuthMethod = nil
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text(loc.string(.back))
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.raveTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                        TextField(loc.string(.loginEmail), text: $viewModel.email)
                            .textFieldStyle(RaveTextFieldStyle())
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)

                        SecureField(loc.string(.loginPassword), text: $viewModel.password)
                            .textFieldStyle(RaveTextFieldStyle())
                            .textContentType(.password)

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.raveDanger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: {
                            Task {
                                await viewModel.signIn()
                                if viewModel.isSignedIn { onSignIn() }
                            }
                        }) {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView().tint(.white)
                                }
                                Text(viewModel.isLoading ? loc.string(.loginSigningIn) : loc.string(.loginSignIn))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .raveButtonStyle()

                        Button {
                            withAnimation { showSignUp = true }
                        } label: {
                            Text(loc.string(.loginDontHaveAccount))
                                .font(.subheadline)
                                .foregroundColor(.ravePrimary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 28)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }

                // ── Google / Apple auto-sign-in (placeholder) ───
                if selectedAuthMethod == .google || selectedAuthMethod == .apple {
                    VStack(spacing: 20) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedAuthMethod = nil
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.raveTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()

                        ProgressView()
                            .tint(.ravePrimary)

                        Text("\(loc.string(.loginConnecting)) \(selectedAuthMethod == .google ? "Google" : "Apple")...")
                            .font(.subheadline)
                            .foregroundColor(.raveTextSecondary)

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .onAppear {
                        // TODO: Wire up real Google Sign-In / Sign in with Apple
                        // For now, fallback to email sign in after a moment
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedAuthMethod = .email
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }

                Spacer()

                // ── Terms ──────────────────────────────────────
                Text(loc.string(.loginTerms))
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showSignUp) {
            SignUpView(viewModel: viewModel, onSignUp: onSignIn)
        }
    }
}

// MARK: - Sign Up View
struct SignUpView: View {
    @State private var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var onSignUp: () -> Void

    init(viewModel: AuthViewModel, onSignUp: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSignUp = onSignUp
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.raveBackground
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.ravePrimary.opacity(0.12))
                                .frame(width: 80, height: 80)

                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundColor(.ravePrimary)
                        }

                        Text(loc.string(.loginCreateAccount))
                            .font(.title.bold())
                            .foregroundColor(.white)

                        Text(loc.string(.loginJoinParty))
                            .font(.subheadline)
                            .foregroundColor(.raveTextSecondary)
                    }
                    .padding(.bottom, 20)

                    VStack(spacing: 14) {
                        TextField(loc.string(.loginUsername), text: $viewModel.username)
                            .textFieldStyle(RaveTextFieldStyle())
                            .textContentType(.username)
                            .autocapitalization(.none)

                        TextField(loc.string(.loginEmail), text: $viewModel.email)
                            .textFieldStyle(RaveTextFieldStyle())
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)

                        SecureField(loc.string(.loginPassword), text: $viewModel.password)
                            .textFieldStyle(RaveTextFieldStyle())
                            .textContentType(.newPassword)
                    }
                    .padding(.horizontal, 28)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.raveDanger)
                            .padding(.horizontal, 28)
                    }

                    Button(action: {
                        Task {
                            await viewModel.signUp()
                            if viewModel.isSignedIn { onSignUp() }
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView().tint(.white)
                            }
                            Text(loc.string(.loginCreateAccount))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .raveButtonStyle()
                    .padding(.horizontal, 28)
                    .disabled(!viewModel.isSignUpFormValid || viewModel.isLoading)

                    Spacer()
                }
            }
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ravePrimary)
                    }
                }
            }
            .navigationBarBackButtonHidden()
        }
    }
}

// MARK: - Custom Text Field Style
struct RaveTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.raveSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.raveSurface.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(.raveTextPrimary)
            .font(.body)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
    }
}
