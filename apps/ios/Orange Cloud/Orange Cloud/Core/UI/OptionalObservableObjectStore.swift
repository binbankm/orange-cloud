//
//  OptionalObservableObjectStore.swift
//  Orange Cloud
//
//  Bridges lazily created ObservableObject instances into SwiftUI on iOS 16.
//

import Combine
import SwiftUI

@MainActor
final class OptionalObservableObjectStore: ObservableObject {

    /// 用类型擦除保存值并手动发布变化：当前 Swift 6.3 优化器会在泛型可观察
    /// 存储的 synthesized deinit 上崩溃（Release 专属）。值变化和内层 ViewModel
    /// 变化均由下方手动发送 objectWillChange 驱动。
    private var storedValue: AnyObject?
    private var changeSubscription: AnyCancellable?

    func value<Object: ObservableObject>(as type: Object.Type) -> Object? {
        storedValue as? Object
    }

    func set<Object: ObservableObject>(_ newValue: Object) {
        changeSubscription?.cancel()
        changeSubscription = nil
        storedValue = newValue
        objectWillChange.send()
        changeSubscription = newValue.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
