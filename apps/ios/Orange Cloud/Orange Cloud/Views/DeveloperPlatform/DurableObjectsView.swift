//
//  DurableObjectsView.swift
//  Orange Cloud
//
//  Durable Objects 命名空间（命名空间本身只读：由 Worker 迁移声明，API 不支持增删改）。
//  点命名空间可下钻浏览其对象实例（只读，游标分页）。account 级，workers-scripts.read。
//

import SwiftUI

struct DurableObjectsView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let session: SessionStore
    @StateObject private var vmStore = OptionalObservableObjectStore()
    private var vm: DurableObjectsViewModel? { vmStore.value(as: DurableObjectsViewModel.self) }
    @State private var detailTarget: DurableObjectNamespace?

    var body: some View {

        let _ = preferences.languageRaw
        Group {
            if let vm { content(vm) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background { SkyBackground() }
        .ocNavigationTitle("Durable Objects")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detailTarget) { ns in
            DurableObjectInstancesSheet(session: session, namespace: ns)
        }
        .task {
            await session.ensureAccounts()
            guard vm == nil else { return }
            let model = DurableObjectsViewModel(service: session.durableObjectService, accountId: session.selectedAccount?.id)
            vmStore.set(model)
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: DurableObjectsViewModel) -> some View {
        if vm.isLoading && !vm.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.namespaces.isEmpty {
            OCContentUnavailableView {
                Label(AppLocalization.string(localized: "没有 Durable Objects"), systemImage: "cube.transparent")
            } description: {
                Text(vm.error ?? AppLocalization.string(localized: "该账号下还没有 Durable Object 命名空间。命名空间由 Worker 迁移声明。"))
            }
        } else {
            List {
                Section {
                    ForEach(vm.namespaces) { ns in
                        Button { detailTarget = ns } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(ns.name ?? ns.className ?? ns.id)
                                            .font(.callout.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                                        if ns.useSqlite == true {
                                            Text.ocLocalized("SQLite").font(.caption2.weight(.semibold))
                                                .foregroundStyle(Color.ocOrangeText)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.ocOrange.opacity(0.14), in: Capsule())
                                        }
                                    }
                                    if let cls = ns.className {
                                        Text(verbatim: "class \(cls)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    if let script = ns.script {
                                        Text(script).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text.ocLocalized("点按浏览对象实例 · 命名空间的增删改请在 Worker 迁移中进行。")
                }
                .glassRow()
            }
            .daybreakList()
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - 对象实例浏览 sheet（只读，游标分页）

private struct DurableObjectInstancesSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    let session: SessionStore
    let namespace: DurableObjectNamespace

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vmStore = OptionalObservableObjectStore()
    private var vm: DurableObjectInstancesViewModel? { vmStore.value(as: DurableObjectInstancesViewModel.self) }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Group {
                if let vm { content(vm) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .background { SkyBackground() }
            .navigationTitle(namespace.name ?? namespace.className ?? namespace.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.string(localized: "完成")) { dismiss() } }
            }
            .task {
                guard vm == nil else { return }
                let model = DurableObjectInstancesViewModel(
                    service: session.durableObjectService,
                    accountId: session.selectedAccount?.id,
                    namespaceId: namespace.id
                )
                vmStore.set(model)
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: DurableObjectInstancesViewModel) -> some View {
        if vm.isLoading && !vm.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.instances.isEmpty {
            OCContentUnavailableView {
                Label(AppLocalization.string(localized: "没有对象"), systemImage: "cube")
            } description: {
                Text(vm.error ?? AppLocalization.string(localized: "该命名空间下还没有对象实例。对象在首次被访问时自动创建。"))
            }
        } else {
            List {
                Section {
                    ForEach(vm.instances) { obj in
                        HStack {
                            Text(obj.id).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if obj.hasStoredData == true {
                                Text.ocLocalized("有数据").font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.ocOrangeText)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.ocOrange.opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if vm.hasMore {
                        Button {
                            Task { await vm.loadMore() }
                        } label: {
                            HStack {
                                Spacer()
                                if vm.isLoading { ProgressView() } else { Text.ocLocalized("加载更多") }
                                Spacer()
                            }
                        }
                        .disabled(vm.isLoading)
                    }
                } header: {
                    Text.ocLocalized("\(vm.instances.count) 个对象")
                } footer: {
                    Text.ocLocalized("对象实例只读：展示对象 ID 与是否已写入存储。")
                }
                .glassRow()
            }
            .daybreakList()
        }
    }
}
