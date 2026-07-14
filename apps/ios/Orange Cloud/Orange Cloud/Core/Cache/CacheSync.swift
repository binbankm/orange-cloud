//
//  CacheSync.swift
//  Orange Cloud
//
//  Zone / Worker 列表 → SwiftData 缓存的共享同步逻辑。
//  Dashboard 首屏与各列表页都会拉取同一份数据，这里收口避免两份 upsert 代码。
//

import Foundation
import WidgetKit

@MainActor
enum CacheSync {

    /// Zone 列表 upsert 进缓存（删掉远端已不存在的条目），
    /// 并同步主屏 Widget 快照与 Spotlight 索引。
    /// 缓存写失败（含 iOS 17.x 的 CoreData NSException）静默放弃：数据已在手，UI 不受影响。
    static func syncZones(_ zones: [Zone], accountId: String, accountName: String) {
        // 仅替换当前账号的数据；CacheStore 会保留其余账号及固定状态。
        CacheStore.shared.replaceZones(zones, accountId: accountId)

        WidgetSnapshot(
            accountId: accountId,
            accountName: accountName,
            totalZones: zones.count,
            activeZones: zones.filter { $0.status == "active" }.count,
            updatedAt: Date()
        ).save()
        // 即使分析接口暂时无权限或网络失败，域名指标/请求地形 Widget 也应先
        // 获得可展示的域名基础快照；后续流量请求成功会用真实 24h 指标覆盖。
        let existing = Dictionary(uniqueKeysWithValues: WidgetDataStore.loadZones(accountId: accountId).map { ($0.id, $0) })
        let baselineMetrics = zones.map { zone in
            existing[zone.id] ?? WidgetZoneMetrics(
                id: zone.id,
                name: zone.name,
                requests: 0,
                bytes: 0,
                threats: 0,
                uniques: 0,
                cacheHitRate: nil,
                requestsTrend: nil,
                requestsSeries: [],
                bytesSeries: [],
                updatedAt: Date(),
                accountId: accountId
            )
        }
        WidgetDataStore.saveZones(baselineMetrics, accountId: accountId)
        WidgetCenter.shared.reloadTimelines(ofKind: "ZoneStatusWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ZoneStatWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ZoneChartWidget")

        SpotlightIndexer.indexZones(zones)
    }

    /// Worker 脚本列表 upsert 进缓存（仅限当前账号）；写失败静默放弃（同上）。
    static func syncWorkers(_ scripts: [WorkerScript], accountId: String) {
        CacheStore.shared.replaceWorkers(scripts, accountId: accountId)
    }
}
