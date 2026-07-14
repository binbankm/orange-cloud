//
//  EmailRoutingModels.swift
//  Orange Cloud
//
//  Email Routing：域名级路由规则 + 账号级目的地址。
//  规则 GET/POST/PUT/DELETE /zones/{id}/email/routing/rules（scope email-routing-rule.*）
//  设置 GET /zones/{id}/email/routing + POST .../enable|.../disable
//  地址 GET/POST/DELETE /accounts/{id}/email/routing/addresses（scope email-routing-address.*）
//

import Foundation

/// GET /zones/{id}/email/routing —— 域名的 Email Routing 总开关与状态
nonisolated struct EmailRoutingSettings: Codable, Sendable {
    let id:      String?
    let tag:     String?
    let name:    String?
    let enabled: Bool?
    let status:  String?    // ready / unconfigured / misconfigured ...

    var isEnabled: Bool { enabled ?? false }
}

/// 规则匹配条件：type=literal 时 field/value 有值（如 field=to, value=me@x.com）；type=all 为catch-all
nonisolated struct EmailRoutingMatcher: Codable, Sendable {
    let type:  String
    let field: String?
    let value: String?
}

/// 规则动作：forward → value 为目的邮箱数组；worker → value 为 worker 名；drop → 无 value
nonisolated struct EmailRoutingAction: Codable, Sendable {
    let type:  String
    let value: [String]?
}

/// GET /zones/{id}/email/routing/rules 的单条规则
nonisolated struct EmailRoutingRule: Codable, Sendable, Identifiable {
    let id:       String
    let tag:      String?
    let name:     String?
    let enabled:  Bool?
    let priority: Int?
    let matchers: [EmailRoutingMatcher]
    let actions:  [EmailRoutingAction]

    var isEnabled: Bool { enabled ?? false }

    /// 第一个 literal 匹配的收件地址（catch-all 规则返回 nil）
    var matchAddress: String? {
        matchers.first(where: { $0.type == "literal" })?.value
    }

    /// 第一个动作的可读摘要
    var actionSummary: String {
        guard let action = actions.first else { return AppLocalization.string(localized: "无动作") }
        switch action.type {
        case "forward": return action.value?.joined(separator: ", ") ?? AppLocalization.string(localized: "转发")
        case "worker":  return action.value?.first.map { "Worker · \($0)" } ?? "Worker"
        case "drop":    return AppLocalization.string(localized: "丢弃")
        default:        return action.type
        }
    }

    var isCatchAll: Bool { matchers.contains { $0.type == "all" } }
}

/// 创建/更新规则的请求体
nonisolated struct EmailRoutingRuleInput: Codable, Sendable {
    let name:     String?
    let enabled:  Bool
    let matchers: [EmailRoutingMatcher]
    let actions:  [EmailRoutingAction]

    /// 转发规则便捷构造：把 to 地址转发到一个已验证的目的地址
    static func forward(name: String?, to matchAddress: String, destination: String, enabled: Bool) -> EmailRoutingRuleInput {
        .init(
            name: name,
            enabled: enabled,
            matchers: [.init(type: "literal", field: "to", value: matchAddress)],
            actions: [.init(type: "forward", value: [destination])]
        )
    }
}

/// GET /accounts/{id}/email/routing/addresses 的目的地址（账号级共享）
nonisolated struct EmailDestinationAddress: Codable, Sendable, Identifiable {
    let id:       String
    let tag:      String?
    let email:    String
    let verified: String?    // 验证通过的时间戳；未验证为 nil
    let created:  String?

    var isVerified: Bool { verified != nil }
}

/// 新增目的地址请求体（提交后 Cloudflare 给该邮箱发验证信）
nonisolated struct EmailDestinationCreate: Codable, Sendable {
    let email: String
}
