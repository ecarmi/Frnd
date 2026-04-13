import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var onboardingComplete: Bool = false
    @Published var isLoading: Bool = false

    static let shared = AppState()

    private init() {
        // Restore session from keychain/userdefaults
        isAuthenticated = APIService.shared.isAuthenticated
        if let data = UserDefaults.standard.data(forKey: "current_user"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            currentUser = user
            onboardingComplete = user.onboardingComplete
        }
    }

    func setUser(_ user: User) {
        currentUser = user
        isAuthenticated = true
        onboardingComplete = user.onboardingComplete
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "current_user")
        }
    }

    func logout() {
        APIService.shared.logout()
        currentUser = nil
        isAuthenticated = false
        onboardingComplete = false
        UserDefaults.standard.removeObject(forKey: "current_user")
    }

    func refreshUser() async {
        guard isAuthenticated else { return }
        do {
            let user = try await APIService.shared.fetchMe()
            setUser(user)
        } catch {}
    }
}
