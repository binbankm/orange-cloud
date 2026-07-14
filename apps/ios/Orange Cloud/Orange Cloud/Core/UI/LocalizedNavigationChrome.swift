//
//  LocalizedNavigationChrome.swift
//  Orange Cloud
//
//  UIKit 的返回按钮文案不会响应 SwiftUI 的 `Locale` 环境变化。此桥接器在语言改变时
//  更新所有活跃 NavigationStack 的上一页标题，确保不需要退出应用即可显示正确语言。
//

import SwiftUI
import UIKit

struct LocalizedNavigationChrome: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> LocalizedNavigationChromeController {
        LocalizedNavigationChromeController()
    }

    func updateUIViewController(_ controller: LocalizedNavigationChromeController, context: Context) {
        controller.applyCurrentLanguage()
    }
}

final class LocalizedNavigationChromeController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyCurrentLanguage()
    }

    func applyCurrentLanguage() {
        DispatchQueue.main.async { [weak self] in
            guard let root = self?.view.window?.rootViewController else { return }
            Self.configureNavigationItems(in: root, backTitle: AppLocalization.navigationBackTitle)
        }
    }

    private static func configureNavigationItems(in controller: UIViewController, backTitle: String) {
        if let navigationController = controller as? UINavigationController {
            navigationController.viewControllers.forEach { viewController in
                viewController.navigationItem.backButtonTitle = backTitle
            }
        }
        controller.children.forEach { configureNavigationItems(in: $0, backTitle: backTitle) }
        controller.presentedViewController.map { configureNavigationItems(in: $0, backTitle: backTitle) }
    }
}
