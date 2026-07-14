//
//  SettingsView.swift
//  Orange Cloud
//
//  设置根页：已登录的 Cloudflare 账号（多身份）、通知、关于。
//  退出登录在各账号详情页内；全部退出后自动回到登录页。
//

import SwiftUI
import StoreKit
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @ObservedObject private var telemetry = TelemetryStore.shared

    @State private var showAddAccount = false
    @State private var showProPaywall = false
    @State private var showAddAccountPaywall = false
    @State private var showAuditPaywall = false
    @State private var showFeedback = false
    @State private var logShareItems: [Any]?

    /// 「今日」用量的日界口径（App Group，与 Widget 共享），默认 UTC
    @AppStorage(DayBoundary.storageKey, store: UserDefaults(suiteName: WidgetSnapshot.appGroupID))
    private var dayBoundaryRaw = DayBoundary.utc.rawValue

    @AppStorage(AppMotion.storageKey)     private var reduceAnimations = false

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            List {
                // ── Cloudflare 账号（登录身份）──
                Section {
                    ForEach(auth.sessions) { identity in
                        NavigationLink {
                            IdentityDetailView(identity: identity)
                        } label: {
                            identityRow(identity)
                        }
                    }

                    Button {
                        // 多账号是 Pro 功能：已有身份且未解锁时走付费墙
                        if !entitlements.isPro && !auth.sessions.isEmpty {
                            showAddAccountPaywall = true
                        } else {
                            showAddAccount = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "plus", color: .ocOrange, size: 38)
                            Text("添加账号")
                                .foregroundStyle(Color.ocOrangeText)
                            if !entitlements.isPro && !auth.sessions.isEmpty {
                                Spacer()
                                ProBadge()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Cloudflare 账号")
                } footer: {
                    Text("每个账号独立登录授权。点击账号查看权限与退出登录。")
                }
                .glassRow()

                // ── Orange Cloud Pro（开源自编译构建无此入口）──
                #if !OPENSOURCE_UNLOCKED
                Section {
                    Button {
                        showProPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "sparkles", color: .ocOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Orange Cloud Pro")
                                    .foregroundStyle(.primary)
                                Text(entitlements.isPro ? "已解锁，感谢支持" : "多账号与专业功能")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entitlements.isPro {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color.ocOrangeText)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .glassRow()
                #endif

                // ── 用量口径 ──
                Section {
                    Picker(selection: $dayBoundaryRaw) {
                        ForEach(DayBoundary.allCases) { boundary in
                            Text(AppLocalization.string(localized: boundary.localizationKey))
                                .tag(boundary.rawValue)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "clock", color: .ocOrange)
                            Text("「今日」按")
                        }
                    }
                } header: {
                    Text("用量")
                } footer: {
                    Text("决定用量统计里「今日」从哪个零点起算。Cloudflare 免费额度按 UTC 重置，选「本地时间」只改变 App 的统计窗口，不改变额度重置时刻；D1/KV 受接口按 UTC 天聚合的限制，始终按 UTC 统计。")
                }
                .glassRow()

                // ── 外观与语言 ──
                Section {
                    NavigationLink {
                        AppearanceThemeView()
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "circle.lefthalf.filled", color: .indigo)
                        Text(AppLocalization.string(localized: "外观"))
                            Spacer()
                            Text(preferences.appearance.label)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker(selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language.rawValue)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "character.bubble", color: .teal)
                            Text("语言")
                        }
                    }

                    Toggle(isOn: $reduceAnimations) {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "wand.and.rays.inverse", color: .purple)
                            Text("减少动画")
                        }
                    }
                } header: {
                    Text("外观与语言")
                } footer: {
                    Text("语言默认跟随系统，选择后立即生效。开启「减少动画」后，页面切换与界面变化将省去过渡动画，操作更跟手。")
                }
                .glassRow()

                // ── 通知 ──
                NotificationSettingsSection()

                // ── 推送中心（免登录可用；登录后可联动 CF 告警）──
                Section {
                    NavigationLink {
                        PushCenterView()
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "bell.badge.fill", color: .ocOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("推送中心")
                                    .foregroundStyle(.primary)
                                Text("推送端点 · CF 告警直推")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("给自己的端点 curl 即推到手机；登录后还能把 Cloudflare 告警的 webhook 指过来。")
                }
                .glassRow()

                // ── 服务状态 ──
                Section {
                    NavigationLink {
                        CloudflareStatusView()
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "waveform.path.ecg", color: .green)
                            Text("Cloudflare 状态")
                        }
                    }
                } header: {
                    Text("服务状态")
                } footer: {
                    Text("来自 cloudflarestatus.com 的官方服务状态与事件。")
                }
                .glassRow()

                // ── 开发者工具箱（免登录可用）──
                Section {
                    Button {
                        AppRouter.shared.presentToolbox = true
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "wrench.and.screwdriver", color: .ocOrange)
                            Text("开发者工具箱")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("工具")
                } footer: {
                    Text("DNS、SSL、HTTP、WHOIS、CIDR 等随身工具，无需 CF 账号。")
                }
                .glassRow()

                // ── 审计日志（账号级，Pro）──
                Section {
                    if entitlements.isPro {
                        NavigationLink {
                            AuditLogListView(session: session)
                        } label: {
                            HStack(spacing: 12) {
                                TintIcon(systemImage: "clock.arrow.circlepath", color: .indigo)
                                Text("审计日志")
                            }
                        }
                    } else {
                        Button {
                            showAuditPaywall = true
                        } label: {
                            HStack(spacing: 12) {
                                TintIcon(systemImage: "clock.arrow.circlepath", color: .indigo)
                                Text("审计日志")
                                    .foregroundStyle(.primary)
                                Spacer()
                                ProBadge()
                            }
                        }
                    }
                } header: {
                    Text("审计日志")
                } footer: {
                    Text("查看当前账号最近 30 天「谁在何时改了什么」。")
                }
                .glassRow()

                // ── 帮助与反馈 ──
                Section {
                    Button {
                        showFeedback = true
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "envelope", color: .ocOrange)
                            Text("发送反馈")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button {
                        exportLogs()
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "doc.text.magnifyingglass", color: .gray)
                            Text("导出诊断日志")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("帮助与反馈")
                } footer: {
                    Text("反馈通过邮件发送给我们，可附带本地诊断日志（不含你的令牌或密钥）便于排查问题。")
                }
                .glassRow()

                // ── 体验者计划（opt-in 遥测）──
                Section {
                    Toggle(isOn: $telemetry.isOptedIn) {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "waveform.path.ecg", color: .teal)
                            Text("体验者计划")
                        }
                    }
                } footer: {
                    Text("开启后上报匿名诊断日志与崩溃信息（不含令牌、账号数据或任何个人信息），帮助我们更快定位登录与稳定性问题。")
                }
                .glassRow()

                // ── 关于（详情收进二级页，给根页减负）──
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "info", color: .blue)
                            Text("关于")
                        }
                    }
                } footer: {
                    Text("版本、评分、社区与法律信息。")
                }
                .glassRow()
            }
            .daybreakList()
            .ocNavigationTitle("设置")
            .task {
                await session.ensureAccounts()
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountSheet()
            }
            .sheet(isPresented: $showProPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showAddAccountPaywall) {
                PaywallView(feature: .multiAccount)
            }
            .sheet(isPresented: $showAuditPaywall) {
                PaywallView(feature: .auditLog)
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackView()
            }
            .sheet(isPresented: logShareBinding) {
                if let logShareItems {
                    ActivityView(items: logShareItems)
                }
            }
        }
    }

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { preferences.appearanceRaw },
            set: { preferences.selectAppearance($0) }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { preferences.languageRaw },
            set: { preferences.selectLanguage($0) }
        )
    }

    /// 导出诊断日志：写到临时文件并拉起系统分享
    private func exportLogs() {
        if let url = LogFileStore.shared.exportedFileURL() {
            logShareItems = [url]
        } else {
            logShareItems = [AppLocalization.string(localized: "（暂无诊断日志）")]
        }
    }

    private var logShareBinding: Binding<Bool> {
        Binding(get: { logShareItems != nil }, set: { if !$0 { logShareItems = nil } })
    }

    // MARK: - 身份行

    private func identityRow(_ identity: AuthSessionMeta) -> some View {
        HStack(spacing: 12) {
            Text(String(identity.label.first ?? "C").uppercased())
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
                .background(
                    LinearGradient(
                        colors: [Color.ocOrange.mixed(with: .white, by: 0.35), .ocOrangePressed],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.label)
                    .font(.body)
                    .lineLimit(1)
                Text("\(identity.scopes.count) 项权限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if auth.currentSessionId == identity.id {
                Text("当前")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ocOrangeText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.ocOrange.opacity(0.14), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

/// 外观与主题集中页，布局与系统设置一致。
private struct AppearanceThemeView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    var body: some View {
        let _ = preferences.themeRaw
        List {
            Section {
                Picker(selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "circle.lefthalf.filled", color: .indigo)
                        Text(AppLocalization.string(localized: "外观"))
                    }
                }
            }
            .glassRow()

            Section {
                ThemePaletteRow()
            } header: {
                Text(AppLocalization.string(localized: "主题色"))
            }
            .glassRow()
        }
        .daybreakList()
        .navigationTitle(Text(AppLocalization.string(localized: "外观")))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: preferences.themeRaw) { _ in WidgetCenter.shared.reloadAllTimelines() }
    }

    private var appearanceBinding: Binding<String> {
        Binding(get: { preferences.appearanceRaw }, set: { preferences.selectAppearance($0) })
    }
}

