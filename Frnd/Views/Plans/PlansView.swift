import SwiftUI
import Combine

@MainActor
final class PlansViewModel: ObservableObject {
    @Published var plans: [Plan] = []
    @Published var isLoading = false
    @Published var error: String?

    func loadPlans() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        var fetchedPlans: [Plan] = []
        do {
            fetchedPlans = try await APIService.shared.fetchMyPlans()
        } catch {
            self.error = error.localizedDescription
        }

        plans = fetchedPlans
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

struct PlansView: View {
    @StateObject private var viewModel = PlansViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showCreatePlan = false
    @State private var prefillEvent: Event?

    private var activePlans: [Plan] { viewModel.plans.filter { $0.status != .archived } }
    private var hasPlanTabContent: Bool { !activePlans.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if viewModel.isLoading && !hasPlanTabContent {
                    ProgressView()
                        .tint(.ember)
                } else {
                    plansList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Plans")
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreatePlan = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.ember)
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
        .onAppear {
            Task { await refreshPlansData() }
        }
        .onChange(of: appState.plansRefreshID) {
            Task { await refreshPlansData() }
        }
    }

    private func refreshPlansData() async {
        await viewModel.loadPlans()
    }

    private var plansList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Spacing.base) {
                if let error = viewModel.error, hasPlanTabContent {
                    LoadErrorCard(
                        title: "Plans partially unavailable",
                        message: error,
                        retryTitle: "Reload Plans",
                        retry: {
                            Task { await refreshPlansData() }
                        }
                    )
                }

                if !activePlans.isEmpty {
                    sectionHeader("Active Plans", count: activePlans.count)
                    ForEach(activePlans) { plan in
                        NavigationLink(destination: PlanDetailView(plan: plan)) {
                            PlanRowView(plan: plan, currentUserId: appState.currentUser?.id ?? "")
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !hasPlanTabContent {
                    if let error = viewModel.error {
                        LoadErrorCard(
                            title: "Plans unavailable",
                            message: error,
                            retryTitle: "Reload Plans",
                            retry: {
                                Task { await refreshPlansData() }
                            }
                        )
                    } else {
                        emptyState
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
            Text("No active plans yet")
                .font(.headingMedium)
                .foregroundColor(.textPrimary)
            Text("Create a plan and it will show up here once it’s active.")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
            Button("Start a Plan") { showCreatePlan = true }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxxl)
    }
}

// MARK: - Plan Row

struct PlanRowView: View {
    let plan: Plan
    let currentUserId: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                statusBadge

                Spacer()

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
