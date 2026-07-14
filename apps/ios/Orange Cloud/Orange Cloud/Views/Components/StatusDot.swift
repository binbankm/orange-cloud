//
//  StatusDot.swift
//  Orange Cloud
//
//  Zone 状态指示点：active 绿 / pending 橙 / paused 红，外圈同色光晕（设计稿 StatusDot）。
//

import SwiftUI

struct StatusDot: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let status: String
    var size: CGFloat = 8

    // 开启「不用颜色区分」时，圆点换成带形状的符号，状态不再只靠颜色传达
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var color: Color {
        switch status {
        case "active":                    .green
        case "pending", "initializing":   .orange
        default:                          .red
        }
    }

    private var glyph: String {
        switch status {
        case "active":                    "checkmark.circle.fill"
        case "pending", "initializing":   "clock.fill"
        default:                          "pause.circle.fill"
        }
    }

    /// 读屏标签，与 ZoneDetailView.statusText 用同一组文案
    private var label: String {
        switch status {
        case "active":                  AppLocalization.string(localized: "已启用")
        case "pending", "initializing": AppLocalization.string(localized: "待激活")
        default:                        AppLocalization.string(localized: "已暂停")
        }
    }

    var body: some View {

        let _ = preferences.languageRaw
        Group {
            if differentiateWithoutColor {
                Image(systemName: glyph)
                    .font(.system(size: size + 3))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .background(
                        Circle()
                            .fill(color.opacity(0.13))
                            .frame(width: size + 6, height: size + 6)
                    )
            }
        }
        .accessibilityLabel(label)
    }
}

#Preview {
    HStack(spacing: 16) {
        StatusDot(status: "active")
        StatusDot(status: "pending")
        StatusDot(status: "paused")
    }
    .padding()
}
