import SwiftUI

@main
struct FrndApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var savedEventsStore = SavedEventsStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(savedEventsStore)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    appState.handleDeepLink(url)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SwiftUI.Group {
            if appState.isAuthenticated && appState.onboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: appState.onboardingComplete)
    }
}
