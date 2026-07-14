//
//  ZoneDetailView.swift
//  Orange Cloud
//
//  单域名中枢（设计稿 zone-detail.jsx）：
//  hero 卡（头像 + 域名 + 状态/套餐 + 24h 流量统计）+ 管理 / 分析 / 操作分组 + 区域 ID。
//

import SwiftUI

struct ZoneDetailView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @State private var zone: CachedZone
    let session: SessionStore

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cacheStore: CacheStore

    // 域名信息（WHOIS）
    @State private var whoisInfo: WhoisInfo?
    @State private var isFetchingWhois = false

    // 分析区（内嵌第一层级，ViewModel 由本页持有，下拉刷新共用）
    @StateObject private var analyticsViewModel: ZoneAnalyticsViewModel

    // 操作区
    @StateObject private var actionsViewModel: ZoneActionsViewModel
    @State private var showPurgeConfirm = false
    @State private var showPurgeSheet = false
    @State private var showPurgeDone = false
    @State private var showActionDenied = false
    @State private var deniedScopeHint = ""
    /// 开关类操作先收口到这里，confirmationDialog 确认后才调 API
    @State private var pendingAction: PendingZoneAction?

    init(zone: CachedZone, session: SessionStore) {
        _zone = State(initialValue: zone)
        self.session = session
        let zoneId = zone.id
        _analyticsViewModel = StateObject(wrappedValue: ZoneAnalyticsViewModel(
            analyticsService: session.analyticsService, zoneId: zoneId
        ))
        _actionsViewModel = StateObject(wrappedValue: ZoneActionsViewModel(
            service: session.zoneSettingsService, zoneId: zoneId
        ))
    }

    private var records: [CachedDNSRecord] { cacheStore.records(for: zone.id) }

    private var canReadSettings: Bool { auth.hasScope("zone-settings.read") }
    private var canEditSettings: Bool { auth.hasScope("zone-settings.write") }
    private var canPurge: Bool { auth.hasScope("cache.purge") }

    /// DNS 记录数：本地已同步过记录用实时缓存计数；否则用 Dashboard/入页回写的
    /// total_count（CachedZone.dnsRecordCount），避免首进详情页默认显示 0 条。
    private var dnsRecordDisplayCount: Int {
        records.isEmpty ? (zone.dnsRecordCount ?? 0) : records.count
    }

    private var statusText: String {
        switch zone.status {
        case "active":                  AppLocalization.string(localized: "已启用")
        case "pending", "initializing": AppLocalization.string(localized: "待激活")
        default:                        AppLocalization.string(localized: "已暂停")
        }
    }

    var body: some View {

        let _ = preferences.languageRaw
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard

                // 分析：图表直接内嵌第一层级，置于管理之前
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string(localized: "分析"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)
                    if auth.hasScope("analytics.read") {
                        ZoneAnalyticsSection(viewModel: analyticsViewModel)
                    } else {
                        Label(AppLocalization.string(localized: "需要「流量分析」权限才能展示流量图表"), systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                            .glassIsland(cornerRadius: OCLayout.chipRadius)
                    }
                }

                // 域名信息
                sectionCard(AppLocalization.string(localized: "域名信息")) {
                    if isFetchingWhois && whoisInfo == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if let whois = whoisInfo {
                        VStack(spacing: 12) {
                            if let registrar = whois.registrar {
                                infoRow(title: AppLocalization.string(localized: "注册商"), value: registrar)
                            }
                            if let created = whois.created {
                                infoRow(title: AppLocalization.string(localized: "注册时间"), value: AppLocalization.abbreviatedDate(created))
                            }
                            if let expires = whois.expires {
                                let days = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
                                let dayText = days < 0 ? AppLocalization.string(localized: "已过期 \(-days) 天") : AppLocalization.string(localized: "剩 \(days) 天")
                                infoRow(title: AppLocalization.string(localized: "到期时间"), value: "\(AppLocalization.abbreviatedDate(expires)) (\(dayText))")
                            }
                            if whois.registrar == nil && whois.expires == nil {
                                Text(AppLocalization.string(localized: "未查询到公开的 WHOIS 信息"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    } else {
                        Button {
                            Task { await fetchWhois() }
                        } label: {
                            Label(AppLocalization.string(localized: "查询域名信息"), systemImage: "info.circle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // 本卡内 eager 门控行的保留判据：目的页是叶子（内部只开 sheet、不再 push）。
                // 「规则」「负载均衡」的目的页还要继续 push，已改值式（ZoneRoute + 栈根 navdest）；
                // 其余若日后加内层 push，必须同步改值式。
                sectionCard(AppLocalization.string(localized: "管理")) {
                    PermissionGatedNavigationLink(
                        label: "DNS 记录",
                        systemImage: "network",
                        requiredScope: "dns.read",
                        showsChevron: true
                    ) {
                        DNSListView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }
                    .listRowStyleValue(AppLocalization.string(localized: "\(dnsRecordDisplayCount) 条"))

                    ProGatedNavigationLink(
                        label: "WAF 防火墙",
                        systemImage: "shield",
                        requiredScope: "zone-waf.read",
                        feature: .waf,
                        tint: .purple,
                        showsChevron: true
                    ) {
                        WAFRuleListView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    ProGatedNavigationLink(
                        label: "Rate Limiting",
                        systemImage: "gauge",
                        requiredScope: "zone-waf.read",
                        feature: .rateLimit,
                        tint: .pink,
                        showsChevron: true
                    ) {
                        RateLimitRulesView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    // 规则族（Transform / 缓存 / Snippets / 重定向 / 源站 / 配置 / 压缩 /
                    // 自定义错误 / Page Rules / URL 规范化）统一收进「规则」二级入口
                    PermissionGatedValueLink(
                        label: "规则",
                        systemImage: "list.bullet.rectangle",
                        requiredScope: "zone.read",
                        tint: .orange,
                        showsChevron: true,
                        value: ZoneRoute.rulesHub(zoneId: zone.id, zoneName: zone.name)
                    )

                    ProGatedNavigationLink(
                        label: "Email Routing",
                        systemImage: "envelope",
                        requiredScope: "email-routing-rule.read",
                        feature: .emailRouting,
                        tint: .pink,
                        showsChevron: true
                    ) {
                        EmailRoutingView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: "SSL/TLS",
                        systemImage: "lock.shield",
                        requiredScope: "zone-settings.read",
                        tint: .green,
                        showsChevron: true
                    ) {
                        ZoneSSLSettingsView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: "性能与缓存",
                        systemImage: "speedometer",
                        requiredScope: "zone-settings.read",
                        tint: .teal,
                        showsChevron: true
                    ) {
                        ZonePerformanceView(zoneId: zone.id, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: "SSL 证书",
                        systemImage: "checkmark.seal",
                        requiredScope: "ssl-and-certificates.read",
                        tint: .green,
                        showsChevron: true
                    ) {
                        ZoneSSLCertsView(zoneId: zone.id, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: "IP 访问规则",
                        systemImage: "hand.raised",
                        requiredScope: "firewall-services.read",
                        tint: .red,
                        showsChevron: true
                    ) {
                        ZoneAccessRulesView(zoneId: zone.id, session: session)
                    }

                    ProGatedValueLink(
                        label: "负载均衡",
                        systemImage: "arrow.left.arrow.right",
                        requiredScope: "load-balancers.read",
                        feature: .loadBalancing,
                        tint: .pink,
                        showsChevron: true,
                        value: ZoneRoute.loadBalancers(zoneId: zone.id, zoneName: zone.name)
                    )
                }

                sectionCard(AppLocalization.string(localized: "操作")) {
                    settingToggleRow(
                        title: AppLocalization.string(localized: "Under Attack 模式"),
                        subtitle: AppLocalization.string(localized: "对所有访客启用质询页"),
                        icon: "shield.lefthalf.filled",
                        tint: .red,
                        isOn: actionsViewModel.underAttack,
                        isBusy: actionsViewModel.isTogglingUnderAttack,
                        requestToggle: { on in pendingAction = .underAttack(on) }
                    )

                    settingToggleRow(
                        title: AppLocalization.string(localized: "开发模式"),
                        subtitle: AppLocalization.string(localized: "临时绕过缓存（3 小时后自动关闭）"),
                        icon: "hammer",
                        tint: .blue,
                        isOn: actionsViewModel.devMode,
                        isBusy: actionsViewModel.isTogglingDevMode,
                        requestToggle: { on in pendingAction = .devMode(on) }
                    )

                    Button {
                        if canPurge {
                            showPurgeConfirm = true
                        } else {
                            deniedScopeHint = "cache.purge"
                            showActionDenied = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "trash", color: .ocOrange)
                            Text(AppLocalization.string(localized: "清理全部缓存"))
                                .foregroundStyle(.primary)
                            Spacer()
                            if actionsViewModel.isPurging {
                                ProgressView()
                            } else if !canPurge {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(actionsViewModel.isPurging)

                    Button {
                        if canPurge {
                            showPurgeSheet = true
                        } else {
                            deniedScopeHint = "cache.purge"
                            showActionDenied = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "scissors", color: .ocOrange)
                            Text(AppLocalization.string(localized: "按目标清理缓存"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: canPurge ? "chevron.right" : "lock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(actionsViewModel.isPurging)
                }

                if !zone.nameServers.isEmpty {
                    sectionCard(AppLocalization.string(localized: "Name Servers")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(zone.nameServers, id: \.self) { server in
                                Text(server)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Zone ID footer
                Text(AppLocalization.string(localized: "Zone ID · \(zone.id)"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
            .padding()
        }
        .background { SkyBackground() }
        .navigationTitle(zone.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(zone.pinned ? AppLocalization.string(localized: "取消固定") : AppLocalization.string(localized: "固定到首页"),
                       systemImage: zone.pinned ? "pin.fill" : "pin") {
                    withAnimation(.ocSmooth) {
                        zone.pinned.toggle()
                    }
                    CacheStore.shared.setPinned(zone.pinned, zoneId: zone.id)
                }
            }
        }
        .ocSensoryFeedback(.impact(weight: .light), trigger: zone.pinned)
        .ocSensoryFeedback(.success, trigger: actionsViewModel.didPurge)
        .task {
            if canReadSettings {
                await actionsViewModel.loadSettings()
            }
        }
        .task {
            await fetchWhois()
        }
        .task {
            // 该 zone 尚未统计过记录数（前 50 个之外 / Dashboard 未加载完就进来）：
            // 入页轻量拉一次 total_count 回写缓存，首屏不显示 0 条
            if zone.dnsRecordCount == nil, records.isEmpty, auth.hasScope("dns.read"),
               let count = try? await session.dnsService.recordCount(zoneId: zone.id) {
                zone.dnsRecordCount = count
                CacheStore.shared.setDNSRecordCount(count, zoneId: zone.id)
            }
        }
        .refreshable {
            if auth.hasScope("analytics.read") {
                await analyticsViewModel.refresh()
            }
            if canReadSettings {
                await actionsViewModel.loadSettings()
            }
            await fetchWhois()
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: .init(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmLabel) {
                Task {
                    switch action {
                    case .underAttack(let on): await actionsViewModel.setUnderAttack(on)
                    case .devMode(let on):     await actionsViewModel.setDevMode(on)
                    }
                }
            }
        } message: { action in
            Text(action.message(zoneName: zone.name))
        }
        .confirmationDialog(AppLocalization.string(localized: "清理全部缓存？"), isPresented: $showPurgeConfirm, titleVisibility: .visible) {
            Button(AppLocalization.string(localized: "清理"), role: .destructive) {
                Task { await actionsViewModel.purgeCache() }
            }
        } message: {
            Text(AppLocalization.string(localized: "将清空 \(zone.name) 在 Cloudflare 边缘的所有缓存，回源流量会短暂上升。"))
        }
        .alert(AppLocalization.string(localized: "缓存已清理"), isPresented: $showPurgeDone) {
            Button(AppLocalization.string(localized: "好"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string(localized: "边缘节点将在数秒内完成清理。"))
        }
        .sheet(isPresented: $showPurgeSheet) {
            PurgeCacheSheet(zoneName: zone.name) { mode, items in
                switch mode {
                case .url:    await actionsViewModel.purgeURLs(items)
                case .prefix: await actionsViewModel.purgePrefixes(items)
                case .host:   await actionsViewModel.purgeHosts(items)
                case .tag:    await actionsViewModel.purgeTags(items)
                }
            }
        }
        .onChange(of: actionsViewModel.didPurge) { _ in
            showPurgeDone = true
        }
        .alert(AppLocalization.string(localized: "权限不足"), isPresented: $showActionDenied) {
            if let sessionId = auth.currentSessionId, !deniedScopeHint.isEmpty {
                Button(AppLocalization.string(localized: "一键重授权")) {
                    let scope = deniedScopeHint
                    Task { await auth.reauthorize(sessionId: sessionId, additionalScopes: [scope]) }
                }
            }
            Button(AppLocalization.string(localized: "好"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string(localized: "当前授权未包含此操作所需权限（\(deniedScopeHint)）。点「一键重授权」补齐，无需退出登录。"))
        }
        .alert(AppLocalization.string(localized: "操作失败"), isPresented: .init(
            get: { actionsViewModel.error != nil },
            set: { if !$0 { actionsViewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionsViewModel.error ?? "")
        }
    }

    // MARK: - 域名信息 Helpers

    private func fetchWhois() async {
        guard whoisInfo == nil && !isFetchingWhois else { return }
        isFetchingWhois = true
        defer { isFetchingWhois = false }
        do {
            whoisInfo = try await RDAPService().lookup(domain: zone.name)
        } catch {
            // Ignore error gracefully
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    // MARK: - 设置开关行

    private func settingToggleRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isOn: Bool,
        isBusy: Bool,
        requestToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy {
                ProgressView()
            } else if canEditSettings && actionsViewModel.settingsLoaded {
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { on in requestToggle(on) }
                ))
                .labelsHidden()
                .accessibilityLabel(title)
            } else {
                Button {
                    deniedScopeHint = canReadSettings ? "zone-settings.write" : "zone-settings.read"
                    showActionDenied = true
                } label: {
                    if actionsViewModel.settingsLoaded {
                        // 只读授权：显示当前状态
                        Text(isOn ? AppLocalization.string(localized: "开") : AppLocalization.string(localized: "关"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(actionsViewModel.settingsLoaded ? (isOn ? AppLocalization.string(localized: "开") : AppLocalization.string(localized: "关")) : "")
                .accessibilityHint(AppLocalization.string(localized: "需要额外授权才能修改"))
            }
        }
    }

    // MARK: - Hero 卡

    private var heroCard: some View {
        VStack(spacing: 10) {
            ZoneAvatar(domain: zone.name, size: 52)
            Text(zone.name)
                .font(.system(.title2, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    StatusDot(status: zone.status, size: 7)
                        .accessibilityHidden(true)
                    Text(statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(zone.status == "active" ? Color.green : Color.secondary)
                }
                .accessibilityElement(children: .combine)
                PlanBadge(planName: zone.planName)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassIsland()
    }

    // MARK: - 分组卡

    private func sectionCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
            .glassIsland(cornerRadius: OCLayout.chipRadius)
        }
    }

}

// MARK: - 操作区待确认动作

/// 「操作」区的开关动作：先弹确认说明影响，确认后才调 API
private nonisolated enum PendingZoneAction: Identifiable {
    case underAttack(Bool)
    case devMode(Bool)

    var id: String {
        switch self {
        case .underAttack(let on): "underAttack-\(on)"
        case .devMode(let on):     "devMode-\(on)"
        }
    }

    var title: String {
        switch self {
        case .underAttack(true):  AppLocalization.string(localized: "开启 Under Attack 模式？")
        case .underAttack(false): AppLocalization.string(localized: "关闭 Under Attack 模式？")
        case .devMode(true):      AppLocalization.string(localized: "开启开发模式？")
        case .devMode(false):     AppLocalization.string(localized: "关闭开发模式？")
        }
    }

    var confirmLabel: String {
        switch self {
        case .underAttack(true), .devMode(true):   AppLocalization.string(localized: "确认开启")
        case .underAttack(false), .devMode(false): AppLocalization.string(localized: "确认关闭")
        }
    }

    func message(zoneName: String) -> String {
        switch self {
        case .underAttack(true):
            AppLocalization.string(localized: "开启后，访问 \(zoneName) 的所有访客都会先看到约 5 秒的质询页，可能影响正常用户体验。适合正在遭受攻击时使用。")
        case .underAttack(false):
            AppLocalization.string(localized: "关闭后，\(zoneName) 的安全级别将恢复为「中」。")
        case .devMode(true):
            AppLocalization.string(localized: "开启后，\(zoneName) 将临时绕过 Cloudflare 缓存，源站负载会上升；3 小时后自动关闭。")
        case .devMode(false):
            AppLocalization.string(localized: "关闭后，\(zoneName) 立即恢复缓存加速。")
        }
    }
}

// MARK: - 行尾 value 标注

private extension View {
    /// 给 PermissionGatedNavigationLink 行附加右侧 value 文本的轻量包装
    func listRowStyleValue(_ value: String) -> some View {
        overlay(alignment: .trailing) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 24)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 域名子树的值式路由

/// 域名详情子树里「目的页自身还要继续 push」的入口路由。
/// ZoneDetailView 有三个宿主栈（Dashboard 栈 / 网域 compact 栈 / iPad split detail 栈），
/// 本路由的 navdest 必须在三处栈根都注册——统一走 `zoneRouteDestinations(session:)`。
enum ZoneRoute: Hashable {
    case rulesHub(zoneId: String, zoneName: String)
    case loadBalancers(zoneId: String, zoneName: String)
    case snippets(zoneId: String, zoneName: String)
    case bulkRedirects
}

extension View {
    /// 在宿主栈根注册域名子树路由（挂栈根直接子级、`.id()` 内侧，铁律见 DashboardView 外壳注释）
    func zoneRouteDestinations(session: SessionStore) -> some View {
        navigationDestination(for: ZoneRoute.self) { route in
            switch route {
            case .rulesHub(let zoneId, let zoneName):
                ZoneRulesHubView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .loadBalancers(let zoneId, let zoneName):
                LoadBalancerListView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .snippets(let zoneId, let zoneName):
                SnippetsListView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .bulkRedirects:
                BulkRedirectListsView(session: session)
            }
        }
    }
}
