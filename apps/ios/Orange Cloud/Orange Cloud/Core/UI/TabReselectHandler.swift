//
//  TabReselectHandler.swift
//  Orange Cloud
//
//  SwiftUI 的 TabView 没有公开「再次点选当前 Tab」回调。此桥接只使用
//  UITabBarControllerDelegate 的公开 API，在重复选择时回到该 Tab 的根页面。
//

import SwiftUI
import UIKit

struct TabReselectHandler: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> ObserverViewController {
        ObserverViewController()
    }

    func updateUIViewController(_ controller: ObserverViewController, context: Context) {
        controller.installIfNeeded()
    }

    final class ObserverViewController: UIViewController, UITabBarControllerDelegate {
        private weak var observedTabBarController: UITabBarController?
        /// SwiftUI 或宿主已有 delegate 时保留其行为，避免劫持系统的 tab 切换逻辑。
        private weak var downstreamDelegate: UITabBarControllerDelegate?
        private weak var lastSelectedController: UIViewController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // SwiftUI 在首次布局后才可能挂载 UIKit Tab 容器，下一轮 run loop 再找一次。
            DispatchQueue.main.async { [weak self] in
                self?.installIfNeeded()
            }
        }

        func installIfNeeded() {
            guard let tabBarController = nearestTabBarController() ?? tabBarControllerInWindow() else { return }

            if observedTabBarController !== tabBarController {
                restorePreviousDelegateIfNeeded()
                observedTabBarController = tabBarController
                lastSelectedController = tabBarController.selectedViewController
            }

            guard tabBarController.delegate !== self else { return }
            downstreamDelegate = tabBarController.delegate
            tabBarController.delegate = self
        }

        deinit {
            restorePreviousDelegateIfNeeded()
        }

        // MARK: UITabBarControllerDelegate

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            downstreamDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let isReselect = lastSelectedController === viewController
            lastSelectedController = viewController
            downstreamDelegate?.tabBarController?(tabBarController, didSelect: viewController)

            guard isReselect else { return }
            // 等系统完成本次 tab 选择后再回根页，避免同一事件内与 SwiftUI 的状态同步竞争。
            DispatchQueue.main.async { [weak self] in
                self?.popToRoot(in: viewController)
            }
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || downstreamDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if downstreamDelegate?.responds(to: aSelector) == true {
                return downstreamDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }

        // MARK: - 容器发现与导航回退

        private func restorePreviousDelegateIfNeeded() {
            guard let observedTabBarController, observedTabBarController.delegate === self else { return }
            observedTabBarController.delegate = downstreamDelegate
        }

        private func nearestTabBarController() -> UITabBarController? {
            var controller = parent
            while let current = controller {
                if let tabBarController = current as? UITabBarController { return tabBarController }
                controller = current.parent
            }
            return nil
        }

        private func tabBarControllerInWindow() -> UITabBarController? {
            guard let root = view.window?.rootViewController else { return nil }
            return findTabBarController(in: root)
        }

        private func findTabBarController(in controller: UIViewController) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController { return tabBarController }
            for child in controller.children {
                if let tabBarController = findTabBarController(in: child) { return tabBarController }
            }
            if let presented = controller.presentedViewController {
                return findTabBarController(in: presented)
            }
            return nil
        }

        private func popToRoot(in controller: UIViewController) {
            if let navigationController = controller as? UINavigationController {
                guard navigationController.viewControllers.count > 1 else { return }
                navigationController.popToRootViewController(animated: true)
                return
            }
            for child in controller.children {
                popToRoot(in: child)
            }
        }
    }
}
