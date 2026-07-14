//
//  StatusPageModels.swift
//  Orange Cloud
//
//  Cloudflare 官方状态页（cloudflarestatus.com，Statuspage v2 API）。
//  公开接口无 CF 信封（没有 result/success 包装），日期为 ISO8601 字符串。
//

import Foundation

/// GET /api/v2/summary.json
nonisolated struct StatusPageSummary: Codable, Sendable {
    let status:                StatusPageOverall
    let components:            [StatusPageComponent]
    let incidents:             [StatusPageIncident]
    let scheduledMaintenances: [StatusPageIncident]

    enum CodingKeys: String, CodingKey {
        case status, components, incidents
        case scheduledMaintenances = "scheduled_maintenances"
    }
}

/// GET /api/v2/incidents.json（含已解决的历史事件，最近 50 条）
nonisolated struct StatusPageIncidentList: Codable, Sendable {
    let incidents: [StatusPageIncident]
}

/// 总体状态
nonisolated struct StatusPageOverall: Codable, Sendable {
    let indicator:   String   // "none" | "minor" | "major" | "critical" | "maintenance"
    let description: String

    /// 总体状态的本地化描述（未知 indicator 时透出官方英文原文）
    var localizedText: String {
        switch indicator {
        case "none":        AppLocalization.string(localized: "所有系统正常运行")
        case "minor":       AppLocalization.string(localized: "部分服务轻微异常")
        case "major":       AppLocalization.string(localized: "部分服务严重异常")
        case "critical":    AppLocalization.string(localized: "重大服务中断")
        case "maintenance": AppLocalization.string(localized: "维护进行中")
        default:            description
        }
    }
}

nonisolated struct StatusPageComponent: Codable, Identifiable, Sendable {
    let id:      String
    let name:    String
    let status:  String   // "operational" | "degraded_performance" | "partial_outage" | "major_outage" | "under_maintenance"
    let group:   Bool?    // true = 分组容器（如各大洲 PoP 分组），本身不是服务
    let groupId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, group
        case groupId = "group_id"
    }

    var statusText: String {
        switch status {
        case "operational":          AppLocalization.string(localized: "正常")
        case "degraded_performance": AppLocalization.string(localized: "性能下降")
        case "partial_outage":       AppLocalization.string(localized: "部分中断")
        case "major_outage":         AppLocalization.string(localized: "大面积中断")
        case "under_maintenance":    AppLocalization.string(localized: "维护中")
        default:                     status
        }
    }
}

/// 边缘网络大区汇总（由 ViewModel 按分组聚合，非 API 原始结构）
nonisolated struct StatusPageRegion: Identifiable, Sendable {
    let id:       String
    let name:     String   // API 原文（英文）
    let total:    Int
    let impacted: Int      // 非 operational 的节点数

    var localizedName: String {
        switch name {
        case "Africa":                        AppLocalization.string(localized: "非洲")
        case "Asia":                          AppLocalization.string(localized: "亚洲")
        case "Europe":                        AppLocalization.string(localized: "欧洲")
        case "Latin America & the Caribbean": AppLocalization.string(localized: "拉丁美洲和加勒比")
        case "Middle East":                   AppLocalization.string(localized: "中东")
        case "North America":                 AppLocalization.string(localized: "北美")
        case "Oceania":                       AppLocalization.string(localized: "大洋洲")
        default:                              name
        }
    }
}

/// 事件与计划维护共用结构（维护多 scheduled_for 字段）
nonisolated struct StatusPageIncident: Codable, Identifiable, Sendable {
    let id:              String
    let name:            String
    let status:          String   // 事件 "investigating"… / 维护 "scheduled"…
    let impact:          String   // "none" | "minor" | "major" | "critical" | "maintenance"
    let createdAt:       String?
    let updatedAt:       String?
    let scheduledFor:    String?
    let shortlink:       String?
    let incidentUpdates: [StatusPageIncidentUpdate]?

    enum CodingKeys: String, CodingKey {
        case id, name, status, impact, shortlink
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case scheduledFor    = "scheduled_for"
        case incidentUpdates = "incident_updates"
    }

    static func statusText(_ status: String) -> String {
        switch status {
        case "investigating": AppLocalization.string(localized: "调查中")
        case "identified":    AppLocalization.string(localized: "已定位")
        case "monitoring":    AppLocalization.string(localized: "监控中")
        case "resolved":      AppLocalization.string(localized: "已解决")
        case "postmortem":    AppLocalization.string(localized: "事后分析")
        case "scheduled":     AppLocalization.string(localized: "已排期")
        case "in_progress":   AppLocalization.string(localized: "进行中")
        case "verifying":     AppLocalization.string(localized: "验证中")
        case "completed":     AppLocalization.string(localized: "已完成")
        default:              status
        }
    }

    var statusText: String { Self.statusText(status) }

    var impactText: String {
        switch impact {
        case "critical":    AppLocalization.string(localized: "重大")
        case "major":       AppLocalization.string(localized: "严重")
        case "minor":       AppLocalization.string(localized: "轻微")
        case "maintenance": AppLocalization.string(localized: "维护")
        case "none":        AppLocalization.string(localized: "无影响")
        default:            impact
        }
    }
}

nonisolated struct StatusPageIncidentUpdate: Codable, Identifiable, Sendable {
    let id:        String
    let status:    String
    let body:      String
    let displayAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, body
        case displayAt = "display_at"
    }

    var statusText: String { StatusPageIncident.statusText(status) }
}
