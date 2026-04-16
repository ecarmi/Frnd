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
        upsert(group)
    }

    func joinGroup(inviteCode: String) async throws {
        let group = try await APIService.shared.joinGroup(inviteCode: inviteCode)
        upsert(group)
    }

    func joinPublicGroup(id: String) async throws -> Group {
        let group = try await APIService.shared.joinPublicGroup(id: id)
        upsert(group)
        return group
    }

    func updateGroup(id: String, name: String, description: String) async throws -> Group {
        let group = try await APIService.shared.updateGroup(id: id, name: name, description: description)
        upsert(group)
        return group
    }

    func updateGroupMemberRole(groupId: String, userId: String, role: GroupRole) async throws -> Group {
        let group = try await APIService.shared.updateGroupMemberRole(groupId: groupId, userId: userId, role: role)
        upsert(group)
        return group
    }

    func leaveGroup(id: String) async throws {
        try await APIService.shared.leaveGroup(id: id)
        groups.removeAll { $0.id == id }
    }

    func deleteGroup(id: String) async throws {
        try await APIService.shared.deleteGroup(id: id)
        groups.removeAll { $0.id == id }
    }

    func upsert(_ group: Group) {
        groups.removeAll { $0.id == group.id }
        groups.insert(group, at: 0)
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
                        Image(systemName: "plus")
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
                    .frame(maxWidth: .infinity)
                Button("Join") { showJoin = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.xl)
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
                Text(String(group.name.prefix(1)))
                    .font(.headingMedium)
                    .foregroundColor(.violet)
            }
            .frame(width: 48, height: 48)

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
    @State private var group: Group
    @ObservedObject var viewModel: GroupsViewModel
    @State private var activities: [ActivityPost] = []
    @State private var loadingActivities = false
    @State private var showCreateActivity = false
    @State private var showCreateEvent = false
    @State private var showEditGroup = false
    @State private var isJoiningPublicGroup = false
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    init(group: Group, viewModel: GroupsViewModel) {
        _group = State(initialValue: group)
        self.viewModel = viewModel
    }

    private var currentUserId: String? {
        appState.currentUser?.id
    }

    private var currentMembership: GroupMember? {
        guard let currentUserId else { return nil }
        return group.members.first { $0.userId == currentUserId }
    }

    private var currentRole: GroupRole? {
        currentMembership?.role
    }

    private var isMember: Bool {
        currentMembership != nil
    }

    private var isOwner: Bool {
        currentRole == .owner
    }

    private var canManageGroup: Bool {
        currentRole == .owner || currentRole == .admin
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Header
                    headerSection

                    // Invite code (member)
                    if isMember, let code = group.inviteCode {
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
        .navigationBarTitleDisplayMode(.inline)
        .alert("Group Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(group.name)
                    .font(.headingMedium)
                    .foregroundColor(.textPrimary)
            }
            if canManageGroup || isMember {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if canManageGroup {
                            Button("Edit Group") { showEditGroup = true }
                            Button("Post Event") { showCreateEvent = true }
                            Button("Post Activity") { showCreateActivity = true }
                        }
                        if isOwner {
                            Button("Delete Group", role: .destructive) {
                                Task {
                                    do {
                                        try await viewModel.deleteGroup(id: group.id)
                                        dismiss()
                                    } catch {
                                        actionError = error.localizedDescription
                                    }
                                }
                            }
                        } else if isMember {
                            Button("Leave Group", role: .destructive) {
                                Task {
                                    do {
                                        try await viewModel.leaveGroup(id: group.id)
                                        dismiss()
                                    } catch {
                                        actionError = error.localizedDescription
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView(groupId: group.id)
        }
        .sheet(isPresented: $showCreateActivity) {
            CreateActivityView(groupId: group.id) { post in
                activities.insert(post, at: 0)
            }
        }
        .sheet(isPresented: $showEditGroup) {
            EditGroupSheet(group: group, viewModel: viewModel) { updatedGroup in
                applyGroupUpdate(updatedGroup)
            }
        }
        .task {
            if let refreshedGroup = try? await APIService.shared.fetchGroup(id: group.id) {
                applyGroupUpdate(refreshedGroup)
            }
            await loadActivities()
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
            if !group.isPrivate && !isMember {
                Button {
                    Task {
                        isJoiningPublicGroup = true
                        defer { isJoiningPublicGroup = false }
                        do {
                            let joined = try await viewModel.joinPublicGroup(id: group.id)
                            applyGroupUpdate(joined)
                            await loadActivities()
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                } label: {
                    if isJoiningPublicGroup {
                        ProgressView().tint(.white)
                    } else {
                        Text("Join Group")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isJoiningPublicGroup)
                .padding(.top, Spacing.sm)
            }
        }
    }

    private func inviteCodeSection(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Invite Link")
                .font(.mono)
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
                .tracking(2)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    Text("frnd://join/group/\(code)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.teal)
                        .lineLimit(1)
                    Text("Share the link or send the code directly")
                        .font(.captionSmall)
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                ShareLink(
                    item: URL(string: "frnd://join/group/\(code)")!,
                    subject: Text("Join my group on Frnd"),
                    message: Text("Tap to join \"\(group.name)\" on Frnd")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.teal)
                }
            }
            .padding(Spacing.base)
            .background(Color.teal.opacity(0.1))
            .cornerRadius(Radius.md)
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
                        if isOwner, let currentUserId, member.userId != currentUserId {
                            Menu {
                                if member.role == .member {
                                    Button("Make Admin") {
                                        Task { await updateMemberRole(member, to: .admin) }
                                    }
                                }
                                if member.role == .admin {
                                    Button("Remove Admin") {
                                        Task { await updateMemberRole(member, to: .member) }
                                    }
                                }
                                Button("Make Owner") {
                                    Task { await updateMemberRole(member, to: .owner) }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundColor(.textTertiary)
                                    .frame(width: 28, height: 28)
                            }
                        }
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
                if canManageGroup {
                    Button("Post") { showCreateActivity = true }
                        .font(.captionMedium)
                        .foregroundColor(.ember)
                }
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
                        ActivityPostCard(
                            post: post,
                            onUpdate: { updated in
                                if let idx = activities.firstIndex(where: { $0.id == updated.id }) {
                                    activities[idx] = updated
                                }
                            },
                            onDelete: { deletedId in
                                activities.removeAll { $0.id == deletedId }
                            }
                        )
                    }
                }
            }
        }
    }

    private func loadActivities() async {
        loadingActivities = true
        activities = (try? await APIService.shared.fetchActivities(groupId: group.id)) ?? []
        loadingActivities = false
    }

    private func applyGroupUpdate(_ updatedGroup: Group) {
        group = updatedGroup
        if let currentUserId, updatedGroup.members.contains(where: { $0.userId == currentUserId }) {
            viewModel.upsert(updatedGroup)
        } else {
            viewModel.groups.removeAll { $0.id == updatedGroup.id }
        }
    }

    private func updateMemberRole(_ member: GroupMember, to role: GroupRole) async {
        do {
            let updated = try await viewModel.updateGroupMemberRole(groupId: group.id, userId: member.userId, role: role)
            applyGroupUpdate(updated)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Edit Group Sheet

struct EditGroupSheet: View {
    let group: Group
    @ObservedObject var viewModel: GroupsViewModel
    let onSaved: (Group) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var isLoading = false
    @State private var error: String?

    init(group: Group, viewModel: GroupsViewModel, onSaved: @escaping (Group) -> Void) {
        self.group = group
        self.viewModel = viewModel
        self.onSaved = onSaved
        _name = State(initialValue: group.name)
        _description = State(initialValue: group.description)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                Form {
                    Section("Group Info") {
                        TextField("Name", text: $name)
                            .foregroundColor(.textPrimary)
                        TextField("Description", text: $description, axis: .vertical)
                            .foregroundColor(.textPrimary)
                            .lineLimit(3...6)
                    }
                    if let error {
                        Section {
                            Text(error).foregroundColor(.rose)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            error = nil
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedName.isEmpty else {
                                error = "Name is required"
                                return
                            }

                            isLoading = true
                            defer { isLoading = false }
                            do {
                                let updated = try await viewModel.updateGroup(
                                    id: group.id,
                                    name: trimmedName,
                                    description: description.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                                onSaved(updated)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .foregroundColor(.ember)
                    .disabled(isLoading)
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
                            error = nil
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
                    .disabled(isLoading)
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
                    TextField("Invite code or frnd:// link", text: $inviteCode)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.teal)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.bgSurface)
                        .cornerRadius(Radius.md)
                        .padding(.horizontal, Spacing.xl)
                    if let error = error {
                        Text(error).foregroundColor(.rose).font(.captionMedium)
                    }
                    Button("Join") {
                        Task {
                            error = nil
                            let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedCode.isEmpty else {
                                error = "Invite code is required"
                                return
                            }
                            isLoading = true
                            do {
                                try await viewModel.joinGroup(inviteCode: trimmedCode)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading)
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
