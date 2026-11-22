import Foundation
import TodaydoCore

struct DeviceInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var path: String
    var lastBackup: Date?
    var ready: Bool
}

struct SnapshotInfo: Identifiable, Hashable {
    var id: String { url.lastPathComponent }
    var url: URL
    var date: Date
}


@MainActor
final class BackupService: ObservableObject {
    unowned let model: AppModel
    @Published var lastICloudBackup: Date?
    @Published var message = ""

    init(model: AppModel) { self.model = model }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("todaydo", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var snapshotDir: URL {
        let d = supportDir.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    

    
    func dailySnapshot() {
        let key = model.dc.dayKey(model.dc.dayStart(containing: Date())).replacingOccurrences(of: "-", with: "")
        let dest = Self.snapshotDir.appendingPathComponent("todaydo-\(key).sqlite")
        if !FileManager.default.fileExists(atPath: dest.path) {
            do { try model.db.backup(to: dest.path) } catch { message = "Snapshot failed: \(error)" }
        }
        let all = snapshots()
        let keep = max(1, model.settings.snapshotKeep)
        for s in all.dropFirst(keep) { try? FileManager.default.removeItem(at: s.url) }
    }

    func snapshots() -> [SnapshotInfo] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.snapshotDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("todaydo-") && $0.pathExtension == "sqlite" }
            .map { SnapshotInfo(url: $0, date: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    func restore(_ s: SnapshotInfo) {
        model.tracker.commitBoundary()
        do {
            try model.db.restore(from: s.url.path)
            model.classifier.reload(model.db)
            model.reloadMeta()
            message = "Restored from \(s.url.lastPathComponent) Restore"
        } catch {
            message = "Restore failed: \(error)"
        }
    }

    // MARK: - iCloud

    static var icloudRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/todaydo", isDirectory: true)
    }

    static var icloudAvailable: Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path)
    }

    private var ownDir: URL { Self.icloudRoot.appendingPathComponent("devices/\(model.db.deviceId)", isDirectory: true) }

    func icloudBackup() {
        guard Self.icloudAvailable else { message = "Not detected: iCloud Drive"; return }
        do {
            try FileManager.default.createDirectory(at: ownDir, withIntermediateDirectories: true)
            let tmp = ownDir.appendingPathComponent("todaydo.tmp")
            try model.db.backup(to: tmp.path)
            let dest = ownDir.appendingPathComponent("todaydo.sqlite")
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.moveItem(at: tmp, to: dest)
            let meta: [String: Any] = [
                "id": model.db.deviceId, "name": model.db.deviceName,
                "model": Host.current().localizedName ?? "", "lastBackup": Date().timeIntervalSince1970,
            ]
            try JSONSerialization.data(withJSONObject: meta).write(to: ownDir.appendingPathComponent("meta.json"))
            lastICloudBackup = Date()
            message = "iCloud Backup complete"
        } catch {
            message = "iCloud Backup failed: \(error.localizedDescription)"
        }
    }

    
    func otherDevices() -> [DeviceInfo] {
        let dir = Self.icloudRoot.appendingPathComponent("devices", isDirectory: true)
        let subs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [DeviceInfo] = []
        for sub in subs where sub.lastPathComponent != model.db.deviceId {
            let db = sub.appendingPathComponent("todaydo.sqlite")
            let meta = sub.appendingPathComponent("meta.json")
            var name = sub.lastPathComponent
            var last: Date?
            if let d = try? Data(contentsOf: meta), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                name = (j["name"] as? String) ?? name
                if let t = j["lastBackup"] as? Double { last = Date(timeIntervalSince1970: t) }
            }
            let ready = FileManager.default.fileExists(atPath: db.path)
            if !ready { try? FileManager.default.startDownloadingUbiquitousItem(at: db) }
            out.append(DeviceInfo(id: sub.lastPathComponent, name: name, path: db.path, lastBackup: last, ready: ready))
        }
        return out.sorted { $0.name < $1.name }
    }
}
