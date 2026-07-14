//
//  Orange_CloudApp.swift
//  Orange Cloud
//
//  Created by 陳柘 on 2026/6/10.
//

import SwiftUI
import CoreSpotlight
import ActivityKit

@main
struct Orange_CloudApp: App {

    @StateObject private var authManager: AuthManager
    @StateObject private var preferences = AppPreferencesStore.shared
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppMotion.storageKey) private var reduceAnimations = false

    init() {
        // 最先安装崩溃捕获，让启动期任意一步崩溃都能被记录、随下次反馈带出。
        CrashReporter.install()
        CrashReporter.recordBreadcrumb("AppStart begin")
        #if DEBUG
        MockCloudflare.activateIfRequested()   // 诊断 mock：仅 ORANGE_MOCK=1 时生效
        #endif
        let manager = AuthManager()
        _authManager = StateObject(wrappedValue: manager)
        CrashReporter.recordBreadcrumb("AppStart auth manager created")
        // 串行预热缓存库实体解析（iOS 17.x 冷启动首次并发 fetch 竞态，Sentry APPLE-IOS-Y）
        CacheStore.shared.warmUp()
        WhatsNewGate.wasLoggedInAtLaunch = manager.isLoggedIn
        BackgroundRefresh.register(authManager: manager)
        // iOS 26 连续后台任务（R2 大对象 copy/move 续传），须在启动时注册处理器
        if #available(iOS 26.0, *) {
            ContinuedTaskRunner.register()
        }
        WatchSessionManager.shared.start(authManager: manager)
        EntitlementStore.shared.start()
        // 体验者计划：仅当用户此前已同意才会真正拉起 Sentry（默认不初始化）。
        // 须在 CrashReporter.install() 之后，让 Sentry 链式保留我们的崩溃 handler。
        _ = TelemetryStore.shared
        Self.reapOrphanTailActivities()
        AppLog.logLaunch(
            loggedIn: manager.isLoggedIn,
            sessionCount: manager.sessions.count
        )
        CrashReporter.recordBreadcrumb("AppStart launch completed")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(preferences)
                .environmentObject(EntitlementStore.shared)
                .environmentObject(CacheStore.shared)
                .background(LocalizedNavigationChrome())
                .tint(preferences.theme.primary)
                .preferredColorScheme(preferences.appearance.colorScheme)
                // 语言选择会改变此环境值；SwiftUI 立即使整棵视图树按新语言重绘，无需重启 App。
                .environment(\.locale, preferences.language.locale)
                // 「减少动画」：全局抹掉隐式与 withAnimation 过渡，让界面变化即时生效
                .transaction { txn in
                    if reduceAnimations {
                        txn.disablesAnimations = true
                        txn.animation = nil
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightTap(activity)
                }
        }
        .onChange(of: scenePhase) { _ in
            AppLog.app.info("scenePhase -> \(String(describing: scenePhase))")
            if scenePhase == .active {
                preferences.refreshSystemLanguage()
            }
            if scenePhase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }

    /// 收尸：结束上次进程残留的 tail Live Activity。冷启动时没有任何 VM 持有引用，
    /// 屏上若还挂着卡片，必是崩溃 / 强杀遗留的孤儿——逐个 .immediate 结束。
    private static func reapOrphanTailActivities() {
        if #available(iOS 16.2, *) {
            for activity in Activity<TailActivityAttributes>.activities {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    /// Spotlight 搜索结果点击：跳到对应模块（Zone/DNS 都归属 Zones Tab）
    private func handleSpotlightTap(_ activity: NSUserActivity) {
        guard activity.userInfo?[CSSearchableItemActivityIdentifier] is String else { return }
        AppRouter.shared.pendingModule = .zones
    }
}
