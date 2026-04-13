import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: OnboardingStep = .welcome
    @State private var phone: String = ""
    @State private var otp: String = ""
    @State private var selectedVibes: Set<String> = []
    @State private var name: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isDevMode = false

    enum OnboardingStep {
        case welcome, phone, otp, name, vibes, done
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                if step != .welcome {
                    HStack(spacing: 8) {
                        ForEach(0..<4) { i in
                            Capsule()
                                .fill(stepIndex >= i ? Color.ember : Color.bgBorder)
                                .frame(width: stepIndex >= i ? 24 : 8, height: 4)
                                .animation(.spring(response: 0.3), value: stepIndex)
                        }
                    }
                    .padding(.top, 16)
                }

                Spacer()

                Group {
                    switch step {
                    case .welcome: WelcomeStep(onContinue: { withAnimation { step = .phone } })
                    case .phone:   PhoneStep(phone: $phone, isLoading: $isLoading, error: $errorMessage, onContinue: sendOTP)
                    case .otp:     OTPStep(otp: $otp, phone: phone, isLoading: $isLoading, error: $errorMessage, onContinue: verifyOTP, onBack: { step = .phone })
                    case .name:    NameStep(name: $name, onContinue: { withAnimation { step = .vibes } })
                    case .vibes:   VibeSelectionStep(selected: $selectedVibes, isLoading: $isLoading, onContinue: completeOnboarding)
                    case .done:    EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private var stepIndex: Int {
        switch step {
        case .welcome: return -1
        case .phone:   return 0
        case .otp:     return 1
        case .name:    return 2
        case .vibes:   return 3
        case .done:    return 4
        }
    }

    // MARK: - Actions

    private func sendOTP() {
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await APIService.shared.requestOTP(phone: phone)
                withAnimation { step = .otp }
            } catch {
                // Backend unreachable — activate dev bypass
                #if DEBUG
                isDevMode = true
                errorMessage = "Dev mode: use code 000000"
                withAnimation { step = .otp }
                #else
                errorMessage = error.localizedDescription
                #endif
            }
        }
    }

    private func verifyOTP() {
        #if DEBUG
        if isDevMode && otp == "000000" {
            let mockUser = User(
                id: UUID().uuidString, phone: phone, name: "",
                avatarURL: nil, latitude: 41.7991, longitude: -87.5876,
                onboardingComplete: false, createdAt: Date()
            )
            appState.setUser(mockUser)
            withAnimation { step = .name }
            return
        }
        #endif
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let auth = try await APIService.shared.verifyOTP(phone: phone, code: otp)
                appState.setUser(auth.user)
                withAnimation { step = .name }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func completeOnboarding() {
        #if DEBUG
        if isDevMode {
            guard let current = appState.currentUser else { return }
            let completed = User(
                id: current.id, phone: current.phone, name: name.isEmpty ? "Dev User" : name,
                avatarURL: nil, latitude: current.latitude, longitude: current.longitude,
                onboardingComplete: true, createdAt: current.createdAt
            )
            appState.setUser(completed)
            return
        }
        #endif
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let user = try await APIService.shared.completeOnboarding(vibeTagNames: Array(selectedVibes))
                appState.setUser(user)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Welcome Step

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Text("Frnd")
                    .font(.custom("Georgia", size: 64))
                    .foregroundColor(.textPrimary)
                Text("Your city, tonight.")
                    .font(.headingMedium)
                    .foregroundColor(.ember)
                Text("A personalized, social feed of things to do near you — with built-in tools to rally your crew and go.")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Get Started", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Phone Step

private struct PhoneStep: View {
    @Binding var phone: String
    @Binding var isLoading: Bool
    @Binding var error: String?
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's your number?")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text("We'll text you a verification code.")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
            }

            VStack(spacing: 12) {
                TextField("", text: $phone, prompt: Text("+1 (555) 000-0000").foregroundColor(.textTertiary))
                    .font(.headingLarge)
                    .foregroundColor(.textPrimary)
                    .keyboardType(.phonePad)
                    .padding()
                    .background(Color.bgRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))

                if let error = error {
                    Text(error)
                        .font(.captionMedium)
                        .foregroundColor(.rose)
                }
            }

            Button(action: onContinue) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Send Code")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(phone.count < 10 || isLoading)
        }
    }
}

// MARK: - OTP Step

private struct OTPStep: View {
    @Binding var otp: String
    let phone: String
    @Binding var isLoading: Bool
    @Binding var error: String?
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter the code")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text("Sent to \(phone)")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
            }

            VStack(spacing: 12) {
                TextField("", text: $otp, prompt: Text("000000").foregroundColor(.textTertiary))
                    .font(.custom("Georgia", size: 36))
                    .foregroundColor(.textPrimary)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.bgRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))

                if let error = error {
                    Text(error)
                        .font(.captionMedium)
                        .foregroundColor(.rose)
                }
            }

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    if isLoading { ProgressView().tint(.white) } else { Text("Verify") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(otp.count < 6 || isLoading)

                Button("Back", action: onBack)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Name Step

private struct NameStep: View {
    @Binding var name: String
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What should we call you?")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text("Your name is shown to friends on plans.")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
            }

            TextField("", text: $name, prompt: Text("Your name").foregroundColor(.textTertiary))
                .font(.headingLarge)
                .foregroundColor(.textPrimary)
                .padding()
                .background(Color.bgRaised)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))

            Button("Continue", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// MARK: - Vibe Selection Step

private struct VibeSelectionStep: View {
    @Binding var selected: Set<String>
    @Binding var isLoading: Bool
    let onContinue: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick your vibes")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text("Choose at least 5 to personalize your feed.")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(VibeTag.all) { tag in
                        VibeTagButton(tag: tag, isSelected: selected.contains(tag.name)) {
                            if selected.contains(tag.name) {
                                selected.remove(tag.name)
                            } else {
                                selected.insert(tag.name)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 360)

            Button(action: onContinue) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Build My Feed (\(selected.count) selected)")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected.count < 5 || isLoading)
        }
    }
}

private struct VibeTagButton: View {
    let tag: VibeTag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(tag.emoji)
                    .font(.system(size: 28))
                Text(tag.name)
                    .font(.captionMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isSelected ? Color.categoryColor(for: tag.category) : .textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? Color.categoryColor(for: tag.category).opacity(0.15) : Color.bgRaised)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(isSelected ? Color.categoryColor(for: tag.category) : Color.bgBorder)
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
            .animation(.spring(response: 0.2), value: isSelected)
        }
    }
}
