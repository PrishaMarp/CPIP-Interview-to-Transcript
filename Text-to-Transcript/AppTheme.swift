//
//  AppTheme.swift
//  Text-to-Transcript
//

import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.35, green: 0.45, blue: 0.95)
    static let accentSecondary = Color(red: 0.55, green: 0.38, blue: 0.92)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.97, blue: 1.0),
            Color(red: 0.92, green: 0.94, blue: 0.99)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBackground = Color(.systemBackground)
    static let subtleFill = Color(.secondarySystemBackground)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

extension View {
    func appCard() -> some View {
        modifier(CardModifier())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                if isEnabled {
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentSecondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Color.gray.opacity(0.35)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ActionRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(AppTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionRow(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

