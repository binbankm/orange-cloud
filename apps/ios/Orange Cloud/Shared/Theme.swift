//
//  Theme.swift
//  Orange Cloud
//
//  设计系统色板（orange-cloud/project/_ds/tokens/colors.css）。
//  品牌主色是 Cloudflare 橙 #F48120，不是系统橙。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// App 内可选的主题主色。默认保留 Cloudflare 橙，其他 target 因未设置该偏好也会回退到橙色。
nonisolated enum AppTheme: String, CaseIterable, Identifiable, Sendable {

    case cloudflareOrange
    case oceanBlue
    case forestGreen
    case indigo
    case mint
    case violet, rose, coral, amber, yellow, graphite

    var id: String { rawValue }

    static let storageKey = "appTheme"

    static var current: AppTheme {
        let appValue = UserDefaults.standard.string(forKey: storageKey)
        let sharedValue = UserDefaults(suiteName: WidgetSnapshot.appGroupID)?.string(forKey: storageKey)
        return AppTheme(rawValue: appValue ?? sharedValue ?? "") ?? .cloudflareOrange
    }

    /// 主 App 在主题变更时同步给 Widget；独立 extension 读取 App Group 内的同一偏好。
    static func syncToAppGroup(_ rawValue: String) {
        UserDefaults(suiteName: WidgetSnapshot.appGroupID)?.set(rawValue, forKey: storageKey)
    }

    var primary: Color {
        switch self {
        case .cloudflareOrange: Color(red: 0xF4 / 255, green: 0x81 / 255, blue: 0x20 / 255)
        case .oceanBlue:       Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        case .forestGreen:     Color(red: 0x1F / 255, green: 0x9D / 255, blue: 0x5B / 255)
        case .indigo:          Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
        case .mint:            Color(red: 0x0F / 255, green: 0x9D / 255, blue: 0x8A / 255)
        case .violet:          Color(red: 0xAF / 255, green: 0x52 / 255, blue: 0xDE / 255)
        case .rose:            Color(red: 0xF4 / 255, green: 0x3F / 255, blue: 0x92 / 255)
        case .coral:           Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x5F / 255)
        case .amber:           Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x1A / 255)
        case .yellow:          Color(red: 0xFF / 255, green: 0xC1 / 255, blue: 0x07 / 255)
        case .graphite:        Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
        }
    }

    /// 主 CTA 与浅色背景可交互文字使用的深色变体，确保有足够对比度。
    var pressed: Color {
        switch self {
        case .cloudflareOrange: Color(red: 0xD8 / 255, green: 0x6F / 255, blue: 0x12 / 255)
        case .oceanBlue:       Color(red: 0x00 / 255, green: 0x66 / 255, blue: 0xCC / 255)
        case .forestGreen:     Color(red: 0x17 / 255, green: 0x7A / 255, blue: 0x46 / 255)
        case .indigo:          Color(red: 0x5B / 255, green: 0x21 / 255, blue: 0xB6 / 255)
        case .mint:            Color(red: 0x0B / 255, green: 0x77 / 255, blue: 0x68 / 255)
        case .violet:          Color(red: 0x7E / 255, green: 0x2B / 255, blue: 0x9D / 255)
        case .rose:            Color(red: 0xC2 / 255, green: 0x18 / 255, blue: 0x5B / 255)
        case .coral:           Color(red: 0xC9 / 255, green: 0x32 / 255, blue: 0x37 / 255)
        case .amber:           Color(red: 0xC8 / 255, green: 0x5E / 255, blue: 0x00 / 255)
        case .yellow:          Color(red: 0xA8 / 255, green: 0x78 / 255, blue: 0x00 / 255)
        case .graphite:        Color(red: 0x63 / 255, green: 0x63 / 255, blue: 0x68 / 255)
        }
    }

    /// 首页「晨昏」背景的亮色调。保留时间层次，同时让整个画布随主题色变化。
    var skyDawn: [Color] { [lightSky(tint: 0.35), lightSky(tint: 0.08)] }
    var skyDay: [Color]  { [lightSky(tint: 0.20), lightSky(tint: 0.04)] }
    var skyDusk: [Color] { [lightSky(tint: 0.45), lightSky(tint: 0.07)] }
    var skyEmber: [Color] { [darkSky(tint: 0.16), darkSky(tint: 0.08), darkSky(tint: 0.04)] }
    var skyNight: [Color] { [darkSky(tint: 0.09), darkSky(tint: 0.04)] }

    private var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .cloudflareOrange: (0xF4 / 255, 0x81 / 255, 0x20 / 255)
        case .oceanBlue:       (0x0A / 255, 0x84 / 255, 0xFF / 255)
        case .forestGreen:     (0x1F / 255, 0x9D / 255, 0x5B / 255)
        case .indigo:          (0x7C / 255, 0x3A / 255, 0xED / 255)
        case .mint:            (0x0F / 255, 0x9D / 255, 0x8A / 255)
        case .violet:          (0xAF / 255, 0x52 / 255, 0xDE / 255)
        case .rose:            (0xF4 / 255, 0x3F / 255, 0x92 / 255)
        case .coral:           (0xFF / 255, 0x5A / 255, 0x5F / 255)
        case .amber:           (0xFF / 255, 0x8A / 255, 0x1A / 255)
        case .yellow:          (0xFF / 255, 0xC1 / 255, 0x07 / 255)
        case .graphite:        (0x8E / 255, 0x8E / 255, 0x93 / 255)
        }
    }

    private func lightSky(tint: Double) -> Color {
        let c = rgb
        return Color(
            red: 1 - (1 - c.red) * tint,
            green: 1 - (1 - c.green) * tint,
            blue: 1 - (1 - c.blue) * tint
        )
    }

    private func darkSky(tint: Double) -> Color {
        let c = rgb
        let base = (red: 0.035, green: 0.04, blue: 0.06)
        return Color(
            red: base.red + (c.red - base.red) * tint,
            green: base.green + (c.green - base.green) * tint,
            blue: base.blue + (c.blue - base.blue) * tint
        )
    }
}

