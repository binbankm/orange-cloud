//
//  AuditLogViewModel.swift
//  Orange Cloud
//
//  审计日志列表：最近 30 天，游标分页（下滑续接）。
//

import Foundation
import Combine

@MainActor
final class AuditLogViewModel: ObservableObject {

    @Published private(set) var entries: [IdentifiedAuditEntry] = []
    @Published private(set) var canLoadMore = false
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?

    private let service: AuditLogService
    private let accountId: String

    /// 时间窗在首次加载时固定，续页复用同一窗口（游标分页要求查询参数一致）
    private var since:  Date?
    private var before: Date?
    private var cursor: String?

    /// 查询窗口：最近 30 天
    private static let windowDays: TimeInterval = 30 * 24 * 3600

    init(service: AuditLogService, accountId: String) {
        self.service = service
        self.accountId = accountId
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        let before = Date()
        let since = before.addingTimeInterval(-Self.windowDays)
        self.before = before
        self.since = since
        self.cursor = nil

        do {
            let page = try await service.list(
                accountId: accountId, since: since, before: before, cursor: nil
            )
            entries = (page.result ?? []).map { IdentifiedAuditEntry(entry: $0) }
            cursor = page.cursor
            canLoadMore = !(page.cursor?.isEmpty ?? true)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore,
              let cursor, let since, let before else { return }
        isLoadingMore = true
        do {
            let page = try await service.list(
                accountId: accountId, since: since, before: before, cursor: cursor
            )
            entries.append(contentsOf: (page.result ?? []).map { IdentifiedAuditEntry(entry: $0) })
            self.cursor = page.cursor
            canLoadMore = !(page.cursor?.isEmpty ?? true)
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingMore = false
    }
}
