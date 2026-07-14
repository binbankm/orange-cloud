//
//  MainTabView.swift
//  Orange Cloud
//
//  iPhone 底部 Tab，iPad 自动侧边栏（sidebarAdaptable，iOS 18+）；iOS 16/17 回退经典 TabView。
//  iOS 26 自动 Liquid Glass TabBar。
//

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var preferences: AppPreferencesStore
    @SceneStorage("selectedMainTab") private var selectedTabRaw = AppTab.dashboard.rawValue
    @ObservedObject private var router = AppRouter.shared

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .dashboard },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        let _ = (preferences.themeRaw, preferences.appearanceRaw, preferences.languageRaw)
        tabContainer
            .background(TabReselectHandler())
            .task {
                consumePendingRoute()
                await session.ensureAccounts()
            }
            .onChange(of: router.pendingModule) { _ in
                consumePendingRoute()
            }
    }

    @ViewBuilder
    private var tabContainer: some View {
        if #available(iOS 18.0, *) {
            // iOS 18+：值式 Tab + 侧边栏自适应（iPad 自动侧边栏）
            TabView(selection: selectedTab) {
                Tab(AppLocalization.string(localized: "概览"), systemImage: "square.grid.2x2", value: AppTab.dashboard) {
                    dashboardTab
                }
                Tab(AppLocalization.string(localized: "域名"), systemImage: "globe", value: AppTab.zones) {
                    zonesTab
                }
                Tab(AppLocalization.string(localized: "开发者"), systemImage: "chevron.left.forwardslash.chevron.right", value: AppTab.developer) {
                    developerTab
                }
                Tab(AppLocalization.string(localized: "存储"), systemImage: "externaldrive", value: AppTab.storage) {
                    storageTab
                }
                Tab(AppLocalization.string(localized: "设置"), systemImage: "gear", value: AppTab.settings) {
                    settingsTab
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            // iOS 16/17：经典 TabView（底部 Tab；iPad 不走侧边栏自适应）
            TabView(selection: selectedTab) {
                dashboardTab
                    .tabItem { Label(AppLocalization.string(localized: "概览"), systemImage: "square.grid.2x2") }
                    .tag(AppTab.dashboard)
                zonesTab
                    .tabItem { Label(AppLocalization.string(localized: "域名"), systemImage: "globe") }
                    .tag(AppTab.zones)
                developerTab
                    .tabItem { Label(AppLocalization.string(localized: "开发者"), systemImage: "chevron.left.forwardslash.chevron.right") }
                    .tag(AppTab.developer)
                storageTab
                    .tabItem { Label(AppLocalization.string(localized: "存储"), systemImage: "externaldrive") }
                    .tag(AppTab.storage)
                settingsTab
                    .tabItem { Label(AppLocalization.string(localized: "设置"), systemImage: "gear") }
                    .tag(AppTab.settings)
            }
        }
    }

    // MARK: - Tab 内容（两套 TabView 写法共用）

    // 账号维度的重建（.id(selectedAccount)）一律在各 Tab 视图内部、导航容器之内完成，
    // **这里不允许出现任何 .id**：ensureAccounts 可能在任意 Tab 可见时才完成或重试成功
    // （启动拉取失败后各页 load 都会重试），selectedAccount nil→账号翻转若重建可见
    // NavigationStack，iOS 17.0.x 导航栏硬断言必崩——1.8.2(24) 复发的根因就是
    // zones/developer/storage 三个 Tab 在此处残留的外层 .id（详见 DashboardView 注释）。

    @ViewBuilder private var dashboardTab: some View {
        DashboardView(session: session)
    }

    @ViewBuilder private var zonesTab: some View {
        ZoneListView(session: session)
    }

    @ViewBuilder private var developerTab: some View {
        // 开发者平台聚合入口：Workers / Queues / Durable Objects / Hyperdrive / Workers AI / AI Gateway
        DeveloperHubView(session: session)
    }

    @ViewBuilder private var storageTab: some View {
        StorageView(session: session)
    }

    @ViewBuilder private var settingsTab: some View {
        SettingsView()
    }

    /// App Intent（Siri/快捷指令/Spotlight）发起的跳转
    private func consumePendingRoute() {
        guard let module = router.pendingModule else { return }
        router.pendingModule = nil
        selectedTab.wrappedValue = switch module {
        case .dashboard: .dashboard
        case .zones:     .zones
        case .workers:   .developer    // Workers 现归入「开发者」聚合 Tab
        case .storage:   .storage
        case .settings:  .settings
        }
    }

    enum AppTab: String, Hashable {
        case dashboard, zones, developer, storage, settings
    }
}
