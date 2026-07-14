//
//  ProxiedBadge.swift
//  Orange Cloud
//

import SwiftUI

/// Cloudflare 代理状态徽标：橙色云朵 = 已代理，灰色 = 仅 DNS
struct ProxiedBadge: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    let proxied: Bool

    var body: some View {

        let _ = preferences.languageRaw
        Image(systemName: proxied ? "cloud.fill" : "cloud")
            .foregroundStyle(proxied ? Color.ocOrange : Color.secondary)
            .accessibilityLabel(proxied ? AppLocalization.string(localized: "已代理") : AppLocalization.string(localized: "仅 DNS"))
    }
}
