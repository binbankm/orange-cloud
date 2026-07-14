//
//  OrangeCloudWidgetsBundle.swift
//  OrangeCloudWidgets
//

import WidgetKit
import SwiftUI

@main
struct OrangeCloudWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // 每种用量服务单独注册，iOS 16–17 都能直接添加；避免旧静态
        // UsageWidget 只固定 Workers、使 R2/D1/KV 没有可用入口。
        ZoneStatWidget()
        ZoneChartWidget()
        UsageWidget()
        R2UsageWidget()
        D1UsageWidget()
        KVUsageWidget()
        ZoneStatusWidget()
        if #available(iOS 18.0, *) {
            // 控制中心 ControlWidget 仅 iOS 18+ 可用
            OrangeCloudControlWidget()
        }
        if #available(iOSApplicationExtension 16.1, *) {
            TailLiveActivityWidget()
        }
    }
}
