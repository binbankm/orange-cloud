//
//  WorkerTailViewModel.swift
//  Orange Cloud
//
//  Workers 实时日志编排：创建 tail session → 连接 WebSocket → 消费事件流。
//  断线/过期自动重建一次，再失败交给用户手动重连；退出时销毁 tail。
//

import Foundation
import Combine
import ActivityKit

@MainActor
final class WorkerTailViewModel: ObservableObject {

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(reason: String?)
    }

    nonisolated struct LogLine: Identifiable, Sendable {
        let id: UUID
        let timestamp: Date
        let level: String      // "event" | "log" | "info" | "warn" | "error" | "exception"
        let text: String
    }

    @Published private(set) var lines: [LogLine] = []
    @Published private(set) var state: ConnectionState = .idle
    @Published var isPaused = false

    private let service: WorkerTailService
    private let accountId: String
    private let scriptName: String

    private var socket: TailSocket?
    private var streamTask: Task<Void, Never>?
    private var tailId: String?
    private var didAutoReconnect = false
    private var userStopped = false

    // Live Activity（Dynamic Island + 锁屏）
    // Live Activity 自 iOS 16.1 提供；用类型擦除让 iOS 16.0 仍可加载实时日志。
    private var activity: Any?
    private var eventCount = 0
    private var lastActivityUpdate = Date.distantPast
    private var heartbeatTask: Task<Void, Never>?
    private var isBackground = false

    private static let maxLines = 1000
    // Live Activity 多久没刷新就被系统判定为「停滞」并置灰；前台靠心跳持续续期
    private static let staleWindow: TimeInterval = 30

    init(service: WorkerTailService, accountId: String, scriptName: String) {
        self.service = service
        self.accountId = accountId
        self.scriptName = scriptName
    }

    // MARK: - 生命周期

    func start() async {
        await teardown()
        userStopped = false
        didAutoReconnect = false
        await connect()
    }

    func stop() async {
        userStopped = true
        await teardown()
        endActivity()
        state = .idle
    }

    func clear() {
        lines.removeAll()
    }

    private func connect() async {
        state = .connecting
        do {
            let session = try await service.createTail(accountId: accountId, scriptName: scriptName)
            tailId = session.id
            let socket = try service.makeSocket(for: session)
            self.socket = socket
            state = .connected
            startActivityIfNeeded()

            streamTask = Task {
                do {
                    for try await item in await socket.events() {
                        handle(item)
                    }
                    streamEnded(error: nil)
                } catch {
                    streamEnded(error: error)
                }
            }
        } catch {
            state = .disconnected(reason: error.localizedDescription)
        }
    }

    private func teardown() async {
        streamTask?.cancel()
        streamTask = nil
        if let socket {
            await socket.close()
        }
        socket = nil
        if let tailId {
            let id = tailId
            self.tailId = nil
            // 尽力销毁，失败不阻塞
            try? await service.deleteTail(accountId: accountId, scriptName: scriptName, tailId: id)
        }
    }

    /// 流结束：用户主动停止 / 已进后台则忽略；否则自动重建一次，再失败转为断开态
    private func streamEnded(error: Error?) {
        guard !userStopped, !isBackground else { return }
        if !didAutoReconnect {
            didAutoReconnect = true
            Task {
                await teardown()
                await connect()
            }
        } else {
            state = .disconnected(reason: error?.localizedDescription ?? AppLocalization.string(localized: "连接已断开"))
            updateActivity(force: true)
        }
    }

    // MARK: - 前后台

    /// 进入后台：tail 的 WebSocket 会被系统挂起、无法再收事件（前台 URLSession 在挂起后不工作，
    /// 后台 URLSession 又不支持 WebSocket）。立刻把 Live Activity 置为「已暂停」并停掉心跳——
    /// 卡片诚实置灰而非冻结成「看着像在跑」。连接本身不动，交给系统挂起。
    func enterBackground() {
        guard !userStopped, !isBackground else { return }
        isBackground = true
        stopHeartbeat()
        markActivityStale()
    }

    /// 回到前台：挂起期间连接基本已断（心跳停发 → tail session 多半已过期），
    /// 主动重连一次并把卡片刷回活跃；事件计数沿用，用户看到的是无缝续上。
    func enterForeground() {
        guard isBackground else { return }
        isBackground = false
        guard !userStopped else { return }
        Task { await start() }
    }

    // MARK: - 事件 → 日志行

    private func handle(_ item: TailTraceItem) {
        guard !isPaused else { return }

        var newLines: [LogLine] = []
        let eventDate = item.eventTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? Date()

        // 触发事件概要行
        if let request = item.event?.request {
            let method = request.method ?? "GET"
            let url = request.url ?? ""
            let outcome = item.outcome ?? "?"
            newLines.append(LogLine(id: UUID(), timestamp: eventDate, level: "event",
                                    text: "\(method) \(url) → \(outcome)"))
        } else if let cron = item.event?.cron {
            newLines.append(LogLine(id: UUID(), timestamp: eventDate, level: "event",
                                    text: "cron \(cron) → \(item.outcome ?? "?")"))
        }

        // console.* 输出
        for log in item.logs ?? [] {
            let date = log.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? eventDate
            let text = (log.message ?? []).map(\.displayText).joined(separator: " ")
            newLines.append(LogLine(id: UUID(), timestamp: date, level: log.level, text: text))
        }

        // 异常
        for exception in item.exceptions ?? [] {
            let date = exception.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? eventDate
            let text = [exception.name, exception.message].compactMap(\.self).joined(separator: ": ")
            newLines.append(LogLine(id: UUID(), timestamp: date, level: "exception", text: text))
        }

        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }

        eventCount += 1
        updateActivity()
    }

    // MARK: - Live Activity

    private func startActivityIfNeeded() {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity == nil {
            eventCount = 0
            activity = try? Activity.request(
                attributes: TailActivityAttributes(scriptName: scriptName),
                content: makeContent(connected: true)
            )
        } else {
            // 已有活动（多为后台→前台复活）：刷新回活跃态
            updateActivity(force: true)
        }
        startHeartbeat()
    }

    /// 节流更新：默认 1 秒一次，连接状态变化时强制。
    /// 每次把 staleDate 推后 staleWindow——前台持续刷新即永不停滞，一旦挂起停更便到点自动置灰。
    private func updateActivity(force: Bool = false) {
        guard #available(iOS 16.2, *), let activity = activity as? Activity<TailActivityAttributes> else { return }
        guard force || Date().timeIntervalSince(lastActivityUpdate) > 1 else { return }
        lastActivityUpdate = Date()
        let content = makeContent(connected: state == .connected)
        Task { await activity.update(content) }
    }

    /// 进后台时调用：staleDate=now 让系统立刻把卡片置灰，呈「已暂停」。
    private func markActivityStale() {
        guard #available(iOS 16.2, *), let activity = activity as? Activity<TailActivityAttributes> else { return }
        lastActivityUpdate = Date()
        let content = ActivityContent(
            state: TailActivityAttributes.ContentState(
                eventCount: eventCount,
                lastLine: lines.last?.text ?? "",
                isConnected: false
            ),
            staleDate: Date()
        )
        Task { await activity.update(content) }
    }

    @available(iOS 16.2, *)
    private func makeContent(connected: Bool) -> ActivityContent<TailActivityAttributes.ContentState> {
        ActivityContent(
            state: TailActivityAttributes.ContentState(
                eventCount: eventCount,
                lastLine: lines.last?.text ?? "",
                isConnected: connected
            ),
            staleDate: Date().addingTimeInterval(Self.staleWindow)
        )
    }

    /// 心跳：前台连接期间即使没有新事件，也每 20s 续一次 staleDate，
    /// 避免静默 worker（迟迟无请求）被误判停滞置灰。后台时随进程挂起自然冻结。
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, !Task.isCancelled else { break }
                if !self.isBackground, self.state == .connected {
                    self.updateActivity(force: true)
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func endActivity() {
        stopHeartbeat()
        guard #available(iOS 16.2, *), let activity = activity as? Activity<TailActivityAttributes> else {
            self.activity = nil
            return
        }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
