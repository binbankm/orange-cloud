//
//  AppLocalization.swift
//  Orange Cloud
//
//  App 内语言选择的统一字符串入口。`String(localized:)` 默认绑定进程启动时的
//  Locale，运行中修改 AppleLanguages 后会保留旧语言；这里始终使用用户当前选择的
//  Locale 与对应 lproj Bundle，以支持不重启 App 的完整即时切换。
//

import Foundation
import SwiftUI

nonisolated enum AppLocalization {

    private static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? "") ?? .system
    }

    private static var bundle: Bundle {
        let selected = language
        guard let path = Bundle.main.path(forResource: selected.localizationIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    /// 与 `String(localized:table:)` 对应，但不使用进程启动时缓存的默认 locale。
    static func string(localized key: String.LocalizationValue, table: String? = nil) -> String {
        let selected = language
        return String(localized: key, table: table, bundle: bundle, locale: selected.locale)
    }

    /// 应用内语言优先的短日期格式；不能使用 Foundation 的默认 Locale，
    /// 否则用户选择简体中文、系统仍为英文时会显示为 “Feb 22, 2025”。
    static func abbreviatedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// 与应用内语言同步的日期与时间格式；不要直接调用 `Date.formatted`，它会回退到设备地区。
    static func dateTime(_ date: Date, timeStyle: DateFormatter.Style = .none) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    /// 根据应用语言与地区约定排列日期字段，例如英文为 "Jul 14, 8:30 PM"。
    static func date(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func relativeDate(_ date: Date, relativeTo referenceDate: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    /// UIKit 的系统返回按钮不会随着 SwiftUI 的 Locale 环境立即刷新，显式提供应用语言标题。
    static var navigationBackTitle: String {
        switch language {
        case .system: return NSLocalizedString("Back", comment: "Navigation back button")
        case .zhHans, .zhHant, .zhHK: return "返回"
        case .en: return "Back"
        case .ja: return "戻る"
        case .ko: return "뒤로"
        case .de: return "Zurück"
        case .fr: return "Retour"
        case .esMX: return "Atrás"
        case .ptBR, .ptPT: return "Voltar"
        case .ar: return "رجوع"
        case .tr: return "Geri"
        }
    }
}

extension View {
    /// 以当前应用语言解析导航标题，规避 SwiftUI 对进程启动语言的缓存。
    func ocNavigationTitle(_ title: String.LocalizationValue) -> some View {
        navigationTitle(Text(verbatim: AppLocalization.string(localized: title)))
    }
}

extension Text {
    /// 以应用当前选择的 Bundle 解析普通正文，避免 `Text("…")` 固定在进程启动语言。
    static func ocLocalized(_ key: String.LocalizationValue) -> Text {
        Text(verbatim: AppLocalization.string(localized: key))
    }
}
