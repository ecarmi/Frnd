import SwiftUI

struct LoadErrorCard: View {
    let title: String
    let message: String
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.rose)
                Text(title)
                    .font(.headingSmall)
                    .foregroundColor(.textPrimary)
            }

            Text(message)
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Spacing.base)
        .cardStyle()
    }
}
