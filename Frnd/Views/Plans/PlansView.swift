import SwiftUI
import Combine

@MainActor
final class PlansViewModel: ObservableObject {
    @Published var plans: [Plan] = []
    @Published var goingEvents: [Event] = []
    @Published var isLoading = false
    @Published var error: String?

    func loadPlans() async {
        isLoading = true
        defer { isLoading = false }
        let fetchedPlans = (try? await APIService.shared.fetchMyPlans()) ?? []
        let upcomingGoing = (try? await APIService.shared.fetchGoingEvents()) ?? []

        plans = fetchedPlans
        let plannedEventIDs = Set(fetchedPlans.flatMap(\.eventOptions).map(\.id))
        goingEvents = upcomingGoing.filter { !plannedEventIDs.contains($0.id) }
    }

    func createPlan(title: String, eventIds: [String], inviteeIds: [String]) async throws -> Plan {
        let plan = try await APIService.shared.createPlan(title: title, eventIds: eventIds, inviteeIds: inviteeIds)
        insertOrUpdate(plan)
        return plan
    }

    func insertOrUpdate(_ plan: Plan) {
        plans.removeAll { $0.id == plan.id }
        plans.insert(plan, at: 0)
    }
}

@MainActor
final class PublicGroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        groups = (try? await APIService.shared.fetchPublicGroups()) ?? []
    }
}

struct PlansView: View {
    @StateObject private var viewModel = PlansViewModel()
    @StateObject private var groupsViewModel = GroupsViewModel()
    @StateObject private var publicGroupsViewModel = PublicGroupsViewModel()
    @EnvironmentObject private var savedEventsStore: SavedEventsStore
    @State private var showCreatePlan = false
    @State private var prefillEvent: Event?
    @State private var selectedSegment = 0
    @State private var showCreateGroup = false
    @State private var showJoinGroup = false
    @EnvironmentObject var appState: AppState

    private var activePlans: [Plan] { viewModel.plans.filter { $0.status != .archived } }
    private var pastPlans:   [Plan] { viewModel.plans.filter { $0.status == .archived } }
    private var hasPlanTabContent: Bool {
        !savedEventsStore.savedEvents.isEmpty || !viewModel.goingEvents.isEmpty || !viewModel.plans.isEmpty
    }

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
                        } else if !hasPlanTabContent {
                            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            plansList
                        }
                    case 1:
                        GroupsViewEmbedded(
                            viewModel: groupsViewModel,
                            showCreate: $showCreateGroup,
                            showJoin: $showJoinGroup
                        )
                    case 2:
                        PublicGroupsViewEmbedded(
                            viewModel: publicGroupsViewModel,
                            groupsViewModel: groupsViewModel
                        )
                    default:
                        EmptyView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(["Plans", "My Groups", "Public Groups"][selectedSegment])
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedSegment == 1 || selectedSegment == 2 {
                        Menu {
                            Button("Create Group") { showCreateGroup = true }
                            Button("Join via Code") { showJoinGroup = true }
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(.ember)
                        }
                    } else {
                        Button {
                            if selectedSegment == 0 { showCreatePlan = true }
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(.ember)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePlan, onDismiss: {
            prefillEvent = nil
            Task { await refreshPlansData() }
        }) {
            CreatePlanView(prefillEvent: prefillEvent) { createdPlan in
                viewModel.insertOrUpdate(createdPlan)
            }
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupSheet(viewModel: groupsViewModel)
        }
        .sheet(isPresented: $showJoinGroup) {
            JoinGroupSheet(viewModel: groupsViewModel)
        }
        .onAppear {
            Task { await refreshPlansData() }
        }
    }

    private func refreshPlansData() async {
        await viewModel.loadPlans()
        await groupsViewModel.load()
        await publicGroupsViewModel.load()
        let savedEvents = (try? await APIService.shared.fetchSavedEvents()) ?? savedEventsStore.savedEvents
        savedEventsStore.replaceSavedEvents(savedEvents)
    }

    private var segmentPicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(Array(["Plans", "My Groups", "Public Groups"].enumerated()), id: \.offset) { idx, label in
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
                if !savedEventsStore.savedEvents.isEmpty {
                    sectionHeader("Saved Events", count: savedEventsStore.savedEvents.count)
                    ForEach(savedEventsStore.savedEvents.prefix(4)) { event in
                        EventPlanRow(event: event) {
                            prefillEvent = event
                            showCreatePlan = true
                        }
                    }
                }

                if !viewModel.goingEvents.isEmpty {
                    sectionHeader("Going", count: viewModel.goingEvents.count)
                    ForEach(viewModel.goingEvents.prefix(6)) { event in
                        EventPlanRow(event: event) {
                            prefillEvent = event
                            showCreatePlan = true
                        }
                    }
                }

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
            Text("Create a plan with or without an event and invite your crew.")
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

private struct EventPlanRow: View {
    let event: Event
    let onStartPlan: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.categoryColor(for: event.category).opacity(0.18))
                    .frame(width: 46, height: 46)
                Text(event.category.emoji)
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headingSmall)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text("\(event.startTime.relativeEventTime) · \(event.venue.name)")
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Start Plan", action: onStartPlan)
                .font(.captionMedium)
                .foregroundColor(.ember)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.ember.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(Spacing.md)
        .cardStyle()
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
                Text(createdAtLabel)
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

    private var createdAtLabel: String {
        plan.createdAt.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Embedded wrappers (no NavigationStack, inherits parent)

struct GroupsViewEmbedded: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Binding var showCreate: Bool
    @Binding var showJoin: Bool

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
                    HStack(spacing: Spacing.sm) {
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
        .task { await viewModel.load() }
    }
}

