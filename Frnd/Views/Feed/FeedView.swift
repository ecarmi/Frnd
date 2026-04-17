import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @EnvironmentObject private var savedEventsStore: SavedEventsStore
    @State private var selectedFilter: TimeFilter = .all
    @State private var selectedTab: FeedTab = .forYou
    @State private var showCreateEvent = false
    @State private var selectedEvent: Event?
    @State private var editingEvent: Event?
    @State private var eventPendingDeletion: Event?
    @State private var actionError: String?

    enum FeedTab: String, CaseIterable {
        case forYou = "For You"
        case bookmarked = "Bookmarked"
        case going = "Going"
        case myEvents = "My Events"
    }

    enum TimeFilter: String, CaseIterable {
        case all     = "All"
        case tonight = "Tonight"
        case thisWeek = "This Week"
        case weekend = "Weekend"

        func matches(_ date: Date) -> Bool {
            let cal = Calendar.current
            let now = Date()

            switch self {
            case .all:
                return true

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
        viewModel.events
            .filter { selectedFilter.matches($0.startTime) }
            .sorted { $0.startTime < $1.startTime }
    }

    private var bookmarkedEvents: [Event] {
        savedEventsStore.savedEvents
            .sorted { $0.startTime < $1.startTime }
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
                    Text("Events")
                        .font(.custom("Georgia", size: 24))
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateEvent = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.ember)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView(groupId: nil, onCreated: { newEvent in
                viewModel.events.insert(newEvent, at: 0)
                viewModel.insertOrUpdateMyEvent(newEvent)
            })
        }
        .sheet(item: $editingEvent) { event in
            CreateEventView(
                groupId: nil,
                existingEvent: event,
                onUpdated: { updated in
                    viewModel.insertOrUpdateMyEvent(updated)
                    if selectedEvent?.id == updated.id {
                        selectedEvent = updated
                    }
                }
            )
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .alert("Delete Event?", isPresented: Binding(
            get: { eventPendingDeletion != nil },
            set: { if !$0 { eventPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let event = eventPendingDeletion else { return }
                deleteEvent(event)
                eventPendingDeletion = nil
            }
        } message: {
            Text("This event will be removed anywhere it appears.")
        }
        .alert("Event Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task {
            await viewModel.loadFeed(refresh: true)
            await viewModel.loadGoingEvents()
            await viewModel.loadMyEvents()
            let fetchedSavedEvents = (try? await APIService.shared.fetchSavedEvents()) ?? savedEventsStore.savedEvents
            savedEventsStore.replaceSavedEvents(fetchedSavedEvents)
            savedEventsStore.bootstrap(from: viewModel.events)
        }
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedTab.rawValue)
                            .font(.custom("Georgia", size: 28))
                            .foregroundColor(.textPrimary)

                        Text(subtitleText)
                            .font(.captionMedium)
                            .foregroundColor(.textSecondary)
                    }

                    contentTabs

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

                if let error = currentError {
                    LoadErrorCard(
                        title: selectedTab == .forYou ? "Could not load the feed" : "Could not load events",
                        message: error,
                        retry: {
                            Task { await reloadSelectedTab() }
                        }
                    )
                    .padding(.horizontal, Spacing.base)
                    .padding(.bottom, Spacing.md)
                }

                if currentEvents.isEmpty && !isCurrentTabLoading {
                    if currentError != nil {
                        errorState
                    } else {
                        emptyState
                    }
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        if selectedTab == .forYou {
                            ForEach(filteredEvents) { event in
                                EventCardView(
                                    event: event,
                                    onSave: {
                                        Task { try? await savedEventsStore.toggle(event: event) }
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
                        } else if selectedTab == .myEvents {
                            ForEach(currentEvents) { event in
                                ManageEventRow(
                                    event: event,
                                    onOpen: { selectedEvent = event },
                                    onEdit: { editingEvent = event },
                                    onDelete: { eventPendingDeletion = event }
                                )
                                .padding(.horizontal, Spacing.base)
                            }
                        } else {
                            ForEach(currentEvents) { event in
                                Button {
                                    selectedEvent = event
                                } label: {
                                    SearchResultRow(event: event)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, Spacing.base)
                            }
                        }

                        if selectedTab == .forYou, viewModel.isLoadingMore {
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
            await reloadSelectedTab()
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
            Text(emptyStateEmoji)
                .font(.system(size: 48))

            Text(emptyStateTitle)
                .font(.headingMedium)
                .foregroundColor(.textPrimary)

            Text(emptyStateMessage)
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xxxl)
    }

    private var errorState: some View {
        LoadErrorCard(
            title: selectedTab == .forYou ? "Feed unavailable" : "Events unavailable",
            message: currentError ?? "Something went wrong while loading events.",
            retry: {
                Task { await reloadSelectedTab() }
            }
        )
        .padding(.horizontal, Spacing.base)
    }

    private var currentEvents: [Event] {
        switch selectedTab {
        case .forYou:
            return filteredEvents
        case .bookmarked:
            return bookmarkedEvents.filter { selectedFilter.matches($0.startTime) }
        case .going:
            return viewModel.goingEvents
                .filter { selectedFilter.matches($0.startTime) }
                .sorted { $0.startTime < $1.startTime }
        case .myEvents:
            return viewModel.myEvents
                .filter { selectedFilter.matches($0.startTime) }
                .sorted { $0.startTime < $1.startTime }
        }
    }

    private var currentError: String? {
        switch selectedTab {
        case .forYou:
            return viewModel.error
        case .bookmarked:
            return nil
        case .going:
            return viewModel.goingError
        case .myEvents:
            return viewModel.myEventsError
        }
    }

    private var isCurrentTabLoading: Bool {
        switch selectedTab {
        case .forYou:
            return viewModel.isLoading
        case .bookmarked:
            return false
        case .going:
            return viewModel.isLoadingGoing
        case .myEvents:
            return viewModel.isLoadingMyEvents
        }
    }

    private var subtitleText: String {
        switch selectedTab {
        case .forYou:
            return viewModel.areaLabel
        case .bookmarked:
            return "\(bookmarkedEvents.count) saved event\(bookmarkedEvents.count == 1 ? "" : "s")"
        case .going:
            return "\(viewModel.goingEvents.count) event\(viewModel.goingEvents.count == 1 ? "" : "s") you're going to"
        case .myEvents:
            return "\(viewModel.myEvents.count) event\(viewModel.myEvents.count == 1 ? "" : "s") you can manage"
        }
    }

    private var contentTabs: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(FeedTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.captionSmall)
                        .foregroundColor(selectedTab == tab ? .white : .textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.ember : Color.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selectedTab == tab ? Color.clear : Color.bgBorder)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var emptyStateEmoji: String {
        switch selectedTab {
        case .forYou:
            return "🗓️"
        case .bookmarked:
            return "🔖"
        case .going:
            return "✅"
        case .myEvents:
            return "🛠️"
        }
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .forYou:
            return "Nothing \(selectedFilter.rawValue.lowercased())"
        case .bookmarked:
            return "No bookmarked events \(selectedFilter == .all ? "" : selectedFilter.rawValue.lowercased())".trimmingCharacters(in: .whitespaces)
        case .going:
            return "No going events \(selectedFilter == .all ? "" : selectedFilter.rawValue.lowercased())".trimmingCharacters(in: .whitespaces)
        case .myEvents:
            return "No editable events \(selectedFilter == .all ? "" : selectedFilter.rawValue.lowercased())".trimmingCharacters(in: .whitespaces)
        }
    }

    private var emptyStateMessage: String {
        switch selectedTab {
        case .forYou:
            return "Try a different time range or check back later."
        case .bookmarked:
            return "Events you save will appear here."
        case .going:
            return "RSVP to an event and it will show up here."
        case .myEvents:
            return "Events you created or can manage as a group admin will appear here."
        }
    }

    private func reloadSelectedTab() async {
        switch selectedTab {
        case .forYou:
            await viewModel.loadFeed(refresh: true)
            await viewModel.loadGoingEvents()
            let fetchedSavedEvents = (try? await APIService.shared.fetchSavedEvents()) ?? savedEventsStore.savedEvents
            savedEventsStore.replaceSavedEvents(fetchedSavedEvents)
            savedEventsStore.bootstrap(from: viewModel.events)
        case .bookmarked:
            let fetchedSavedEvents = (try? await APIService.shared.fetchSavedEvents()) ?? savedEventsStore.savedEvents
            savedEventsStore.replaceSavedEvents(fetchedSavedEvents)
        case .going:
            await viewModel.loadGoingEvents()
        case .myEvents:
            await viewModel.loadMyEvents()
        }
    }

    private func deleteEvent(_ event: Event) {
        Task {
            do {
                try await APIService.shared.deleteEvent(id: event.id)
                viewModel.removeMyEvent(id: event.id)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

private struct ManageEventRow: View {
    let event: Event
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Button(action: onOpen) {
                SearchResultRow(event: event)
            }
            .buttonStyle(.plain)

            HStack(spacing: Spacing.sm) {
                Spacer()

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.captionMedium)
                        .foregroundColor(.ember)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.ember.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.captionMedium)
                }
            }
            .padding(.horizontal, 4)
        }
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
