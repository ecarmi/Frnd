import SwiftUI
import MapKit

struct EventDetailView: View {
    @State private var event: Event
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var savedEventsStore: SavedEventsStore
    @State private var rsvpStatus: RSVPStatus?
    @State private var showCreatePlan = false
    @State private var isRSVPLoading = false
    @State private var showAttendees = false
    @State private var attendees: [User] = []
    @State private var isLoadingAttendees = false
    @State private var attendeeError: String?

    init(event: Event) {
        _event = State(initialValue: event)
        _rsvpStatus = State(initialValue: event.userRSVPStatus)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                ZStack(alignment: .topLeading) {
                    heroImage
                    // Dismiss button
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(16)
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Title block
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            PillView(text: primaryTimeLabel, color: .ember)
                            PillView(text: event.priceDisplay, color: event.isFree ? .teal : .textSecondary)
                            Spacer()
                            PillView(text: event.category.displayName, color: Color.categoryColor(for: event.category))
                        }

                        Text(event.title)
                            .font(.headingLarge)
                            .foregroundColor(.textPrimary)

                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "mappin.fill")
                                .font(.captionMedium)
                                .foregroundColor(.ember)
                            Text("\(event.venue.name) · \(event.venue.address)")
                                .font(.captionMedium)
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    // Attendee strip
                    if !event.friendsGoing.isEmpty || event.totalInterested > 0 {
                        attendeeStrip
                    }

                    // Action buttons
                    actionButtons

                    Divider().overlay(Color.bgBorder)

