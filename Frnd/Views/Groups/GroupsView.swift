import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class GroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await APIService.shared.fetchMyGroups()
        } catch {
            // No mock groups — show empty state on backend failure
        }
    }

    func createGroup(name: String, description: String, isPrivate: Bool) async throws {
        let group = try await APIService.shared.createGroup(name: name, description: description, isPrivate: isPrivate)
        groups.insert(group, at: 0)
    }

    func joinGroup(inviteCode: String) async throws {
        let group = try await APIService.shared.joinGroup(inviteCode: inviteCode)
        if !groups.contains(where: { $0.id == group.id }) {
            groups.insert(group, at: 0)
        }
    }

    func leaveGroup(id: String) async throws {
        try await APIService.shared.leaveGroup(id: id)
        groups.removeAll { $0.id == id }
    }
}

// MARK: - Groups View

struct GroupsView: View {
    @StateObject private var viewModel = GroupsViewModel()
    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if viewModel.isLoading && viewModel.groups.isEmpty {
                    ProgressView().tint(.ember)
                } else if viewModel.groups.isEmpty {
                    emptyState
                } else {
                    groupsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Groups")
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Create Group") { showCreate = true }
                        Button("Join via Code") { showJoin = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.ember)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateGroupSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showJoin) {
            JoinGroupSheet(viewModel: viewModel)
        }
        .task { await viewModel.load() }
    }

    private var groupsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: Spacing.base) {
                ForEach(viewModel.groups) { group in
                    NavigationLink(destination: GroupDetailView(group: group, viewModel: viewModel)) {
                        GroupRowView(group: group)
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 88)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, Spacing.base)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Text("🏠")
                .font(.system(size: 56))
            Text("No groups yet")
                .font(.headingMedium)
                .foregroundColor(.textPrimary)
            Text("Create a private space for your crew or join one with an invite code.")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
            HStack(spacing: Spacing.base) {
                Button("Create") { showCreate = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Join") { showJoin = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Group Row

struct GroupRowView: View {
    let group: Group

    var body: some View {
        HStack(spacing: Spacing.base) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.violet.opacity(0.2))
                    .frame(width: 48, height: 48)
                Text(String(group.name.prefix(1)))
                    .font(.headingMedium)
                    .foregroundColor(.violet)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(group.name)
                        .font(.headingSmall)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if group.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.captionSmall)
                            .foregroundColor(.textTertiary)
                    }
                }
                if !group.description.isEmpty {
                    Text(group.description)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                    .font(.captionSmall)
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.captionMedium)
                .foregroundColor(.textTertiary)
        }
        .padding(Spacing.base)
        .cardStyle()
    }
}

// MARK: - Group Detail

struct GroupDetailView: View {
    let group: Group
    @ObservedObject var viewModel: GroupsViewModel
    @State private var activities: [ActivityPost] = []
    @State private var loadingActivities = false
    @State private var showCreateActivity = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Header
                    headerSection

                    // Invite code (owner)
                    if let code = group.inviteCode {
                        inviteCodeSection(code)
                    }

                    // Members
                    membersSection

                    // Activity posts
                    activitiesSection
                }
                .padding(Spacing.base)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Post Activity") { showCreateActivity = true }
                    Button("Leave Group", role: .destructive) {
                        Task {
                            try? await viewModel.leaveGroup(id: group.id)
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showCreateActivity) {
            CreateActivityView(groupId: group.id) { post in
                activities.insert(post, at: 0)
            }
        }
        .task {
            loadingActivities = true
            activities = (try? await APIService.shared.fetchActivities(groupId: group.id)) ?? []
            loadingActivities = false
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.violet.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Text(String(group.name.prefix(1)))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.violet)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                    Text("\(group.memberCount) members · \(group.isPrivate ? "Private" : "Public")")
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }
            }
            if !group.description.isEmpty {
                Text(group.description)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func inviteCodeSection(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Invite Code")
                .font(.mono)
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
                .tracking(2)
            HStack {
                Text(code)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.teal)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.teal)
                }
            }
            .padding(Spacing.base)
            .background(Color.teal.opacity(0.1))
            .cornerRadius(Radius.base)
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Members · \(group.members.count)")
                .font(.mono)
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
                .tracking(2)
            LazyVStack(spacing: Spacing.sm) {
                ForEach(group.members) { member in
                    HStack {
                        AvatarView(name: member.user?.name ?? "?", imageURL: member.user?.avatarURL, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.user?.name ?? "Unknown")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                            Text(member.role.rawValue.capitalized)
                                .font(.captionSmall)
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Activity Posts")
                    .font(.mono)
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                    .tracking(2)
                Spacer()
                Button("Post") { showCreateActivity = true }
                    .font(.captionMedium)
                    .foregroundColor(.ember)
            }
            if loadingActivities {
                ProgressView().tint(.ember)
            } else if activities.isEmpty {
                Text("No activity posts yet. Be first!")
                    .font(.captionMedium)
                    .foregroundColor(.textTertiary)
                    .padding(.vertical, Spacing.sm)
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(activities) { post in
                        ActivityPostCard(post: post) { updated in
                            if let idx = activities.firstIndex(where: { $0.id == updated.id }) {
                                activities[idx] = updated
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Create Group Sheet

struct CreateGroupSheet: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                Form {
                    Section("Group Info") {
                        TextField("Name", text: $name)
                            .foregroundColor(.textPrimary)
                        TextField("Description (optional)", text: $description)
                            .foregroundColor(.textPrimary)
                    }
                    Section {
                        Toggle("Private Group", isOn: $isPrivate)
                    } footer: {
                        Text("Private groups require an invite code to join.")
                            .foregroundColor(.textTertiary)
                    }
                    if let error = error {
                        Section {
                            Text(error).foregroundColor(.rose)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task {
                            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                                error = "Name is required"
                                return
                            }
                            isLoading = true
                            do {
                                try await viewModel.createGroup(name: name, description: description, isPrivate: isPrivate)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isLoading = false
                        }
                    }
                    .foregroundColor(.ember)
                    .disabled(name.isEmpty || isLoading)
                }
            }
        }
    }
}

// MARK: - Join Group Sheet

struct JoinGroupSheet: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: Spacing.xl) {
                    Text("🔑")
                        .font(.system(size: 56))
                    Text("Enter Invite Code")
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                    TextField("Invite code", text: $inviteCode)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.teal)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.bgSurface)
                        .cornerRadius(Radius.base)
                        .padding(.horizontal, Spacing.xl)
                    if let error = error {
                        Text(error).foregroundColor(.rose).font(.captionMedium)
                    }
                    Button("Join") {
                        Task {
                            isLoading = true
                            do {
                                try await viewModel.joinGroup(inviteCode: inviteCode.trimmingCharacters(in: .whitespaces))
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(inviteCode.isEmpty || isLoading)
                }
                .padding(Spacing.xl)
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
            }
        }
    }
}
