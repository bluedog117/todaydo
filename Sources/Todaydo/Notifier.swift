import AppKit
import SwiftUI
import UserNotifications



@MainActor
enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func setup() {
        guard available else { return }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze for 10 minutes", options: [])
        let mute = UNNotificationAction(identifier: "mute", title: "Mute for today", options: [])
        let stood = UNNotificationAction(identifier: "stood", title: "I stood up", options: [])
        c.setNotificationCategories([
            UNNotificationCategory(identifier: "REMINDER", actions: [snooze, mute], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "STAND", actions: [stood, snooze, mute], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "INFO", actions: [], intentIdentifiers: [], options: []),
        ])
    }

    static func send(title: String, body: String, ruleId: String? = nil, category: String = "REMINDER") {
        guard available else { print("[Notifications] \(title) \(body)"); return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = ruleId == nil ? "INFO" : category
        if let r = ruleId { content.userInfo = ["ruleId": r] }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    
    static func playSystemSound(_ name: String) {
        guard name != "__mute__" else { return }
        if name == "__beep__" {
            NSSound.beep()
            return
        }
        if let s = NSSound(named: NSSound.Name(name)) {
            s.stop()
            s.play()
        } else {
            NSSound.beep()
        }
    }
}



final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
enum FloatingPanel {
    private static var panels: [String: NSPanel] = [:]
    private static var timers: [String: Timer] = [:]

    static func show<V: View>(id: String, duration: TimeInterval?, @ViewBuilder content: () -> V) {
        close(id: id, animated: false)
        let hosting = NSHostingView(rootView: content())
        let size = hosting.fittingSize
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panels[id] = panel
        layout()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        if let d = duration {
            timers[id] = Timer.scheduledTimer(withTimeInterval: d, repeats: false) { _ in
                MainActor.assumeIsolated { FloatingPanel.close(id: id) }
            }
        }
    }

    static func close(id: String, animated: Bool = true) {
        timers[id]?.invalidate(); timers[id] = nil
        guard let p = panels.removeValue(forKey: id) else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
        } else {
            p.orderOut(nil)
        }
        layout()
    }

    
    private static func layout() {
        guard let screen = NSScreen.main else { return }
        var y = screen.visibleFrame.minY + 16
        for p in panels.values.sorted(by: { $0.frame.width < $1.frame.width }) {
            let x = screen.visibleFrame.maxX - p.frame.width - 16
            p.setFrameOrigin(NSPoint(x: x, y: y))
            y += p.frame.height + 10
        }
    }
}

struct ToastView: View {
    var title: String
    var message: String
    var icon = "clock.badge"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
        .padding(6)
    }
}
