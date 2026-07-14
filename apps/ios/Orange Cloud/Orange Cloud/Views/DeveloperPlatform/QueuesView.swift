//
//  QueuesView.swift
//  Orange Cloud
//
//  Cloudflare Queues 列表 + 新建 / 删除 + 详情管理。account 级，读 queues.read / 写 queues.write。
//  详情用 sheet（自带 NavigationStack）：暂停/恢复投递、改保留期与投递延迟、重命名、清空消息、删除。
//

import SwiftUI

struct QueuesView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let session: SessionStore

    @EnvironmentObject private var auth: AuthManager
    @StateObject private var vmStore = OptionalObservableObjectStore()
    private var vm: QueuesViewModel? { vmStore.value(as: QueuesViewModel.self) }
    @State private var showCreate = false
    @State private var detailTarget: CFQueue?
    @State private var deleteTarget: CFQueue?
    @State private var writeDenied = false

    private var canWrite: Bool { auth.hasScope("queues.write") }

    var body: some View {

        let _ = preferences.languageRaw
        Group {
            if let vm { content(vm) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background { SkyBackground() }
        .ocNavigationTitle("Queues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string(localized: "新建队列"), systemImage: "plus") {
                        if canWrite { showCreate = true } else { writeDenied = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            if let vm { QueueCreateView(viewModel: vm) }
        }
        .sheet(item: $detailTarget) { queue in
            if let vm { QueueDetailSheet(viewModel: vm, queueId: queue.queueId) }
        }
        .alert(AppLocalization.string(localized: "权限不足"), isPresented: $writeDenied) {
            Button(AppLocalization.string(localized: "好"), role: .cancel) {}
        } message: {
            Text.ocLocalized("当前授权未包含 Queues 写权限（queues.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .confirmationDialog(
            deleteTarget.map { AppLocalization.string(localized: "删除队列「\($0.name)」？") } ?? "",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string(localized: "删除"), role: .destructive) {
                if let q = deleteTarget, let vm { Task { await vm.delete(q) } }
            }
        } message: {
            Text.ocLocalized("删除后该队列及其未消费消息将被移除，不可撤销。")
        }
        .task {
            await session.ensureAccounts()
            guard vm == nil else { return }
            let model = QueuesViewModel(service: session.queueService, accountId: session.selectedAccount?.id)
            vmStore.set(model)
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: QueuesViewModel) -> some View {
        if vm.isLoading && !vm.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.queues.isEmpty {
            OCContentUnavailableView {
                Label(AppLocalization.string(localized: "没有队列"), systemImage: "tray.2")
            } description: {
                Text(vm.error ?? AppLocalization.string(localized: "该账号下还没有 Queue。"))
            } actions: {
                if canWrite {
                    Button(AppLocalization.string(localized: "新建队列")) { showCreate = true }
                        .buttonStyle(.borderedProminent).tint(Color.ocOrangePressed).fontWeight(.bold)
                }
            }
        } else {
            List {
                Section {
                    ForEach(vm.queues) { queue in
                        Button { detailTarget = queue } label: {
                            QueueRow(queue: queue)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if canWrite {
                                Button(role: .destructive) { deleteTarget = queue } label: {
                                    Label(AppLocalization.string(localized: "删除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                } footer: {
                    Text.ocLocalized("点按查看详情与管理 · 生产者 / 消费者绑定在 Worker 中配置。")
                }
                .glassRow()
            }
            .daybreakList()
            .refreshable { await vm.load() }
            .ocSensoryFeedback(.success, trigger: vm.didChange)
        }
    }
}

private struct QueueRow: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    let queue: CFQueue

    var body: some View {

        let _ = preferences.languageRaw
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(queue.name).font(.callout.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                Text.ocLocalized("\(queue.producers?.count ?? 0) 生产者 · \(queue.consumers?.count ?? 0) 消费者")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if queue.settings?.deliveryPaused == true {
                Text.ocLocalized("已暂停").font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ocOrangeText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.ocOrange.opacity(0.14), in: Capsule())
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - 详情管理 sheet

private struct QueueDetailSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @ObservedObject var viewModel: QueuesViewModel
    let queueId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager
    @State private var showRename = false
    @State private var showSettings = false
    @State private var showPurge = false
    @State private var showDelete = false

    private var canWrite: Bool { auth.hasScope("queues.write") }
    private var queue: CFQueue? { viewModel.queues.first { $0.queueId == queueId } }
    private var isPaused: Bool { queue?.settings?.deliveryPaused ?? false }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Group {
                if let queue { detail(queue) } else { ProgressView() }
            }
            .background { SkyBackground() }
            .navigationTitle(queue?.name ?? AppLocalization.string(localized: "队列"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.string(localized: "完成")) { dismiss() } }
                if canWrite {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button(AppLocalization.string(localized: "重命名"), systemImage: "pencil") { showRename = true }
                            Button(AppLocalization.string(localized: "编辑设置"), systemImage: "slider.horizontal.3") { showSettings = true }
                            Button(AppLocalization.string(localized: "清空消息"), systemImage: "trash.slash", role: .destructive) { showPurge = true }
                            Divider()
                            Button(AppLocalization.string(localized: "删除队列"), systemImage: "trash", role: .destructive) { showDelete = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showRename) {
                if let queue { QueueRenameSheet(viewModel: viewModel, queueId: queueId, currentName: queue.name) }
            }
            .sheet(isPresented: $showSettings) {
                if let queue { QueueSettingsSheet(viewModel: viewModel, queueId: queueId, settings: queue.settings) }
            }
            .confirmationDialog(
                AppLocalization.string(localized: "清空队列全部消息？"),
                isPresented: $showPurge, titleVisibility: .visible
            ) {
                Button(AppLocalization.string(localized: "清空消息"), role: .destructive) {
                    Task { await viewModel.purge(queueId: queueId) }
                }
            } message: {
                Text.ocLocalized("将永久删除该队列中所有未消费的消息，不可撤销。队列本身保留。")
            }
            .confirmationDialog(
                queue.map { AppLocalization.string(localized: "删除队列「\($0.name)」？") } ?? "",
                isPresented: $showDelete, titleVisibility: .visible
            ) {
                Button(AppLocalization.string(localized: "删除"), role: .destructive) {
                    if let queue {
                        Task { await viewModel.delete(queue); dismiss() }
                    }
                }
            } message: {
                Text.ocLocalized("删除后该队列及其未消费消息将被移除，不可撤销。")
            }
            // 队列被删（列表里没了）时自动收起
            .onChange(of: viewModel.queues.contains { $0.queueId == queueId }) { stillThere in
                if !stillThere { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func detail(_ queue: CFQueue) -> some View {
        List {
            Section {
                LabeledContent(AppLocalization.string(localized: "状态")) {
                    Text(isPaused ? "投递已暂停" : "投递中")
                        .foregroundStyle(isPaused ? Color.ocOrangeText : .secondary)
                }
                if canWrite {
                    Button {
                        Task { await viewModel.togglePause(queueId: queueId, paused: !isPaused) }
                    } label: {
                        Label(isPaused ? "恢复投递" : "暂停投递",
                              systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .disabled(viewModel.isSaving)
                }
            } header: {
                Text.ocLocalized("投递")
            } footer: {
                Text.ocLocalized("暂停后队列仍会接收消息，但暂停向消费者投递。")
            }
            .glassRow()

            Section(AppLocalization.string(localized: "设置")) {
                LabeledContent(AppLocalization.string(localized: "消息保留期"), value: Self.formatSeconds(queue.settings?.messageRetentionPeriod))
                LabeledContent(AppLocalization.string(localized: "投递延迟"), value: Self.formatSeconds(queue.settings?.deliveryDelay))
                if let created = queue.createdOn, let date = WorkerScript.parseDate(created) {
                    LabeledContent(AppLocalization.string(localized: "创建于"), value: AppLocalization.dateTime(date, timeStyle: .short))
                }
            }
            .glassRow()

            Section {
                if let producers = queue.producers, !producers.isEmpty {
                    ForEach(Array(producers.enumerated()), id: \.offset) { _, p in
                        Text(p.script ?? p.type ?? AppLocalization.string(localized: "未知")).font(.callout.monospaced()).lineLimit(1)
                    }
                } else {
                    Text.ocLocalized("无生产者").foregroundStyle(.secondary).font(.callout)
                }
            } header: {
                Text.ocLocalized("生产者（\(queue.producersTotalCount ?? queue.producers?.count ?? 0)）")
            }
            .glassRow()

            Section {
                if let consumers = queue.consumers, !consumers.isEmpty {
                    ForEach(Array(consumers.enumerated()), id: \.offset) { _, c in
                        ConsumerRow(consumer: c)
                    }
                } else {
                    Text.ocLocalized("无消费者").foregroundStyle(.secondary).font(.callout)
                }
            } header: {
                Text.ocLocalized("消费者（\(queue.consumersTotalCount ?? queue.consumers?.count ?? 0)）")
            } footer: {
                Text.ocLocalized("消费者绑定与批处理参数在 Worker 中配置。")
            }
            .glassRow()

            if let error = viewModel.error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }.glassRow()
            }
        }
        .daybreakList()
    }

    /// 秒 → 可读时长（如 345600 → 「4 天」）；nil → 「—」
    static func formatSeconds(_ seconds: Int?) -> String {
        guard let s = seconds else { return "—" }
        if s == 0 { return AppLocalization.string(localized: "无") }
        if s % 86400 == 0 { return AppLocalization.string(localized: "\(s / 86400) 天") }
        if s % 3600 == 0 { return AppLocalization.string(localized: "\(s / 3600) 小时") }
        if s % 60 == 0 { return AppLocalization.string(localized: "\(s / 60) 分钟") }
        return AppLocalization.string(localized: "\(s) 秒")
    }
}

private struct ConsumerRow: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    let consumer: CFQueueEndpoint

    var body: some View {

        let _ = preferences.languageRaw
        VStack(alignment: .leading, spacing: 3) {
            Text(consumer.script ?? consumer.type ?? AppLocalization.string(localized: "未知"))
                .font(.callout.monospaced()).lineLimit(1)
            if let s = consumer.settings {
                let parts = [
                    s.batchSize.map { AppLocalization.string(localized: "批 \($0)") },
                    s.maxRetries.map { AppLocalization.string(localized: "重试 \($0)") },
                    s.maxConcurrency.map { AppLocalization.string(localized: "并发 \($0)") }
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let dlq = consumer.deadLetterQueue {
                Text.ocLocalized("死信队列：\(dlq)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 重命名

private struct QueueRenameSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @ObservedObject var viewModel: QueuesViewModel
    let queueId: String
    let currentName: String

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(viewModel: QueuesViewModel, queueId: String, currentName: String) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.queueId = queueId
        self.currentName = currentName
        _name = State(initialValue: currentName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != currentName && !viewModel.isSaving }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Form {
                Section {
                    TextField(AppLocalization.string(localized: "队列名称"), text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.callout.monospaced())
                } footer: {
                    Text.ocLocalized("小写字母 / 数字 / 连字符。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .ocNavigationTitle("重命名队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await viewModel.update(queueId: queueId, queueName: trimmed) { dismiss() } }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text.ocLocalized("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}

// MARK: - 编辑设置（保留期 / 投递延迟）

private struct QueueSettingsSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @ObservedObject var viewModel: QueuesViewModel
    let queueId: String

    @Environment(\.dismiss) private var dismiss
    @State private var retentionText: String
    @State private var delayText: String

    init(viewModel: QueuesViewModel, queueId: String, settings: CFQueueSettings?) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.queueId = queueId
        _retentionText = State(initialValue: settings?.messageRetentionPeriod.map(String.init) ?? "345600")
        _delayText = State(initialValue: settings?.deliveryDelay.map(String.init) ?? "0")
    }

    private var retention: Int? { Int(retentionText) }
    private var delay: Int? { Int(delayText) }
    private var canSave: Bool {
        guard let r = retention, (60...1_209_600).contains(r),
              let d = delay, (0...43_200).contains(d) else { return false }
        return !viewModel.isSaving
    }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Form {
                Section {
                    TextField(AppLocalization.string(localized: "消息保留期（秒）"), text: $retentionText).keyboardType(.numberPad)
                } footer: {
                    Text.ocLocalized("60 秒 – 14 天（1209600 秒）。当前约 \(QueueDetailSheet.formatSeconds(retention))。")
                }
                Section {
                    TextField(AppLocalization.string(localized: "投递延迟（秒）"), text: $delayText).keyboardType(.numberPad)
                } footer: {
                    Text.ocLocalized("0 – 12 小时（43200 秒）。消息进入队列后延迟多久才投递。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .ocNavigationTitle("编辑设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let r = retention, let d = delay else { return }
                        Task {
                            let ok = await viewModel.update(
                                queueId: queueId,
                                settings: CFQueueSettingsPatch(deliveryDelay: d, messageRetentionPeriod: r)
                            )
                            if ok { dismiss() }
                        }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text.ocLocalized("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}

private struct QueueCreateView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @ObservedObject var viewModel: QueuesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && !viewModel.isSaving }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Form {
                Section {
                    TextField(AppLocalization.string(localized: "队列名称"), text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.callout.monospaced())
                } footer: {
                    Text.ocLocalized("小写字母 / 数字 / 连字符。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .ocNavigationTitle("新建队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await viewModel.create(name: trimmed) { dismiss() } }
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
}
