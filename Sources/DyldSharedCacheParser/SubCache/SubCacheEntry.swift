import BinaryParsing
import Foundation

/// Subcache entry version 1 (older format without file suffix).
public struct SubCacheEntryV1: Sendable, Hashable {
    /// UUID of the subcache file.
    public let uuid: UUID

    /// VM offset from main cache base address.
    public let cacheVMOffset: UInt64

    public init(uuid: UUID, cacheVMOffset: UInt64) {
        self.uuid = uuid
        self.cacheVMOffset = cacheVMOffset
    }
}

extension SubCacheEntryV1 {
    /// Size of this structure in bytes.
    public static let size = 24

    /// Parse a SubCacheEntryV1 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        // UUID (16 bytes)
        let uuidBytes = try Array<UInt8>(parsing: &input, byteCount: 16)
        self.uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))

        self.cacheVMOffset = try UInt64(parsingLittleEndian: &input)
    }
}

/// Subcache entry (current format with file suffix).
public struct SubCacheEntry: Sendable, Hashable {
    /// UUID of the subcache file.
    public let uuid: UUID

    /// VM offset from main cache base address.
    public let cacheVMOffset: UInt64

    /// File name suffix (e.g., ".25.data", ".03.development").
    public let fileSuffix: String

    public init(uuid: UUID, cacheVMOffset: UInt64, fileSuffix: String) {
        self.uuid = uuid
        self.cacheVMOffset = cacheVMOffset
        self.fileSuffix = fileSuffix
    }

    /// Generate the full subcache file name given the main cache name.
    public func fileName(forMainCache mainCacheName: String) -> String {
        return mainCacheName + fileSuffix
    }
}

extension SubCacheEntry {
    /// Size of this structure in bytes.
    public static let size = 56

    /// Parse a SubCacheEntry from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        // UUID (16 bytes)
        let uuidBytes = try Array<UInt8>(parsing: &input, byteCount: 16)
        self.uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))

        self.cacheVMOffset = try UInt64(parsingLittleEndian: &input)

        // File suffix (32 bytes, null-terminated)
        let suffixBytes = try Array<UInt8>(parsing: &input, byteCount: 32)
        self.fileSuffix = String(bytes: suffixBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
    }
}
