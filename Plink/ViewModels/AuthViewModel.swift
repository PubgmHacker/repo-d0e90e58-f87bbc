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
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() async {
        try? await authService.signOut()
        user = nil
    }
}
