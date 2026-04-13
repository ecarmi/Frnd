import SwiftUI

struct EventCardView: View {
    let event: Event
    let onSave: () -> Void
    let onRSVP: () -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var showDetail = false

    private let swipeThreshold: CGFloat = 80

    var body: some View {
        ZStack(alignment: .top) {
            // Background card (gives slight depth)
            cardContent
                .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
                .rotationEffect(.degrees(cardRotation))
                .gesture(swipeGesture)
                .onTapGesture { showDetail = true }

            // Swipe overlays
            swipeOverlays
        }
        .sheet(isPresented: $showDetail) {
            EventDetailView(event: event)
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image / gradient
            heroSection

            // Info section
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Title
                Text(event.title)
                    .font(.headingMedium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                // Venue + distance
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mappin.fill")
                        .font(.captionSmall)
                        .foregroundColor(.ember)
                    Text(event.venue.name)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                    Text("·")
                        .foregroundColor(.textTertiary)
                    Text("0.8 mi")
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }

                // Pill row
                HStack(spacing: Spacing.sm) {
                    PillView(text: event.startTime.relativeEventTime, color: .ember)
                    PillView(text: event.priceDisplay, color: event.isFree ? .teal : .textSecondary)
                    Spacer()
                }

                // Social proof row
                socialProofRow

                // AI Reason chip
                if let reason = event.aiReasonChip {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.captionSmall)
                            .foregroundColor(.teal)
                        Text(reason)
                            .font(.captionMedium)
                            .foregroundColor(.teal)
                    }
                }

                Divider()
                    .overlay(Color.bgBorder)

                // Action row
                actionRow
            }
            .padding(Spacing.base)
        }
        .cardStyle()
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.categoryColor(for: event.category).opacity(0.7),
                            Color.bgSurface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(event.category.emoji)
                        .font(.system(size: 72))
                        .opacity(0.8)
                    Spacer()
                }
                Spacer()
            }

            // Category label
            HStack {
                PillView(text: event.category.displayName, color: Color.categoryColor(for: event.category))
                    .padding(12)
                Spacer()
            }
        }
        .frame(height: 200)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Radius.lg, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: Radius.lg
            )
        )
    }

    // MARK: - Social Proof

    private var socialProofRow: some View {
        HStack(spacing: Spacing.sm) {
            if !event.friendsGoing.isEmpty {
                HStack(spacing: -6) {
                    ForEach(event.friendsGoing.prefix(3)) { user in
                        AvatarView(name: user.name, imageURL: user.avatarURL, size: 24)
                            .overlay(Circle().strokeBorder(Color.bgSurface, lineWidth: 1.5))
                    }
                }
                let names = event.friendsGoing.prefix(2).map {
                    $0.name.components(separatedBy: " ").first ?? $0.name
                }.joined(separator: ", ")
                let extra = max(0, event.friendsGoing.count - 2)
                let label = extra > 0 ? "\(names) + \(extra) going" : "\(names) going"
                Text(label)
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
            } else if event.totalInterested > 0 {
                Image(systemName: "person.fill")
                    .font(.captionSmall)
                    .foregroundColor(.textTertiary)
                Text("\(event.totalInterested) interested")
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 0) {
            // Save
            ActionButton(
                icon: event.isSaved ? "bookmark.fill" : "bookmark",
                color: event.isSaved ? .ember : .textTertiary,
                action: onSave
            )
            Spacer()
            // Share
            ActionButton(icon: "paperplane", color: .textTertiary) {
                // Share sheet
            }
            Spacer()
            // RSVP
            Button(action: onRSVP) {
                HStack(spacing: 6) {
                    Image(systemName: event.userRSVPStatus == .going ? "checkmark" : "ticket.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(event.userRSVPStatus == .going ? "Going" : (event.isFree ? "RSVP" : "Get Tickets"))
                        .font(.captionMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.base)
                .frame(height: 36)
                .background(event.userRSVPStatus == .going ? Color.teal : Color.ember)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Swipe Overlays

    private var swipeOverlays: some View {
        ZStack {
            // Dismiss overlay (swipe left)
            if dragOffset.width < -20 {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.rose)
                        Text("Not for me")
                            .font(.captionMedium)
                            .foregroundColor(.rose)
                    }
                    .padding(20)
                    .opacity(min(1.0, abs(dragOffset.width) / swipeThreshold))
                }
            }

            // Save overlay (swipe right)
            if dragOffset.width > 20 {
                HStack {
                    VStack {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.teal)
                        Text("Saved")
                            .font(.captionMedium)
                            .foregroundColor(.teal)
                    }
                    .padding(20)
                    .opacity(min(1.0, dragOffset.width / swipeThreshold))
                    Spacer()
                }
            }
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                cardRotation = Double(value.translation.width / 20)
            }
            .onEnded { value in
                let width = value.translation.width
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if width < -swipeThreshold {
                        // Swipe left - dismiss
                        dragOffset = CGSize(width: -500, height: 0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSwipeLeft()
                        }
                    } else if width > swipeThreshold {
                        // Swipe right - save
                        dragOffset = CGSize(width: 500, height: 0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSwipeRight()
                        }
                    } else {
                        dragOffset = .zero
                        cardRotation = 0
                    }
                }
            }
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
    }
}
