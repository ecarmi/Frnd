import SwiftUI
import Combine
import UserNotifications
import CoreLocation

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
        async let attendedResult = try? APIService.shared.fetchAttendedEvents()
        friends = (await friendsResult) ?? []
        savedEvents = (await savedResult) ?? []
        attendedEvents = (await attendedResult) ?? []
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showSettings = false
    @State private var showEditName = false
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
        .sheet(isPresented: $showEditName) {
            EditNameSheet()
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
                HStack(spacing: 6) {
                    Text(appState.currentUser?.name ?? "Your Profile")
                        .font(.headingLarge)
                        .foregroundColor(.textPrimary)
                    Button { showEditName = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                }
                if let email = appState.currentUser?.email {
                    Text(email)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }
                if let uni = appState.currentUser?.university {
                    Text(uni)
                        .font(.captionSmall)
                        .foregroundColor(.textTertiary)
                }
            }

            // Stats row
            HStack(spacing: Spacing.xxxl) {
                StatView(value: "\(viewModel.attendedEvents.count)", label: "Attended")
                StatView(value: "\(viewModel.savedEvents.count)", label: "Saved")
                StatView(value: "\(viewModel.friends.count)", label: "Friends")
            }
            .padding(.top, Spacing.sm)

            // Invite button
            ShareLink(item: "Join me on Frnd — the app for discovering campus events and making plans with friends. Download it here: https://frnd.app") {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                    Text("Invite Friends")
                }
                .font(.captionMedium)
                .foregroundColor(.ember)
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, 8)
                .background(Color.ember.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.ember.opacity(0.3)))
            }
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
        SwiftUI.Group {
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
                if viewModel.attendedEvents.isEmpty {
                    emptyTabState(icon: "ticket", message: "Events you've attended will appear here")
                } else {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(viewModel.attendedEvents) { event in
                            SearchResultRow(event: event)
                                .padding(.horizontal, Spacing.base)
                        }
                    }
                    .padding(.top, Spacing.md)
                }
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

    @State private var notificationsEnabled = false
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                List {
                    Section("Permissions") {
                        // Notifications
                        HStack {
                            Label("Notifications", systemImage: "bell.fill")
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if notificationsEnabled {
                                Text("On")
                                    .font(.captionMedium)
                                    .foregroundColor(.teal)
                            } else {
                                Button("Enable") {
                                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                                        Task { @MainActor in checkNotificationStatus() }
                                    }
                                }
                                .font(.captionMedium)
                                .foregroundColor(.ember)
                            }
                        }

                        // Location
                        HStack {
                            Label("Location", systemImage: "location.fill")
                                .foregroundColor(.textPrimary)
                            Spacer()
                            switch locationStatus {
                            case .authorizedWhenInUse, .authorizedAlways:
                                Text("On")
                                    .font(.captionMedium)
                                    .foregroundColor(.teal)
                            case .denied, .restricted:
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .font(.captionMedium)
                                .foregroundColor(.ember)
                            default:
                                Text("Not set")
                                    .font(.captionMedium)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .listRowBackground(Color.bgRaised)

                    Section("Account") {
                        Button { showPrivacy = true } label: {
                            Label("Privacy Policy", systemImage: "person.badge.shield.checkmark")
                                .foregroundColor(.textPrimary)
                        }
                        Link(destination: URL(string: "mailto:support@frnd.app")!) {
                            Label("Help & Support", systemImage: "questionmark.circle")
                                .foregroundColor(.textPrimary)
                        }
                        HStack {
                            Label("Version", systemImage: "info.circle")
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Text("1.0.0")
                                .font(.captionMedium)
                                .foregroundColor(.textTertiary)
                        }
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
            .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
            .task { checkNotificationStatus(); checkLocationStatus() }
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    private func checkLocationStatus() {
        locationStatus = CLLocationManager().authorizationStatus
    }
}

// MARK: - Privacy Policy View

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("Last updated: April 2026")
                        .font(.captionMedium)
                        .foregroundColor(.textTertiary)

                    policySection("Information We Collect",
                        """
                        We collect the information you provide when creating your account, including your .edu email address, name, and interests. We also collect your device location when you grant permission, used solely to show nearby events.
                        """)

                    policySection("How We Use Your Information",
                        """
                        Your information is used to personalize your event feed, connect you with friends, and improve the app experience. We do not sell your personal data to third parties.
                        """)

                    policySection("Location Data",
                        """
                        Location is used only while the app is in use to display nearby events and is never stored or shared with other users without your consent.
                        """)

                    policySection("Data Sharing",
                        """
                        Your name and university are visible to other verified .edu users on the platform. Your email address is never displayed publicly. We do not share your data with advertisers.
                        """)

                    policySection("Data Retention",
                        """
                        You may delete your account at any time by contacting support@frnd.app. Upon deletion, your personal data is removed within 30 days.
                        """)

                    policySection("Contact",
                        """
                        Questions about this policy? Email us at privacy@frnd.app.
                        """)
                }
                .padding(Spacing.base)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.headingSmall)
                .foregroundColor(.textPrimary)
            Text(body)
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - Edit Name Sheet

private struct EditNameSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: Spacing.xl) {
                    TextField("Display name", text: $name)
                        .font(.bodyLarge)
                        .foregroundColor(.textPrimary)
                        .padding()
                        .background(Color.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))

                    if let error = error {
                        Text(error).foregroundColor(.rose).font(.captionMedium)
                    }

                    Spacer()
                }
                .padding(Spacing.xl)
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            isLoading = true
                            do {
                                let updated = try await APIService.shared.updateProfile(
                                    name: name.trimmingCharacters(in: .whitespaces),
                                    vibeTagIds: nil
                                )
                                appState.setUser(updated)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isLoading = false
                        }
                    }
                    .foregroundColor(.ember)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
        }
        .onAppear { name = appState.currentUser?.name ?? "" }
    }
}