/// 内联主题调色盘，形式与 macOS 设置中的色块选择一致。
private struct ThemePaletteRow: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    var body: some View {
        let _ = preferences.themeRaw
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TintIcon(systemImage: "paintpalette.fill", color: .ocOrange)
                Text(AppLocalization.string(localized: "主题色"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        preferences.selectTheme(theme.rawValue)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(theme.primary)
                                .frame(width: 40, height: 40)
                            if preferences.theme == theme {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
                                    .frame(width: 46, height: 46)
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                        // 固定选中态尺寸，避免外扩描边盖住相邻色块。
                        .frame(width: 54, height: 54)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.rawValue)
                    .accessibilityValue(preferences.theme == theme ? AppLocalization.string(localized: "当前") : "")
                }
            }
        }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 添加账号（新 OAuth 登录，不影响现有身份）

private struct AddAccountSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            PermissionSelectionView(freshLogin: true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
        // 登录成功 → currentSessionId 切到新身份 → 关闭弹层
        .onChange(of: auth.currentSessionId) { _ in
            dismiss()
        }
        .interactiveDismissDisabled(auth.isLoading)
    }
}

// MARK: - 通知（主开关授权后再展开子开关）

private struct NotificationSettingsSection: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @AppStorage(AppNotifications.masterKey) private var notificationsEnabled = false
    @AppStorage("notifyZoneStatus")   private var notifyZoneStatus = true
    @AppStorage("notifyWorkerErrors") private var notifyWorkerErrors = true

    @State private var systemDenied = false
    @State private var isRequesting = false

    var body: some View {

        let _ = preferences.languageRaw
        Section {
            Toggle(isOn: $notificationsEnabled) {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "bell.badge", color: .ocOrange)
                    Text("允许通知")
                    if isRequesting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRequesting)

            if systemDenied {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "gear", color: .gray)
                        Text("前往系统设置开启通知权限")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if notificationsEnabled && !systemDenied {
                Toggle(isOn: $notifyZoneStatus) {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "globe", color: .ocOrange)
                        Text("域名状态变更")
                    }
                }
                Toggle(isOn: $notifyWorkerErrors) {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "exclamationmark.triangle", color: .red)
                        Text("Worker 错误通知")
                    }
                }
            }
        } header: {
            Text("通知")
        } footer: {
            Text(notificationsEnabled && !systemDenied
                 ? AppLocalization.string(localized: "通过系统后台刷新检测变化后发送本地通知。时机由 iOS 调度，可能有数分钟至数小时延迟。")
                 : AppLocalization.string(localized: "开启后在 Zone 状态变化或 Workers 出错时收到提醒。"))
        }
        .onChange(of: notificationsEnabled) { _ in
            guard notificationsEnabled else { return }
            Task {
                isRequesting = true
                let granted = await AppNotifications.requestAuthorization()
                isRequesting = false
                if granted {
                    systemDenied = false
                } else {
                    systemDenied = true
                    notificationsEnabled = false
                }
            }
        }
        .task {
            // 系统层被拒时同步关闭主开关
            let status = await AppNotifications.authorizationStatus()
            systemDenied = (status == .denied)
            if systemDenied {
                notificationsEnabled = false
            }
        }
        .glassRow()
    }
}
