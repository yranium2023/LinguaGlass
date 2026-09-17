import AppKit
import SwiftUI

@MainActor
private final class OverlayModel: ObservableObject {
    @Published var english = "Start listening in the main window"
    @Published var chinese = "中文翻译将在这里显示"
    @Published var partial = false
    @Published var collapsed = false
    @Published var isDark = false
    @Published var accentIndex = 0

    var accent: Color {
        switch accentIndex {
        case 2: Color(red: 0.65, green: 0.30, blue: 0.73)
        case 3: Color(red: 0.96, green: 0.25, blue: 0.57)
        case 4: Color(red: 1.00, green: 0.29, blue: 0.31)
        case 5: Color(red: 1.00, green: 0.46, blue: 0.08)
        case 6: Color(red: 1.00, green: 0.72, blue: 0.00)
        case 7: Color(red: 0.32, green: 0.72, blue: 0.22)
        case 8: Color(red: 0.52, green: 0.54, blue: 0.58)
        default: Color(red: 0.02, green: 0.45, blue: 0.93)
        }
    }
}

private final class InteractiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DraggableOverlayHost<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let controls = NSRect(x: max(0, bounds.width - 112), y: max(0, bounds.height - 48), width: 112, height: 48)
        if controls.contains(location) {
            super.mouseDown(with: event)
        } else {
            window?.performDrag(with: event)
        }
    }
}

private struct OverlayCaptionView: View {
    @ObservedObject var model: OverlayModel
    let onCollapse: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: model.isDark
                    ? [Color(red: 0.055, green: 0.07, blue: 0.105), Color(red: 0.075, green: 0.09, blue: 0.135)]
                    : [Color(red: 0.965, green: 0.975, blue: 0.99), Color(red: 0.91, green: 0.94, blue: 0.985)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).opacity(model.isDark ? 0.72 : 0.58)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(model.accent)
                    Text("LINGUAGLASS  ·  LIVE CAPTIONS")
                        .font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .foregroundStyle(model.isDark ? .white.opacity(0.52) : .black.opacity(0.46))
                    Spacer()
                    overlayButton(model.collapsed ? "chevron.up" : "chevron.down", action: onCollapse)
                    overlayButton("xmark", action: onClose)
                }
                .padding(.horizontal, 18).frame(height: 46)
                .contentShape(Rectangle())
                Rectangle().fill(model.isDark ? .white.opacity(0.08) : .black.opacity(0.08)).frame(height: 1)
                VStack(alignment: .leading, spacing: model.collapsed ? 0 : 9) {
                    Text(model.english)
                        .font(.system(size: model.collapsed ? 17 : 16, weight: .medium))
                        .foregroundStyle(model.isDark
                            ? (model.partial ? .white.opacity(0.52) : .white.opacity(0.76))
                            : (model.partial ? .black.opacity(0.40) : .black.opacity(0.62)))
                        .lineLimit(model.collapsed ? 1 : 2)
                    if !model.collapsed {
                        Text(model.chinese)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(model.isDark ? .white : Color(red: 0.08, green: 0.10, blue: 0.15))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, model.collapsed ? 10 : 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(model.isDark ? .white.opacity(0.12) : .black.opacity(0.10), lineWidth: 1))
    }

    private func overlayButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(model.isDark ? .white.opacity(0.72) : .black.opacity(0.62))
        .background(model.isDark ? .white.opacity(0.08) : .black.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(model.isDark ? .white.opacity(0.08) : .black.opacity(0.07)))
    }
}

@MainActor
final class OverlayPanelController: NSWindowController {
    var onClose: (() -> Void)?
    private let model = OverlayModel()

    convenience init() {
        let panel = InteractiveOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 190),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 520, height: 92)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        self.init(window: panel)
        let host = DraggableOverlayHost(rootView: OverlayCaptionView(
            model: model,
            onCollapse: { [weak self] in self?.toggleCollapsed() },
            onClose: { [weak self] in self?.closeOverlay() }
        ))
        host.wantsLayer = true
        host.layer?.cornerRadius = 18
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host
        panel.orderOut(nil)
    }

    func setVisible(_ visible: Bool) {
        guard let window else { return }
        if visible {
            if window.frame.origin == .zero { window.center() }
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func update(english: String, chinese: String, partial: Bool) {
        model.english = english
        model.chinese = chinese
        model.partial = partial
    }

    func setClickThrough(_ enabled: Bool) { window?.ignoresMouseEvents = enabled }

    func setAppearance(isDark: Bool, accentIndex: Int) {
        model.isDark = isDark
        model.accentIndex = accentIndex
        window?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func toggleCollapsed() {
        model.collapsed.toggle()
        guard let window else { return }
        var frame = window.frame
        let newHeight: CGFloat = model.collapsed ? 92 : 190
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        window.setFrame(frame, display: true, animate: true)
    }

    private func closeOverlay() {
        setVisible(false)
        onClose?()
    }
}
