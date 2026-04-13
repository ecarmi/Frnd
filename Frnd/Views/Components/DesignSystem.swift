import SwiftUI

// MARK: - Color System

extension Color {
    // Backgrounds
    static let bgPrimary    = Color(hex: "#0C0C0F")
    static let bgSurface    = Color(hex: "#16161A")
    static let bgRaised     = Color(hex: "#1E1E24")
    static let bgBorder     = Color(hex: "#2A2A32")

    // Text
    static let textPrimary  = Color(hex: "#E8E6E3")
    static let textSecondary = Color(hex: "#9A9A9F")
    static let textTertiary = Color(hex: "#5A5A62")

    // Accents
    static let ember        = Color(hex: "#FF6B35")  // Primary CTA
    static let rose         = Color(hex: "#FB7185")
    static let teal         = Color(hex: "#2DD4BF")
    static let violet       = Color(hex: "#A78BFA")
    static let gold         = Color(hex: "#FBBF24")

    // Category colors
    static func categoryColor(for category: EventCategory) -> Color {
        switch category {
        case .music:       return .ember
        case .nightlife:   return .violet
        case .foodDrink:   return .gold
        case .arts:        return .rose
        case .sports:      return .teal
        case .other:       return .textSecondary
        }
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Typography

extension Font {
    // Display — used for hero moments
    static let displayLarge  = Font.custom("Georgia", size: 36).weight(.regular)
    static let displayMedium = Font.custom("Georgia", size: 28).weight(.regular)

    // Headings — SF Pro bold (system)
    static let headingLarge  = Font.system(size: 22, weight: .bold, design: .default)
    static let headingMedium = Font.system(size: 18, weight: .bold, design: .default)
    static let headingSmall  = Font.system(size: 15, weight: .bold, design: .default)

    // Body
    static let bodyLarge     = Font.system(size: 15, weight: .regular)
    static let bodyMedium    = Font.system(size: 14, weight: .regular)

    // Caption
    static let captionMedium = Font.system(size: 12, weight: .medium)
    static let captionSmall  = Font.system(size: 11, weight: .medium)

    // Mono / Labels
    static let mono          = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let monoSmall     = Font.system(size: 10, weight: .medium, design: .monospaced)
}

// MARK: - Spacing

enum Spacing {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let base: CGFloat = 16
    static let lg:   CGFloat = 20
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius

enum Radius {
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 14
    static let xl:   CGFloat = 20
    static let pill: CGFloat = 100
}

// MARK: - Card Style

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.bgBorder, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardModifier()) }
}

// MARK: - Primary Button

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headingSmall)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.ember)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.1, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headingSmall)
            .foregroundColor(.ember)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.ember, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(configuration.isPressed ? Color.ember.opacity(0.1) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.1, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Pill / Tag

struct PillView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.captionSmall)
            .foregroundColor(color)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let name: String
    let imageURL: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(gradientForName(name))
            if imageURL == nil {
                Text(initials)
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }

    private func gradientForName(_ name: String) -> LinearGradient {
        let colors: [(Color, Color)] = [
            (.ember, .rose),
            (.violet, .teal),
            (.gold, .ember),
            (.teal, .violet),
            (.rose, .violet),
        ]
        let index = abs(name.hashValue) % colors.count
        return LinearGradient(
            colors: [colors[index].0, colors[index].1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Loading Shimmer

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.bgRaised)
            .overlay(
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.06), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: phase * geo.size.width)
                        .frame(width: geo.size.width * 2)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Background modifier

extension View {
    func appBackground() -> some View {
        self.background(Color.bgPrimary.ignoresSafeArea())
    }
}
