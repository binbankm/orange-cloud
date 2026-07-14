//
//  ContentView.swift
//  Orange Cloud
//
//  根视图：按登录态路由到欢迎页或主界面。
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var preferences: AppPreferencesStore
    @StateObject private var router = AppRouter.shared
    @AppStorage(AppMotion.storageKey) private var reduceAnimations = false

    var body: some View {
        // 明确读取已发布的主题状态，确保子树中使用的动态主题色在切换后重新求值。
        let _ = (preferences.themeRaw, preferences.appearanceRaw, preferences.languageIdentity)
        return Group {
            if auth.isLoggedIn {
                // 按身份重建会话子树：切换/新增登录身份时 SessionStore（含 token 客户端）全新创建
                SessionRootView(auth: auth)
                    .id(auth.currentSessionId)
                    // 本地化资源与 UIKit 导航标题都在语言改变时重建；选中的 Tab 用 SceneStorage 保留。
                    .id(preferences.languageIdentity)
            } else {
                LoginView()
                    .id(preferences.languageIdentity)
            }
        }
        .animation(.ocSmooth, value: auth.isLoggedIn)
        // App「减少动画」开关下注全树：Zoom 导航转场 / 玻璃岛浮现 / 骨架闪烁统一读它
        .environment(\.appReduceMotion, reduceAnimations)
        // 「免登录工具箱」挂在 auth 闸门之上（不随 .id 会话重建销毁），
        // 登录前后、通知点按统一从这里弹出。
        .fullScreenCover(isPresented: $router.presentToolbox) {
            ToolboxHubView()
        }
        // 启动自愈：清掉「文件」App 里不属于当前存活身份的孤儿挂载 domain（重装/登出残留，
        // 表现为侧边栏同名重复且删不掉、每重装一次多一个）。一次性，登录态与否都跑。
        .task {
            await FileProviderMountManager.reconcile(
                liveSessionIds: Set(auth.sessions.map(\.id.uuidString))
            )
        }
    }
}

/// 登录后才存在的子树：持有本次会话的 SessionStore（API Client + Services）
private struct SessionRootView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @StateObject private var session: SessionStore

    init(auth: AuthManager) {
        _session = StateObject(wrappedValue: SessionStore(authManager: auth))
    }

    var body: some View {

        let _ = preferences.languageIdentity
        MainTabView()
            // 语言切换是 UI 配置变更：重建导航栈，避免任意深层页面保留旧语言的 UIKit 标题。
            .id(preferences.languageIdentity)
            .environmentObject(session)
            .whatsNewSheet()
            .telemetryConsentPrompt()
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(AppPreferencesStore.shared)
        .environmentObject(CacheStore.shared)
}
