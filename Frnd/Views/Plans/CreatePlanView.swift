import SwiftUI

struct CreatePlanView: View {
    let prefillEvent: Event?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var title: String = ""
    @State private var selectedEventIds: Set<String> = []
    @State private var inviteeIds: Set<String> = []
    @State private var isLoading = false
    @State private var friends: [Friendship] = []

    init(prefillEvent: Event?) {
        self.prefillEvent = prefillEvent
        if let event = prefillEvent {
            _title = State(initialValue: event.title)
            _selectedEventIds = State(initialValue: [event.id])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        // Title
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Plan Name")
                                .font(.mono)
                                .foregroundColor(.textTertiary)
                                .textCase(.uppercase)
                                .tracking(1.5)

                            TextField("", text: $title,
                                      prompt: Text("e.g. \"Saturday Night\"").foregroundColor(.textTertiary))
                                .font(.headingMedium)
                                .foregroundColor(.textPrimary)
                                .padding()
                                .background(Color.bgRaised)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))
                        }

                        // Prefilled event
                        if let event = prefillEvent {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Event")
                                    .font(.mono)
                                    .foregroundColor(.textTertiary)
                                    .textCase(.uppercase)
                                    .tracking(1.5)

                                HStack(spacing: Spacing.md) {
                                    Text(event.category.emoji)
                                        .font(.system(size: 28))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title)
                                            .font(.headingSmall)
                                            .foregroundColor(.textPrimary)
                                        Text(event.startTime.relativeEventTime + " · " + event.venue.name)
                                            .font(.captionMedium)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.teal)
                                }
                                .padding(Spacing.base)
                                .cardStyle()
                            }
                        }

                        // Invite friends
                        if !friends.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Invite")
                                    .font(.mono)
                                    .foregroundColor(.textTertiary)
                                    .textCase(.uppercase)
                                    .tracking(1.5)

                                ForEach(friends) { friendship in
                                    if let user = friendship.otherUser {
                                        InviteRow(
                                            user: user,
                                            isSelected: inviteeIds.contains(user.id)
                                        ) {
                                            if inviteeIds.contains(user.id) {
                                                inviteeIds.remove(user.id)
                                            } else {
                                                inviteeIds.insert(user.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Button(action: createPlan) {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Label("Create Plan", systemImage: "person.2.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.base)
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .task {
            friends = (try? await APIService.shared.fetchFriends()) ?? []
        }
    }

    private func createPlan() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                _ = try await APIService.shared.createPlan(
                    title: title.trimmingCharacters(in: .whitespaces),
                    eventIds: Array(selectedEventIds),
                    inviteeIds: Array(inviteeIds)
                )
                dismiss()
            } catch {
                // Handle error
            }
        }
    }
}

private struct InviteRow: View {
    let user: User
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.md) {
                AvatarView(name: user.name, imageURL: user.avatarURL, size: 40)
                Text(user.name)
                    .font(.headingSmall)
                    .foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .ember : .textTertiary)
            }
            .padding(Spacing.md)
            .cardStyle()
        }
        .animation(.spring(response: 0.2), value: isSelected)
    }
}
