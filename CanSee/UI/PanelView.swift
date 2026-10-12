//
//  PanelView.swift
//  CanSee
//
//  Root of the menu bar panel.
//

import AppKit
import Observation
import SwiftUI

@Observable
final class PanelState {
    enum Page { case main, settings }

    var page: Page = .main
    /// Time-driven views tick only while the panel is on screen.
    var isVisible = false
}

struct PanelView: View {
    let manager: AwakeManager
    let preferences: Preferences
    let power: PowerMonitor
    let panel: PanelState

    @State private var look: CGPoint = .zero
    @State private var eyeCenter: CGPoint = .zero
    @State private var isBlinking = false

    private static let space = "panel"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let notice = manager.notice {
                NoticeBanner(notice: notice) { manager.notice = nil }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            content
                .padding(.horizontal, 16)
            footer
        }
        .frame(width: 312)
        .coordinateSpace(.named(Self.space))
        .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
            switch phase {
            case .active(let location): look = lookVector(toward: location)
            case .ended: look = .zero
            }
        }
        .onChange(of: panel.isVisible) { _, visible in
            if visible && manager.isActive { blink() }
        }
        .animation(.smooth(duration: 0.3), value: manager.isActive)
        .animation(.smooth(duration: 0.25), value: panel.page)
        .animation(.smooth(duration: 0.25), value: manager.notice)
    }

    private var header: some View {
        HStack(spacing: 12) {
            EyeGlyph(openness: manager.isActive ? (isBlinking ? 0.05 : 1) : 0, look: manager.isActive ? look : .zero)
                .frame(width: 52, height: 36)
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .named(Self.space))
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { eyeCenter = $0 }
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: manager.isActive)
                .animation(.smooth(duration: 0.18), value: look)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("CanSee")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.7), radius: 3)
                    Text(statusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HoverIconButton(
                systemImage: panel.page == .settings ? "xmark" : "gearshape",
                help: panel.page == .settings ? "Ayarları kapat" : "Ayarlar"
            ) {
                panel.page = panel.page == .settings ? .main : .settings
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder private var content: some View {
        switch panel.page {
        case .settings:
            SettingsView(manager: manager, preferences: preferences)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        case .main:
            if let session = manager.session {
                ActiveView(session: session, manager: manager, power: power, preferences: preferences, isVisible: panel.isVisible)
                    .transition(.opacity)
            } else {
                SetupView(manager: manager, preferences: preferences, isVisible: panel.isVisible)
                    .transition(.opacity)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("CanSee \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(manager.isActive ? "Durdur ve çık" : "Çık") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Kept short; the chips below say whether the lid may be closed.
    private var statusText: String {
        manager.isActive ? "Uyanık tutuluyor" : "Uyku normal"
    }

    private var statusColor: Color {
        guard let session = manager.session else { return .secondary }
        return session.mode == .systemWide || !manager.hasLid ? .green : .orange
    }

    /// The pointer's direction from the eye, normalized to the unit circle.
    private func lookVector(toward location: CGPoint) -> CGPoint {
        let dx = (location.x - eyeCenter.x) / 150
        let dy = (eyeCenter.y - location.y) / 110
        let length = (dx * dx + dy * dy).squareRoot()
        return length > 1 ? CGPoint(x: dx / length, y: dy / length) : CGPoint(x: dx, y: dy)
    }

    private func blink() {
        withAnimation(.easeIn(duration: 0.08)) { isBlinking = true }
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.16)) { isBlinking = false }
        }
    }
}

#if DEBUG
#Preview("Boşta") {
    let preferences = Preferences()
    let power = PowerMonitor()
    PanelView(manager: AwakeManager(preferences: preferences, power: power).preview(), preferences: preferences, power: power, panel: PanelState())
}

#Preview("Oturum") {
    let preferences = Preferences()
    let power = PowerMonitor()
    let session = AwakeManager.Session(start: .now.addingTimeInterval(-2_400), end: .now.addingTimeInterval(9_000), mode: .systemWide, ownsSleepSetting: true)
    PanelView(manager: AwakeManager(preferences: preferences, power: power).preview(session: session), preferences: preferences, power: power, panel: PanelState())
}
#endif
