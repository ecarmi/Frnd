import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showingEventDetail: Event?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if viewModel.isLoading && viewModel.events.isEmpty {
                    loadingState
                } else if viewModel.events.isEmpty {
                    emptyState
                } else {
                    feedContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Frnd")
                        .font(.custom("Georgia", size: 24))
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            // Location filter
                        } label: {
                            Image(systemName: "location.fill")
                                .foregroundColor(.ember)
                        }
                        Button {
                            // Filter sheet
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.textSecondary)
                        }
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
            LazyVStack(spacing: Spacing.base) {
                // Tonight header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("For You")
                            .font(.custom("Georgia", size: 28))
                            .foregroundColor(.textPrimary)
                        Text("Tonight in Chicago")
                            .font(.captionMedium)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    // Time filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(["Tonight", "This Week", "Weekend"], id: \.self) { label in
                                PillView(text: label, color: label == "Tonight" ? .ember : .textTertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.base)

                ForEach(viewModel.events) { event in
                    EventCardView(
                        event: event,
                        onSave: { viewModel.toggleSave(eventId: event.id) },
                        onRSVP: {
                            Task {
                                await viewModel.rsvp(
                                    eventId: event.id,
                                    status: event.userRSVPStatus == .going ? .interested : .going
                                )
                            }
                        },
                        onSwipeLeft: {
                            Task { await viewModel.swipe(event: event, direction: .left) }
                        },
                        onSwipeRight: {
                            Task { await viewModel.swipe(event: event, direction: .right) }
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

                // Bottom padding for tab bar
                Color.clear.frame(height: 88)
            }
        }
        .refreshable {
            await viewModel.loadFeed(refresh: true)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.base) {
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
            Text("✨")
                .font(.system(size: 64))
            Text("No events nearby")
                .font(.headingMedium)
                .foregroundColor(.textPrimary)
            Text("Try expanding your radius or check back later.")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            Button("Refresh") {
                Task { await viewModel.loadFeed(refresh: true) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(width: 160)
        }
        .padding(Spacing.xxxl)
    }
}

// MARK: - Shimmer Card

private struct ShimmerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShimmerView()
                .frame(height: 200)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Radius.lg, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: Radius.lg
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
                    topLeadingRadius: 0, bottomLeadingRadius: Radius.lg,
                    bottomTrailingRadius: Radius.lg, topTrailingRadius: 0
                )
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.bgBorder)
        )
    }
}
