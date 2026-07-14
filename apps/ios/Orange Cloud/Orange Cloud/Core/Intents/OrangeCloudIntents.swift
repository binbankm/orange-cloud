//
//  OrangeCloudIntents.swift
//  Orange Cloud
//
//  App Intents：Siri / 快捷指令 / Spotlight 入口。
//  查询走 SwiftData 缓存（离线可用），打开模块通过 AppRouter 路由。
//

import Foundation
import Combine
import AppIntents

// MARK: - 路由（Intent → 主界面 Tab）

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pendingModule: AppModule?
    /// 置 true 时在根层以全屏 cover 弹出「免登录工具箱」。
    /// 入口统一：登录页次级按钮 / 设置入口 / 通知点按都设此标志，挂在 auth 闸门之上。
    @Published var presentToolbox = false

    private init() {}
}

nonisolated enum AppModule: String, AppEnum {
    case dashboard, zones, workers, storage, settings

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "模块"

    static let caseDisplayRepresentations: [AppModule: DisplayRepresentation] = [
        .dashboard: "概览",
        .zones:     "域名",
        .workers:   "Workers",
        .storage:   "存储",
        .settings:  "设置",
    ]
}

// MARK: - 查询域名状态

struct CheckZoneStatusIntent: AppIntent {

    nonisolated static let title: LocalizedStringResource = "查询域名状态"
    nonisolated static let description = IntentDescription("查看某个域名的状态与套餐（来自本地缓存，离线可用）")

    @Parameter(title: "域名")
    var zone: ZoneEntity

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("查询 \(\.$zone) 的状态")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let statusText = zone.status == "active" ? AppLocalization.string(localized: "正常运行") : zone.status
        let name = zone.name
        let plan = zone.planName
        return .result(dialog: IntentDialog(stringLiteral: AppLocalization.string(localized: "\(name) 当前\(statusText)，套餐 \(plan)。")))
    }
}

// MARK: - 打开模块

struct OpenModuleIntent: AppIntent {

    nonisolated static let title: LocalizedStringResource = "打开 Orange Cloud"
    nonisolated static let description = IntentDescription("跳转到指定功能模块")
    nonisolated static let openAppWhenRun = true

    @Parameter(title: "模块", default: .dashboard)
    var module: AppModule

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$module)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingModule = module
        return .result()
    }
}

// MARK: - Siri 短语注册
//
// AppShortcutsProvider / AppShortcut 从 iOS 16.4 才有，部署目标 16.0 下需要
// 用 @available 隔离；iOS 16.0-16.3 上无 Siri 建议的预置短语（Intent 本身仍可
// 由用户从快捷指令 App 手动运行，perform() 不受影响）。

@available(iOS 16.4, *)
nonisolated struct OrangeCloudShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckZoneStatusIntent(),
            phrases: [
                "用 \(.applicationName) 查域名",
                "查询 \(.applicationName) 域名状态",
            ],
            shortTitle: "域名状态",
            systemImageName: "globe"
        )
        AppShortcut(
            intent: OpenModuleIntent(),
            phrases: [
                "打开 \(.applicationName)",
            ],
            shortTitle: "打开模块",
            systemImageName: "square.grid.2x2"
        )
    }
}
