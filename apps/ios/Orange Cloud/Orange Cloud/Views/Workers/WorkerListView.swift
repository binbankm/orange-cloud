//
//  WorkerListView.swift
//  Orange Cloud
//
//  Workers 列表（设计稿 workers.jsx）：
//  bolt 圆底图标 + mono 名称 + handlers 副标题 + 相对部署时间，左滑直达实时日志。
//

import SwiftUI

struct WorkerListView: View {

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cacheStore: CacheStore
    @EnvironmentObject private var preferences: AppPreferencesStore

    @StateObject private var viewModel: WorkerListViewModel
    @StateObject private var uploadViewModel: WorkerUploadViewModel
    @State private var searchText = ""
    @State private var tailTarget: CachedWorkerScript?
    @State private var showTailDenied = false
    @State private var showCreate = false
    @State private var createDenied = false
    @AppStorage("workerListSort") private var sort: ResourceSort = .name

    private var canWrite: Bool { auth.hasScope("workers-scripts.write") }

    init(session: SessionStore) {
        let accountId = session.selectedAccount?.id ?? ""
        _viewModel = StateObject(wrappedValue: WorkerListViewModel(workerService: session.workerService))
        _uploadViewModel = StateObject(wrappedValue: WorkerUploadViewModel(service: session.workerService, accountId: accountId))
    }

    private var filteredScripts: [CachedWorkerScript] {
        let cachedScripts = cacheStore.scripts(for: session.selectedAccount?.id ?? "")
        let scripts = searchText.isEmpty ? cachedScripts : cachedScripts.filter { $0.id.localizedCaseInsensitiveContains(searchText) }
        return sort.sorted(scripts, created: \.createdOn, modified: \.modifiedOn)
    }

    private var cachedScripts: [CachedWorkerScript] {
        cacheStore.scripts(for: session.selectedAccount?.id ?? "")
    }

    var body: some View {
        let _ = preferences.languageRaw
        // 复用宿主（开发者平台 / 旧 Tab）的单一 NavigationStack，本视图不自带 stack：
        //  · 自带 stack → 嵌套栈，点击行进详情会回弹到上级（开发者 Tab）；
        //  · 在「被 push 的子视图」上挂 .navigationDestination 又会失灵（导航栏切了、内容不切）。
        // 故详情走「行内 NavigationLink(destination:)」直接 push 进宿主栈，实时日志改用 .sheet，均不依赖 .navigationDestination。
        // iOS 17 整页卡死 / iOS 26 秒级卡顿的根因是宿主 eager 急切构造本页，已在 PermissionGatedNavigationLink 用 LazyView 解决。
        Group {
            Group {
                if cachedScripts.isEmpty && viewModel.isLoading {
                    SkeletonList(rows: 8, trailing: true)
                } else if cachedScripts.isEmpty {
                    emptyState
                } else if filteredScripts.isEmpty {
                    OCContentUnavailableView.search(text: searchText)
                } else {
                    scriptList
                }
            }
            .background { SkyBackground() }
            .ocNavigationTitle("Workers")
            .searchable(text: $searchText, prompt: "搜索脚本")
            .sheet(item: $tailTarget) { script in
                NavigationStack {
                    WorkerTailView(accountId: script.accountId, scriptName: script.id, session: session)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ResourceSortMenu(sort: $sort)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建 Worker", systemImage: "plus") {
                        if canWrite { showCreate = true } else { createDenied = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    RefreshButton(
                        isLoading: viewModel.isLoading,
                        failed: viewModel.error != nil,
                        action: { Task { await refresh() } }
                    )
                }
            }
            .sheet(isPresented: $showCreate) {
                WorkerUploadView(mode: .create, viewModel: uploadViewModel) {
                    Task { await refresh() }
                }
            }
            .ocSensoryFeedback(.success, trigger: uploadViewModel.didUpload)
            .task {
                await refresh()
            }
            .alert("权限不足", isPresented: $showTailDenied) {
                Button("好", role: .cancel) {}
            } message: {
                Text("当前授权未包含实时日志权限（workers-tail.read）。\n请在设置中退出登录后重新授权以启用此功能。")
            }
            .alert("权限不足", isPresented: $createDenied) {
                Button("好", role: .cancel) {}
            } message: {
                Text("当前授权未包含 Workers 写权限（workers-scripts.write）。\n请在设置中退出登录后重新授权以启用此功能。")
            }
        }
    }

    private var scriptList: some View {
        List {
            Section {
                ForEach(filteredScripts) { script in
                    NavigationLink(value: script) {
                        WorkerRow(script: script)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            if auth.hasScope("workers-tail.read") {
                                tailTarget = script
                            } else {
                                showTailDenied = true
                            }
                        } label: {
                            Label("查看日志", systemImage: "text.alignleft")
                        }
                        .tint(Color.ocOrange)
                    }
                }
            } header: {
                Text.ocLocalized("\(cachedScripts.count) 个 Worker")
            } footer: {
                Label("向左滑动查看实时日志 · 点按查看详情", systemImage: "hand.draw")
                    .font(.caption)
            }
            .glassRow()
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await refresh()
        }
    }

    private var emptyState: some View {
        OCContentUnavailableView {
            Label("没有 Workers", systemImage: "bolt.slash")
        } description: {
            Text("在 Cloudflare Dashboard 部署你的第一个 Worker")
        } actions: {
            Button("刷新") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ocOrangePressed)
            .fontWeight(.bold)
        }
    }

    private func refresh() async {
        await session.ensureAccounts()
        guard let accountId = session.selectedAccount?.id else { return }
        await viewModel.refresh(accountId: accountId)
    }
}

// MARK: - Worker 行（设计稿 WorkerRow）

struct WorkerRow: View {
    let script: CachedWorkerScript

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "bolt.fill", color: .ocOrange, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(script.id)
                    .font(.callout.weight(.semibold).monospaced())
                    .lineLimit(1)
                if !script.handlers.isEmpty {
                    Text(script.handlers.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let modified = WorkerScript.parseDate(script.modifiedOn) {
                Text(modified, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
