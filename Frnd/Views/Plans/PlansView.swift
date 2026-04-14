import SwiftUI
import Combine

@MainActor
final class PlansViewModel: ObservableObject {
    @Published var plans: [Plan] = []
    @Published var isLoading = false
    @Published var error: String?

    func loadPlans() async {
        isLoading = true
        defer { isLoading = false }
        do {
            plans = try await APIService.shared.fetchMyPlans()
        } catch {
            plans = Plan.mockPlans
        }
    }

    func createPlan(title: String, eventIds: [String], inviteeIds: [String]) async throws -> Plan {
        let plan = try await APIService.shared.createPlan(title: title, eventIds: eventIds, inviteeIds: inviteeIds)
        plans.insert(plan, at: 0)
        return plan
    }
}

struct PlansView: View {
    @StateObject private var viewModel = PlansViewModel()
    @State private var showCreatePlan = false
    @State private var selectedSegment = 0
    @EnvironmentObject var appState: AppState

    private var activePlans: [Plan] { viewModel.plans.filter { $0.status != .archived } }
    private var pastPlans:   [Plan] { viewModel.plans.filter { $0.status == .archived } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Segment control
                    segmentPicker
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, Spacing.sm)

                    // Content
                    switch selectedSegment {
                    case 0:
                        if viewModel.isLoading && viewModel.plans.isEmpty {
                            ProgressView().tint(.ember).frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if viewModel.plans.isEmpty {
                            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            plansList
                        }
                    case 1:
                        GroupsViewEmbedded()
                    case 2:
                        ActivityFeedViewEmbedded()
                    default:
                        EmptyView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(["Plans", "Groups", "LFG"][selectedSegment])
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedSegment == 0 { showCreatePlan = true }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.ember)
                            .opacity(selectedSegment == 0 ? 1 : 0)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePlan, onDismiss: {
            Task { await viewModel.loadPlans() }
        }) {
            CreatePlanView(prefillEvent: nil)
        }
        .task { await viewModel.loadPlans() }
    }

    private var segmentPicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(Array(["Plans", "Groups", "LFG"].enumerated()), id: \.offset) { idx, label in
                Button {
                    withAnimation(.spring(response: 0.25)) { selectedSegment = idx }
                } label: {
                    Text(label)
                        .font(.captionSmall)
                        .foregroundColor(selectedSegment == idx ? .white : .textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedSegment == idx ? Color.ember : Color.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selectedSegment == idx ? Color.clear : Color.bgBorder)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var plansList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Spacing.base) {
                // Active plans
                if !activePlans.isEmpty {
                    sectionHeader("Active Plans", count: activePlans.count)
                    ForEach(activePlans) { plan in
                        NavigationLink(destination: PlanDetailView(plan: plan)) {
                            PlanRowView(plan: plan, currentUserId: appState.currentUser?.id ?? "")
                        }
                    }
                }

                // Past plans
                if !pastPlans.isEmpty {
                    sectionHeader("Memories", count: nil)
                        .padding(.top, Spacing.sm)
                    ForEach(pastPlans) { plan in
                        NavigationLink(destination: PlanDetailView(plan: plan)) {
                            PlanRowView(plan: plan, currentUserId: appState.currentUser?.id ?? "")
                        }
                    }
                }

                Color.clear.frame(height: 88)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, Spacing.base)
        }
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title)
                .font(.mono)
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
                .tracking(2)
            if let count = count {
                Text("\(count)")
                    .font(.mono)
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.ember.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Text("👥")
                .font(.system(size: 56))
            Text("No plans yet")
                .font(.headingMedium)
                .foregroundColor(.textPrimary)
            Text("Create a plan around an event and invite your crew.")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
            Button("Start a Plan") { showCreatePlan = true }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 200)
        }
    }
}

// MARK: - Plan Row

struct PlanRowView: View {
    let plan: Plan
    let currentUserId: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                // Status badge
                statusBadge

                Spacer()

                // Member avatars
                HStack(spacing: -6) {
                    ForEach(plan.members.prefix(4)) { member in
                        AvatarView(
                            name: member.user?.name ?? "?",
                            imageURL: member.user?.avatarURL,
                            size: 28
                        )
                        .overlay(Circle().strokeBorder(Color.bgSurface, lineWidth: 1.5))
                    }
                }
            }

            Text(plan.title)
                .font(.headingSmall)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            if let event = plan.eventOptions.first {
                HStack(spacing: 6) {
                    Text(event.category.emoji)
                    Text(event.title)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack {
                Image(systemName: "person.2.fill")
                    .font(.captionSmall)
                    .foregroundColor(.textTertiary)
                Text("\(plan.confirmedCount) going")
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)

                if plan.pendingInvites > 0 {
                    Text("·")
                        .foregroundColor(.textTertiary)
                    Text("\(plan.pendingInvites) pending")
                        .font(.captionMedium)
                        .foregroundColor(.gold)
                }
                Spacer()
                Text(plan.createdAt, style: .relative)
                    .font(.captionSmall)
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(Spacing.base)
        .cardStyle()
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch plan.status {
            case .proposal: return ("Proposed", Color.textSecondary)
            case .voting:   return ("Voting", Color.gold)
            case .locked:   return ("Locked In", Color.teal)
            case .live:     return ("Live Now", Color.ember)
            case .archived: return ("Memory", Color.textTertiary)
            }
        }()
        return PillView(text: label, color: color)
    }
}

// MARK: - Embedded wrappers (no NavigationStack, inherits parent)

struct GroupsViewEmbedded: View {
    @StateObject private var viewModel = GroupsViewModel()
    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            if viewModel.groups.isEmpty && !viewModel.isLoading {
                VStack(spacing: Spacing.xl) {
                    Text("🏠").font(.system(size: 56))
                    Text("No groups yet").font(.headingMedium).foregroundColor(.textPrimary)
                    Text("Create a private space for your crew.")
                        .font(.bodyMedium).foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, Spacing.xxxl)
                    HStack(spacing: Spacing.base) {
                        Button("Create") { showCreate = true }.buttonStyle(PrimaryButtonStyle())
                        Button("Join") { showJoin = true }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Spacing.base) {
                        ForEach(viewModel.groups) { group in
                            NavigationLink(destination: GroupDetailView(group: group, viewModel: viewModel)) {
                                GroupRowView(group: group)
                            }.buttonStyle(.plain)
                        }
                        Color.clear.frame(height: 88)
                    }
                    .padding(Spacing.base)
                }
            }
        }
        .sheet(isPresented: $showCreate) { CreateGroupSheet(viewModel: viewModel) }
        .sheet(isPresented: $showJoin) { JoinGroupSheet(viewModel: viewModel) }
        .toolbar {
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
        .task { await viewModel.load() }
    }
}

struct ActivityFeedViewEmbedded: View {
    @StateObject private var viewModel = ActivityViewModel()
    @State private var showCreate = false

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            if viewModel.posts.isEmpty && !viewModel.isLoading {
                VStack(spacing: Spacing.xl) {
                    Text("🙋").font(.system(size: 56))
                    Text("No activity posts").font(.headingMedium).foregroundColor(.textPrimary)
                    Text("Post an activity to find others to join you.")
                        .font(.bodyMedium).foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, Spacing.xxxl)
                    Button("Post Activity") { showCreate = true }.buttonStyle(PrimaryButtonStyle())
                }
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
                    .padding(Spacing.base)
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateActivityView(groupId: nil) { post in
                viewModel.posts.insert(post, at: 0)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.ember)
                }
            }
        }
        .task { await viewModel.load() }
    }
}
