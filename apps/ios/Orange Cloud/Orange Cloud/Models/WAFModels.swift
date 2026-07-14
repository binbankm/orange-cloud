//
//  WAFModels.swift
//  Orange Cloud
//
//  WAF 自定义规则（Rulesets API，phase = http_request_firewall_custom）。
//  GET /zones/{id}/rulesets/phases/http_request_firewall_custom/entrypoint
//

import Foundation

nonisolated struct WAFRuleset: Codable, Sendable {
    let id:    String
    let name:  String?
    let phase: String?
    let rules: [WAFRule]?
}

nonisolated struct WAFRule: Codable, Identifiable, Hashable, Sendable {
    let id:          String
    let action:      String?         // "block" | "challenge" | "managed_challenge" | "js_challenge" | "log" | "skip"
    let expression:  String?
    let description: String?
    let enabled:     Bool?
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case id, action, expression, description, enabled
        case lastUpdated = "last_updated"
    }

    var actionText: String {
        switch action {
        case "block":             AppLocalization.string(localized: "拦截")
        case "challenge":         AppLocalization.string(localized: "质询")
        case "managed_challenge": AppLocalization.string(localized: "托管质询")
        case "js_challenge":      AppLocalization.string(localized: "JS 质询")
        case "log":               AppLocalization.string(localized: "记录")
        case "skip":              AppLocalization.string(localized: "跳过")
        case "allow":             AppLocalization.string(localized: "放行")
        default:                  action ?? "—"
        }
    }
}

/// PATCH 规则只更新 enabled
nonisolated struct WAFRuleToggle: Codable, Sendable {
    let enabled: Bool
}

/// 新建规则（POST rules / PUT entrypoint 共用）
nonisolated struct WAFRuleCreate: Codable, Sendable {
    let action:      String
    let expression:  String
    let description: String?
    let enabled:     Bool
}

/// PUT entrypoint 创建规则集（Zone 首条自定义规则时）
nonisolated struct WAFEntrypointUpdate: Codable, Sendable {
    let rules: [WAFRuleCreate]
}

// MARK: - 「书写规则」可视化构建器（生成 Cloudflare Rules 表达式）

/// 字段值类型，决定可用运算符与值的引号规则
nonisolated enum WAFValueType: Sendable {
    case string    // 加双引号
    case ip        // 不加引号（IP / CIDR）
    case number    // 不加引号
    case country   // 双引号的两位国家码
}

/// 可选字段（curated 常用集）
nonisolated struct WAFField: Identifiable, Sendable {
    let field: String      // 表达式字段名，如 http.host
    let label: String
    let type:  WAFValueType
    var id: String { field }
}

/// Cloudflare Rules 运算符
nonisolated enum WAFOperator: String, CaseIterable, Identifiable, Sendable {
    case eq, ne, contains, matches, isin, gt, ge, lt, le

    var id: String { rawValue }
    /// 表达式里的实际 token（in 是关键字）
    var token: String { self == .isin ? "in" : rawValue }

    var label: String {
        switch self {
        case .eq:       AppLocalization.string(localized: "等于")
        case .ne:       AppLocalization.string(localized: "不等于")
        case .contains: AppLocalization.string(localized: "包含")
        case .matches:  AppLocalization.string(localized: "匹配正则")
        case .isin:     AppLocalization.string(localized: "属于")
        case .gt:       AppLocalization.string(localized: "大于")
        case .ge:       AppLocalization.string(localized: "大于等于")
        case .lt:       AppLocalization.string(localized: "小于")
        case .le:       AppLocalization.string(localized: "小于等于")
        }
    }

    static func available(for type: WAFValueType) -> [WAFOperator] {
        switch type {
        case .string:  [.eq, .ne, .contains, .matches, .isin]
        case .ip:      [.eq, .ne, .isin]
        case .number:  [.eq, .ne, .gt, .ge, .lt, .le]
        case .country: [.eq, .ne, .isin]
        }
    }
}

