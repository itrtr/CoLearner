import AppKit
import SwiftUI

// MARK: - Color palette

/// A refined, modern palette that keeps CoLearner's warm reading-room character
/// but with cleaner neutrals, crisper contrast, and better dark-mode separation.
/// Chrome (toolbars/sidebars) uses cool grays; paper surfaces stay warm.
enum CLColor {
    // Backdrops
    static let desk = Color.clDynamic(light: 0xEDEAE3, dark: 0x000000)

    // Chrome — cool, neutral, slightly translucent-feeling
    static let window = Color.clDynamic(light: 0xF6F5F1, dark: 0x1C1C1E)
    static let chrome = Color.clDynamic(light: 0xEFEDE7, dark: 0x232325)

    // Paper / reader surfaces — warm
    static let paper = Color.clDynamic(light: 0xFBFAF6, dark: 0x1E1D1B)
    static let surface = Color.clDynamic(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let surface2 = Color.clDynamic(light: 0xF4F2ED, dark: 0x333336)

    // Ink
    static let ink = Color.clDynamic(light: 0x1A1A1A, dark: 0xF5F3EE)
    static let ink2 = Color.clDynamic(light: 0x4A4A4D, dark: 0xC7C5C0)
    static let ink3 = Color.clDynamic(light: 0x86868B, dark: 0x8E8E93)
    static let ink4 = Color.clDynamic(light: 0xAEAEAE, dark: 0x636366)

    // Borders — very subtle, rely more on background contrast + shadows
    static let border = Color.clDynamic(
        light: 0x000000, dark: 0xFFFFFF,
        lightAlpha: 0.06, darkAlpha: 0.08
    )
    static let border2 = Color.clDynamic(
        light: 0x000000, dark: 0xFFFFFF,
        lightAlpha: 0.10, darkAlpha: 0.12
    )
    static let borderStrong = Color.clDynamic(
        light: 0x000000, dark: 0xFFFFFF,
        lightAlpha: 0.16, darkAlpha: 0.20
    )

    // Accent — terracotta, slightly more vibrant
    static let accent = Color.clDynamic(light: 0xD4663E, dark: 0xE8915C)
    static let accentInk = Color.clDynamic(light: 0x9C4221, dark: 0xF4C4A0)
    static let accentSoft = Color.clDynamic(
        light: 0xD4663E, dark: 0xE8915C,
        lightAlpha: 0.10, darkAlpha: 0.14
    )
    static let accentEdge = Color.clDynamic(
        light: 0xD4663E, dark: 0xE8915C,
        lightAlpha: 0.30, darkAlpha: 0.40
    )

    // Selection
    static let selected = Color.clDynamic(
        light: 0xD4663E, dark: 0xE8915C,
        lightAlpha: 0.10, darkAlpha: 0.16
    )
    static let selectedStrong = Color.clDynamic(
        light: 0xD4663E, dark: 0xE8915C,
        lightAlpha: 0.18, darkAlpha: 0.24
    )

    // Hover
    static let hover = Color.clDynamic(
        light: 0x000000, dark: 0xFFFFFF,
        lightAlpha: 0.04, darkAlpha: 0.06
    )

    // Semantic
    static let success = Color.clDynamic(light: 0x2D9F5E, dark: 0x3FBF7A)
    static let danger = Color.clDynamic(light: 0xD04040, dark: 0xF06060)
}

// MARK: - Metrics

enum CLMetric {
    static let titleBarHeight: CGFloat = 44
    static let toolbarHeight: CGFloat = 44
    static let chatHeaderHeight: CGFloat = 44
    static let leftPaneMinWidth: CGFloat = 240
    static let leftPaneWidth: CGFloat = 280
    static let leftPaneMaxWidth: CGFloat = 440
    static let rightPaneMinWidth: CGFloat = 340
    static let rightPaneWidth: CGFloat = 400
    static let rightPaneMaxWidth: CGFloat = 680
    static let rowHeight: CGFloat = 30
    static let radius: CGFloat = 10
    static let radiusSmall: CGFloat = 8
    static let radiusTiny: CGFloat = 6
}

// MARK: - Typography

enum CLFont {
    static let titleDoc = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodySmall = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .medium)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let meta = Font.system(size: 11, design: .monospaced)
    static let eyebrow = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let pdfBody = Font.system(size: 11, design: .serif)
}

// MARK: - Primitive views

struct CLDivider: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    init(_ axis: Axis) { self.axis = axis }

    var body: some View {
        Rectangle()
            .fill(CLColor.border)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

struct CLSectionHeader: View {
    let title: String
    var trailing: String?
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12 * interfaceScale, weight: .semibold))
                .foregroundStyle(CLColor.ink2)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11 * interfaceScale, weight: .medium, design: .monospaced))
                    .foregroundStyle(CLColor.ink4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Toolbar icon button

struct CLToolbarIconButton: View {
    let systemImage: String
    var title: String
    var isActive = false
    var isDisabled = false
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14 * interfaceScale, weight: .medium))
                .foregroundStyle(isActive ? CLColor.accentInk : CLColor.ink2)
                .frame(width: 30 * interfaceScale, height: 30 * interfaceScale)
                .background(
                    isActive ? CLColor.accentSoft
                    : (isHovered ? CLColor.hover : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: CLMetric.radiusTiny))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .onHover { isHovered = $0 }
        .help(title)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

// MARK: - Context chip

struct CLContextChip: View {
    let systemImage: String
    let title: String
    var meta: String?
    var isActive = false
    var isDisabled = false
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11 * interfaceScale, weight: .medium))
                Text(title)
                    .font(.system(size: 12 * interfaceScale, weight: isActive ? .semibold : .medium))
                if let meta {
                    Text(meta)
                        .font(.system(size: 10 * interfaceScale, design: .monospaced))
                        .foregroundStyle(CLColor.ink4)
                }
            }
            .lineLimit(1)
            .foregroundStyle(isActive ? CLColor.accentInk : CLColor.ink2)
            .padding(.horizontal, 10)
            .frame(height: 26 * interfaceScale)
            .background(
                isActive ? CLColor.accentSoft
                : (isHovered ? CLColor.hover : CLColor.surface2)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

// MARK: - Button styles

struct CLPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: CLMetric.radiusTiny)
                    .fill(CLColor.accent)
                    .opacity(configuration.isPressed ? 0.80 : 1)
            )
            .shadow(color: CLColor.accent.opacity(0.25), radius: 3, y: 1)
    }
}

struct CLGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CLColor.ink2)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: CLMetric.radiusTiny)
                    .fill(configuration.isPressed ? CLColor.hover : CLColor.surface2)
            )
    }
}

// MARK: - Card modifier

extension View {
    func clCard(cornerRadius: CGFloat = CLMetric.radiusSmall) -> some View {
        self
            .background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    /// Material-backed elevated surface for toolbars, headers, and floating panels.
    func clMaterialBar() -> some View {
        self.background(.regularMaterial)
    }
}

// MARK: - Color helpers

extension Color {
    static func clDynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.clHex(
                isDark ? dark : light,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }
}

extension NSColor {
    static func clHex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
