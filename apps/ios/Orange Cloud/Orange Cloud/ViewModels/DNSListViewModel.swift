//
//  DNSListViewModel.swift
//  Orange Cloud
//
//  DNS 记录的拉取与增删改，全部同步进 SwiftData 缓存。
//

import Foundation
import Combine

@MainActor
final class DNSListViewModel: ObservableObject {

    @Published var isLoading = false
    @Published var isSaving  = false
    @Published var error: String?
    @Published var didSave = false      // sensoryFeedback 触发器

    private let dnsService: DNSService
    private let zoneId: String
    private let zoneName: String
    /// 进行中的加载任务（见 ZoneListViewModel：独立 Task 承载加载，避免下拉手势取消导致 .cancelled 误报）
    private var loadTask: Task<Void, Never>?

    init(dnsService: DNSService, zoneId: String, zoneName: String = "") {
        self.dnsService = dnsService
        self.zoneId = zoneId
        self.zoneName = zoneName
    }

    func refresh(force: Bool = false) async {
        // 非强制（首屏/切 Tab）且缓存仍新鲜：用缓存（@Query 已渲染），不重发请求
        if !force, CachePolicy.dnsFresh(zoneId: zoneId) { return }
        // 复用进行中的加载，并把网络加载放进独立 Task：下拉手势 / searchable 取消
        // .refreshable 子任务时不波及加载，避免 URLError.cancelled 误报为加载失败
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.load()
        }
        loadTask = task
        defer { loadTask = nil }
        await task.value
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let records = try await dnsService.listRecords(zoneId: zoneId)
            sync(records: records)
            SpotlightIndexer.indexDNSRecords(records, zoneId: zoneId, zoneName: zoneName)
        } catch is CancellationError {
            // 任务取消属正常生命周期，不算加载失败
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession 把任务取消转成 .cancelled，同样不展示为错误
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 新建或更新记录；recordId == nil 表示新建。成功返回 true。
    func save(recordId: String?, record: CreateDNSRecord) async -> Bool {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let saved: DNSRecord
            if let recordId {
                saved = try await dnsService.updateRecord(zoneId: zoneId, recordId: recordId, record: record)
            } else {
                saved = try await dnsService.createRecord(zoneId: zoneId, record: record)
            }
            upsert(saved)
            didSave.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: - 设备端 AI 生成（自然语言 → 结构化 → 记录草稿）

    @Published var isGenerating = false
    @Published var generationError: String?

    /// 用自然语言生成一条记录草稿；失败时写入 generationError 并返回 nil。
    func generateRecord(from naturalLanguage: String, locale: Locale = .current) async -> GeneratedDNSRecord? {
        let trimmed = naturalLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return nil }
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }
        do {
            return try await DNSAssistant.generateRecord(from: trimmed, locale: locale)
        } catch {
            generationError = error.localizedDescription
            return nil
        }
    }

    func delete(recordId: String) async {
        error = nil
        do {
            try await dnsService.deleteRecord(zoneId: zoneId, recordId: recordId)
            CacheStore.shared.removeRecord(id: recordId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 缓存同步（写失败静默放弃：API 数据已在手，UI 不受影响）

    private func sync(records: [DNSRecord]) {
        CacheStore.shared.replaceRecords(records, zoneId: zoneId)
    }

    private func upsert(_ record: DNSRecord) {
        CacheStore.shared.upsert(record: record, zoneId: zoneId)
    }
}
