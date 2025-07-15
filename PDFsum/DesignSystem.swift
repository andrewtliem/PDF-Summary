import SwiftUI

// MARK: - Design System
struct DesignSystem {
    // Typography
    static let titleLarge = Font.system(size: 28, weight: .bold, design: .default)
    static let titleMedium = Font.system(size: 22, weight: .semibold, design: .default)
    static let titleSmall = Font.system(size: 18, weight: .semibold, design: .default)
    static let headline = Font.system(size: 16, weight: .semibold, design: .default)
    static let body = Font.system(size: 14, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)
    static let caption = Font.system(size: 11, weight: .medium, design: .default)
    
    // Colors
    static let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0) // #007AFF
    static let secondaryBlue = Color(red: 0.20, green: 0.67, blue: 1.0) // #34AAFF
    static let accentGreen = Color(red: 0.20, green: 0.78, blue: 0.35) // #34C759
    static let accentOrange = Color(red: 1.0, green: 0.58, blue: 0.0) // #FF9500
    static let accentRed = Color(red: 1.0, green: 0.23, blue: 0.19) // #FF3B30
    static let accentPurple = Color(red: 0.75, green: 0.35, blue: 0.95) // #BF59F3
    static let accentTeal = Color(red: 0.20, green: 0.67, blue: 0.86) // #34AADC
    
    // Text Colors
    static let textPrimary = Color(NSColor.labelColor)
    static let textSecondary = Color(NSColor.secondaryLabelColor)
    static let textTertiary = Color(NSColor.tertiaryLabelColor)
    static let textBlack = Color.black
    
    // Background Colors
    static let backgroundPrimary = Color(NSColor.windowBackgroundColor)
    static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
    static let backgroundTertiary = Color(NSColor.textBackgroundColor)
    
    // Section Accent Colors
    static let sectionHeaderBackground = Color(NSColor.controlBackgroundColor).opacity(0.8)
    static let documentsSectionAccent = primaryBlue.opacity(0.05)
    static let summarySectionAccent = accentTeal.opacity(0.05)
    
    // Separator
    static let separatorColor = Color(NSColor.separatorColor)
    static let cardBackground = Color(NSColor.controlBackgroundColor)
    
    // Spacing
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32
    
    // Corner Radius
    static let cornerRadiusS: CGFloat = 6
    static let cornerRadiusM: CGFloat = 10
    static let cornerRadiusL: CGFloat = 14
    static let cornerRadiusXL: CGFloat = 20
    
    // Shadows
    static let shadowLight = Color.black.opacity(0.05)
    static let shadowMedium = Color.black.opacity(0.1)
    static let shadowStrong = Color.black.opacity(0.2)
}

// MARK: - Settings Design System Extensions
extension DesignSystem {
    // Settings-specific colors
    static let settingsCardBackground = Color(NSColor.textBackgroundColor)
    static let settingsBackground = Color(NSColor.controlBackgroundColor)
    static let settingsAccentBlue = primaryBlue
    static let settingsAccentGreen = accentGreen
    static let settingsAccentOrange = accentOrange
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    let isDestructive: Bool
    
    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.headline)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.spacingL)
            .padding(.vertical, DesignSystem.spacingM)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                    .fill(isDestructive ? DesignSystem.accentRed : DesignSystem.primaryBlue)
                    .shadow(color: DesignSystem.shadowMedium, radius: 2, x: 0, y: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.body)
            .foregroundColor(DesignSystem.primaryBlue)
            .padding(.horizontal, DesignSystem.spacingM)
            .padding(.vertical, DesignSystem.spacingS)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusS)
                    .fill(DesignSystem.primaryBlue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusS)
                            .stroke(DesignSystem.primaryBlue.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Settings Button Styles
struct SettingsCardButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(DesignSystem.spacingL)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                    .fill(isSelected ? DesignSystem.primaryBlue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                            .stroke(isSelected ? DesignSystem.primaryBlue : DesignSystem.separatorColor, lineWidth: 2)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - macOS System Button Style
struct MacOSButtonStyle: ButtonStyle {
    let isDestructive: Bool
    let isSecondary: Bool
    
    init(isDestructive: Bool = false, isSecondary: Bool = false) {
        self.isDestructive = isDestructive
        self.isSecondary = isSecondary
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.body)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, DesignSystem.spacingL)
            .padding(.vertical, DesignSystem.spacingS)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderColor, lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 0.5, x: 0, y: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var backgroundColor: Color {
        if isDestructive {
            return DesignSystem.accentRed
        } else if isSecondary {
            return Color(NSColor.controlBackgroundColor)
        } else {
            return DesignSystem.primaryBlue
        }
    }
    
    private var foregroundColor: Color {
        if isDestructive || !isSecondary {
            return .white
        } else {
            return DesignSystem.textPrimary
        }
    }
    
    private var borderColor: Color {
        if isDestructive {
            return DesignSystem.accentRed.opacity(0.3)
        } else if isSecondary {
            return Color(NSColor.separatorColor)
        } else {
            return DesignSystem.primaryBlue.opacity(0.3)
        }
    }
} 