import AppKit
import SwiftUI

enum CLColor {
    static let desk = Color.clDynamic(light: 0xECE5D6, dark: 0x0E0C0A)
    static let window = Color.clDynamic(light: 0xFBF7F0, dark: 0x1B1815)
    static let paper = Color.clDynamic(light: 0xFBF7F0, dark: 0x1D1916)
    static let surface = Color.clDynamic(light: 0xFFFFFF, dark: 0x1F1C19)
    static let ink = Color.clDynamic(light: 0x1C1816, dark: 0xEFE6D6)
    static let ink2 = Color.clDynamic(light: 0x4B4239, dark: 0xC9BDAB)
    static let ink3 = Color.clDynamic(light: 0x7A7066, dark: 0x8B8174)
    static let ink4 = Color.clDynamic(light: 0xA89E90, dark: 0x5E5649)
    static let border = Color.clDynamic(light: 0xEBE2D2, dark: 0x2C2824)
    static let border2 = Color.clDynamic(light: 0xDDD1BD, dark: 0x3A342D)
    static let borderStrong = Color.clDynamic(light: 0xC6B8A0, dark: 0x4A4239)
    static let accent = Color.clDynamic(light: 0xC96442, dark: 0xD9995D)
    static let accentInk = Color.clDynamic(light: 0x6D351F, dark: 0xF0C48F)
    static let selected = Color.clDynamic(
        light: 0xC96442,
        dark: 0xDC8C64,
        lightAlpha: 0.12,
        darkAlpha: 0.16
    )
    static let selectedStrong = Color.clDynamic(
        light: 0xC96442,
        dark: 0xDC8C64,
        lightAlpha: 0.22,
        darkAlpha: 0.28
    )
    static let hover = Color.clDynamic(
        light: 0x1F1812,
        dark: 0xFFF0DC,
        lightAlpha: 0.05,
        darkAlpha: 0.05
    )
    static let accentSoft = Color.clDynamic(
        light: 0xC96442,
        dark: 0xD9995D,
        lightAlpha: 0.12,
        darkAlpha: 0.16
    )
    static let accentEdge = Color.clDynamic(
        light: 0xC96442,
        dark: 0xD9995D,
        lightAlpha: 0.35,
        darkAlpha: 0.45
    )
}

enum CLMetric {
    static let titleBarHeight: CGFloat = 36
    static let toolbarHeight: CGFloat = 38
    static let chatHeaderHeight: CGFloat = 38
    static let leftPaneMinWidth: CGFloat = 220
    static let leftPaneWidth: CGFloat = 270
    static let leftPaneMaxWidth: CGFloat = 440
    static let rightPaneMinWidth: CGFloat = 320
    static let rightPaneWidth: CGFloat = 390
    static let rightPaneMaxWidth: CGFloat = 680
    static let rowHeight: CGFloat = 26
}

enum CLFont {
    static let titleDoc = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodySmall = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .medium)
    static let meta = Font.system(size: 11, design: .monospaced)
    static let eyebrow = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let pdfBody = Font.system(size: 11, design: .serif)
}

struct CLDivider: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis

    init(_ axis: Axis) {
        self.axis = axis
    }

    var body: some View {
        Rectangle()
            .fill(CLColor.border)
            .frame(
                width: axis == .vertical ? 0.5 : nil,
                height: axis == .horizontal ? 0.5 : nil
            )
    }
}

struct CLSectionHeader: View {
    let title: String
    var trailing: String?
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10 * interfaceScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(CLColor.ink3)
            Spacer()
            if let trailing {
                Text(trailing.uppercased())
                    .font(.system(size: 10 * interfaceScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CLColor.ink4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

struct CLToolbarIconButton: View {
    let systemImage: String
    var title: String
    var isActive = false
    var isDisabled = false
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13 * interfaceScale, weight: .medium))
                .foregroundStyle(isActive ? CLColor.accentInk : CLColor.ink2)
                .frame(width: 26 * interfaceScale, height: 26 * interfaceScale)
                .background(isActive ? CLColor.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? CLColor.accentEdge : Color.clear, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(title)
    }
}

struct CLContextChip: View {
    let systemImage: String
    let title: String
    var meta: String?
    var isActive = false
    var isDisabled = false
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11 * interfaceScale, weight: .medium))
                Text(title)
                    .font(.system(size: 11 * interfaceScale, weight: isActive ? .medium : .regular))
                if let meta {
                    Text(meta)
                        .font(.system(size: 10 * interfaceScale, design: .monospaced))
                        .opacity(0.65)
                }
            }
            .lineLimit(1)
            .foregroundStyle(isActive ? CLColor.accentInk : CLColor.ink2)
            .padding(.horizontal, 8)
            .frame(height: 22 * interfaceScale)
            .background(isActive ? CLColor.selected : CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? CLColor.accentEdge : CLColor.border2, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

struct CLPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(CLColor.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CLGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CLColor.ink2)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(configuration.isPressed ? CLColor.hover : CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CLColor.border2, lineWidth: 0.5)
            }
    }
}

extension View {
    func clCard(cornerRadius: CGFloat = 8) -> some View {
        background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(CLColor.border2, lineWidth: 0.5)
            }
    }
}

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
