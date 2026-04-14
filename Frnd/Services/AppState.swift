import SwiftUI
import Combine

enum DeepLink: Equatable {
    case joinGroup(code: String)
    case joinPlan(code: String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var onboardingComplete: Bool = false
    @Published var isLoading: Bool = false
    @Published var pendingDeepLink: DeepLink?

    static let shared = AppState()

    private init() {
        // Restore session — a saved user means authenticated (real token or dev bypass)
        if let data = UserDefaults.standard.data(forKey: "current_user"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            currentUser = user
            isAuthenticated = true
            onboardingComplete = user.onboardingComplete
        } else {
            isAuthenticated = APIService.shared.isAuthenticated
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

    func handleDeepLink(_ url: URL) {
        // frnd://join/group/<code>
        // frnd://join/plan/<code>
        guard url.scheme == "frnd",
              url.host == "join" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2 else { return }
        let type = parts[0]
        let code = parts[1]
        switch type {
        case "group": pendingDeepLink = .joinGroup(code: code)
        case "plan":  pendingDeepLink = .joinPlan(code: code)
        default: break
        }
    }
}
