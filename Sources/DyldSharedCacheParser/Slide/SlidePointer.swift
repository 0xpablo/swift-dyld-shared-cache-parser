import Foundation

/// Slide pointer for version 3 slide info (arm64e).
///
/// These pointers can be either plain or authenticated (PAC-signed).
public enum SlidePointer3: Sendable, Hashable {
    /// A plain (non-authenticated) pointer.
    case plain(pointerValue: UInt64, offsetToNext: UInt16)

    /// An authenticated (PAC-signed) pointer.
    case authenticated(
        offsetFromBase: UInt32,
        diversityData: UInt16,
        hasAddressDiversity: Bool,
        key: UInt8,
        offsetToNext: UInt16
    )

    /// Initialize from raw 64-bit value.
    public init(raw: UInt64) {
        let isAuthenticated = (raw >> 63) != 0

        if isAuthenticated {
            let offsetFromBase = UInt32(raw & 0xFFFFFFFF)
            let diversityData = UInt16((raw >> 32) & 0xFFFF)
            let hasAddressDiversity = ((raw >> 48) & 1) != 0
            let key = UInt8((raw >> 49) & 0x3)
            let offsetToNext = UInt16((raw >> 51) & 0x7FF)

            self = .authenticated(
                offsetFromBase: offsetFromBase,
                diversityData: diversityData,
                hasAddressDiversity: hasAddressDiversity,
                key: key,
                offsetToNext: offsetToNext
            )
        } else {
            // Plain pointer: 51 bits for value, 11 bits for delta
            let pointerValue = raw & 0x0007FFFFFFFFFFFF // 51 bits
            let offsetToNext = UInt16((raw >> 51) & 0x7FF) // 11 bits

            self = .plain(pointerValue: pointerValue, offsetToNext: offsetToNext)
        }
    }

    /// Whether this pointer is authenticated.
    public var isAuthenticated: Bool {
        switch self {
        case .plain: return false
        case .authenticated: return true
        }
    }

    /// The offset to the next pointer in the chain.
    public var offsetToNextPointer: UInt16 {
        switch self {
        case .plain(_, let offset): return offset
        case .authenticated(_, _, _, _, let offset): return offset
        }
    }

    /// Calculate the rebased value for a plain pointer.
    public func rebasedValue(slide: Int64) -> UInt64? {
        switch self {
        case .plain(let pointerValue, _):
            // Reconstruct the 64-bit pointer from the 51-bit encoded value
            let top8Bits = pointerValue & 0x0007F80000000000
            let bottom43Bits = pointerValue & 0x000007FFFFFFFFFF
            let targetValue = (top8Bits << 13) | bottom43Bits
            return UInt64(bitPattern: Int64(bitPattern: targetValue) + slide)
        case .authenticated:
            return nil // Authenticated pointers need special handling
        }
    }
}

/// Slide pointer for version 5 slide info.
///
/// Similar to V3 but uses chained fixup format from dyld_chained_ptr_*.
public enum SlidePointer5: Sendable, Hashable {
    /// A regular (non-authenticated) rebase.
    case regular(target: UInt64, high8: UInt8, offsetToNext: UInt16)

    /// An authenticated rebase.
    case authenticated(
        target: UInt64,
        diversityData: UInt16,
        hasAddressDiversity: Bool,
        key: UInt8,
        offsetToNext: UInt16
    )

    /// Initialize from raw 64-bit value.
    public init(raw: UInt64) {
        let isAuthenticated = (raw >> 63) != 0

        if isAuthenticated {
            // auth: target(32) | diversity(16) | addrDiv(1) | key(2) | next(11) | unused(1) | auth(1)
            let target = UInt64(raw & 0xFFFFFFFF)
            let diversityData = UInt16((raw >> 32) & 0xFFFF)
            let hasAddressDiversity = ((raw >> 48) & 1) != 0
            let key = UInt8((raw >> 49) & 0x3)
            let offsetToNext = UInt16((raw >> 51) & 0x7FF)

            self = .authenticated(
                target: target,
                diversityData: diversityData,
                hasAddressDiversity: hasAddressDiversity,
                key: key,
                offsetToNext: offsetToNext
            )
        } else {
            // regular: target(51) | next(11) | high8(8) or similar layout
            // The exact layout depends on the chained fixup format
            let target = raw & 0x000007FFFFFFFFFF // 43 bits for target
            let high8 = UInt8((raw >> 43) & 0xFF)
            let offsetToNext = UInt16((raw >> 51) & 0x7FF)

            self = .regular(target: target, high8: high8, offsetToNext: offsetToNext)
        }
    }

    /// Whether this pointer is authenticated.
    public var isAuthenticated: Bool {
        switch self {
        case .regular: return false
        case .authenticated: return true
        }
    }

    /// The offset to the next pointer in the chain.
    public var offsetToNextPointer: UInt16 {
        switch self {
        case .regular(_, _, let offset): return offset
        case .authenticated(_, _, _, _, let offset): return offset
        }
    }

    /// Calculate the rebased value given the value add and slide.
    public func rebasedValue(valueAdd: UInt64, slide: Int64) -> UInt64 {
        switch self {
        case .regular(let target, let high8, _):
            let baseValue = target + valueAdd
            let signedValue = Int64(bitPattern: baseValue) + slide
            let result = UInt64(bitPattern: signedValue)
            // Apply high8 to top byte
            return (result & 0x00FFFFFFFFFFFFFF) | (UInt64(high8) << 56)
        case .authenticated(let target, _, _, _, _):
            let baseValue = target + valueAdd
            return UInt64(bitPattern: Int64(bitPattern: baseValue) + slide)
        }
    }
}

/// PAC key identifiers for authenticated pointers.
public enum PACKey: UInt8, Sendable {
    case ia = 0 // Instruction address key A
    case ib = 1 // Instruction address key B
    case da = 2 // Data address key A
    case db = 3 // Data address key B
}
