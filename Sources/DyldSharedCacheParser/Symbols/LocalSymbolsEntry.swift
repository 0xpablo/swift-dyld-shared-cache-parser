import BinaryParsing

/// Per-dylib local symbols entry (32-bit version).
///
/// Maps a dylib to its range of local symbols in the nlist array.
public struct LocalSymbolsEntry32: Sendable, Hashable {
    /// Offset in cache file to the start of this dylib.
    public let dylibOffset: UInt32

    /// Start index in the nlist array for this dylib's local symbols.
    public let nlistStartIndex: UInt32

    /// Number of local symbols for this dylib.
    public let nlistCount: UInt32

    public init(
        dylibOffset: UInt32,
        nlistStartIndex: UInt32,
        nlistCount: UInt32
    ) {
        self.dylibOffset = dylibOffset
        self.nlistStartIndex = nlistStartIndex
        self.nlistCount = nlistCount
    }
}

extension LocalSymbolsEntry32 {
    /// Size of this structure in bytes.
    public static let size = 12

    /// Parse a LocalSymbolsEntry32 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.dylibOffset = try UInt32(parsingLittleEndian: &input)
        self.nlistStartIndex = try UInt32(parsingLittleEndian: &input)
        self.nlistCount = try UInt32(parsingLittleEndian: &input)
    }
}

/// Per-dylib local symbols entry (64-bit version).
///
/// Maps a dylib to its range of local symbols in the nlist array.
/// Used in newer cache formats with larger offset fields.
public struct LocalSymbolsEntry64: Sendable, Hashable {
    /// Offset in cache buffer to the start of this dylib.
    public let dylibOffset: UInt64

    /// Start index in the nlist array for this dylib's local symbols.
    public let nlistStartIndex: UInt32

    /// Number of local symbols for this dylib.
    public let nlistCount: UInt32

    public init(
        dylibOffset: UInt64,
        nlistStartIndex: UInt32,
        nlistCount: UInt32
    ) {
        self.dylibOffset = dylibOffset
        self.nlistStartIndex = nlistStartIndex
        self.nlistCount = nlistCount
    }
}

extension LocalSymbolsEntry64 {
    /// Size of this structure in bytes.
    public static let size = 16

    /// Parse a LocalSymbolsEntry64 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.dylibOffset = try UInt64(parsingLittleEndian: &input)
        self.nlistStartIndex = try UInt32(parsingLittleEndian: &input)
        self.nlistCount = try UInt32(parsingLittleEndian: &input)
    }
}

/// Unified local symbols entry that works with both 32-bit and 64-bit formats.
public struct LocalSymbolsEntry: Sendable, Hashable {
    /// Offset in cache to the start of this dylib.
    public let dylibOffset: UInt64

    /// Start index in the nlist array for this dylib's local symbols.
    public let nlistStartIndex: UInt32

    /// Number of local symbols for this dylib.
    public let nlistCount: UInt32

    public init(
        dylibOffset: UInt64,
        nlistStartIndex: UInt32,
        nlistCount: UInt32
    ) {
        self.dylibOffset = dylibOffset
        self.nlistStartIndex = nlistStartIndex
        self.nlistCount = nlistCount
    }

    /// Initialize from a 32-bit entry.
    public init(_ entry32: LocalSymbolsEntry32) {
        self.dylibOffset = UInt64(entry32.dylibOffset)
        self.nlistStartIndex = entry32.nlistStartIndex
        self.nlistCount = entry32.nlistCount
    }

    /// Initialize from a 64-bit entry.
    public init(_ entry64: LocalSymbolsEntry64) {
        self.dylibOffset = entry64.dylibOffset
        self.nlistStartIndex = entry64.nlistStartIndex
        self.nlistCount = entry64.nlistCount
    }
}
