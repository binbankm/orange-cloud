//
//  OrangeCloudWidgetsBundle.swift
//  OrangeCloudWidgets
//

import WidgetKit
import SwiftUI

@main
struct OrangeCloudWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ZoneStatWidget()
        ZoneChartWidget()
        UsageWidget()
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
