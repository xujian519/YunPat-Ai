import Foundation

// MARK: - Bit Operations

/// 对标 Tokio `util/bit.rs` 的位操作工具集
///
/// 提供无锁并发编程常用的位打包、位标志操作、定位操作。
/// 用于状态机、原子计数、高效标记等场景。
public enum Bits {

    // MARK: - Pack / Unpack

    /// 打包两个 `UInt32` 到一个 `UInt64`
    ///
    /// 对标 Tokio `bit::pack`，用于 token 计数、指标累加等需要
    /// 两个计数器共用一个 `AtomicUInt64` 的场景。
    @inlinable
    public static func pack(_ high: UInt32, _ low: UInt32) -> UInt64 {
        (UInt64(high) << 32) | UInt64(low)
    }

    /// 从打包的 `UInt64` 解包出两个 `UInt32`
    @inlinable
    public static func unpack(_ value: UInt64) -> (high: UInt32, low: UInt32) {
        (UInt32(value >> 32), UInt32(value & 0xFFFF_FFFF))
    }

    // MARK: - Bit flags

    /// 测试第 `pos` 位是否为 1（pos: 0-indexed）
    @inlinable
    public static func isSet(_ value: Int, pos: Int) -> Bool {
        (value & (1 << pos)) != 0
    }

    /// 设置第 `pos` 位为 1
    @inlinable
    public static func set(_ value: inout Int, pos: Int) {
        value |= (1 << pos)
    }

    /// 清除第 `pos` 位
    @inlinable
    public static func clear(_ value: inout Int, pos: Int) {
        value &= ~(1 << pos)
    }

    // MARK: - Alignment

    /// 向上对齐到 `alignment` 的倍数
    ///
    /// 对标 Tokio `util/bit.rs:align`，用于内存对齐计算。
    @inlinable
    public static func alignUp(_ number: Int, to alignment: Int) -> Int {
        ((number + alignment - 1) / alignment) * alignment
    }

    // MARK: - Bit counting

    /// 置位 bit 数（popcount）
    @inlinable
    public static func popCount(_ value: Int) -> Int {
        value.nonzeroBitCount
    }

    /// 首个置位 bit 的位置（trailing zeros）
    @inlinable
    public static func trailingZeroBit(_ value: Int) -> Int {
        value.trailingZeroBitCount
    }
}
