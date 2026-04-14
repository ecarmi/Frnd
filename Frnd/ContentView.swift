import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .feed
    @State private var joinedPlan: Plan?
    @State private var joinedGroup: Group?
    @State private var deepLinkError: String?
    @EnvironmentObject var appState: AppState

    enum Tab: Int, CaseIterable {
        case feed, map, plans, search, profile
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                FeedView()
                    .tag(Tab.feed)

                MapTabView()
                    .tag(Tab.map)

                PlansView()
                    .tag(Tab.plans)

                SearchView()
                    .tag(Tab.search)

                ProfileView()
                    .tag(Tab.profile)
            }
            // Hide default tab bar
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom glassmorphism tab bar
            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .appBackground()
        .onChange(of: appState.pendingDeepLink) { link in
            guard let link else { return }
            Task {
                await handleDeepLink(link)
                appState.pendingDeepLink = nil
            }
        }
        .sheet(item: $joinedPlan) { plan in
            NavigationStack {
                PlanDetailView(plan: plan)
                    .environmentObject(appState)
            }
        }
        .alert("Could not join", isPresented: Binding(
            get: { deepLinkError != nil },
            set: { if !$0 { deepLinkError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deepLinkError ?? "")
        }
    }

    private func handleDeepLink(_ link: DeepLink) async {
        switch link {
        case .joinGroup(let code):
            do {
                let group = try await APIService.shared.joinGroup(inviteCode: code)
                joinedGroup = group
                selectedTab = .search
            } catch {
                deepLinkError = "Could not join group: \(error.localizedDescription)"
            }
        case .joinPlan(let code):
            do {
                let plan = try await APIService.shared.joinPlanByCode(code)
                joinedPlan = plan
            } catch {
                deepLinkError = "Could not join plan: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab

    struct TabItem {
        let tab: MainTabView.Tab
        let icon: String
        let label: String
    }

    private let items: [TabItem] = [
        TabItem(tab: .feed,    icon: "sparkles",        label: "For You"),
        TabItem(tab: .map,     icon: "map.fill",         label: "Map"),
        TabItem(tab: .plans,   icon: "person.2.fill",    label: "Plans"),
        TabItem(tab: .search,  icon: "magnifyingglass",  label: "Search"),
        TabItem(tab: .profile, icon: "person.fill",      label: "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.label) { item in
                TabBarButton(item: item, isSelected: selectedTab == item.tab) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        selectedTab = item.tab
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 28) // above home indicator
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.bgSurface.opacity(0.7))
                )
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.bgBorder),
            alignment: .top
        )
    }
}

private struct TabBarButton: View {
    let item: CustomTabBar.TabItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .ember : .textTertiary)
                    .scaleEffect(isSelected ? 1.1 : 1.0)

                // Active dot
                Circle()
                    .fill(isSelected ? Color.ember : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Helpers: Time formatting

extension Date {
    var relativeEventTime: String {
        let now = Date()
        let diff = self.timeIntervalSince(now)
        let hours = diff / 3600

        if diff < 0 {
            return "Now"
        } else if hours < 2 {
            return "Tonight"
        } else if Calendar.current.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h a"
            return "Tonight, \(formatter.string(from: self))"
        } else if Calendar.current.isDateInTomorrow(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h a"
            return "Tomorrow, \(formatter.string(from: self))"
        } else if diff < 48 * 3600 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d · h a"
            return formatter.string(from: self)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d · h a"
            return formatter.string(from: self)
        }
    }
}
