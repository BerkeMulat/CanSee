//
//  Components.swift
//  CanSee
//
//  Shared look: palette, chips, banners, settings rows and button styles.
//

import SwiftUI

enum Theme {
    /// Teal to violet, used by the countdown ring, the iris and the app icon.
    static let aurora = [
        Color(red: 0.20, green: 0.84, blue: 0.78),
        Color(red: 0.24, green: 0.70, blue: 0.98),
        Color(red: 0.42, green: 0.42, blue: 0.97),
        Color(red: 0.70, green: 0.40, blue: 0.98),
    ]
    static let accent = Color(red: 0.38, green: 0.40, blue: 0.96)
    static let start = [aurora[1], aurora[2], aurora[3]]
    static let stop = [Color(red: 0.97, green: 0.40, blue: 0.47), Color(red: 0.86, green: 0.22, blue: 0.38)]
}

struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct Chip: View {
    let icon: String
    let text: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint ?? .secondary)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill((tint ?? .primary).opacity(tint == nil ? 0.06 : 0.13)))
        .fixedSize()
    }
}

struct NoticeBanner: View {
    let notice: AwakeManager.Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
            Text(notice.text)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Kapat")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.12)))
    }

    private var tint: Color {
        switch notice.kind {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }

    private var icon: String {
        switch notice.kind {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.fill.quaternary))
        }
    }
}

struct SettingRow<Accessory: View>: View {
    let icon: String
    let title: String
    let detail: String?
    let accessory: Accessory

    init(icon: String, title: String, detail: String?, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory
                .labelsHidden()
        }
    }
}

/// A session option laid out like a Control Center tile: icon and switch on top, label below.
struct OptionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                    Spacer(minLength: 4)
                    Capsule()
                        .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 26, height: 15)
                        .overlay(alignment: isOn ? .trailing : .leading) {
                            Circle()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                                .padding(2)
                        }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .padding(10)
            .background(shape.fill(isOn ? AnyShapeStyle(tint.opacity(0.14)) : isHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary)))
            .overlay(shape.strokeBorder(isOn ? AnyShapeStyle(tint.opacity(0.5)) : AnyShapeStyle(.separator), lineWidth: isOn ? 1 : 0.5))
            .contentShape(shape)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Açık" : "Kapalı")
        .accessibilityAddTraits(.isButton)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 34)
    }
}

struct HoverIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.fill.tertiary).opacity(isHovered ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The panel's main action: a gradient pill with a soft glow in its own color.
struct ProminentButtonStyle: ButtonStyle {
    let colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        ProminentButton(configuration: configuration, colors: colors)
    }

    private struct ProminentButton: View {
        let configuration: ButtonStyleConfiguration
        let colors: [Color]

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background {
                    shape
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
                        .overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        .shadow(color: (colors.last ?? .clear).opacity(isHovered ? 0.5 : 0.3), radius: isHovered ? 10 : 6, y: 2)
                }
                .contentShape(shape)
                .brightness(configuration.isPressed ? -0.06 : (isHovered ? 0.04 : 0))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.55)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: isHovered)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// Quiet secondary action, filled like the preset tiles.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration)
    }

    private struct SoftButton: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            configuration.label
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(shape.fill(isHovered ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary)))
                .contentShape(shape)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: isHovered)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}
