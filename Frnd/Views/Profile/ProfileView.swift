import SwiftUI
import Combine

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var savedEvents: [Event] = []
    @Published var attendedEvents: [Event] = []
    @Published var friends: [Friendship] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let friendsResult = try? APIService.shared.fetchFriends()
        async let savedResult = try? APIService.shared.fetchSavedEvents()
        friends = (await friendsResult) ?? []
        savedEvents = (await savedResult) ?? []
        attendedEvents = []
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showSettings = false
    @State private var selectedTab: ProfileTab = .saved

    enum ProfileTab: String, CaseIterable {
        case saved    = "Saved"
        case attended = "Attended"
        case friends  = "Friends"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        profileHeader
                        tasteProfileSection
                        tabPicker
                        tabContent
                        Color.clear.frame(height: 88)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task { await viewModel.load() }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: Spacing.md) {
            AvatarView(
                name: appState.currentUser?.name ?? "You",
                imageURL: appState.currentUser?.avatarURL,
                size: 88
            )
            .overlay(Circle().strokeBorder(Color.ember, lineWidth: 2))

            VStack(spacing: 4) {
                Text(appState.currentUser?.name ?? "Your Profile")
                    .font(.headingLarge)
                    .foregroundColor(.textPrimary)
                if let phone = appState.currentUser?.phone {
                    Text(phone)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }
            }

            // Stats row
            HStack(spacing: Spacing.xxxl) {
                StatView(value: "\(viewModel.attendedEvents.count)", label: "Attended")
                StatView(value: "\(viewModel.savedEvents.count)", label: "Saved")
                StatView(value: "\(viewModel.friends.count)", label: "Friends")
            }
            .padding(.top, Spacing.sm)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.xl)
    }

    // MARK: - Taste Profile

    private var tasteProfileSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.teal)
                Text("Your Taste Profile")
                    .font(.headingSmall)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button("Edit") {}
                    .font(.captionMedium)
                    .foregroundColor(.ember)
            }

            if let summary = appState.currentUser?.tasteProfile?.humanReadableSummary {
                Text(summary)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            } else {
                Text("You lean toward: live music, late-night venues, $10–$30 range")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }

            // Category affinity bars
            VStack(spacing: Spacing.sm) {
                ForEach(EventCategory.allCases, id: \.self) { cat in
                    TasteBar(category: cat, value: affinityValue(for: cat))
                }
            }
        }
        .padding(Spacing.base)
        .cardStyle()
        .padding(.horizontal, Spacing.base)
        .padding(.bottom, Spacing.xl)
    }

    private func affinityValue(for category: EventCategory) -> Double {
        let affinities = appState.currentUser?.tasteProfile?.categoryAffinities ?? [:]
        return affinities[category.rawValue] ?? Double.random(in: 0.3...0.9)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.headingSmall)
                            .foregroundColor(selectedTab == tab ? .textPrimary : .textTertiary)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.ember : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Spacing.base)
        .overlay(
            Rectangle()
                .fill(Color.bgBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .saved:
                if viewModel.savedEvents.isEmpty {
                    emptyTabState(icon: "bookmark", message: "Events you save will appear here")
                } else {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(viewModel.savedEvents) { event in
                            SearchResultRow(event: event)
                                .padding(.horizontal, Spacing.base)
                        }
                    }
                    .padding(.top, Spacing.md)
                }
            case .attended:
                emptyTabState(icon: "ticket", message: "Events you've attended will appear here")
            case .friends:
                friendsList
            }
        }
        .padding(.top, Spacing.md)
    }

    private func emptyTabState(icon: String, message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.textTertiary)
            Text(message)
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, Spacing.xxxl)
    }

    private var friendsList: some View {
        LazyVStack(spacing: Spacing.sm) {
            if viewModel.friends.isEmpty {
                emptyTabState(icon: "person.2", message: "Add friends to see their plans and activity")
            } else {
                ForEach(viewModel.friends) { friendship in
                    if let user = friendship.otherUser {
                        HStack(spacing: Spacing.md) {
                            AvatarView(name: user.name, imageURL: user.avatarURL, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.name)
                                    .font(.headingSmall)
                                    .foregroundColor(.textPrimary)
                                PillView(
                                    text: friendship.tier == .innerCircle ? "Inner Circle" : "Friend",
                                    color: friendship.tier == .innerCircle ? .ember : .textSecondary
                                )
                            }
                            Spacer()
                        }
                        .padding(Spacing.md)
                        .cardStyle()
                        .padding(.horizontal, Spacing.base)
                    }
                }
            }
        }
    }
}

// MARK: - Sub Views

private struct StatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headingLarge)
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.captionSmall)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .tracking(1)
        }
    }
}

private struct TasteBar: View {
    let category: EventCategory
    let value: Double

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: 4) {
                Text(category.emoji).font(.captionSmall)
                Text(category.displayName)
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
                    .frame(width: 90, alignment: .leading)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bgBorder)
                    Capsule()
                        .fill(Color.categoryColor(for: category).opacity(0.8))
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                List {
                    Section {
                        settingsRow(icon: "bell.fill", label: "Notifications", color: .ember)
                        settingsRow(icon: "location.fill", label: "Location", color: .teal)
                        settingsRow(icon: "music.note", label: "Connect Spotify", color: .violet)
                    }
                    .listRowBackground(Color.bgRaised)

                    Section {
                        settingsRow(icon: "person.badge.shield.checkmark", label: "Privacy", color: .gold)
                        settingsRow(icon: "questionmark.circle", label: "Help & Support", color: .textSecondary)
                        settingsRow(icon: "info.circle", label: "About Frnd", color: .textSecondary)
                    }
                    .listRowBackground(Color.bgRaised)

                    Section {
                        Button {
                            appState.logout()
                            dismiss()
                        } label: {
                            Label("Sign Out", systemImage: "arrow.left.circle")
                                .foregroundColor(.rose)
                        }
                    }
                    .listRowBackground(Color.bgRaised)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                }
            }
        }
    }

    private func settingsRow(icon: String, label: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .foregroundColor(.textPrimary)
            .font(.bodyLarge)
    }
}
