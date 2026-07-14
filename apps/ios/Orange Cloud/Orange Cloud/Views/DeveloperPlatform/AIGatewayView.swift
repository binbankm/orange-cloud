//
//  AIGatewayView.swift
//  Orange Cloud
//
//  Cloudflare AI Gateway 列表 + 新建 / 删除。account 级，读 aig.read / 写 aig.write。
//

import SwiftUI

struct AIGatewayView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let session: SessionStore

    @EnvironmentObject private var auth: AuthManager
    @StateObject private var vmStore = OptionalObservableObjectStore()
    private var vm: AIGatewayViewModel? { vmStore.value(as: AIGatewayViewModel.self) }
    @State private var showCreate = false
    @State private var deleteTarget: AIGateway?
    @State private var writeDenied = false

    private var canWrite: Bool { auth.hasScope("aig.write") }

    var body: some View {

        let _ = preferences.languageRaw
        Group {
            if let vm { content(vm) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background { SkyBackground() }
        .ocNavigationTitle("AI Gateway")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string(localized: "新建网关"), systemImage: "plus") {
                        if canWrite { showCreate = true } else { writeDenied = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            if let vm { AIGatewayCreateView(viewModel: vm) }
        }
        .alert(AppLocalization.string(localized: "权限不足"), isPresented: $writeDenied) {
            Button(AppLocalization.string(localized: "好"), role: .cancel) {}
        } message: {
            Text.ocLocalized("当前授权未包含 AI Gateway 写权限（aig.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .confirmationDialog(
            deleteTarget.map { AppLocalization.string(localized: "删除网关「\($0.id)」？") } ?? "",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string(localized: "删除"), role: .destructive) {
                if let g = deleteTarget, let vm { Task { await vm.delete(g) } }
            }
        } message: {
            Text.ocLocalized("删除后该网关的端点与日志将不可用，不可撤销。")
        }
        .task {
            await session.ensureAccounts()
            guard vm == nil else { return }
            let model = AIGatewayViewModel(service: session.aiGatewayService, accountId: session.selectedAccount?.id)
            vmStore.set(model)
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: AIGatewayViewModel) -> some View {
        if vm.isLoading && !vm.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.gateways.isEmpty {
            OCContentUnavailableView {
                Label(AppLocalization.string(localized: "没有 AI Gateway"), systemImage: "brain.head.profile")
            } description: {
                Text(vm.error ?? AppLocalization.string(localized: "该账号下还没有 AI Gateway。"))
            } actions: {
                if canWrite {
                    Button(AppLocalization.string(localized: "新建网关")) { showCreate = true }
                        .buttonStyle(.borderedProminent).tint(Color.ocOrangePressed).fontWeight(.bold)
                }
            }
        } else {
            List {
                Section {
                    ForEach(vm.gateways) { gateway in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(gateway.id).font(.callout.weight(.semibold).monospaced()).lineLimit(1)
                            Text(subtitle(gateway)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing) {
                            if canWrite {
                                Button(role: .destructive) { deleteTarget = gateway } label: {
                                    Label(AppLocalization.string(localized: "删除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                } footer: {
                    Text.ocLocalized("AI Gateway 为 LLM 调用提供缓存、限速与日志。")
                }
                .glassRow()
            }
            .daybreakList()
            .refreshable { await vm.load() }
            .ocSensoryFeedback(.success, trigger: vm.didChange)
        }
    }

    private func subtitle(_ g: AIGateway) -> String {
        var parts: [String] = []
        if (g.collectLogs ?? false) { parts.append(AppLocalization.string(localized: "日志开")) }
        if let ttl = g.cacheTtl, ttl > 0 { parts.append(AppLocalization.string(localized: "缓存 \(ttl)s")) }
        if let lim = g.rateLimitingLimit, lim > 0 { parts.append(AppLocalization.string(localized: "限速 \(lim)")) }
        return parts.isEmpty ? AppLocalization.string(localized: "默认配置") : parts.joined(separator: " · ")
    }
}

private struct AIGatewayCreateView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @ObservedObject var viewModel: AIGatewayViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var gatewayId = ""
    @State private var collectLogs = true
    @State private var cacheTtl = 0
    @State private var rateLimitingLimit = 0
    @State private var rateLimitingInterval = 60

    private var trimmedId: String { gatewayId.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedId.isEmpty && !viewModel.isSaving }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Form {
                Section {
                    TextField(AppLocalization.string(localized: "网关 ID"), text: $gatewayId)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.callout.monospaced())
                } header: {
                    Text.ocLocalized("标识")
                } footer: {
                    Text.ocLocalized("小写字母 / 数字 / 连字符，创建后不可更改。")
                }
                Section(AppLocalization.string(localized: "日志与缓存")) {
                    Toggle(AppLocalization.string(localized: "收集日志"), isOn: $collectLogs)
                    Stepper(value: $cacheTtl, in: 0...86400, step: 60) {
                        Text.ocLocalized("缓存 TTL：\(cacheTtl) 秒")
                    }
                }
                Section {
                    Stepper(value: $rateLimitingLimit, in: 0...100000, step: 10) {
                        let limit = rateLimitingLimit == 0 ? AppLocalization.string(localized: "不限") : String(rateLimitingLimit)
                        Text.ocLocalized("限速上限：\(limit)")
                    }
                    Stepper(value: $rateLimitingInterval, in: 1...3600, step: 10) {
                        Text.ocLocalized("限速窗口：\(rateLimitingInterval) 秒")
                    }
                } header: {
                    Text.ocLocalized("限速")
                } footer: {
                    Text.ocLocalized("上限为 0 表示不限速。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .ocNavigationTitle("新建网关")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text.ocLocalized("创建").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }

    private func save() async {
        let body = AIGatewayCreate(
            id: trimmedId,
            cacheInvalidateOnUpdate: false,
            cacheTtl: cacheTtl,
            collectLogs: collectLogs,
            rateLimitingInterval: rateLimitingInterval,
            rateLimitingLimit: rateLimitingLimit
        )
        if await viewModel.create(body) { dismiss() }
    }
}
