//
//  ZoneActionsViewModel.swift
//  Orange Cloud
//
//  Zone 详情页「操作」区：Under Attack / 开发模式开关 + 缓存清理。
//

import Foundation
import Combine

@MainActor
final class ZoneActionsViewModel: ObservableObject {

    @Published private(set) var underAttack = false
    @Published private(set) var devMode = false
    @Published private(set) var settingsLoaded = false

    @Published var isTogglingUnderAttack = false
    @Published var isTogglingDevMode = false
    @Published var isPurging = false
    @Published var didPurge = false
    @Published var error: String?

    private let service: ZoneSettingsService
    private let zoneId: String

    init(service: ZoneSettingsService, zoneId: String) {
        self.service = service
        self.zoneId = zoneId
    }

    func loadSettings() async {
        guard !settingsLoaded else { return }
        async let securityTask = service.getSetting(zoneId: zoneId, setting: "security_level")
        async let devTask = service.getSetting(zoneId: zoneId, setting: "development_mode")
        // 读不到（无 zone-settings.read 等）就保持未加载态，开关显示为锁定
        guard let security = try? await securityTask, let dev = try? await devTask else { return }
        underAttack = security == "under_attack"
        devMode = dev == "on"
        settingsLoaded = true
    }

    func setUnderAttack(_ on: Bool) async {
        guard !isTogglingUnderAttack else { return }
        isTogglingUnderAttack = true
        error = nil
        do {
            // 关闭时恢复为 medium（Cloudflare 默认安全级别；API 不记录开启前的旧值）
            let value = try await service.setSetting(
                zoneId: zoneId, setting: "security_level",
                value: on ? "under_attack" : "medium"
            )
            underAttack = value == "under_attack"
        } catch {
            self.error = error.localizedDescription
        }
        isTogglingUnderAttack = false
    }

    func setDevMode(_ on: Bool) async {
        guard !isTogglingDevMode else { return }
        isTogglingDevMode = true
        error = nil
        do {
            let value = try await service.setSetting(
                zoneId: zoneId, setting: "development_mode",
                value: on ? "on" : "off"
            )
            devMode = value == "on"
        } catch {
            self.error = error.localizedDescription
        }
        isTogglingDevMode = false
    }

    func purgeCache() async {
        guard !isPurging else { return }
        isPurging = true
        error = nil
        do {
            try await service.purgeAllCache(zoneId: zoneId)
            didPurge.toggle()
        } catch {
            self.error = error.localizedDescription
        }
        isPurging = false
    }

    /// 按 URL 清理缓存（单文件 purge，调用方负责限制 ≤ 30 个 URL）
    func purgeURLs(_ urls: [String]) async {
        await runPurge(urls) { try await service.purgeFiles(zoneId: zoneId, urls: $0) }
    }

    /// 按 URL 前缀清理缓存（调用方负责限制 ≤ 30 个）
    func purgePrefixes(_ prefixes: [String]) async {
        await runPurge(prefixes) { try await service.purgePrefixes(zoneId: zoneId, prefixes: $0) }
    }

    /// 按主机名清理缓存（调用方负责限制 ≤ 30 个）
    func purgeHosts(_ hosts: [String]) async {
        await runPurge(hosts) { try await service.purgeHosts(zoneId: zoneId, hosts: $0) }
    }

    /// 按 Cache-Tag 清理缓存（调用方负责限制 ≤ 30 个）
    func purgeTags(_ tags: [String]) async {
        await runPurge(tags) { try await service.purgeTags(zoneId: zoneId, tags: $0) }
    }

    /// 缓存清理统一执行：去重并发、清空错误、成功翻 didPurge 触发反馈
    private func runPurge(_ items: [String], _ op: ([String]) async throws -> Void) async {
        guard !isPurging, !items.isEmpty else { return }
        isPurging = true
        error = nil
        do {
            try await op(items)
            didPurge.toggle()
        } catch {
            self.error = error.localizedDescription
        }
        isPurging = false
    }
}
