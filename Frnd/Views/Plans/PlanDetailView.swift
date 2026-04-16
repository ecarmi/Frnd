import SwiftUI
import Combine

struct PlanDetailView: View {
        @State var plan: Plan
        @State private var messageText = ""
        @State private var isSending = false
        @State private var carpools: [Carpool] = []
        @State private var showOfferCarpool = false
        @State private var showInviteSheet = false
        @FocusState private var isMessageFieldFocused: Bool
        @State private var keyboardHeight: CGFloat = 0
        @EnvironmentObject var appState: AppState
        
        var body: some View {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Plan header
                    planHeader
                    
                    Divider().overlay(Color.bgBorder)
                    
                    // Event options / voting (if in voting state)
                    if plan.status == .voting && plan.eventOptions.count > 1 {
                        votingSection
                    }
                    
                    // Logistics (if locked or live)
                    if plan.status == .locked || plan.status == .live {
                        logisticsSection
                    }
                    
                    // Carpool section (locked or live)
                    if (plan.status == .locked || plan.status == .live) && !carpools.isEmpty {
                        carpoolSection
                        Divider().overlay(Color.bgBorder)
                    }
                    
                    Divider().overlay(Color.bgBorder)
                    
                    // Messages
                    messagesList
                    
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                keyboardHeight = frame.height
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
            .safeAreaInset(edge: .bottom) {
                if plan.status != .archived {
                    messageInput
                }
            }
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showOfferCarpool) {
                OfferCarpoolSheet(planId: plan.id) { carpool in
                    carpools.append(carpool)
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                InviteFriendsSheet(plan: plan) { updatedPlan in
                    plan = updatedPlan
                }
            }
            .task {
                async let freshPlan = try? APIService.shared.fetchPlan(id: plan.id)
                async let freshCarpools = try? APIService.shared.fetchCarpools(planId: plan.id)
                if let p = await freshPlan { plan = p }
                carpools = (await freshCarpools) ?? []
            }
        }
        
        // MARK: - Plan Header
        
