import BinaryParsing
import Foundation

/// Maximum number of page starts to prevent excessive memory allocation.
/// A typical large cache might have ~100K pages, so 1M is a reasonable limit.
private let maxPageStartsCount: UInt32 = 1_000_000

/// Protocol for slide info structures.
///
/// Slide info describes how pointers in data pages need to be
/// rebased when the cache is loaded at a non-default address.
public protocol SlideInfo: Sendable {
    /// The slide info version number.
    var version: UInt32 { get }

    /// The page size used for this slide info.
    var pageSize: UInt32 { get }
}

/// Slide info version 1 (oldest format, uses bitmap).
public struct SlideInfoV1: SlideInfo, Sendable {
    public let version: UInt32
    public let tocOffset: UInt32
    public let tocCount: UInt32
    public let entriesOffset: UInt32
    public let entriesCount: UInt32
    public let entriesSize: UInt32

    public var pageSize: UInt32 { 4096 }

    public init(
        version: UInt32,
        tocOffset: UInt32,
        tocCount: UInt32,
        entriesOffset: UInt32,
        entriesCount: UInt32,
        entriesSize: UInt32
    ) {
        self.version = version
        self.tocOffset = tocOffset
        self.tocCount = tocCount
        self.entriesOffset = entriesOffset
        self.entriesCount = entriesCount
        self.entriesSize = entriesSize
    }
}

extension SlideInfoV1 {
    /// Size of the header in bytes.
    public static let headerSize = 24

    /// Parse SlideInfoV1 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.version = try UInt32(parsingLittleEndian: &input)
        guard self.version == 1 else {
            throw DyldCacheError.unknownSlideInfoVersion(self.version)
        }
        self.tocOffset = try UInt32(parsingLittleEndian: &input)
        self.tocCount = try UInt32(parsingLittleEndian: &input)
        self.entriesOffset = try UInt32(parsingLittleEndian: &input)
        self.entriesCount = try UInt32(parsingLittleEndian: &input)
        self.entriesSize = try UInt32(parsingLittleEndian: &input)
    }
}

/// Slide info version 2 (linked list with delta encoding).
public struct SlideInfoV2: SlideInfo, Sendable {
    public let version: UInt32
    public let pageSize: UInt32
    public let pageStartsOffset: UInt32
    public let pageStartsCount: UInt32
    public let pageExtrasOffset: UInt32
    public let pageExtrasCount: UInt32
    public let deltaMask: UInt64
    public let valueAdd: UInt64

    public init(
        version: UInt32,
        pageSize: UInt32,
        pageStartsOffset: UInt32,
        pageStartsCount: UInt32,
        pageExtrasOffset: UInt32,
        pageExtrasCount: UInt32,
        deltaMask: UInt64,
        valueAdd: UInt64
    ) {
        self.version = version
        self.pageSize = pageSize
        self.pageStartsOffset = pageStartsOffset
        self.pageStartsCount = pageStartsCount
        self.pageExtrasOffset = pageExtrasOffset
        self.pageExtrasCount = pageExtrasCount
        self.deltaMask = deltaMask
        self.valueAdd = valueAdd
    }

    /// The value mask (inverse of delta mask).
    public var valueMask: UInt64 {
        ~deltaMask
    }
}

extension SlideInfoV2 {
    /// Size of the header in bytes.
    public static let headerSize = 40

    /// Page has no rebasing.
    public static let pageAttrNoRebase: UInt16 = 0x4000

    /// Index is into extras array.
    public static let pageAttrExtra: UInt16 = 0x8000

    /// Last chain entry for page.
    public static let pageAttrEnd: UInt16 = 0x8000

    /// Parse SlideInfoV2 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.version = try UInt32(parsingLittleEndian: &input)
        guard self.version == 2 else {
            throw DyldCacheError.unknownSlideInfoVersion(self.version)
        }
        self.pageSize = try UInt32(parsingLittleEndian: &input)
        self.pageStartsOffset = try UInt32(parsingLittleEndian: &input)
        self.pageStartsCount = try UInt32(parsingLittleEndian: &input)
        self.pageExtrasOffset = try UInt32(parsingLittleEndian: &input)
        self.pageExtrasCount = try UInt32(parsingLittleEndian: &input)
        self.deltaMask = try UInt64(parsingLittleEndian: &input)
        self.valueAdd = try UInt64(parsingLittleEndian: &input)
    }
}

