//
//  ZonePerformanceView.swift
//  Orange Cloud
//
//  「性能与缓存」面板：网络优化开关 + 缓存控制。读走 zone-settings.read，
//  写走 zone-settings.write。所有设置均为 /zones/{id}/settings/{id} 字符串值。
//

import SwiftUI

struct ZonePerformanceView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @StateObject private var viewModel: ZonePerformanceViewModel
    @EnvironmentObject private var auth: AuthManager

    init(zoneId: String, session: SessionStore) {
        _viewModel = StateObject(wrappedValue: ZonePerformanceViewModel(
            service: session.zoneSettingsService, zoneId: zoneId
        ))
    }

    private var canEdit: Bool { auth.hasScope("zone-settings.write") }

    private struct ToggleSpec { let id: String; let title: String; let subtitle: String; let icon: String }

    private var networkSpecs: [ToggleSpec] {
        [
            .init(id: "brotli",      title: AppLocalization.string(localized: "Brotli 压缩"),     subtitle: AppLocalization.string(localized: "用 Brotli 压缩响应，体积更小"), icon: "archivebox"),
            .init(id: "http2",       title: "HTTP/2",                            subtitle: AppLocalization.string(localized: "多路复用，降低连接开销"),       icon: "bolt.horizontal"),
            .init(id: "http3",       title: "HTTP/3 (QUIC)",                     subtitle: AppLocalization.string(localized: "基于 QUIC 的更快传输"),         icon: "bolt.horizontal.circle"),
            .init(id: "0rtt",        title: AppLocalization.string(localized: "0-RTT 连接恢复"),  subtitle: AppLocalization.string(localized: "加快重复访客的握手"),           icon: "arrow.clockwise"),
            .init(id: "early_hints", title: "Early Hints",                       subtitle: AppLocalization.string(localized: "提前下发 103 提示预加载资源"),   icon: "hare"),
            .init(id: "websockets",  title: "WebSockets",                        subtitle: AppLocalization.string(localized: "允许 WebSocket 长连接"),       icon: "arrow.left.arrow.right"),
            .init(id: "ipv6",        title: AppLocalization.string(localized: "IPv6 兼容"),       subtitle: AppLocalization.string(localized: "为源站提供 IPv6 访问"),         icon: "network"),
        ]
    }

    var body: some View {

        let _ = preferences.languageRaw
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !viewModel.loaded {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        OCContentUnavailableView {
                            Label(AppLocalization.string(localized: "无法读取设置"), systemImage: "lock")
                        } description: {
                            Text("当前授权未包含「缓存与防护」的读取权限。请退出登录后重新授权。")
                        }
                        .padding(.top, 40)
                    }
                } else {
                    networkCard
                    cacheCard
                    if !canEdit {
                        Text("当前为只读授权，如需修改请重新登录并勾选「缓存与防护」的编辑权限。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                    }
                }
            }
            .padding()
        }
        .background { SkyBackground() }
        .ocNavigationTitle("性能与缓存")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("操作失败", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - 网络优化

    private var networkCard: some View {
        card(AppLocalization.string(localized: "网络优化")) {
            VStack(spacing: 16) {
                ForEach(networkSpecs, id: \.id) { spec in
                    toggleRow(spec)
                }
            }
        }
    }

    // MARK: - 缓存

    private var cacheCard: some View {
        card(AppLocalization.string(localized: "缓存")) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "speedometer", color: .ocOrange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("缓存级别")
                        Text("决定哪些请求按查询字符串缓存")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.updating.contains("cache_level") {
                        ProgressView()
                    } else {
                        Picker(AppLocalization.string(localized: "缓存级别"), selection: Binding(
                            get: { viewModel.cacheLevel },
                            set: { lvl in Task { await viewModel.setCacheLevel(lvl) } }
                        )) {
                            ForEach(CacheLevel.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(!canEdit)
                    }
                }
                toggleRow(.init(id: "always_online", title: "Always Online",
                                subtitle: AppLocalization.string(localized: "源站离线时提供缓存快照"), icon: "wifi.slash"))
                toggleRow(.init(id: "sort_query_string_for_cache", title: AppLocalization.string(localized: "排序查询字符串"),
                                subtitle: AppLocalization.string(localized: "忽略查询参数顺序以提升命中率"), icon: "arrow.up.arrow.down"))
            }
        }
    }

    // MARK: - 复用组件

    private func toggleRow(_ spec: ToggleSpec) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: spec.icon, color: .ocOrange)
            VStack(alignment: .leading, spacing: 1) {
                Text(spec.title)
                Text(spec.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.updating.contains(spec.id) {
                ProgressView()
            } else {
                Toggle("", isOn: Binding(
                    get: { viewModel.isOn(spec.id) },
                    set: { on in Task { await viewModel.setToggle(spec.id, on) } }
                ))
                .labelsHidden()
                .accessibilityLabel(spec.title)
                .disabled(!canEdit)
            }
        }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .glassIsland(cornerRadius: OCLayout.chipRadius)
        }
    }
}
