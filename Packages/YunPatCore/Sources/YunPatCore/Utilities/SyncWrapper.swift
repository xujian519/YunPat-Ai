import Foundation

// MARK: - Sync Wrapper

/// 对标 Tokio `util/sync_wrapper.rs`：将 `Send + !Sync` 类型转换为 `Sync`
/// 通过禁止所有不可变访问来安全跨线程共享。
///
/// ## 原理
///
/// 一个类型如果是 `Send`，意味着可以在线程间转移所有权。
/// 但如果它也是 `!Sync`，意味着不能通过共享引用访问。
/// `SyncWrapper<T>` 通过只暴露可变访问（`withLock` / `consume`）
/// 来解决这个矛盾——既然是可变访问，同一时刻只有一个线程访问，
/// 因此是安全的。
///
/// ## 使用场景
///
/// ```swift
/// // 某些 Send 但 !Sync 的内部类型需要跨 actor 传递
/// let wrapper = SyncWrapper(MySendOnlyType())
/// Task.detached {
///     // 安全：只能通过 consume 获取所有权
///     let value = wrapper.consume()
/// }
/// ```
public struct SyncWrapper<T: Sendable>: @unchecked Sendable {
    private var value: T

    /// 从 Sendable 值创建 SyncWrapper
    public init(_ value: T) {
        self.value = value
    }

    /// 消费包装器，取回内部值（转移所有权）
    public consuming func consume() -> T {
        value
    }

    /// 获取不可变引用（仅限调用者确保线程安全）
    ///
    /// - Warning: 此方法不安全，调用者必须保证同一时刻只有一个线程访问
    ///   对标 Tokio `SyncWrapper::get` —— 仅限内部使用。
    fileprivate func unsafeRef() -> T {
        value
    }
}

// MARK: - SendableBox

/// 将非 Sendable 类型包装为 Sendable 的 unsafe 桥接
///
/// 对标 Tokio `util/sync_wrapper.rs` 的扩展用途：
/// 在某些必须跨越 Sendable 边界的场景下使用。
///
/// - Warning: 调用者必须保证线程安全
public struct SendableBox<T>: @unchecked Sendable {
    private var value: T

    public init(_ value: T) {
        self.value = value
    }

    /// 消费并取回所有权
    public consuming func consume() -> T {
        value
    }
}
