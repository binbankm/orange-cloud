//
//  AppPreferences.swift
//  Orange Cloud
//
//  App 级显示偏好：外观（跟随系统 / 亮色 / 暗色）与界面语言。
//  外观经根视图 preferredColorScheme 即时生效；语言由根视图注入 Locale 即时生效，
//  不修改 AppleLanguages：它是系统语言偏好，修改后会污染「跟随系统」。
//

import SwiftUI
import Combine

/// 外观模式，存 UserDefaults（appAppearance）
nonisolated enum AppAppearance: String, CaseIterable, Identifiable, Sendable {

    case system
    case light
    case dark

    var id: String { rawValue }

    static let storageKey = "appAppearance"

    var label: String {
        switch self {
        case .system: return AppLocalization.string(localized: "跟随系统")
        case .light:  return AppLocalization.string(localized: "亮色")
        case .dark:   return AppLocalization.string(localized: "暗色")
        }
    }

    /// nil = 跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

extension AppTheme {

    var label: String {
        switch self {
        case .cloudflareOrange: return AppLocalization.string(localized: "Cloudflare 橙")
        case .oceanBlue:       return AppLocalization.string(localized: "海洋蓝")
        case .forestGreen:     return AppLocalization.string(localized: "森林绿")
        case .indigo:          return AppLocalization.string(localized: "靛青紫")
        case .mint:            return AppLocalization.string(localized: "薄荷青")
        case .violet:          return AppLocalization.string(localized: "Violet")
        case .rose:            return AppLocalization.string(localized: "Rose")
        case .coral:           return AppLocalization.string(localized: "Coral")
        case .amber:           return AppLocalization.string(localized: "Amber")
        case .yellow:          return AppLocalization.string(localized: "Yellow")
        case .graphite:        return AppLocalization.string(localized: "Graphite")
        }
    }
}

/// 外观、主题色与语言的单一状态源。持久化写入和 UI 发布在同一主线程事务中完成，
/// 避免多个 `@AppStorage` 在快速连续切换时发生视图刷新顺序不一致。
@MainActor
final class AppPreferencesStore: ObservableObject {

    static let shared = AppPreferencesStore()

    @Published private(set) var themeRaw: String
    @Published private(set) var appearanceRaw: String
    @Published private(set) var languageRaw: String
    @Published private(set) var languageRevision = 0

    var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .cloudflareOrange
    }

    var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    /// 用于让根视图在系统语言变化或“跟随系统”清理旧覆盖时重新建立导航层级。
    var languageIdentity: String {
        "\(languageRaw)-\(languageRevision)"
    }

    private init() {
        themeRaw = UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? AppTheme.cloudflareOrange.rawValue
        appearanceRaw = UserDefaults.standard.string(forKey: AppAppearance.storageKey) ?? AppAppearance.system.rawValue
        languageRaw = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.system.rawValue
        // 迁移早期版本写入的 app 级 AppleLanguages。该覆盖会让「跟随系统」误显示旧语言。
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        AppTheme.syncToAppGroup(themeRaw)
    }

    func selectTheme(_ rawValue: String) {
        let validValue = AppTheme(rawValue: rawValue)?.rawValue ?? AppTheme.cloudflareOrange.rawValue
        guard themeRaw != validValue else { return }
        UserDefaults.standard.set(validValue, forKey: AppTheme.storageKey)
        AppTheme.syncToAppGroup(validValue)
        themeRaw = validValue
    }

    func selectAppearance(_ rawValue: String) {
        let validValue = AppAppearance(rawValue: rawValue)?.rawValue ?? AppAppearance.system.rawValue
        guard appearanceRaw != validValue else { return }
        UserDefaults.standard.set(validValue, forKey: AppAppearance.storageKey)
        appearanceRaw = validValue
    }

    func selectLanguage(_ rawValue: String) {
        let validValue = AppLanguage(rawValue: rawValue)?.rawValue ?? AppLanguage.system.rawValue
        // 语言由 AppLocalization + SwiftUI Locale 驱动；绝不写 AppleLanguages，
        // 否则“跟随系统”会继续读取上次手动选择的语言。
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.set(validValue, forKey: AppLanguage.storageKey)
        if languageRaw != validValue {
            languageRaw = validValue
        } else {
            // 例如英文切回「跟随系统」后再次选择它，也要重建此前缓存的 UIKit 文案。
            languageRevision &+= 1
        }
    }

    /// App 从后台回到前台时，若选择“跟随系统”，同步系统设置后的语言和 UIKit 标题。
    func refreshSystemLanguage() {
        guard language == .system else { return }
        languageRevision &+= 1
    }
}

/// 动效偏好，存 UserDefaults（reduceAppAnimations）。开启后由根视图统一禁用过渡/隐式动画，
/// 让页面切换与界面变化更跟手（独立于系统「减弱动态效果」，由用户在设置里手动控制）。
nonisolated enum AppMotion {
    static let storageKey = "reduceAppAnimations"
}

/// 界面语言，存 UserDefaults（appLanguage）。rawValue 即语言代码（system 除外）。
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {

    case system = "system"
    case zhHans = "zh-Hans"
    case en     = "en"
    case zhHant = "zh-Hant"
    case zhHK   = "zh-HK"
    case ja     = "ja"
    case ko     = "ko"
    case de     = "de"
    case fr     = "fr"
    case esMX   = "es-MX"
    case ptBR   = "pt-BR"
    case ptPT   = "pt-PT"
    case ar     = "ar"
    case tr     = "tr"

    var id: String { rawValue }

    static let storageKey = "appLanguage"

    /// 语言选择器内的名称随当前界面语言变化，例如中文界面显示“英语”、
    /// 英文界面显示“English”。使用 Foundation 的语言名本地化，避免维护一套易遗漏的手写对照表。
    var label: String {
        if self == .system {
            return AppLocalization.string(localized: "跟随系统")
        }
        return Self.interfaceLocale.localizedString(forIdentifier: rawValue)
            ?? Self.interfaceLocale.localizedString(forLanguageCode: rawValue)
            ?? rawValue
    }

    private static var interfaceLocale: Locale {
        let rawValue = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        return (AppLanguage(rawValue: rawValue) ?? .system).locale
    }

    /// 系统语言来自 NSGlobalDomain，不读取本 App 可能遗留的 AppleLanguages 覆盖。
    private static var systemLanguageIdentifier: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let languages = global?["AppleLanguages"] as? [String]
        return languages?.first ?? Locale.autoupdatingCurrent.identifier
    }

    /// SwiftUI 根视图使用的语言环境。system 直接使用系统全局语言。
    var locale: Locale {
        self == .system ? Locale(identifier: Self.systemLanguageIdentifier) : Locale(identifier: rawValue)
    }

    /// 用于从字符串目录选择 lproj；系统模式明确按全局语言匹配，而不是 Bundle 的启动期缓存。
    var localizationIdentifier: String {
        guard self == .system else { return rawValue }
        return Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: [Self.systemLanguageIdentifier]
        ).first ?? Bundle.main.developmentLocalization ?? "zh-Hans"
    }
}