                    // Description
                    if !event.description.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("About")
                                .font(.headingSmall)
                                .foregroundColor(.textPrimary)
                            Text(event.description)
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    // Vibe tags
                    if !event.tags.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Vibe")
                                .font(.headingSmall)
                                .foregroundColor(.textPrimary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    ForEach(event.tags, id: \.self) { tag in
                                        PillView(text: tag, color: .textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    Divider().overlay(Color.bgBorder)

                    // Mini map
                    venueSection

                }
                .padding(.horizontal, 20)
                .padding(.top, Spacing.xl)
                .padding(.bottom, 100)
            }
        }
        .background(Color.bgPrimary)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showCreatePlan) {
            CreatePlanView(prefillEvent: event)
        }
        .sheet(isPresented: $showAttendees) {
            AttendeesSheet(
                title: event.title,
                attendees: attendees,
                isLoading: isLoadingAttendees,
                error: attendeeError
            )
        }
        .task {
            await refreshEvent()
        }
    }

    // MARK: - Hero Image

    private var heroImage: some View {
        ZStack {
            if let _ = event.imageURL {
                // AsyncImage would go here with real data
                Rectangle()
                    .fill(heroGradient)
            } else {
                Rectangle()
                    .fill(heroGradient)
            }
            LinearGradient(
                colors: [Color.clear, Color.bgPrimary],
                startPoint: UnitPoint(x: 0.5, y: 0.5),
                endPoint: .bottom
            )
        }
        .frame(height: 280)
        .overlay(
            VStack {
                Spacer()
                Text(event.category.emoji)
                    .font(.system(size: 64))
                    .padding(.bottom, 20)
            }
        )
    }

    private var heroGradient: LinearGradient {
        let color = Color.categoryColor(for: event.category)
        return LinearGradient(
            colors: [color.opacity(0.6), Color.bgPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Attendee Strip

    private var attendeeStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                Task { await loadAttendees() }
            } label: {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Who's going")
                            .font(.headingSmall)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.captionMedium)
                            .foregroundColor(.textTertiary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: -8) {
                            ForEach(event.friendsGoing.prefix(8)) { user in
                                AvatarView(name: user.name, imageURL: user.avatarURL, size: 40)
                                    .overlay(Circle().strokeBorder(Color.bgPrimary, lineWidth: 2))
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    Text("Tap to view the attendee list")
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        let isSaved = savedEventsStore.isSaved(event)

        return HStack(spacing: Spacing.md) {
            Button {
                toggleRSVP()
            } label: {
                HStack {
                    if isRSVPLoading {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: rsvpStatus == .going ? "checkmark" : (event.activityPostId == nil ? "ticket.fill" : "person.badge.plus"))
                            .font(.system(size: 14, weight: .bold))
                        Text(rsvpButtonLabel)
                            .font(.headingSmall)
                    }
                }
                .foregroundColor(rsvpStatus == .going ? Color.ember : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(rsvpStatus == .going ? Color.clear : Color.ember)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.ember, lineWidth: rsvpStatus == .going ? 1 : 0))
            }
            .disabled(isRSVPLoading)

            Button {
                Task { try? await savedEventsStore.toggle(event: event) }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 20))
                    .foregroundColor(isSaved ? .ember : .textSecondary)
                    .frame(width: 48, height: 48)
                    .background(Color.bgRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }

            if event.activityPostId == nil {
                Button {
                    showCreatePlan = true
                } label: {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.violet)
                        .frame(width: 48, height: 48)
                        .background(Color.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
            }
        }
    }

    private var rsvpButtonLabel: String {
        if event.activityPostId != nil {
            return rsvpStatus == .going ? "Joined" : "Join Activity"
        }
        switch rsvpStatus {
        case .going:      return "Going"
        case .interested: return "Interested"
        default:          return event.isFree ? "RSVP Free" : "Get Tickets"
        }
    }

    private func toggleRSVP() {
        guard !isRSVPLoading else { return }

        isRSVPLoading = true
        Task {
            defer { isRSVPLoading = false }
            if let activityPostId = event.activityPostId {
                let wasJoined = rsvpStatus == .going
                rsvpStatus = wasJoined ? nil : .going
                event.userRSVPStatus = rsvpStatus

                do {
                    let updatedActivity: ActivityPost
                    if wasJoined {
                        try await APIService.shared.leaveActivity(id: activityPostId)
                        updatedActivity = try await APIService.shared.fetchActivity(id: activityPostId)
                    } else {
                        updatedActivity = try await APIService.shared.joinActivity(id: activityPostId)
                    }
                    event.friendsGoing = updatedActivity.participants.compactMap(\.user)
                    event.totalInterested = updatedActivity.participantCount
                    event.userRSVPStatus = updatedActivity.isJoined ? .going : nil
                    rsvpStatus = event.userRSVPStatus
                } catch {
                    rsvpStatus = wasJoined ? .going : nil
                    event.userRSVPStatus = rsvpStatus
                }
            } else {
                let previousStatus = rsvpStatus
                let newStatus: RSVPStatus = rsvpStatus == .going ? .interested : .going
                rsvpStatus = newStatus
                event.userRSVPStatus = newStatus

                do {
                    let rsvp = try await APIService.shared.rsvp(eventId: event.id, status: newStatus)
                    rsvpStatus = rsvp.status
                    event.userRSVPStatus = rsvp.status
                    await refreshEvent()
                } catch {
                    rsvpStatus = previousStatus
                    event.userRSVPStatus = previousStatus
                }
            }
        }
    }

    private func refreshEvent() async {
        if let activityPostId = event.activityPostId {
            guard let activity = try? await APIService.shared.fetchActivity(id: activityPostId) else { return }
            event.friendsGoing = activity.participants.compactMap(\.user)
            event.totalInterested = activity.participantCount
            event.userRSVPStatus = activity.isJoined ? .going : nil
            rsvpStatus = event.userRSVPStatus
            return
        }

        guard let refreshed = try? await APIService.shared.fetchEvent(id: event.id) else { return }
        event = refreshed
        rsvpStatus = refreshed.userRSVPStatus
    }

    private func loadAttendees() async {
        isLoadingAttendees = true
        attendeeError = nil
        showAttendees = true
        defer { isLoadingAttendees = false }

        do {
            if let activityPostId = event.activityPostId {
                let activity = try await APIService.shared.fetchActivity(id: activityPostId)
                attendees = activity.participants.compactMap(\.user)
            } else {
                attendees = try await APIService.shared.fetchEventAttendees(id: event.id)
            }
        } catch {
            attendees = []
            attendeeError = error.localizedDescription
        }
    }

    private var primaryTimeLabel: String {
        guard event.activityPostId != nil else { return event.startTime.relativeEventTime }

        let calendar = Calendar.current
        if calendar.isDateInToday(event.startTime) {
            return "Tonight, \(event.startTime.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(event.startTime) {
            return "Tomorrow, \(event.startTime.formatted(date: .omitted, time: .shortened))"
        }
        return event.startTime.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Venue Section

    private var venueSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Venue")
                .font(.headingSmall)
                .foregroundColor(.textPrimary)

            // Mini map snapshot
            Map(initialPosition: .region(MKCoordinateRegion(
                center: event.venue.location,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker(event.venue.name, coordinate: event.venue.location)
                    .tint(Color.ember)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .disabled(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.venue.name)
                    .font(.headingSmall)
                    .foregroundColor(.textPrimary)
                Text(event.venue.address)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }

            if !event.venue.vibeTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(event.venue.vibeTags, id: \.self) { tag in
                            PillView(text: tag, color: .teal)
                        }
                    }
                }
            }
        }
    }
}

private struct AttendeesSheet: View {
    let title: String
    let attendees: [User]
    let isLoading: Bool
    let error: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.ember)
                } else if let error {
                    LoadErrorCard(
                        title: "Could not load attendees",
                        message: error,
                        retryTitle: "Close",
                        retry: { dismiss() }
                    )
                    .padding(.horizontal, Spacing.base)
                } else if attendees.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Text("No one is going yet")
                            .font(.headingMedium)
                            .foregroundColor(.textPrimary)
                        Text("Attendees will appear here once people join.")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Spacing.xxxl)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(attendees) { attendee in
                                HStack(spacing: Spacing.md) {
                                    AvatarView(name: attendee.name, imageURL: attendee.avatarURL, size: 44)
                                    Text(attendee.name)
                                        .font(.bodyLarge)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                }
                                .padding(Spacing.md)
                                .cardStyle()
                            }
                        }
                        .padding(Spacing.base)
                    }
                }
            }
            .navigationTitle("Attendees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }
}
