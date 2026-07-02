import Foundation

// MARK: - Seedable Random Generator

/// 对标 Tokio `util/rand.rs` 的可种子伪随机数生成器
///
/// 用于需要确定性行为的场景（如 SubAgent 任务分配、测试重复）。
/// 基于 xoshiro256** 算法，周期 2^256 - 1。
///
/// ## 使用场景
///
/// ```swift
/// var rng = RandGenerator(seed: 42)
/// let choice = rng.next(in: 0..<10)  // 确定性输出
/// ```
public struct RandGenerator: Sendable {
    private struct State {
        var state0: UInt64
        var state1: UInt64
        var state2: UInt64
        var state3: UInt64
    }
    private var state: State

    /// 使用指定种子初始化（不允许 0）
    public init(seed: UInt64) {
        precondition(seed != 0, "Seed must not be 0")
        // SplitMix64 初始化
        var seedValue: UInt64 = seed
        func next() -> UInt64 {
            seedValue &+= 0x9E37_79B9_7F4A_7C15
            var mix: UInt64 = seedValue
            mix = (mix ^ (mix >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mix = (mix ^ (mix >> 27)) &* 0x94D0_49BB_1331_11EB
            return mix ^ (mix >> 31)
        }
        state = State(state0: next(), state1: next(), state2: next(), state3: next())
    }

    // MARK: - xoshiro256**

    /// 生成下一个 UInt64
    public mutating func next() -> UInt64 {
        let result: UInt64 = rotl(state.state1 &* 5, 7) &* 9
        let shifted: UInt64 = state.state1 << 17

        state.state2 ^= state.state0
        state.state3 ^= state.state1
        state.state1 ^= state.state2
        state.state0 ^= state.state3

        state.state2 ^= shifted
        state.state3 = rotl(state.state3, 45)

        return result
    }

    /// 生成 [0..<upperBound) 范围的随机整数
    public mutating func next(in range: Range<Int>) -> Int {
        Int(next() % UInt64(range.upperBound - range.lowerBound)) + range.lowerBound
    }

    /// 生成 [0..<upperBound) 范围的 UInt64
    @inlinable
    public mutating func next(upperBound: UInt64) -> UInt64 {
        next() % upperBound
    }

    /// 生成 [0, 1) 范围的 Double
    public mutating func nextDouble() -> Double {
        let val = next()
        // 取高 53 位
        return Double(val >> 11) * 1.1102230246251565e-16  // 1.0 / 2^53
    }

    /// 生成随机 Bool
    public mutating func nextBool() -> Bool {
        next() & 1 == 1
    }
}

// MARK: - Internal Helpers

@inlinable
internal func rotl(_ value: UInt64, _ shift: Int) -> UInt64 {
    (value << shift) | (value >> (64 - shift))
}

// MARK: - Global Seed Generator

/// 对标 Tokio `util/rand/rt.rs` 的运行时种子生成器
public enum SeedGenerator {
    /// 基于系统熵源生成随机种子
    public static func systemSeed() -> UInt64 {
        var seed: UInt64 = 0
        withUnsafeMutableBytes(of: &seed) { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, ptr.count, baseAddress)
        }
        // 确保非零
        return seed == 0 ? 1 : seed
    }
}