nonisolated extension Color {

    /// 当前主题色 — 装饰、天空插画、TintIcon 圆底、图表线、选中态。
    /// 兼容保留旧命名，避免各页面出现两套主题逻辑。
    static var ocOrange: Color { AppTheme.current.primary }

    /// 当前主题的深色变体，也用作主 CTA 填充。
    static var ocOrangePressed: Color { AppTheme.current.pressed }

    /// Enterprise 金 #C99A1E
    static let ocGold = Color(red: 0xC9 / 255, green: 0x9A / 255, blue: 0x1E / 255)

    /// 浅色背景上的主题文字 / 可交互主题图标专用：
    /// 浅色模式用深色变体，深色模式用主题主色；切换主题时即时重新取值。
    static var ocOrangeText: Color {
        #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(AppTheme.current.primary)
                : UIColor(AppTheme.current.pressed)
        })
        #else
        return ocOrange
        #endif
    }
}

/// 域名字母头像的哈希色板（与设计稿 AV_PALETTE 一致）
nonisolated enum AvatarPalette {

    static let colors: [Color] = [
        Color(red: 0xE8 / 255, green: 0x74 / 255, blue: 0x3B / 255),
        Color(red: 0x3D / 255, green: 0x86 / 255, blue: 0xE0 / 255),
        Color(red: 0x1F / 255, green: 0x9D / 255, blue: 0x5B / 255),
        Color(red: 0x9B / 255, green: 0x59 / 255, blue: 0xC9 / 255),
        Color(red: 0xE0 / 255, green: 0x50 / 255, blue: 0x8C / 255),
        Color(red: 0xC9 / 255, green: 0x9A / 255, blue: 0x1E / 255),
        Color(red: 0x2B / 255, green: 0xAF / 255, blue: 0xA6 / 255),
        Color(red: 0x5B / 255, green: 0x6C / 255, blue: 0xE0 / 255),
        Color(red: 0xD8 / 255, green: 0x5C / 255, blue: 0x5C / 255),
        Color(red: 0x4F / 255, green: 0x7C / 255, blue: 0x9C / 255),
    ]

    /// 与设计稿一致的字符串哈希：h = h * 31 + char
    static func color(for text: String) -> Color {
        var hash: UInt32 = 0
        for unit in text.unicodeScalars {
            hash = hash &* 31 &+ UInt32(unit.value)
        }
        return colors[Int(hash % UInt32(colors.count))]
    }
}
