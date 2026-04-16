import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published var posts: [ActivityPost] = []
    @Published var isLoading = false

    func load(groupId: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        posts = (try? await APIService.shared.fetchActivities(groupId: groupId)) ?? []
    }

    func join(id: String) async throws {
        let updated = try await APIService.shared.joinActivity(id: id)
        replace(updated)
    }

    func leave(id: String) async throws {
        try await APIService.shared.leaveActivity(id: id)
        posts.removeAll { $0.id == id }
    }

    private func replace(_ post: ActivityPost) {
        if let idx = posts.firstIndex(where: { $0.id == post.id }) {
            posts[idx] = post
        }
    }
}

// MARK: - Activity Feed View (public LFG posts)

struct ActivityFeedView: View {
    @StateObject private var viewModel = ActivityViewModel()
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    ProgressView().tint(.ember)
                } else if viewModel.posts.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: Spacing.base) {
                            ForEach(viewModel.posts) { post in
                                ActivityPostCard(
                                    post: post,
                                    onUpdate: { updated in
                                        if let idx = viewModel.posts.firstIndex(where: { $0.id == updated.id }) {
                                            viewModel.posts[idx] = updated
                                        }
                                    },
                                    onDelete: { deletedId in
                                        viewModel.posts.removeAll { $0.id == deletedId }
                                    }
                                )
                            }
                            Color.clear.frame(height: 88)
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.top, Spacing.base)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Looking For Group")
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.ember)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateActivityView(groupId: nil) { post in
                viewModel.posts.insert(post, at: 0)
            }
        }
        .task { await viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Text("🙋")
                .font(.system(size: 56))
            Text("No activity posts")
                .font(.headingMedium)
                .foregroundColor(.textPrimary)
            Text("Post an activity to find others to join you.")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
            Button("Post Activity") { showCreate = true }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Activity Post Card

struct ActivityPostCard: View {
    let post: ActivityPost
    let onUpdate: (ActivityPost) -> Void
    var onDelete: ((String) -> Void)? = nil
    var canManageGroupPost: Bool = false

    @EnvironmentObject private var appState: AppState
    @State private var isLoading = false
    @State private var showEdit = false

    private var isCreator: Bool {
        post.creatorId == appState.currentUser?.id
    }

    private var canEditPost: Bool {
        isCreator || canManageGroupPost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Header row
            HStack(spacing: Spacing.sm) {
                AvatarView(name: post.creator?.name ?? "?", imageURL: post.creator?.avatarURL, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.creator?.name ?? "Someone")
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                    if let time = post.scheduledTime {
                        Text(time, style: .relative)
                            .font(.captionSmall)
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                if canEditPost {
                    Menu {
                        Button("Edit") { showEdit = true }
                        Button("Delete", role: .destructive) {
                            Task {
                                isLoading = true
                                defer { isLoading = false }
                                do {
                                    try await APIService.shared.deleteActivity(id: post.id)
                                    onDelete?(post.id)
                                } catch {}
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 28, height: 28)
                    }
                }

                // Type pill
                Text("\(post.activityType.emoji) \(post.activityType.displayName)")
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.bgSurface)
                    .clipShape(Capsule())
            }

            // Content
            Text(post.title)
                .font(.headingSmall)
                .foregroundColor(.textPrimary)

            HStack(spacing: Spacing.xs) {
                if post.isAnnouncement {
                    PillView(text: "Announcement", color: .ember)
                }
                if let groupName = post.groupName {
                    PillView(text: groupName, color: .textSecondary)
                }
                if post.groupId != nil {
                    PillView(text: post.isMembersOnly ? "Members Only" : "Open to Everyone", color: .teal)
                }
            }

            if !post.description.isEmpty {
                Text(post.description)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .lineLimit(3)
            }

            // Location + time
            HStack(spacing: Spacing.base) {
                if let location = post.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                if let max = post.maxParticipants {
                    Spacer()
                    Text("\(post.participantCount)/\(max)")
                        .font(.captionMedium)
                        .foregroundColor(post.participantCount >= max ? .rose : .textSecondary)
                }
            }

            // Participant avatars + join button
            HStack {
                HStack(spacing: -8) {
                    ForEach(post.participants.prefix(5)) { p in
                        AvatarView(name: p.user?.name ?? "?", imageURL: p.user?.avatarURL, size: 24)
                            .overlay(Circle().strokeBorder(Color.bgSurface, lineWidth: 1.5))
                    }
                }

                Spacer()

                if !post.isAnnouncement {
                    joinButton
                }
            }
        }
        .padding(Spacing.base)
        .cardStyle()
        .sheet(isPresented: $showEdit) {
            CreateActivityView(existingPost: post) { updated in
                onUpdate(updated)
            }
        }
    }

    private var joinButton: some View {
        Button {
            Task {
                isLoading = true
                defer { isLoading = false }
                do {
                    if post.isJoined {
                        try await APIService.shared.leaveActivity(id: post.id)
                        let updated = try await APIService.shared.fetchActivity(id: post.id)
                        onUpdate(updated)
                    } else {
                        let updated = try await APIService.shared.joinActivity(id: post.id)
                        onUpdate(updated)
                    }
                } catch {}
            }
        } label: {
            if isLoading {
                ProgressView().scaleEffect(0.7).tint(.ember)
            } else {
                Text(post.isJoined ? "Joined ✓" : "Join")
                    .font(.captionMedium.bold())
                    .foregroundColor(post.isJoined ? .teal : .bgPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(post.isJoined ? Color.teal.opacity(0.2) : Color.ember)
                    .clipShape(Capsule())
            }
        }
        .disabled(isLoading || post.status != .open)
    }
}

// MARK: - Create Activity View

struct CreateActivityView: View {
    let fixedGroupId: String?
    let existingPost: ActivityPost?
    let onSaved: (ActivityPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var title: String
    @State private var description: String
    @State private var activityType: ActivityType
    @State private var location: String
    @State private var scheduledTime: Date
    @State private var hasTime: Bool
    @State private var maxParticipants: String
    @State private var isLoading = false
    @State private var error: String?
    @State private var groups: [Group] = []
    @State private var selectedGroupId: String?
    @State private var isMembersOnly: Bool
    @State private var isAnnouncement: Bool

    init(
        groupId: String? = nil,
        existingPost: ActivityPost? = nil,
        onCreated: @escaping (ActivityPost) -> Void
    ) {
        self.fixedGroupId = groupId
        self.existingPost = existingPost
        self.onSaved = onCreated
        _title = State(initialValue: existingPost?.title ?? "")
        _description = State(initialValue: existingPost?.description ?? "")
        _activityType = State(initialValue: existingPost?.activityType ?? .social)
        _location = State(initialValue: existingPost?.location ?? "")
        _scheduledTime = State(initialValue: existingPost?.scheduledTime ?? Date().addingTimeInterval(3600 * 2))
        _hasTime = State(initialValue: existingPost?.scheduledTime != nil)
        _maxParticipants = State(initialValue: existingPost?.maxParticipants.map(String.init) ?? "")
        _selectedGroupId = State(initialValue: existingPost?.groupId)
        _isMembersOnly = State(initialValue: existingPost?.isMembersOnly ?? (groupId != nil))
        _isAnnouncement = State(initialValue: existingPost?.isAnnouncement ?? false)
    }

    private var resolvedGroupId: String? { fixedGroupId ?? selectedGroupId }
    private var canPickGroup: Bool { fixedGroupId == nil && !adminGroups.isEmpty }
    private var selectedGroup: Group? {
        adminGroups.first { $0.id == resolvedGroupId }
    }
    private var isGroupPost: Bool { resolvedGroupId != nil }
    private var allowsAnnouncements: Bool { selectedGroup?.isPrivate == false && isGroupPost }
    private var adminGroups: [Group] {
        guard let currentUserId = appState.currentUser?.id else { return [] }
        return groups.filter { group in
            group.members.contains {
                $0.userId == currentUserId && ($0.role == .owner || $0.role == .admin)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                Form {
                    Section("What's the plan?") {
                        TextField("Title", text: $title)
                            .foregroundColor(.textPrimary)
                        TextField("Details (optional)", text: $description, axis: .vertical)
                            .foregroundColor(.textPrimary)
                            .lineLimit(3...6)
                    }

                    Section("Type") {
                        Picker("Activity Type", selection: $activityType) {
                            ForEach(ActivityType.allCases, id: \.self) { type in
                                Text("\(type.emoji) \(type.displayName)").tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundColor(.textPrimary)
                    }

                    if isGroupPost {
                        Section("Visibility") {
                            Toggle("Members only", isOn: $isMembersOnly)
                            Text(isMembersOnly
                                 ? "Only group members will see this in the group and For You."
                                 : "Anyone can discover this from For You, and group members will still see it too.")
                                .font(.captionMedium)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    if allowsAnnouncements {
                        Section("Post Type") {
                            Picker("Post Type", selection: $isAnnouncement) {
                                Text("Activity").tag(false)
                                Text("Announcement").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .disabled(existingPost != nil)
                            Text("Announcements are for updates from group admins. Activities are joinable plans.")
                                .font(.captionMedium)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Section("Where & When") {
                        TextField("Location", text: $location)
                            .foregroundColor(.textPrimary)
                        Toggle("Set a time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Time", selection: $scheduledTime, displayedComponents: [.date, .hourAndMinute])
                                .foregroundColor(.textPrimary)
                        }
                    }

                    if !isAnnouncement {
                        Section("Spots") {
                            TextField("Max participants (optional)", text: $maxParticipants)
                                .keyboardType(.numberPad)
                                .foregroundColor(.textPrimary)
                        }
                    }

                    // Group picker — only shown when not launched from within a group
                    if canPickGroup {
                        Section("Link to Group (optional)") {
                            Picker("Group", selection: $selectedGroupId) {
                                Text("None").tag(String?.none)
                                ForEach(adminGroups) { group in
                                    Text(group.name).tag(Optional(group.id))
                                }
                            }
                            .foregroundColor(.textPrimary)
                        }
                    }

                    if let error = error {
                        Section { Text(error).foregroundColor(.rose) }
                    }
                }
                .scrollContentBackground(.hidden)
                .task { groups = (try? await APIService.shared.fetchMyGroups()) ?? [] }
            }
            .navigationTitle(existingPost == nil ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(existingPost == nil ? "Post" : "Save") {
                        Task {
                            error = nil
                            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                                error = "Title is required"
                                return
                            }
                            isLoading = true
                            defer { isLoading = false }
                            do {
                                let maxP = Int(maxParticipants)
                                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                                let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

                                let post: ActivityPost
                                if let existingPost {
                                    post = try await APIService.shared.updateActivity(
                                        id: existingPost.id,
                                        title: trimmedTitle,
                                        description: trimmedDescription,
                                        activityType: activityType,
                                        location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                                        latitude: nil,
                                        longitude: nil,
                                        scheduledTime: hasTime ? scheduledTime : nil,
                                        maxParticipants: maxP,
                                        groupId: resolvedGroupId,
                                        isMembersOnly: isGroupPost ? isMembersOnly : nil,
                                        isAnnouncement: existingPost?.isAnnouncement ?? isAnnouncement
                                    )
                                } else {
                                    post = try await APIService.shared.createActivity(
                                        title: trimmedTitle,
                                        description: trimmedDescription,
                                        activityType: activityType,
                                        location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                                        latitude: nil,
                                        longitude: nil,
                                        scheduledTime: hasTime ? scheduledTime : nil,
                                        maxParticipants: maxP,
                                        groupId: resolvedGroupId,
                                        isMembersOnly: isGroupPost ? isMembersOnly : nil,
                                        isAnnouncement: isAnnouncement
                                    )
                                }
                                onSaved(post)
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