        private var planHeader: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(plan.members) { member in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(
                                    name: member.user?.name ?? "?",
                                    imageURL: member.user?.avatarURL,
                                    size: 44
                                )
                                statusDot(for: member.status)
                            }
                            Text((member.user?.name ?? "?").components(separatedBy: " ").first ?? "?")
                                .font(.captionSmall)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    // Add members button
                    Button {
                        showInviteSheet = true
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(Color.bgRaised)
                                    .frame(width: 44, height: 44)
                                    .overlay(Circle().strokeBorder(Color.bgBorder, style: StrokeStyle(lineWidth: 1, dash: [4])))
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.ember)
                            }
                            Text("Invite")
                                .font(.captionSmall)
                                .foregroundColor(.ember)
                        }
                    }
                }
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.md)
            }
        }
        
        private func statusDot(for status: PlanMemberStatus) -> some View {
            let color: Color = {
                switch status {
                case .going:    return .teal
                case .maybe:    return .gold
                case .invited:  return .textTertiary
                case .declined: return .rose
                }
            }()
            return Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color.bgPrimary, lineWidth: 1.5))
        }
        
        // MARK: - Voting Section
        
        private var votingSection: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.gold)
                    Text("Vote for tonight")
                        .font(.headingSmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.base)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(plan.eventOptions) { event in
                            VoteOptionCard(event: event) {
                                Task {
                                    if let updated = try? await APIService.shared.voteForEvent(planId: plan.id, eventId: event.id) {
                                        plan = updated
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.bottom, Spacing.md)
                }
            }
            .padding(.top, Spacing.md)
        }
        
        // MARK: - Logistics Section
        
        private var logisticsSection: some View {
            HStack(spacing: Spacing.xl) {
                if let event = plan.eventOptions.first(where: { $0.id == plan.selectedEventId }) ?? plan.eventOptions.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Event")
                            .font(.mono)
                            .foregroundColor(.textTertiary)
                            .textCase(.uppercase)
                            .tracking(1.5)
                        Text(event.title)
                            .font(.headingSmall)
                            .foregroundColor(.textPrimary)
                    }
                }
                if let meetTime = plan.meetingTime {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meet At")
                            .font(.mono)
                            .foregroundColor(.textTertiary)
                            .textCase(.uppercase)
                            .tracking(1.5)
                        Text(meetTime, style: .time)
                            .font(.headingSmall)
                            .foregroundColor(.teal)
                    }
                }
                Spacer()
            }
            .padding(Spacing.base)
            .background(Color.bgRaised)
        }
        
        // MARK: - Messages
        
        private var messagesList: some View {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(plan.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromMe: message.userId == (appState.currentUser?.id ?? "")
                            )
                            .id(message.id)
                        }
                        
                        if plan.messages.isEmpty {
                            VStack(spacing: Spacing.md) {
                                Text("💬")
                                    .font(.system(size: 40))
                                Text("Start the conversation")
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                        
                        Color.clear.frame(height: 12).id("bottom")
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, keyboardHeight > 0 ? 88 : 52)
                }
                .defaultScrollAnchor(.bottom)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }
                .onChange(of: plan.messages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        
        // MARK: - Carpool Section
        
        private var carpoolSection: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.teal)
                    Text("Carpools")
                        .font(.headingSmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button("Offer Ride") { showOfferCarpool = true }
                        .font(.captionMedium.bold())
                        .foregroundColor(.teal)
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.md)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(carpools) { carpool in
                            CarpoolCard(carpool: carpool, currentUserId: appState.currentUser?.id ?? "") { updated in
                                if let idx = carpools.firstIndex(where: { $0.id == updated.id }) {
                                    carpools[idx] = updated
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.bottom, Spacing.md)
                }
            }
        }
        
        // MARK: - Message Input
        
        private var messageInput: some View {
            HStack(spacing: Spacing.md) {
                AvatarView(
                    name: appState.currentUser?.name ?? "Me",
                    imageURL: appState.currentUser?.avatarURL,
                    size: 32
                )
                
                HStack {
                    TextField("Message...", text: $messageText)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                        .focused($isMessageFieldFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                    
                    if !messageText.isEmpty {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.ember)
                        }
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.bgRaised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.bgBorder))
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.sm)
            .padding(.bottom, keyboardHeight > 0 ? max(12, keyboardHeight - 34) : 40)
            .background(Color.bgSurface)
            .overlay(Rectangle().fill(Color.bgBorder).frame(height: 0.5), alignment: .top)
        }
        
        private func sendMessage() {
            let text = messageText.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            messageText = ""
            isSending = true
            Task {
                defer { isSending = false }
                if let msg = try? await APIService.shared.sendMessage(planId: plan.id, body: text) {
                    plan.messages.append(msg)
                } else {
                    // Optimistic
                    let msg = Message(
                        id: UUID().uuidString, planId: plan.id,
                        userId: appState.currentUser?.id ?? "me",
                        body: text, type: .text, createdAt: Date()
                    )
                    plan.messages.append(msg)
                }
            }
        }
        
        private func dismissKeyboard() {
            isMessageFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    // MARK: - Vote Option Card
    
    private struct VoteOptionCard: View {
        let event: Event
        let onVote: () -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(event.category.emoji)
                        .font(.system(size: 24))
                    Spacer()
                    PillView(text: event.priceDisplay, color: event.isFree ? .teal : .textSecondary)
                }
                Text(event.title)
                    .font(.headingSmall)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                Text(event.venue.name)
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
                PillView(text: event.startTime.relativeEventTime, color: .ember)
                
                Button("Vote", action: onVote)
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Spacing.base)
            .frame(width: 200)
            .cardStyle()
        }
    }
    
    // MARK: - Carpool Card
    
    private struct CarpoolCard: View {
        let carpool: Carpool
        let currentUserId: String
        let onUpdate: (Carpool) -> Void
        
        @State private var isLoading = false
        
        private var isDriver: Bool { carpool.driverId == currentUserId }
        private var isPassenger: Bool { carpool.passengers.contains(where: { $0.userId == currentUserId }) }
        
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    AvatarView(name: carpool.driver?.name ?? "?", imageURL: carpool.driver?.avatarURL, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDriver ? "You're driving" : (carpool.driver?.name ?? "Driver"))
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                        Text("\(carpool.seatsAvailable) seat\(carpool.seatsAvailable == 1 ? "" : "s") left")
                            .font(.captionSmall)
                            .foregroundColor(carpool.seatsAvailable == 0 ? .rose : .teal)
                    }
                    Spacer()
                }
                
                Label(carpool.departureLocation, systemImage: "mappin")
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                
                if let time = carpool.departureTime {
                    Label(time.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }
                
                if let notes = carpool.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.captionSmall)
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                }
                
                // Passenger avatars
                if !carpool.passengers.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(carpool.passengers.prefix(4)) { p in
                            AvatarView(name: p.user?.name ?? "?", imageURL: p.user?.avatarURL, size: 22)
                                .overlay(Circle().strokeBorder(Color.bgSurface, lineWidth: 1.5))
                        }
                    }
                }
                
                if !isDriver {
                    Button {
                        Task {
                            isLoading = true
                            if isPassenger {
                                try? await APIService.shared.leaveCarpool(carpoolId: carpool.id)
                                // Trigger parent reload on next appear
                            } else {
                                if let updated = try? await APIService.shared.requestCarpoolSeat(carpoolId: carpool.id) {
                                    onUpdate(updated)
                                }
                            }
                            isLoading = false
                        }
                    } label: {
                        Text(isPassenger ? "Cancel Seat" : "Request Seat")
                            .font(.captionMedium.bold())
                            .foregroundColor(isPassenger ? .rose : .bgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isPassenger ? Color.rose.opacity(0.15) : Color.teal)
                            .clipShape(Capsule())
                    }
                    .disabled(isLoading || (carpool.seatsAvailable == 0 && !isPassenger))
                }
            }
            .padding(Spacing.base)
            .frame(width: 220)
            .cardStyle()
        }
    }
    
    // MARK: - Offer Carpool Sheet
    
    struct OfferCarpoolSheet: View {
        let planId: String
        let onCreated: (Carpool) -> Void
        
        @Environment(\.dismiss) private var dismiss
        @State private var departureLocation = ""
        @State private var departureTime = Date().addingTimeInterval(3600)
        @State private var hasTime = true
        @State private var totalSeats = 3
        @State private var notes = ""
        @State private var isLoading = false
        @State private var error: String?
        
        var body: some View {
            NavigationStack {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()
                    Form {
                        Section("Pickup") {
                            TextField("Departure location", text: $departureLocation)
                                .foregroundColor(.textPrimary)
                        }
                        Section("When") {
                            Toggle("Set departure time", isOn: $hasTime)
                            if hasTime {
                                DatePicker("Departure", selection: $departureTime, displayedComponents: [.date, .hourAndMinute])
                                    .foregroundColor(.textPrimary)
                            }
                        }
                        Section("Seats") {
                            Stepper("Total seats: \(totalSeats)", value: $totalSeats, in: 1...8)
                                .foregroundColor(.textPrimary)
                        }
                        Section("Notes (optional)") {
                            TextField("e.g. Meeting at the corner of...", text: $notes, axis: .vertical)
                                .foregroundColor(.textPrimary)
                        }
                        if let error = error {
                            Section { Text(error).foregroundColor(.rose) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .navigationTitle("Offer a Ride")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Offer") {
                            Task {
                                guard !departureLocation.isEmpty else {
                                    error = "Departure location is required"
                                    return
                                }
                                isLoading = true
                                do {
                                    let carpool = try await APIService.shared.offerCarpool(
                                        planId: planId,
                                        departureLocation: departureLocation,
                                        departureLatitude: nil,
                                        departureLongitude: nil,
                                        departureTime: hasTime ? departureTime : nil,
                                        totalSeats: totalSeats,
                                        notes: notes.isEmpty ? nil : notes
                                    )
                                    onCreated(carpool)
                                    dismiss()
                                } catch {
                                    self.error = error.localizedDescription
                                }
                                isLoading = false
                            }
                        }
                        .foregroundColor(.teal)
                        .disabled(departureLocation.isEmpty || isLoading)
                    }
                }
            }
        }
    }
    
    // MARK: - Invite Friends Sheet
    
    struct InviteFriendsSheet: View {
        let plan: Plan
        let onInvited: (Plan) -> Void
        
        @Environment(\.dismiss) private var dismiss
        @State private var friends: [Friendship] = []
        @State private var selected: Set<String> = []
        @State private var isLoading = false
        @State private var isSending = false
        @State private var error: String?
        
        private var alreadyInPlan: Set<String> {
            Set(plan.members.map { $0.userId })
        }
        
        private var invitableFriends: [Friendship] {
            friends.filter {
                guard let user = $0.otherUser else { return false }
                return !alreadyInPlan.contains(user.id)
            }
        }
        
        var body: some View {
            NavigationStack {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()
                    
                    List {
                        // Share link section — always shown at top
                        if let code = plan.inviteCode {
                            Section {
                                ShareLink(
                                    item: URL(string: "frnd://join/plan/\(code)")!,
                                    subject: Text("Join my plan on Frnd"),
                                    message: Text("Tap to join \"\(plan.title)\"")
                                ) {
                                    HStack(spacing: Spacing.md) {
                                        Image(systemName: "link")
                                            .foregroundColor(.ember)
                                            .frame(width: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Share Invite Link")
                                                .font(.headingSmall)
                                                .foregroundColor(.textPrimary)
                                            Text("Anyone with the link can join")
                                                .font(.captionSmall)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.captionSmall)
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            .listRowBackground(Color.bgRaised)
                        }
                        
                        if isLoading {
                            Section {
                                HStack { Spacer(); ProgressView().tint(.ember); Spacer() }
                            }
                            .listRowBackground(Color.bgRaised)
                        } else if !invitableFriends.isEmpty {
                            Section("Also invite friends") {
                                ForEach(invitableFriends) { friendship in
                                    if let user = friendship.otherUser {
                                        Button {
                                            if selected.contains(user.id) {
                                                selected.remove(user.id)
                                            } else {
                                                selected.insert(user.id)
                                            }
                                        } label: {
                                            HStack(spacing: Spacing.md) {
                                                AvatarView(name: user.name, imageURL: user.avatarURL, size: 40)
                                                Text(user.name)
                                                    .font(.headingSmall)
                                                    .foregroundColor(.textPrimary)
                                                Spacer()
                                                if selected.contains(user.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.ember)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .listRowBackground(Color.bgRaised)
                        }
                        
                        if let error = error {
                            Section {
                                Text(error).foregroundColor(.rose).font(.captionMedium)
                            }
                            .listRowBackground(Color.bgRaised)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .navigationTitle("Invite to Plan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Invite (\(selected.count))") {
                            Task {
                                isSending = true
                                do {
                                    let updated = try await APIService.shared.inviteToPlan(
                                        planId: plan.id,
                                        userIds: Array(selected)
                                    )
                                    onInvited(updated)
                                    dismiss()
                                } catch {
                                    self.error = error.localizedDescription
                                }
                                isSending = false
                            }
                        }
                        .foregroundColor(.ember)
                        .disabled(selected.isEmpty || isSending)
                    }
                }
                .task {
                    isLoading = true
                    friends = (try? await APIService.shared.fetchFriends()) ?? []
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - Message Bubble
    
private struct MessageBubble: View {
        let message: Message
        let isFromMe: Bool
        
        var body: some View {
            if message.type == .system {
                Text(message.body)
                    .font(.captionMedium)
                    .foregroundColor(.textTertiary)
                    .italic()
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 8)
                    .background(Color.bgRaised)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else {
                HStack(alignment: .bottom, spacing: Spacing.sm) {
                    if isFromMe { Spacer(minLength: 44) }
                    
                    if !isFromMe {
                        AvatarView(name: message.sender?.name ?? "?", imageURL: message.sender?.avatarURL, size: 28)
                    }
                    
                    VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                        if !isFromMe, let name = message.sender?.name {
                            Text(name.components(separatedBy: " ").first ?? name)
                                .font(.captionSmall)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, 4)
                        }
                        
                        Text(message.body)
                            .font(.bodyMedium)
                            .foregroundColor(isFromMe ? .white : .textPrimary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(isFromMe ? Color.ember : Color.bgRaised)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 16,
                                    bottomLeadingRadius: isFromMe ? 16 : 4,
                                    bottomTrailingRadius: isFromMe ? 4 : 16,
                                    topTrailingRadius: 16
                                )
                            )
                            .frame(maxWidth: 280, alignment: isFromMe ? .trailing : .leading)
                        
                        Text(message.createdAt, style: .time)
                            .font(.captionSmall)
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 4)
                    }
                    
                    if !isFromMe { Spacer(minLength: 44) }
                }
            }
        }
}
