import AppKit
import SwiftUI

enum CLThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        }
    }

    var next: CLThemeMode {
        switch self {
        case .system:
            .dark
        case .dark:
            .light
        case .light:
            .system
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum CLChatFontChoice: String, CaseIterable, Identifiable {
    case system
    case serif
    case monospaced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "System"
        case .serif:
            "Serif"
        case .monospaced:
            "Mono"
        }
    }

    func swiftUIFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            .system(size: size, weight: weight)
        case .serif:
            .system(size: size, weight: weight, design: .serif)
        case .monospaced:
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch self {
        case .system:
            NSFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            NSFont(name: "NewYork-Regular", size: size)
                ?? NSFont(name: "Times New Roman", size: size)
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        case .monospaced:
            NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

private struct CLInterfaceScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct CLChatFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 14
}

private struct CLChatFontChoiceKey: EnvironmentKey {
    static let defaultValue: CLChatFontChoice = .system
}

extension EnvironmentValues {
    var clInterfaceScale: CGFloat {
        get { self[CLInterfaceScaleKey.self] }
        set { self[CLInterfaceScaleKey.self] = min(max(newValue, 0.9), 1.35) }
    }

    var clChatFontSize: CGFloat {
        get { self[CLChatFontSizeKey.self] }
        set { self[CLChatFontSizeKey.self] = min(max(newValue, 12), 22) }
    }

    var clChatFontChoice: CLChatFontChoice {
        get { self[CLChatFontChoiceKey.self] }
        set { self[CLChatFontChoiceKey.self] = newValue }
    }
}

struct DisplaySettingsPanel: View {
    @AppStorage("colearnerThemeMode") private var themeModeRaw = CLThemeMode.system.rawValue
    @AppStorage("colearnerInterfaceScale") private var interfaceScale = 1.0
    @AppStorage("colearnerChatFontSize") private var chatFontSize = 14.0
    @AppStorage("colearnerChatFontChoice") private var chatFontChoiceRaw = CLChatFontChoice.system.rawValue
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                    Text("Display settings")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(CLColor.ink2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    settingLabel("Theme")
                    Picker("Theme", selection: $themeModeRaw) {
                        ForEach(CLThemeMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.iconName)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    settingLabel("Interface \(Int(interfaceScale * 100))%")
                    Slider(value: $interfaceScale, in: 0.9...1.35, step: 0.05)

                    settingLabel("Chat font")
                    Picker("Chat font", selection: $chatFontChoiceRaw) {
                        ForEach(CLChatFontChoice.allCases) { choice in
                            Text(choice.label).tag(choice.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 8) {
                        settingLabel("Chat size")
                        Spacer()
                        Stepper("\(Int(chatFontSize)) pt", value: $chatFontSize, in: 12...22, step: 1)
                            .font(.system(size: 11, weight: .medium))
                    }

                    Text("Preview: Ask about this page")
                        .font(chatFontChoice.swiftUIFont(size: CGFloat(chatFontSize)))
                        .foregroundStyle(CLColor.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CLColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(CLColor.border2, lineWidth: 0.5)
                        }
                }
            }
        }
        .padding(10)
        .background(CLColor.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CLColor.border)
                .frame(height: 0.5)
        }
    }

    private var chatFontChoice: CLChatFontChoice {
        CLChatFontChoice(rawValue: chatFontChoiceRaw) ?? .system
    }

    private func settingLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(CLColor.ink3)
    }
}
