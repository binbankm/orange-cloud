//
//  WorkerBindingsViewModel.swift
//  Orange Cloud
//
//  Worker 密钥（secret_text，专用端点）+ 环境变量（plain_text，PATCH settings）+ 只读绑定清单。
//  改变量一律 read-modify-write：变更项为实体、其余绑定 inherit，绝不丢失既有绑定/密钥。
//

import Foundation
import Combine

@MainActor
final class WorkerBindingsViewModel: ObservableObject {

    @Published private(set) var secrets: [WorkerSecret] = []
    @Published private(set) var settings: WorkerSettings?
    @Published private(set) var loaded = false
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    private let service: WorkerService
    let accountId:  String
    let scriptName: String

    init(service: WorkerService, accountId: String, scriptName: String) {
        self.service    = service
        self.accountId  = accountId
        self.scriptName = scriptName
    }

    /// 环境变量（plain_text）
    var variables: [WorkerBinding] {
        (settings?.bindings ?? []).filter(\.isPlainText).sorted { $0.name < $1.name }
    }

    /// 其它只读绑定（KV / D1 / R2 / DO 等，非变量非密钥）
    var otherBindings: [WorkerBinding] {
        (settings?.bindings ?? []).filter { !$0.isPlainText && !$0.isSecret }.sorted { $0.name < $1.name }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let secretsTask  = service.listSecrets(accountId: accountId, scriptName: scriptName)
            async let settingsTask = service.settings(accountId: accountId, scriptName: scriptName)
            secrets  = try await secretsTask
            settings = try await settingsTask
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - 密钥

    func addSecret(name: String, text: String) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await service.putSecret(accountId: accountId, scriptName: scriptName, name: name, text: text)
            secrets = (try? await service.listSecrets(accountId: accountId, scriptName: scriptName)) ?? secrets
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteSecret(_ secret: WorkerSecret) async {
        error = nil
        do {
            try await service.deleteSecret(accountId: accountId, scriptName: scriptName, name: secret.name)
            secrets.removeAll { $0.name == secret.name }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 环境变量（PATCH settings，其余绑定 inherit）

    func setVariable(name: String, value: String) async -> Bool {
        guard let settings, !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        var bindings = settings.inheritedBindings(excludingName: name)
        bindings.append(WorkerBindingInput(type: "plain_text", name: name, text: value))
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteVariable(_ binding: WorkerBinding) async {
        guard let settings else { return }
        error = nil
        let bindings = settings.inheritedBindings(excludingName: binding.name)
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 批量导入（JSON）

    /// 批量导入变量（plain_text）：单次 PATCH，导入项设为实体、其余绑定 inherit，同名覆盖。原子。
    func bulkImportVariables(_ pairs: [(name: String, value: String)]) async -> Bool {
        guard let settings, !isSaving, !pairs.isEmpty else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        let importedNames = Set(pairs.map(\.name))
        var bindings = settings.bindings
            .filter { !importedNames.contains($0.name) }
            .map { $0.asInherit() }
        for pair in pairs {
            bindings.append(WorkerBindingInput(type: "plain_text", name: pair.name, text: pair.value))
        }
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 批量导入密钥（secret_text）：逐个 PUT（端点不支持批量），同名覆盖。
    /// 任一失败即停，报告已写入数量并刷新列表反映真实状态。
    func bulkImportSecrets(_ pairs: [(name: String, value: String)]) async -> Bool {
        guard !isSaving, !pairs.isEmpty else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        var done = 0
        do {
            for pair in pairs {
                try await service.putSecret(accountId: accountId, scriptName: scriptName, name: pair.name, text: pair.value)
                done += 1
            }
            secrets = (try? await service.listSecrets(accountId: accountId, scriptName: scriptName)) ?? secrets
            return true
        } catch {
            self.error = AppLocalization.string(localized: "已导入 \(done)/\(pairs.count) 项后失败：\(error.localizedDescription)")
            secrets = (try? await service.listSecrets(accountId: accountId, scriptName: scriptName)) ?? secrets
            return false
        }
    }
}
