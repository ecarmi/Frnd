import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: OnboardingStep = .welcome
    @State private var email: String = ""
    @State private var otp: String = ""
    @State private var selectedVibes: Set<String> = []
    @State private var name: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isDevMode = false

    private let devBypassEmail = "ecarmi@uchicago.edu"

    enum OnboardingStep {
        case welcome, email, otp, name, vibes, done
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
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

                SwiftUI.Group {
                    switch step {
                    case .welcome: WelcomeStep(onContinue: { withAnimation { step = .email } })
                    case .email:   EmailStep(email: $email, isLoading: $isLoading, error: $errorMessage, onContinue: sendEmailOTP)
                    case .otp:     OTPStep(otp: $otp, email: email, isLoading: $isLoading, error: $errorMessage, isDevMode: isDevMode, onContinue: verifyOTP, onBack: { step = .email })
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
        case .email:   return 0
        case .otp:     return 1
        case .name:    return 2
        case .vibes:   return 3
        case .done:    return 4
        }
    }

    // MARK: - Actions

    private func sendEmailOTP() {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await APIService.shared.requestEmailOTP(email: trimmed)
                withAnimation { step = .otp }
            } catch {
                // Backend unreachable — fall back to dev mode in DEBUG
                #if DEBUG
                isDevMode = true
                errorMessage = "Dev mode — use code 000000"
                withAnimation { step = .otp }
                #else
                errorMessage = error.localizedDescription
                #endif
            }
        }
    }

    private func verifyOTP() {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let auth = try await APIService.shared.verifyEmailOTP(email: trimmed, code: otp)
                appState.setUser(auth.user)
                if auth.user.onboardingComplete {
                    withAnimation { step = .done }
                } else {
                    withAnimation { step = .name }
                }
            } catch {
                // Backend unreachable — fall back to fully local mock only if dev mode
                #if DEBUG
                if isDevMode && otp == "000000" {
                    let mockUser = User(
                        id: UUID().uuidString,
                        email: trimmed,
                        phone: nil,
                        university: trimmed.hasSuffix("uchicago.edu") ? "University of Chicago" : nil,
                        name: "",
                        avatarURL: nil,
                        latitude: 41.7991,
                        longitude: -87.5876,
                        onboardingComplete: false,
                        createdAt: Date()
                    )
                    appState.setUser(mockUser)
                    withAnimation { step = .name }
                    return
                }
                #endif
                errorMessage = error.localizedDescription
            }
        }
    }

    private func completeOnboarding() {
        #if DEBUG
        if isDevMode {
            guard let current = appState.currentUser else { return }
            let completed = User(
                id: current.id,
                email: current.email,
                phone: current.phone,
                university: current.university,
                name: name.isEmpty ? "Dev User" : name,
                avatarURL: nil,
                latitude: current.latitude,
                longitude: current.longitude,
                onboardingComplete: true,
                createdAt: current.createdAt
            )
            appState.setUser(completed)
            return
        }
        #endif
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let user = try await APIService.shared.completeOnboarding(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    vibeTagNames: Array(selectedVibes)
                )
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
                Text("Your campus, tonight.")
                    .font(.headingMedium)
                    .foregroundColor(.ember)
                Text("Discover events, rally your crew, and actually make plans — all in one place.")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Get Started", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Email Step

private struct EmailStep: View {
    @Binding var email: String
    @Binding var isLoading: Bool
    @Binding var error: String?
    let onContinue: () -> Void

    // Add your school's domain here when expanding to new universities
    private let allowedDomains = ["uchicago.edu"]

    private var isValidEmail: Bool {
        let lower = email.lowercased()
        return lower.contains("@") && allowedDomains.contains(where: { lower.hasSuffix($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("UChicago students")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text("Frnd is launching at UChicago first. Sign in with your uchicago.edu email to join your campus community.")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
            }

            VStack(spacing: 12) {
                TextField(
                    "",
                    text: $email,
                    prompt: Text("you@uchicago.edu").foregroundColor(.textTertiary)
                )
                .font(.bodyLarge)
                .foregroundColor(.textPrimary)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color.bgRaised)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))

                if let error = error {
                    Text(error)
                        .font(.captionMedium)
                        .foregroundColor(error.contains("Dev mode") ? .teal : .rose)
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
            .disabled(!isValidEmail || isLoading)
        }
    }
}

// MARK: - OTP Step

private struct OTPStep: View {
    @Binding var otp: String
    let email: String
    @Binding var isLoading: Bool
    @Binding var error: String?
    let isDevMode: Bool
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Check your email")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text(isDevMode ? "Dev mode active" : "Sent to \(email)")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
            }

            VStack(spacing: 12) {
                TextField("", text: $otp, prompt: Text("000000").foregroundColor(.textTertiary))
                    .font(.custom("Georgia", size: 36))
                    .foregroundColor(.textPrimary)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .onChange(of: otp) {
                        let digitsOnly = otp.filter(\.isNumber)
                        otp = String(digitsOnly.prefix(6))
                    }
                    .padding()
                    .background(Color.bgRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))

                if let error = error {
                    Text(error)
                        .font(.captionMedium)
                        .foregroundColor(error.contains("Dev") ? .teal : .rose)
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
                Text("Choose at least 3 to personalize your feed.")
                    .font(.bodyLarge)
                    .foregroundColor(.textSecondary)
            }

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

            Button(action: onContinue) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Build My Feed  ·  \(selected.count) selected")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected.count < 3 || isLoading)
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
