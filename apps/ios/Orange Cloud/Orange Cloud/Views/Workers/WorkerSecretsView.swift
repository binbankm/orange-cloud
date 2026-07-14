//
//  WorkerSecretsView.swift
//  Orange Cloud
//
//  Worker 密钥（secret_text）+ 环境变量（plain_text）管理 + 只读绑定清单。
//  写操作按 workers-scripts.write 门控；改任一变量都整组回写（其余 inherit），不丢既有绑定。
//

import SwiftUI

struct WorkerSecretsView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @EnvironmentObject private var auth: AuthManager
    @StateObject private var viewModel: WorkerBindingsViewModel
    @State private var sheet: EditorSheet?
    @State private var secretToDelete: WorkerSecret?
    @State private var variableToDelete: WorkerBinding?

    init(accountId: String, scriptName: String, session: SessionStore) {
        _viewModel = StateObject(wrappedValue: WorkerBindingsViewModel(
            service: session.workerService, accountId: accountId, scriptName: scriptName
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-scripts.write") }

    var body: some View {

        let _ = preferences.languageRaw
        Group {
            if !viewModel.loaded && viewModel.isLoading {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else {
                List {
                    secretsSection
                    variablesSection
                    if !viewModel.otherBindings.isEmpty {
                        otherSection
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .ocNavigationTitle("变量与密钥")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("批量导入 JSON", systemImage: "arrow.down.doc") {
                        sheet = .bulkImport
                    }
                }
            }
        }
        .confirmationDialog(
            secretToDelete.map { AppLocalization.string(localized: "删除密钥「\($0.name)」？") } ?? "",
            isPresented: Binding(get: { secretToDelete != nil }, set: { if !$0 { secretToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let s = secretToDelete { Task { await viewModel.deleteSecret(s) } }
            }
        } message: {
            Text("密钥值无法读回，删除后需重新设置，不可撤销。")
        }
        .confirmationDialog(
            variableToDelete.map { AppLocalization.string(localized: "删除变量「\($0.name)」？") } ?? "",
            isPresented: Binding(get: { variableToDelete != nil }, set: { if !$0 { variableToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let v = variableToDelete { Task { await viewModel.deleteVariable(v) } }
            }
        }
        .task { if !viewModel.loaded { await viewModel.load() } }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .bulkImport:
                WorkerBulkImportSheet(viewModel: viewModel)
            default:
                WorkerValueEditorSheet(kind: kind, viewModel: viewModel)
            }
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && sheet == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - 密钥

    private var secretsSection: some View {
        Section {
            if viewModel.secrets.isEmpty {
                Text("暂无密钥").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.secrets) { secret in
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "key.fill", color: .ocOrange)
                        Text(secret.name).font(.callout.weight(.medium))
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        if canWrite {
                            Button("删除", role: .destructive) {
                                secretToDelete = secret
                            }
                        }
                    }
                }
            }
            if canWrite {
                Button {
                    sheet = .secret
                } label: {
                    Label("添加密钥", systemImage: "plus")
                }
            }
        } header: {
            Text("密钥")
        } footer: {
            Text(canWrite
                 ? AppLocalization.string(localized: "密钥值出于安全无法读取，列表只显示名称。同名添加即覆盖。")
                 : AppLocalization.string(localized: "当前授权仅可查看（缺少 workers-scripts.write）。"))
        }
        .glassRow()
    }

    // MARK: - 环境变量

    private var variablesSection: some View {
        Section {
            if viewModel.variables.isEmpty {
                Text("暂无变量").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.variables) { binding in
                    Button {
                        if canWrite { sheet = .variable(binding) }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "textformat", color: .ocOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(binding.name).font(.callout.weight(.medium)).foregroundStyle(.primary)
                                Text(binding.text ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if canWrite {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(!canWrite)
                    .swipeActions(edge: .trailing) {
                        if canWrite {
                            Button("删除", role: .destructive) {
                                variableToDelete = binding
                            }
                        }
                    }
                }
            }
            if canWrite {
                Button {
                    sheet = .variable(nil)
                } label: {
                    Label("添加变量", systemImage: "plus")
                }
            }
        } header: {
            Text("环境变量")
        } footer: {
            Text("明文变量（plain_text），可读可改。改任一项不影响其它绑定。")
        }
        .glassRow()
    }

    // MARK: - 只读绑定

    private var otherSection: some View {
        Section {
            ForEach(viewModel.otherBindings) { binding in
                HStack(spacing: 12) {
                    TintIcon(systemImage: "cube", color: .gray)
                    Text(binding.name).font(.callout)
                    Spacer()
                    Text(binding.typeLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("其它绑定（只读）")
        } footer: {
            Text("KV / D1 / R2 等资源绑定在此查看，编辑请用 Wrangler 或 Dashboard。")
        }
        .glassRow()
    }
}

// MARK: - 添加/编辑弹窗

/// 弹窗类型：新增密钥 / 新增或编辑变量（编辑时锁定名称）/ 批量导入 JSON
private enum EditorSheet: Identifiable {
    case secret
    case variable(WorkerBinding?)
    case bulkImport

    var id: String {
        switch self {
        case .secret:            "secret"
        case .variable(let b):   "var-\(b?.name ?? "new")"
        case .bulkImport:        "bulk"
        }
    }
}

private struct WorkerValueEditorSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    let kind: EditorSheet
    @ObservedObject var viewModel: WorkerBindingsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""

    private var isSecret: Bool { if case .secret = kind { return true }; return false }

    /// 编辑既有变量时锁定名称
    private var lockedName: String? {
        if case .variable(let binding) = kind, let binding { return binding.name }
        return nil
    }

    private var nameValid: Bool {
        let target = lockedName ?? name
        return target.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    private var canSave: Bool {
        nameValid && !value.isEmpty && !viewModel.isSaving
    }

    private var title: String {
        if isSecret { return AppLocalization.string(localized: "添加密钥") }
        return lockedName == nil ? AppLocalization.string(localized: "添加变量") : AppLocalization.string(localized: "编辑变量")
    }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Form {
                Section {
                    if let lockedName {
                        Text(lockedName).font(.callout.monospaced()).foregroundStyle(.secondary)
                    } else {
                        TextField("NAME", text: $name)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("名称")
                } footer: {
                    if lockedName == nil {
                        Text("字母、数字、下划线，且不以数字开头。")
                    }
                }

                Section {
                    if isSecret {
                        SecureField("值", text: $value)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField("值", text: $value, axis: .vertical)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(1...6)
                    }
                } header: {
                    Text(isSecret ? AppLocalization.string(localized: "值（保存后不可读取）") : AppLocalization.string(localized: "值"))
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear {
                if case .variable(let binding) = kind, let binding {
                    value = binding.text ?? ""
                }
            }
        }
    }

    private func save() async {
        viewModel.error = nil
        let ok: Bool
        if isSecret {
            ok = await viewModel.addSecret(name: name, text: value)
        } else {
            ok = await viewModel.setVariable(name: lockedName ?? name, value: value)
        }
        if ok { dismiss() }
    }
}

// MARK: - 批量导入 JSON

/// 导入目标：粘贴的 JSON 键值对作为变量或密钥写入
private enum BulkImportTarget: String, CaseIterable, Identifiable {
    case variable, secret
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .variable ? "变量" : "密钥" }
}

/// 解析失败原因（携带可读信息，供 Result 使用）
private struct BulkParseError: Error {
    let message: String
}

private struct WorkerBulkImportSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @ObservedObject var viewModel: WorkerBindingsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var target: BulkImportTarget = .variable
    @State private var jsonText = ""

    /// 解析结果：成功给出 (name, value) 列表，失败给出可读错误
    private var parsed: Result<[(name: String, value: String)], BulkParseError> {
        Self.parse(jsonText)
    }

    private var pairs: [(name: String, value: String)] {
        if case .success(let p) = parsed { return p }
        return []
    }

    private var parseError: String? {
        if case .failure(let e) = parsed { return e.message }
        return nil
    }

    private var hasInput: Bool {
        !jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canImport: Bool { !pairs.isEmpty && !viewModel.isSaving }

    var body: some View {

        let _ = preferences.languageRaw
        NavigationStack {
            Form {
                Section {
                    Picker("导入为", selection: $target) {
                        ForEach(BulkImportTarget.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(target == .secret
                         ? AppLocalization.string(localized: "作为密钥写入，逐个保存；同名将被覆盖，保存后不可读取。")
                         : AppLocalization.string(localized: "作为明文变量一次性写入；同名将被覆盖，不影响其它绑定。"))
                }

                Section {
                    TextEditor(text: $jsonText)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 180)
                } header: {
                    Text("JSON")
                } footer: {
                    Text("粘贴一个 JSON 对象，键为名称、值为字符串或数字，例如：\n{\n  \"API_KEY\": \"abc123\",\n  \"MAX_RETRY\": 3\n}")
                }

                if hasInput, let parseError {
                    Section { Text(parseError).font(.footnote).foregroundStyle(.red) }
                } else if !pairs.isEmpty {
                    Section { Text("将导入 \(pairs.count) 项").font(.callout).foregroundStyle(.secondary) }
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .ocNavigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await performImport() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("导入").fontWeight(.semibold) }
                    }
                    .disabled(!canImport)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    private func performImport() async {
        viewModel.error = nil
        let ok: Bool
        switch target {
        case .variable: ok = await viewModel.bulkImportVariables(pairs)
        case .secret:   ok = await viewModel.bulkImportSecrets(pairs)
        }
        if ok { dismiss() }
    }

    /// 解析一个扁平 JSON 对象为 (name, value) 列表。
    /// 键须符合环境变量命名（字母/数字/下划线，不以数字开头）；值接受字符串、数字、布尔（转字符串）。
    private static func parse(_ text: String) -> Result<[(name: String, value: String)], BulkParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success([]) }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(BulkParseError(message: AppLocalization.string(localized: "不是有效的 JSON")))
        }
        guard let dict = object as? [String: Any] else {
            return .failure(BulkParseError(message: AppLocalization.string(localized: "需要一个 JSON 对象，形如 {\"KEY\": \"值\"}")))
        }
        let keyPattern = "^[A-Za-z_][A-Za-z0-9_]*$"
        var pairs: [(name: String, value: String)] = []
        var invalidKeys: [String] = []
        for (key, raw) in dict {
            guard key.range(of: keyPattern, options: .regularExpression) != nil else {
                invalidKeys.append(key)
                continue
            }
            let value: String
            if let s = raw as? String {
                value = s
            } else if let n = raw as? NSNumber {
                value = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
            } else {
                return .failure(BulkParseError(message: AppLocalization.string(localized: "键「\(key)」的值必须是字符串或数字")))
            }
            pairs.append((name: key, value: value))
        }
        if !invalidKeys.isEmpty {
            let list = invalidKeys.sorted().joined(separator: ", ")
            return .failure(BulkParseError(message: AppLocalization.string(localized: "以下名称非法（须字母 / 数字 / 下划线，且不以数字开头）：\(list)")))
        }
        return .success(pairs.sorted { $0.name < $1.name })
    }
}
