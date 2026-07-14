//
//  SkyPhase.swift
//  Orange Cloud（主 App 与 Widget Extension 共享）
//
//  「晨昏」的天色定义：由时刻 + 外观模式推导（亮色 = 昼，暗色 = 夜）。
//  主 App 的 SkyBackground 与 Widget 的 WidgetSky 共用同一相位表。
//

import SwiftUI

nonisolated enum SkyPhase {

    case dawn   // 清晨（亮）
    case day    // 白天（亮）
    case dusk   // 黄昏（亮）
    case ember  // 入夜，余晖未尽（暗）
    case night  // 深夜（暗）

    static func current(colorScheme: ColorScheme, hour: Int) -> SkyPhase {
        if colorScheme == .dark {
            return (hour >= 17 && hour < 23) ? .ember : .night
        }
        switch hour {
        case 5..<9:   return .dawn
        case 9..<16:  return .day
        case 16..<24: return .dusk
        default:      return .dawn
        }
    }

    /// 天空主体（自上而下）
    var body: [Color] {
        let theme = AppTheme.current
        switch self {
        case .dawn:  return theme.skyDawn
        case .day:   return theme.skyDay
        case .dusk:  return theme.skyDusk
        case .ember: return theme.skyEmber
        case .night: return theme.skyNight
        }
    }

    /// 顶部光源（白昼是日光，夜里是城市上空的橙色辉光）
    var glow: Color {
        switch self {
        case .dawn:  Color.ocOrange.opacity(0.50)
        case .day:   Color.ocOrange.opacity(0.20)
        case .dusk:  Color.ocOrange.opacity(0.42)
        case .ember: Color.ocOrange.opacity(0.30)
        case .night: Color.ocOrange.opacity(0.15)
        }
    }
}
