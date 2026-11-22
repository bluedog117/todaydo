import Foundation
import AppKit


@MainActor
final class BrowserReader {
    enum Kind { case safari, chromium }

    static let browsers: [String: Kind] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.beta": .chromium,
        "com.google.Chrome.canary": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.brave.Browser": .chromium,
        "company.thebrowser.Browser": .chromium, // Arc
        "com.vivaldi.Vivaldi": .chromium,
        "com.operasoftware.Opera": .chromium,
    ]

    enum Result {
        case domain(String)
        case none            
        case denied          
        case failed
    }

    private var scripts: [String: NSAppleScript] = [:]
    private var backoffUntil: [String: Date] = [:]
    private(set) var deniedBundles: Set<String> = []

    static func isBrowser(_ bundleId: String?) -> Bool {
        guard let b = bundleId else { return false }
        return browsers[b] != nil
    }

    private func script(for bundle: String, kind: Kind) -> NSAppleScript? {
        if let s = scripts[bundle] { return s }
        let src: String
        switch kind {
        case .safari:
            src = """
            tell application id "\(bundle)"
                if (count of windows) is 0 then return ""
                return URL of current tab of front window
            end tell
            """
        case .chromium:
            src = """
            tell application id "\(bundle)"
                if (count of windows) is 0 then return ""
                set m to "normal"
                try
                    set m to mode of front window
                end try
                return m & "|" & (URL of active tab of front window)
            end tell
            """
        }
        guard let s = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        s.compileAndReturnError(&err)
        scripts[bundle] = s
        return s
    }

    func read(bundleId: String) -> Result {
        guard let kind = Self.browsers[bundleId] else { return .none }
        if let until = backoffUntil[bundleId], until > Date() { return deniedBundles.contains(bundleId) ? .denied : .failed }
        guard let s = script(for: bundleId, kind: kind) else { return .failed }
        var err: NSDictionary?
        let out = s.executeAndReturnError(&err)
        if let err {
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            backoffUntil[bundleId] = Date().addingTimeInterval(300)
            if code == -1743 {
                deniedBundles.insert(bundleId)
                return .denied
            }
            return .failed
        }
        deniedBundles.remove(bundleId)
        backoffUntil[bundleId] = nil
        guard var raw = out.stringValue, !raw.isEmpty else { return .none }
        if kind == .chromium {
            let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return .none }
            if parts[0] == "incognito" { return .none }   
            raw = String(parts[1])
        }
        return Self.domain(fromURL: raw).map { .domain($0) } ?? .none
    }

    
    nonisolated static func domain(fromURL raw: String) -> String? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