/// Slide info version 3 (arm64e with pointer authentication).
public struct SlideInfoV3: SlideInfo, Sendable {
    public let version: UInt32
    public let pageSize: UInt32
    public let pageStartsCount: UInt32
    public let authValueAdd: UInt64
    public let pageStarts: [UInt16]

    public init(
        version: UInt32,
        pageSize: UInt32,
        pageStartsCount: UInt32,
        authValueAdd: UInt64,
        pageStarts: [UInt16]
    ) {
        self.version = version
        self.pageSize = pageSize
        self.pageStartsCount = pageStartsCount
        self.authValueAdd = authValueAdd
        self.pageStarts = pageStarts
    }
}

extension SlideInfoV3 {
    /// Size of the header (before pageStarts array).
    public static let headerSize = 20

    /// Page has no rebasing.
    public static let pageAttrNoRebase: UInt16 = 0xFFFF

    /// Parse SlideInfoV3 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.version = try UInt32(parsingLittleEndian: &input)
        guard self.version == 3 else {
            throw DyldCacheError.unknownSlideInfoVersion(self.version)
        }
        self.pageSize = try UInt32(parsingLittleEndian: &input)
        self.pageStartsCount = try UInt32(parsingLittleEndian: &input)
        self.authValueAdd = try UInt64(parsingLittleEndian: &input)

        // Validate page starts count to prevent excessive memory allocation
        guard pageStartsCount <= maxPageStartsCount else {
            throw DyldCacheError.slideInfoParseError(
                version: 3,
                detail: "pageStartsCount (\(pageStartsCount)) exceeds maximum allowed (\(maxPageStartsCount))"
            )
        }

        // Parse page starts array
        var starts: [UInt16] = []
        starts.reserveCapacity(Int(pageStartsCount))
        for _ in 0..<pageStartsCount {
            starts.append(try UInt16(parsingLittleEndian: &input))
        }
        self.pageStarts = starts
    }
}

/// Slide info version 4 (32-bit caches, optimized).
public struct SlideInfoV4: SlideInfo, Sendable {
    public let version: UInt32
    public let pageSize: UInt32
    public let pageStartsOffset: UInt32
    public let pageStartsCount: UInt32
    public let pageExtrasOffset: UInt32
    public let pageExtrasCount: UInt32
    public let deltaMask: UInt64
    public let valueAdd: UInt64

    public init(
        version: UInt32,
        pageSize: UInt32,
        pageStartsOffset: UInt32,
        pageStartsCount: UInt32,
        pageExtrasOffset: UInt32,
        pageExtrasCount: UInt32,
        deltaMask: UInt64,
        valueAdd: UInt64
    ) {
        self.version = version
        self.pageSize = pageSize
        self.pageStartsOffset = pageStartsOffset
        self.pageStartsCount = pageStartsCount
        self.pageExtrasOffset = pageExtrasOffset
        self.pageExtrasCount = pageExtrasCount
        self.deltaMask = deltaMask
        self.valueAdd = valueAdd
    }

    /// The value mask (inverse of delta mask).
    public var valueMask: UInt64 {
        ~deltaMask
    }
}

extension SlideInfoV4 {
    /// Size of the header in bytes.
    public static let headerSize = 40

    /// Page has no rebasing.
    public static let pageNoRebase: UInt16 = 0xFFFF

    /// Mask for page index.
    public static let pageIndexMask: UInt16 = 0x7FFF

    /// Index is into extras array.
    public static let pageUseExtra: UInt16 = 0x8000

    /// Last chain entry for page.
    public static let pageExtraEnd: UInt16 = 0x8000

    /// Parse SlideInfoV4 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.version = try UInt32(parsingLittleEndian: &input)
        guard self.version == 4 else {
            throw DyldCacheError.unknownSlideInfoVersion(self.version)
        }
        self.pageSize = try UInt32(parsingLittleEndian: &input)
        self.pageStartsOffset = try UInt32(parsingLittleEndian: &input)
        self.pageStartsCount = try UInt32(parsingLittleEndian: &input)
        self.pageExtrasOffset = try UInt32(parsingLittleEndian: &input)
        self.pageExtrasCount = try UInt32(parsingLittleEndian: &input)
        self.deltaMask = try UInt64(parsingLittleEndian: &input)
        self.valueAdd = try UInt64(parsingLittleEndian: &input)
    }
}

