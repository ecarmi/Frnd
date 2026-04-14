import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedFilter: TimeFilter = .tonight

    enum TimeFilter: String, CaseIterable {
        case tonight = "Tonight"
        case thisWeek = "This Week"
        case weekend = "Weekend"

        func matches(_ date: Date) -> Bool {
            let cal = Calendar.current
            let now = Date()

            switch self {
            case .tonight:
                return cal.isDateInToday(date) && date >= now

            case .thisWeek:
                guard let weekOut = cal.date(byAdding: .day, value: 7, to: now) else {
                    return false
                }
                return date >= now && date <= weekOut

            case .weekend:
                let weekday = cal.component(.weekday, from: date) // 1 = Sun, 7 = Sat
                return (weekday == 7 || weekday == 1) && date >= now
            }
        }
    }

    private var filteredEvents: [Event] {
        viewModel.events.filter { selectedFilter.matches($0.startTime) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.events.isEmpty {
                    loadingState
                } else {
                    feedContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Frnd")
                        .font(.custom("Georgia", size: 24))
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadFeed(refresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .task {
            await viewModel.loadFeed(refresh: true)
        }
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("For You")
                            .font(.custom("Georgia", size: 28))
                            .foregroundColor(.textPrimary)

                        Text("Chicago · Hyde Park")
                            .font(.captionMedium)
                            .foregroundColor(.textSecondary)
                    }

                    HStack(spacing: Spacing.sm) {
                        ForEach(TimeFilter.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(.spring(response: 0.25)) {
                                    selectedFilter = filter
                                }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.captionSmall)
                                    .foregroundColor(selectedFilter == filter ? .white : .textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedFilter == filter ? Color.ember : Color.bgRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                selectedFilter == filter ? Color.clear : Color.bgBorder
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.base)
                .padding(.bottom, Spacing.md)

                if filteredEvents.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(filteredEvents) { event in
                            EventCardView(
                                event: event,
                                onSave: {
                                    viewModel.toggleSave(eventId: event.id)
                                },
                                onRSVP: {
                                    Task {
                                        await viewModel.rsvp(
                                            eventId: event.id,
                                            status: event.userRSVPStatus == .going ? .interested : .going
                                        )
                                    }
                                }
                            )
                            .padding(.horizontal, Spacing.base)
                            .task {
                                await viewModel.loadMoreIfNeeded(currentEvent: event)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .tint(.ember)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(.bottom, Spacing.base)
                }

                Color.clear
                    .frame(height: 88)
            }
        }
        .refreshable {
            await viewModel.loadFeed(refresh: true)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    ShimmerCard()
                        .padding(.horizontal, Spacing.base)
                }
            }
            .padding(.top, Spacing.base)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Text("🗓️")
                .font(.system(size: 48))

            Text("Nothing \(selectedFilter.rawValue.lowercased())")
                .font(.headingMedium)
                .foregroundColor(.textPrimary)

            Text("Try a different time range or check back later.")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xxxl)
    }
}

// MARK: - Shimmer Card

private struct ShimmerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShimmerView()
                .frame(height: 180)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Radius.lg,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: Radius.lg
                    )
                )

            VStack(alignment: .leading, spacing: 12) {
                ShimmerView()
                    .frame(height: 20)
                    .clipShape(Capsule())

                ShimmerView()
                    .frame(height: 14)
                    .frame(maxWidth: 180)
                    .clipShape(Capsule())

                ShimmerView()
                    .frame(height: 14)
                    .frame(maxWidth: 120)
                    .clipShape(Capsule())
            }
            .padding(Spacing.base)
            .background(Color.bgSurface)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: Radius.lg,
                    bottomTrailingRadius: Radius.lg,
                    topTrailingRadius: 0
                )
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.bgBorder)
        )
    }
}
