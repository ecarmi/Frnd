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
                                ActivityPostCard(post: post) { updated in
                                    if let idx = viewModel.posts.firstIndex(where: { $0.id == updated.id }) {
                                        viewModel.posts[idx] = updated
                                    }
                                }
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

    @State private var isLoading = false

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

                joinButton
            }
        }
        .padding(Spacing.base)
        .cardStyle()
    }

    private var joinButton: some View {
        Button {
            Task {
                isLoading = true
                do {
                    if post.isJoined {
                        try await APIService.shared.leaveActivity(id: post.id)
                        // Signal parent to reload (server has updated state)
                    } else {
                        let updated = try await APIService.shared.joinActivity(id: post.id)
                        onUpdate(updated)
                    }
                } catch {}
                isLoading = false
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
    let groupId: String?
    let onCreated: (ActivityPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var activityType: ActivityType = .social
    @State private var location = ""
    @State private var scheduledTime = Date().addingTimeInterval(3600 * 2)
    @State private var hasTime = false
    @State private var maxParticipants = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var groups: [Group] = []
    @State private var selectedGroupId: String? = nil

    // Resolved group: use injected groupId if provided, otherwise use picker selection
    private var resolvedGroupId: String? { groupId ?? selectedGroupId }

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

                    Section("Where & When") {
                        TextField("Location", text: $location)
                            .foregroundColor(.textPrimary)
                        Toggle("Set a time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Time", selection: $scheduledTime, displayedComponents: [.date, .hourAndMinute])
                                .foregroundColor(.textPrimary)
                        }
                    }

                    Section("Spots") {
                        TextField("Max participants (optional)", text: $maxParticipants)
                            .keyboardType(.numberPad)
                            .foregroundColor(.textPrimary)
                    }

                    // Group picker — only shown when not launched from within a group
                    if groupId == nil && !groups.isEmpty {
                        Section("Link to Group (optional)") {
                            Picker("Group", selection: $selectedGroupId) {
                                Text("None").tag(String?.none)
                                ForEach(groups) { group in
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
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        Task {
                            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                                error = "Title is required"
                                return
                            }
                            isLoading = true
                            do {
                                let maxP = Int(maxParticipants)
                                let post = try await APIService.shared.createActivity(
                                    title: title,
                                    description: description,
                                    activityType: activityType,
                                    location: location.isEmpty ? nil : location,
                                    latitude: nil,
                                    longitude: nil,
                                    scheduledTime: hasTime ? scheduledTime : nil,
                                    maxParticipants: maxP,
                                    groupId: resolvedGroupId
                                )
                                onCreated(post)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isLoading = false
                        }
                    }
                    .foregroundColor(.ember)
                    .disabled(title.isEmpty || isLoading)
                }
            }
        }
    }
}
