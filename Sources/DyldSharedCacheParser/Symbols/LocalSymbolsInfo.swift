import BinaryParsing

/// Header for the local symbols region in the dyld shared cache.
///
/// This structure describes the layout of local symbols, including
/// offsets to the nlist array, string pool, and per-dylib entries.
public struct LocalSymbolsInfo: Sendable, Hashable {
    /// Offset into the local symbols chunk to the nlist entries.
    public let nlistOffset: UInt32

    /// Total count of nlist entries.
    public let nlistCount: UInt32

    /// Offset into the local symbols chunk to the string pool.
    public let stringsOffset: UInt32

    /// Size of the string pool in bytes.
    public let stringsSize: UInt32

    /// Offset into the local symbols chunk to the per-dylib entries array.
    public let entriesOffset: UInt32

    /// Number of per-dylib entries.
    public let entriesCount: UInt32

    public init(
        nlistOffset: UInt32,
        nlistCount: UInt32,
        stringsOffset: UInt32,
        stringsSize: UInt32,
        entriesOffset: UInt32,
        entriesCount: UInt32
    ) {
        self.nlistOffset = nlistOffset
        self.nlistCount = nlistCount
        self.stringsOffset = stringsOffset
        self.stringsSize = stringsSize
        self.entriesOffset = entriesOffset
        self.entriesCount = entriesCount
    }
}

extension LocalSymbolsInfo {
    /// Size of this structure in bytes.
    public static let size = 24

    /// Parse a LocalSymbolsInfo from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.nlistOffset = try UInt32(parsingLittleEndian: &input)
        self.nlistCount = try UInt32(parsingLittleEndian: &input)
        self.stringsOffset = try UInt32(parsingLittleEndian: &input)
        self.stringsSize = try UInt32(parsingLittleEndian: &input)
        self.entriesOffset = try UInt32(parsingLittleEndian: &input)
        self.entriesCount = try UInt32(parsingLittleEndian: &input)
    }
}

extension LocalSymbolsInfo: CustomStringConvertible {
    public var description: String {
        "LocalSymbolsInfo(nlistCount: \(nlistCount), stringsSize: \(stringsSize), entriesCount: \(entriesCount))"
    }
}
