import SwiftUI

struct CreatePlanView: View {
    let prefillEvent: Event?
    let onCreated: ((Plan) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var savedEventsStore: SavedEventsStore
    @State private var title: String = ""
    @State private var selectedEventIds: Set<String> = []
    @State private var isLoading = false
    @State private var savedEvents: [Event] = []
    @State private var errorMessage: String?

    init(prefillEvent: Event?, onCreated: ((Plan) -> Void)? = nil) {
        self.prefillEvent = prefillEvent
        self.onCreated = onCreated
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
                        } else {
                            savedEventsSection
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.captionMedium)
                                .foregroundColor(.rose)
                                .padding(Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.rose.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }

                        Button(action: createPlan) {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Label("Create Plan", systemImage: "person.2.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoading)

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
            let fetchedSavedEvents = (try? await APIService.shared.fetchSavedEvents()) ?? savedEventsStore.savedEvents
            savedEvents = fetchedSavedEvents
            savedEventsStore.replaceSavedEvents(fetchedSavedEvents)
        }
    }

    private func createPlan() {
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Plan name is required."
            return
        }

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let plan = try await APIService.shared.createPlan(
                    title: trimmedTitle,
                    eventIds: Array(selectedEventIds),
                    inviteeIds: []
                )
                onCreated?(plan)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var savedEventsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Saved Events (Optional)")
                .font(.mono)
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
                .tracking(1.5)

            if savedEvents.isEmpty {
                Text("You can create a plan without an event, or bookmark one from the feed and attach it here.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .padding(Spacing.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))
            } else {
                ForEach(savedEvents) { event in
                    Button {
                        if selectedEventIds.contains(event.id) {
                            selectedEventIds.remove(event.id)
                            if title == event.title {
                                title = ""
                            }
                        } else {
                            selectedEventIds = [event.id]
                            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                title = event.title
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Text(event.category.emoji)
                                .font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headingSmall)
                                    .foregroundColor(.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text("\(event.startTime.relativeEventTime) · \(event.venue.name)")
                                    .font(.captionMedium)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Image(systemName: selectedEventIds.contains(event.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(selectedEventIds.contains(event.id) ? .ember : .textTertiary)
                        }
                        .padding(Spacing.md)
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
