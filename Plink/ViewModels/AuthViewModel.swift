import Foundation

// MARK: - Auth View Model
@Observable
final class AuthViewModel {

    // MARK: - State

    var email = ""
    var password = ""
    var username = ""
    var isLoading = false
    var errorMessage: String?
    var isSignedIn = false
    /// 🔧 Pack v3: Admin code verification flow
    var needsAdminCode = false
    var adminCode = ""

    var user: User? {
        didSet {
            isSignedIn = user != nil
        }
    }

    // MARK: - Computed

    var isFormValid: Bool {
        email.contains("@") && password.count >= 6
    }

    var isSignUpFormValid: Bool {
        isFormValid && username.count >= 2
    }

    // MARK: - Services

    private let authService: AuthServiceProtocol

    // MARK: - Init

    init(authService: AuthServiceProtocol) {
        self.authService = authService

        Task {
            self.user = await authService.currentUser()
            self.isSignedIn = self.user != nil
        }
    }

    // MARK: - Actions

    func signIn() async {
        guard isFormValid else { return }
        isLoading = true
        errorMessage = nil

        do {
            user = try await authService.signIn(email: email, password: password)
            // 🔧 Pack v3: Если это админ-почта — запросить код подтверждения
            if email.lowercased() == "koslakandrej@gmail.com" && user?.role != "ADMIN" {
                needsAdminCode = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signUp() async {
        guard isSignUpFormValid else { return }
        isLoading = true
        errorMessage = nil

        do {
            user = try await authService.signUp(email: email, password: password, username: username)
            // 🔧 Pack v3: Если это админ-почта — запросить код подтверждения
            if email.lowercased() == "koslakandrej@gmail.com" {
                needsAdminCode = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 🔧 Pack v3: Verify admin code
    func verifyAdminCode() async {
        guard !adminCode.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            user = try await authService.verifyAdminCode(email: email, code: adminCode)
            needsAdminCode = false
        } catch {
            errorMessage = "Неверный код подтверждения"
        }

        isLoading = false
    }

    func signOut() async {
        try? await authService.signOut()
        user = nil
    }
}
