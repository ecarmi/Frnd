import SwiftUI

struct EventCardView: View {
    let event: Event
    let onSave: () -> Void
    let onRSVP: () -> Void

    @EnvironmentObject private var savedEventsStore: SavedEventsStore
    @State private var showDetail = false

    var body: some View {
        cardContent
            .onTapGesture { showDetail = true }
            .sheet(isPresented: $showDetail) {
                EventDetailView(event: event)
            }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroSection

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(event.title)
                    .font(.headingMedium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mappin.fill")
                        .font(.captionSmall)
                        .foregroundColor(.ember)
                    Text(event.venue.name)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: Spacing.sm) {
                    PillView(text: event.startTime.relativeEventTime, color: .ember)
                    PillView(text: event.priceDisplay, color: event.isFree ? .teal : .textSecondary)
                    Spacer()
                }

                socialProofRow

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

                Divider().overlay(Color.bgBorder)

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

            Text(event.category.emoji)
                .font(.system(size: 72))
                .opacity(0.8)

            VStack(alignment: .leading) {
                CategoryLabel(text: event.category.displayName,
                              color: Color.categoryColor(for: event.category))
                    .padding(.leading, 14)
                    .padding(.top, 14)
                Spacer()
            }
        }
        .frame(height: 180)
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
                let names = event.friendsGoing.prefix(2)
                    .map { $0.name.components(separatedBy: " ").first ?? $0.name }
                    .joined(separator: ", ")
                let extra = max(0, event.friendsGoing.count - 2)
                let label = extra > 0 ? "\(names) +\(extra) going" : "\(names) going"
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
        let isSaved = savedEventsStore.isSaved(event)

        return HStack(spacing: 0) {
            ActionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                color: isSaved ? .ember : .textTertiary,
                action: onSave
            )
            Spacer()
            ShareLink(item: shareText) {
                Image(systemName: "paperplane")
                    .font(.system(size: 20))
                    .foregroundColor(.textTertiary)
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            Spacer()
            Button(action: onRSVP) {
                HStack(spacing: 6) {
                    Image(systemName: event.userRSVPStatus == .going ? "checkmark" : "ticket.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(event.userRSVPStatus == .going
                         ? "Going"
                         : (event.isFree ? "RSVP" : "Get Tickets"))
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

    private var shareText: String {
        "\(event.title) at \(event.venue.name) on \(event.startTime.formatted(date: .abbreviated, time: .shortened)). Check it out on Frnd."
    }
}

// MARK: - Category Label (rectangular, fits text)

private struct CategoryLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.captionSmall)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.4), lineWidth: 0.5))
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
