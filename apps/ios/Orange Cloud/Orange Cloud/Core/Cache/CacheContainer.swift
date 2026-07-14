//
//  CacheContainer.swift
//  Orange Cloud
//
//  iOS 16-compatible cache. Cloudflare data is reproducible from the API, so a
//  single Codable snapshot is safer and simpler than making the app depend on
//  SwiftData (which is unavailable before iOS 17).
//

import Combine
import Foundation

/// 脱离 `CacheStore` 主 actor 的不可变写盘快照，可安全交给后台任务编码。
nonisolated private struct CacheSnapshot: Codable, Sendable {
    var zones: [CachedZone]
    var dnsRecords: [CachedDNSRecord]
    var workerScripts: [CachedWorkerScript]
}

@MainActor
final class CacheStore: ObservableObject {

    static let shared = CacheStore()

    @Published private(set) var zones: [CachedZone] = []
    @Published private(set) var dnsRecords: [CachedDNSRecord] = []
    @Published private(set) var workerScripts: [CachedWorkerScript] = []

    private let storageKey = "ocCacheSnapshotV2"

    /// 节流写盘：多次连续 persist 调用合并为一次，延迟 500ms 在后台队列执行，
    /// 避免逐条 upsert/remove 时在主线程频繁做大对象 JSON 编码 + plist 写盘。
    private var pendingPersistTask: Task<Void, Never>?

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(CacheSnapshot.self, from: data) else { return }
        zones = snapshot.zones
        dnsRecords = snapshot.dnsRecords
        workerScripts = snapshot.workerScripts
    }

    func zones(for accountId: String) -> [CachedZone] {
        zones.filter { $0.accountId == accountId }
    }

    func records(for zoneId: String) -> [CachedDNSRecord] {
        dnsRecords.filter { $0.zoneId == zoneId }
    }

    func scripts(for accountId: String) -> [CachedWorkerScript] {
        workerScripts.filter { $0.accountId == accountId }
    }

    func replaceZones(_ remoteZones: [Zone], accountId: String) {
        let oldByID = Dictionary(uniqueKeysWithValues: zones.filter { $0.accountId == accountId }.map { ($0.id, $0) })
        let refreshed = remoteZones.map { zone -> CachedZone in
            guard var cached = oldByID[zone.id] else { return CachedZone(from: zone, accountId: accountId) }
            cached.update(from: zone)
            return cached
        }
        zones.removeAll { $0.accountId == accountId }
        zones.append(contentsOf: refreshed)
        persist()
    }

    func replaceWorkers(_ remoteScripts: [WorkerScript], accountId: String) {
        let oldByID = Dictionary(uniqueKeysWithValues: workerScripts.filter { $0.accountId == accountId }.map { ($0.id, $0) })
        let refreshed = remoteScripts.map { script -> CachedWorkerScript in
            guard var cached = oldByID[script.id] else { return CachedWorkerScript(from: script, accountId: accountId) }
            cached.update(from: script)
            return cached
        }
        workerScripts.removeAll { $0.accountId == accountId }
        workerScripts.append(contentsOf: refreshed)
        persist()
    }

    func replaceRecords(_ remoteRecords: [DNSRecord], zoneId: String) {
        let oldByID = Dictionary(uniqueKeysWithValues: dnsRecords.filter { $0.zoneId == zoneId }.map { ($0.id, $0) })
        let refreshed = remoteRecords.map { record -> CachedDNSRecord in
            guard var cached = oldByID[record.id] else { return CachedDNSRecord(from: record, zoneId: zoneId) }
            cached.update(from: record)
            return cached
        }
        dnsRecords.removeAll { $0.zoneId == zoneId }
        dnsRecords.append(contentsOf: refreshed)
        persist()
    }

    func upsert(zone: Zone, accountId: String) {
        if let index = zones.firstIndex(where: { $0.id == zone.id }) {
            zones[index].update(from: zone)
        } else {
            zones.append(CachedZone(from: zone, accountId: accountId))
        }
        persist()
    }

    func upsert(record: DNSRecord, zoneId: String) {
        if let index = dnsRecords.firstIndex(where: { $0.id == record.id }) {
            dnsRecords[index].update(from: record)
        } else {
            dnsRecords.append(CachedDNSRecord(from: record, zoneId: zoneId))
        }
        persist()
    }

    func removeRecord(id: String) {
        dnsRecords.removeAll { $0.id == id }
        persist()
    }

    func setPinned(_ pinned: Bool, zoneId: String) {
        guard let index = zones.firstIndex(where: { $0.id == zoneId }) else { return }
        zones[index].pinned = pinned
        persist()
    }

    func setDNSRecordCount(_ count: Int, zoneId: String) {
        guard let index = zones.firstIndex(where: { $0.id == zoneId }) else { return }
        zones[index].dnsRecordCount = count
        persist()
    }

    func warmUp() { _ = zones.count }

    /// 节流写盘：取消上一个未执行的 persist 任务，500ms 后在后台队列序列化并写入。
    /// 多次连续变更（批量 upsert、逐条删除）最终只触发一次磁盘 IO，避免主线程阻塞。
    private func persist() {
        pendingPersistTask?.cancel()
        let snapshot = CacheSnapshot(zones: zones, dnsRecords: dnsRecords, workerScripts: workerScripts)
        let key = storageKey
        pendingPersistTask = Task.detached(priority: .utility) {
            // 等待 500ms 合并同一批写操作；Task 被取消时直接返回，不写盘
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else {
                AppLog.app.error("缓存编码失败，已忽略（下次可从 API 重拉）")
                return
            }
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
