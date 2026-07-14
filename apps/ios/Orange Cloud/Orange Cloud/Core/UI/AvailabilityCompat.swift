//
//  AvailabilityCompat.swift
//  Orange Cloud
//
//  集中存放跨 iOS 版本的 SwiftUI 兼容封装：基线 iOS 16，对 iOS 17+/18+ 专属 API
//  统一在此降级，避免在各视图里散落 #available 守卫。
//

import SwiftUI
import UIKit
// MARK: - 统一动效信号

private struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// App 设置里「减少动画」开关的值（独立于系统辅助功能「减弱动态效果」）。在根视图注入，
    /// 让系统级转场（Zoom 导航转场）与自定义动画（玻璃岛浮现 / 骨架闪烁）都能跟着这个开关走——
    /// 否则开关只接了全局 .transaction，盖不住导航转场与只读系统设置的浮现动画，用户感觉「开了没用」。
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// 详情页：iOS 18+ 应用 Zoom 导航转场；iOS 16/17 或开启「减少动画」时原样返回（标准 push）。
    func zoomNavigationTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZoomNavigationTransition(sourceID: sourceID, namespace: namespace))
    }

    /// 源视图（列表行）：iOS 18+ 标记 Zoom 转场源；iOS 16/17 无操作。
    @ViewBuilder
    func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// 刷新中持续动画：iOS 18+ 用 .rotate 旋转；iOS 17 回退 .pulse
    /// （.rotate 的“持续效果”conformance 自 iOS 18 起才有）。
    @ViewBuilder
    func loadingSpinSymbolEffect(isActive: Bool) -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.rotate, isActive: isActive)
        } else if #available(iOS 17.0, *) {
            symbolEffect(.pulse, isActive: isActive)
        } else {
            self
        }
    }

    /// 出现时弹一下（一次性 bounce）：iOS 18+ 用 .nonRepeating 持续效果；
    /// iOS 16/17 静态显示（.bounce 的“持续效果”conformance 自 iOS 18 起才有）。
    @ViewBuilder
    func oneShotBounceSymbolEffect() -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.bounce, options: .nonRepeating)
        } else {
            self
        }
    }

    /// iOS 16 的触感反馈替代 `sensoryFeedback`（后者从 iOS 17 起提供）。
    func ocSensoryFeedback<T: Equatable>(_ feedback: OCSensoryFeedback, trigger: T) -> some View {
        modifier(OCSensoryFeedbackModifier(feedback: feedback, trigger: trigger))
    }
}

// MARK: - 动画兼容

extension Animation {
    /// iOS 17 的 `.smooth` 在 iOS 16 上以同等节奏的 ease-in-out 降级。
    static var ocSmooth: Animation {
        if #available(iOS 17.0, *) {
            return .smooth
        }
        return .easeInOut(duration: 0.35)
    }

    /// 带时长的 `.smooth` 兼容版本。
    static func ocSmooth(duration: TimeInterval) -> Animation {
        if #available(iOS 17.0, *) {
            return .smooth(duration: duration)
        }
        return .easeInOut(duration: duration)
    }

    /// iOS 17 的 `.snappy` 在 iOS 16 使用接近的弹簧参数。
    static var ocSnappy: Animation {
        if #available(iOS 17.0, *) {
            return .snappy
        }
        return .spring(response: 0.35, dampingFraction: 0.82)
    }
}

enum OCSensoryFeedback {
    case success
    case impact(weight: UIImpactFeedbackGenerator.FeedbackStyle)
}

private struct OCSensoryFeedbackModifier<T: Equatable>: ViewModifier {
    let feedback: OCSensoryFeedback
    let trigger: T

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { _ in
            switch feedback {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .impact(let weight):
                UIImpactFeedbackGenerator(style: weight).impactOccurred()
            }
        }
    }
}

/// Zoom 导航转场（iOS 18+），开启「减少动画」时降级为标准 push。
/// 读环境注入的 appReduceMotion——系统「减弱动态效果」由系统自动让 .zoom 回退，这里只额外接 App 开关。
private struct ZoomNavigationTransition<ID: Hashable>: ViewModifier {
    @Environment(\.appReduceMotion) private var appReduceMotion
    let sourceID: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !appReduceMotion {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

extension Color {
    /// Color.mix(with:by:) 的兼容封装：iOS 18+ 用系统实现；iOS 16/17 回退 UIColor 的 RGB 线性插值。
    nonisolated func mixed(with other: Color, by amount: Double) -> Color {
        if #available(iOS 18.0, *) {
            return mix(with: other, by: amount)
        }
        let t = max(0, min(1, amount))
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        UIColor(self).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        UIColor(other).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            .sRGB,
            red:   Double(ar + (br - ar) * t),
            green: Double(ag + (bg - ag) * t),
            blue:  Double(ab + (bb - ab) * t),
            opacity: Double(aa + (ba - aa) * t)
        )
    }
}
