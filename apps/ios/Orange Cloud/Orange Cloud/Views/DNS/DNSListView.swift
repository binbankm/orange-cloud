//
//  DNSListView.swift
//  Orange Cloud
//
//  DNS 记录列表：@Query 读缓存、下拉刷新、滑动编辑/删除、Sheet 表单增改。
//

import SwiftUI

struct DNSListView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let zoneId: String
    let zoneName: String

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cacheStore: CacheStore

    @StateObject private var viewModel: DNSListViewModel
    @State private var searchText = ""
    @State private var formMode: DNSFormMode?
    @State private var recordToDelete: CachedDNSRecord?
    @State private var deniedScope: String?       // 权限不足时非空，触发提示

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneId = zoneId
        self.zoneName = zoneName
        _viewModel = StateObject(wrappedValue: DNSListViewModel(dnsService: session.dnsService, zoneId: zoneId, zoneName: zoneName))
    }

    private var records: [CachedDNSRecord] {
        cacheStore.records(for: zoneId).sorted {
            ($0.type, $0.name) < ($1.type, $1.name)
        }
    }

    private var filteredRecords: [CachedDNSRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.content.localizedCaseInsensitiveContains(searchText)
                || $0.type.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - 权限检查

    private var canWrite: Bool { auth.hasScope("dns.write") }

    /// dns.write 存在则执行 action，否则弹出权限提示
    private func requireWrite(_ action: () -> Void) {
        if canWrite { action() } else { deniedScope = "dns.write" }
    }

    // MARK: - body

    var body: some View {

        let _ = preferences.languageRaw
        Group {
            if records.isEmpty && viewModel.isLoading {
                SkeletonList(rows: 10, icon: .rounded(width: 52, height: 24), trailing: true)
            } else if records.isEmpty {
                OCContentUnavailableView {
                    Label(AppLocalization.string(localized: "没有 DNS 记录"), systemImage: "network.slash")
                } description: {
                    Text(canWrite ? AppLocalization.string(localized: "点击右上角 + 添加第一条记录") : AppLocalization.string(localized: "当前授权仅限读取，无法添加记录"))
                } actions: {
                    if canWrite {
                        Button(AppLocalization.string(localized: "添加记录")) { formMode = .add }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else if filteredRecords.isEmpty {
                OCContentUnavailableView.search(text: searchText)
            } else {
                recordList
            }
        }
        .background { SkyBackground() }
        .navigationTitle(zoneName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: AppLocalization.string(localized: "搜索记录"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string(localized: "添加"), systemImage: "plus") { requireWrite { formMode = .add } }
            }
        }
        .sheet(item: $formMode) { mode in
            DNSRecordFormView(mode: mode, viewModel: viewModel)
        }
        .confirmationDialog(
            AppLocalization.string(localized: "删除 DNS 记录"),
            isPresented: .init(
                get: { recordToDelete != nil },
                set: { if !$0 { recordToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let record = recordToDelete {
                Button(AppLocalization.string(localized: "删除 \(record.name)"), role: .destructive) {
                    Task {
                        await viewModel.delete(recordId: record.id)
                    }
                }
            }
        } message: {
            Text(AppLocalization.string(localized: "此操作不可撤销，DNS 解析将立即生效变更。"))
        }
        .task {
            await viewModel.refresh()
        }
        .ocSensoryFeedback(.success, trigger: viewModel.didSave)
        // 权限不足提示
        .alert(AppLocalization.string(localized: "权限不足"), isPresented: .init(
            get: { deniedScope != nil },
            set: { if !$0 { deniedScope = nil } }
        )) {
            Button(AppLocalization.string(localized: "好"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string(localized: "当前授权未包含 DNS 编辑权限（\(deniedScope ?? "dns.write")）。\n请在设置中退出登录后重新授权以启用此功能。"))
        }
        // API 错误提示（仅在表单未显示时展示，避免与表单内错误重叠）
        .alert(AppLocalization.string(localized: "出错了"), isPresented: .init(
            get: { viewModel.error != nil && formMode == nil && deniedScope == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button(AppLocalization.string(localized: "好"), role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private var recordList: some View {
        List {
            ForEach(filteredRecords) { record in
                DNSRecordRow(record: record)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            requireWrite { recordToDelete = record }
                        } label: {
                            Label(AppLocalization.string(localized: "删除"), systemImage: "trash")
                        }
                        Button {
                            requireWrite { formMode = .edit(record) }
                        } label: {
                            Label(AppLocalization.string(localized: "编辑"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        requireWrite { formMode = .edit(record) }
                    }
                    .glassRow()
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refresh(force: true)
        }
    }
}

// MARK: - 表单模式

enum DNSFormMode: Identifiable {
    case add
    case edit(CachedDNSRecord)

    var id: String {
        switch self {
        case .add:               "add"
        case .edit(let record):  record.id
        }
    }
}

// MARK: - 记录行

struct DNSRecordRow: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    let record: CachedDNSRecord

    var body: some View {

        let _ = preferences.languageRaw
        HStack(spacing: 12) {
            Text(record.type)
                .font(.caption.bold().monospaced())
                .frame(width: 52)
                .padding(.vertical, 4)
                .background(Color.ocOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color.ocOrangeText)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(record.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            ProxiedBadge(proxied: record.proxied)
        }
        .padding(.vertical, 2)
    }
}
