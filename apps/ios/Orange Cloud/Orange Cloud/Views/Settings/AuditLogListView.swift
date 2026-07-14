//
//  AuditLogListView.swift
//  Orange Cloud
//
//  账号审计日志（最近 30 天）。只读、账号级，复用 account-settings.read。
//

import SwiftUI

struct AuditLogListView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let session: SessionStore

    @StateObject private var vmStore = OptionalObservableObjectStore()
    private var vm: AuditLogViewModel? { vmStore.value(as: AuditLogViewModel.self) }

    var body: some View {

        let _ = preferences.languageRaw
        Group {
            if let vm {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { SkyBackground() }
        .ocNavigationTitle("审计日志")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await session.ensureAccounts()
            guard vm == nil, let accountId = session.selectedAccount?.id else { return }
            let model = AuditLogViewModel(service: session.auditLogService, accountId: accountId)
            vmStore.set(model)
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: AuditLogViewModel) -> some View {
        if vm.isLoading && vm.entries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.entries.isEmpty {
            OCContentUnavailableView {
                Label("暂无审计记录", systemImage: "clock.arrow.circlepath")
            } description: {
                Text(vm.error ?? AppLocalization.string(localized: "最近 30 天没有可显示的账号操作记录。"))
            }
        } else {
            List {
                Section {
                    ForEach(vm.entries) { item in
                        AuditLogRow(entry: item.entry)
                    }
                } footer: {
                    Text("仅显示当前账号最近 30 天的操作记录。")
                }
                .glassRow()

                if vm.canLoadMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onAppear {
                        Task { await vm.loadMore() }
                    }
                }
            }
            .daybreakList()
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - 单条记录

private struct AuditLogRow: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let entry: AuditLogEntry

    private var title: String {
        entry.action?.description?.nilIfEmpty
            ?? entry.action?.type?.nilIfEmpty
            ?? AppLocalization.string(localized: "未知操作")
    }

    private var subtitle: String {
        let who = entry.actor?.email?.nilIfEmpty
            ?? entry.actor?.type?.nilIfEmpty
            ?? AppLocalization.string(localized: "系统")
        if let product = entry.resource?.product?.nilIfEmpty {
            return "\(product) · \(who)"
        }
        return who
    }

    private var relativeTime: String {
        guard let date = entry.timestamp else { return entry.action?.time ?? "" }
        return AppLocalization.relativeDate(date)
    }

    var body: some View {

        let _ = preferences.languageRaw
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(relativeTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.succeeded {
        case .some(true):
            TintIcon(systemImage: "checkmark", color: .green)
        case .some(false):
            TintIcon(systemImage: "xmark", color: .red)
        case .none:
            TintIcon(systemImage: "circle.dotted", color: .gray)
        }
    }
}

private extension String {
    /// 去空白后为空则视为无值
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