struct PublicGroupsViewEmbedded: View {
    @ObservedObject var viewModel: PublicGroupsViewModel
    @ObservedObject var groupsViewModel: GroupsViewModel
    @State private var searchText = ""
    @State private var sortOption: PublicGroupSort = .mostMembers

    private enum PublicGroupSort: String, CaseIterable, Identifiable {
        case mostMembers = "Most Members"
        case newest = "Newest"
        case name = "Name"

        var id: String { rawValue }
    }

    private var displayedGroups: [Group] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = viewModel.groups.filter { group in
            guard !query.isEmpty else { return true }
            return group.name.localizedCaseInsensitiveContains(query) ||
                group.description.localizedCaseInsensitiveContains(query)
        }

        switch sortOption {
        case .mostMembers:
            return filtered.sorted {
                if $0.memberCount == $1.memberCount {
                    return $0.createdAt > $1.createdAt
                }
                return $0.memberCount > $1.memberCount
            }
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            if viewModel.groups.isEmpty && !viewModel.isLoading {
                VStack(spacing: Spacing.xl) {
                    Text("🌍").font(.system(size: 56))
                    Text("No public groups").font(.headingMedium).foregroundColor(.textPrimary)
                    Text("Public groups will appear here once people start opening them up.")
                        .font(.bodyMedium).foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, Spacing.xxxl)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Spacing.base) {
                        VStack(spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.textTertiary)
                                TextField("Search public groups", text: $searchText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundColor(.textPrimary)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.bgRaised)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))

                            HStack {
                                Text("\(displayedGroups.count) groups")
                                    .font(.captionMedium)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Menu {
                                    ForEach(PublicGroupSort.allCases) { option in
                                        Button(option.rawValue) {
                                            sortOption = option
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(sortOption.rawValue)
                                            .font(.captionMedium)
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.captionSmall)
                                    }
                                    .foregroundColor(.ember)
                                }
                            }
                        }

                        if displayedGroups.isEmpty {
                            VStack(spacing: Spacing.sm) {
                                Text("No matching groups")
                                    .font(.headingSmall)
                                    .foregroundColor(.textPrimary)
                                Text("Try a different search or sort.")
                                    .font(.captionMedium)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xl)
                        }

                        ForEach(displayedGroups) { group in
                            NavigationLink(destination: GroupDetailView(group: group, viewModel: groupsViewModel)) {
                                GroupRowView(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                        Color.clear.frame(height: 88)
                    }
                    .padding(Spacing.base)
                }
            }
        }
    }
}