nonisolated enum WAFConditionLogic: String, CaseIterable, Identifiable, Sendable {
    case and, or
    var id: String { rawValue }
    var token: String { rawValue }
    var label: String { self == .and ? AppLocalization.string(localized: "满足全部") : AppLocalization.string(localized: "满足任一") }
}

nonisolated enum WAFExpressionCatalog {
    static let fields: [WAFField] = [
        WAFField(field: "http.host",                label: AppLocalization.string(localized: "主机名"),      type: .string),
        WAFField(field: "http.request.uri.path",    label: AppLocalization.string(localized: "URI 路径"),    type: .string),
        WAFField(field: "http.request.uri.query",   label: AppLocalization.string(localized: "查询字符串"),  type: .string),
        WAFField(field: "http.request.full_uri",    label: AppLocalization.string(localized: "完整 URL"),    type: .string),
        WAFField(field: "http.request.method",      label: AppLocalization.string(localized: "请求方法"),    type: .string),
        WAFField(field: "http.user_agent",          label: "User-Agent",                     type: .string),
        WAFField(field: "http.referer",             label: "Referer",                        type: .string),
        WAFField(field: "http.cookie",              label: "Cookie",                         type: .string),
        WAFField(field: "http.request.version",     label: AppLocalization.string(localized: "HTTP 版本"),   type: .string),
        WAFField(field: "ip.src",                   label: AppLocalization.string(localized: "来源 IP"),     type: .ip),
        WAFField(field: "ip.src.country",           label: AppLocalization.string(localized: "来源国家"),    type: .country),
        WAFField(field: "ip.src.asnum",             label: "ASN",                            type: .number),
        WAFField(field: "cf.threat_score",          label: AppLocalization.string(localized: "威胁分数"),    type: .number),
        WAFField(field: "cf.bot_management.score",  label: AppLocalization.string(localized: "Bot 分数"),    type: .number),
    ]

    static func field(for key: String) -> WAFField? { fields.first { $0.field == key } }

    static func placeholder(for type: WAFValueType) -> String {
        switch type {
        case .string:  "example.com"
        case .ip:      "203.0.113.4"
        case .country: "US"
        case .number:  "10"
        }
    }
}

/// 由条件行生成 Cloudflare Rules 表达式（纯函数，便于复用 / 测试）
nonisolated enum WAFExpressionBuilder {

    /// 单个条件 → 表达式片段；值为空返回 nil（忽略未填完的行）
    static func condition(field: WAFField, op: WAFOperator, rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if op == .isin {
            let items = trimmed
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return nil }
            let set = items.map { quote($0, type: field.type) }.joined(separator: " ")
            return "\(field.field) in {\(set)}"
        }
        return "\(field.field) \(op.token) \(quote(trimmed, type: field.type))"
    }

    /// 多条件按逻辑连接；并列两个以上时每个条件加括号，避免 and/or 优先级歧义
    static func expression(logic: WAFConditionLogic, conditions: [String]) -> String {
        let parts = conditions.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        if parts.count == 1 { return parts[0] }
        return parts.map { "(\($0))" }.joined(separator: " \(logic.token) ")
    }

    private static func quote(_ value: String, type: WAFValueType) -> String {
        switch type {
        case .ip, .number:
            return value
        case .string, .country:
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
    }
}

/// 自定义规则可用的动作（skip 需要额外参数，暂不提供）
nonisolated enum WAFRuleAction: String, CaseIterable, Identifiable, Sendable {
    case block
    case managedChallenge = "managed_challenge"
    case jsChallenge      = "js_challenge"
    case challenge
    case log

    var id: String { rawValue }

    var label: String {
        switch self {
        case .block:            AppLocalization.string(localized: "拦截")
        case .managedChallenge: AppLocalization.string(localized: "托管质询")
        case .jsChallenge:      AppLocalization.string(localized: "JS 质询")
        case .challenge:        AppLocalization.string(localized: "质询")
        case .log:              AppLocalization.string(localized: "仅记录")
        }
    }
}