/// Slide info version 5 (chained fixup format).
public struct SlideInfoV5: SlideInfo, Sendable {
    public let version: UInt32
    public let pageSize: UInt32
    public let pageStartsCount: UInt32
    public let valueAdd: UInt64
    public let pageStarts: [UInt16]

    public init(
        version: UInt32,
        pageSize: UInt32,
        pageStartsCount: UInt32,
        valueAdd: UInt64,
        pageStarts: [UInt16]
    ) {
        self.version = version
        self.pageSize = pageSize
        self.pageStartsCount = pageStartsCount
        self.valueAdd = valueAdd
        self.pageStarts = pageStarts
    }
}

extension SlideInfoV5 {
    /// Size of the header (before pageStarts array).
    public static let headerSize = 20

    /// Page has no rebasing.
    public static let pageAttrNoRebase: UInt16 = 0xFFFF

    /// Parse SlideInfoV5 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.version = try UInt32(parsingLittleEndian: &input)
        guard self.version == 5 else {
            throw DyldCacheError.unknownSlideInfoVersion(self.version)
        }
        self.pageSize = try UInt32(parsingLittleEndian: &input)
        self.pageStartsCount = try UInt32(parsingLittleEndian: &input)
        self.valueAdd = try UInt64(parsingLittleEndian: &input)

        // Validate page starts count to prevent excessive memory allocation
        guard pageStartsCount <= maxPageStartsCount else {
            throw DyldCacheError.slideInfoParseError(
                version: 5,
                detail: "pageStartsCount (\(pageStartsCount)) exceeds maximum allowed (\(maxPageStartsCount))"
            )
        }

        // Parse page starts array
        var starts: [UInt16] = []
        starts.reserveCapacity(Int(pageStartsCount))
        for _ in 0..<pageStartsCount {
            starts.append(try UInt16(parsingLittleEndian: &input))
        }
        self.pageStarts = starts
    }
}

/// Parse any slide info version from data at a specific offset (zero-copy).
///
/// This is the preferred internal method as it avoids data copies by using
/// memory-mapped data directly via ParserSpan seeking.
///
/// - Parameters:
///   - data: The cache data to read from.
///   - offset: The file offset where the slide info begins.
/// - Returns: The parsed slide info.
internal func parseSlideInfoFromOffset(_ data: Data, at offset: Int) throws -> any SlideInfo {
    // Peek at version without copying via subdata
    guard offset + 4 <= data.count else {
        throw DyldCacheError.slideInfoParseError(version: 0, detail: "Offset out of bounds")
    }

    let version = data.withUnsafeBytes { bytes in
        bytes.load(fromByteOffset: offset, as: UInt32.self)
    }

    return try data.withParserSpan { span in
        var slideSpan = try span.seeking(toAbsoluteOffset: offset)
        switch version {
        case 1:
            return try SlideInfoV1(parsing: &slideSpan)
        case 2:
            return try SlideInfoV2(parsing: &slideSpan)
        case 3:
            return try SlideInfoV3(parsing: &slideSpan)
        case 4:
            return try SlideInfoV4(parsing: &slideSpan)
        case 5:
            return try SlideInfoV5(parsing: &slideSpan)
        default:
            throw DyldCacheError.unknownSlideInfoVersion(version)
        }
    }
}

/// Parse any slide info version from raw data.
public func parseSlideInfo(from data: Data) throws -> any SlideInfo {
    guard data.count >= 4 else {
        throw DyldCacheError.slideInfoParseError(version: 0, detail: "Data too small")
    }

    // Peek at version
    let version = data.withUnsafeBytes { bytes in
        bytes.load(as: UInt32.self)
    }

    return try data.withParserSpan { span in
        switch version {
        case 1:
            return try SlideInfoV1(parsing: &span)
        case 2:
            return try SlideInfoV2(parsing: &span)
        case 3:
            return try SlideInfoV3(parsing: &span)
        case 4:
            return try SlideInfoV4(parsing: &span)
        case 5:
            return try SlideInfoV5(parsing: &span)
        default:
            throw DyldCacheError.unknownSlideInfoVersion(version)
        }
    }
}
