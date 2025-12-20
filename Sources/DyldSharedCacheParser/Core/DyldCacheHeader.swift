import BinaryParsing
import Foundation

/// Header flags parsed from the bitfield in the dyld cache header.
public struct HeaderFlags: Sendable, Hashable {
    /// The raw 32-bit value containing the bitfield.
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// dyld3::closure format version (8 bits).
    public var formatVersion: UInt8 {
        UInt8(rawValue & 0xFF)
    }

    /// Whether dyld should expect dylibs on disk and compare inode/mtime.
    public var dylibsExpectedOnDisk: Bool {
        (rawValue & (1 << 8)) != 0
    }

    /// Whether this is a simulator cache.
    public var simulator: Bool {
        (rawValue & (1 << 9)) != 0
    }

    /// Whether this cache was built locally (not by B&I).
    public var locallyBuiltCache: Bool {
        (rawValue & (1 << 10)) != 0
    }

    /// Whether some dylib was built using chained fixups.
    public var builtFromChainedFixups: Bool {
        (rawValue & (1 << 11)) != 0
    }

    /// Whether TLVs use new format (not needing runtime side table).
    public var newFormatTLVs: Bool {
        (rawValue & (1 << 12)) != 0
    }
}

/// The main header structure for a dyld shared cache file.
///
/// This structure contains offsets and counts for all major data regions
/// in the cache file, including mappings, images, symbols, and subcaches.
public struct DyldCacheHeader: Sendable {
    // MARK: - Identification

    /// The raw 16-byte magic string.
    public let magic: String

    /// The parsed architecture.
    public let architecture: CacheArchitecture

    /// Unique identifier for this cache file.
    public let uuid: UUID

    // MARK: - Mappings

    /// File offset to first dyld_cache_mapping_info.
    public let mappingOffset: UInt32

    /// Number of dyld_cache_mapping_info entries.
    public let mappingCount: UInt32

    /// File offset to first dyld_cache_mapping_and_slide_info.
    public let mappingWithSlideOffset: UInt32

    /// Number of dyld_cache_mapping_and_slide_info entries.
    public let mappingWithSlideCount: UInt32

    // MARK: - Images

    /// File offset to first dyld_cache_image_info.
    public let imagesOffset: UInt32

    /// Number of dyld_cache_image_info entries.
    public let imagesCount: UInt32

    /// File offset to first dyld_cache_image_text_info.
    public let imagesTextOffset: UInt64

    /// Number of dyld_cache_image_text_info entries.
    public let imagesTextCount: UInt64

    // MARK: - Symbols

    /// File offset to local symbols region.
    public let localSymbolsOffset: UInt64

    /// Size of local symbols region.
    public let localSymbolsSize: UInt64

    // MARK: - Subcaches

    /// File offset to first dyld_subcache_entry.
    public let subCacheArrayOffset: UInt32

    /// Number of subcache entries.
    public let subCacheArrayCount: UInt32

    /// UUID for the separate .symbols file containing unmapped local symbols.
    public let symbolFileUUID: UUID

    // MARK: - Cache Configuration

    /// Platform number (macOS=1, iOS=2, etc).
    public let platform: CachePlatform

    /// Cache type (development=0, production=1, multi-cache=2).
    public let cacheType: CacheType

    /// Cache subtype for multi-cache.
    public let cacheSubType: UInt32

    /// Header flags bitfield.
    public let flags: HeaderFlags

    // MARK: - Address Space

    /// Base load address of cache if not slid.
    public let sharedRegionStart: UInt64

    /// Overall size required to map the cache and all subcaches.
    public let sharedRegionSize: UInt64

    /// Maximum runtime slide value.
    public let maxSlide: UInt64

    /// Base address of dyld when cache was built.
    public let dyldBaseAddress: UInt64

    // MARK: - Code Signature

    /// File offset of code signature blob.
    public let codeSignatureOffset: UInt64

    /// Size of code signature blob.
    public let codeSignatureSize: UInt64

    // MARK: - Dylibs Trie

    /// Unslid address of trie of indexes of all cached dylibs.
    public let dylibsTrieAddr: UInt64

    /// Size of trie of cached dylib paths.
    public let dylibsTrieSize: UInt64

    // MARK: - TPRO Mappings

    /// File offset to first dyld_cache_tpro_mapping_info.
    public let tproMappingsOffset: UInt32

    /// Number of dyld_cache_tpro_mapping_info entries.
    public let tproMappingsCount: UInt32

    // MARK: - OS Version

    /// OS Version of dylibs in this cache.
    public let osVersion: UInt32

    /// Alternative platform (e.g., iOSMac on macOS).
    public let altPlatform: UInt32

    /// Alternative OS version.
    public let altOsVersion: UInt32
}

extension DyldCacheHeader {
    /// Minimum size of the header that we need to parse.
    /// The full header is ~472 bytes, but older caches may have smaller headers.
    public static let minimumSize = 0x118 // Through subCacheArrayCount

    /// Parse a DyldCacheHeader from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        // Parse magic (16 bytes)
        let magicBytes = try Array<UInt8>(parsing: &input, byteCount: 16)
        let magicString = String(bytes: magicBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
        self.magic = magicString

        guard let arch = CacheArchitecture(magic: magicString) else {
            throw DyldCacheError.invalidMagic(magicString)
        }
        self.architecture = arch

        // Basic mapping info
        self.mappingOffset = try UInt32(parsingLittleEndian: &input)
        self.mappingCount = try UInt32(parsingLittleEndian: &input)

        // Old/unused image fields (skip)
        _ = try UInt32(parsingLittleEndian: &input) // imagesOffsetOld
        _ = try UInt32(parsingLittleEndian: &input) // imagesCountOld

        self.dyldBaseAddress = try UInt64(parsingLittleEndian: &input)
        self.codeSignatureOffset = try UInt64(parsingLittleEndian: &input)
        self.codeSignatureSize = try UInt64(parsingLittleEndian: &input)

        // Unused slide info fields
        _ = try UInt64(parsingLittleEndian: &input) // slideInfoOffsetUnused
        _ = try UInt64(parsingLittleEndian: &input) // slideInfoSizeUnused

        self.localSymbolsOffset = try UInt64(parsingLittleEndian: &input)
        self.localSymbolsSize = try UInt64(parsingLittleEndian: &input)

        // UUID (16 bytes)
        let uuidBytes = try Array<UInt8>(parsing: &input, byteCount: 16)
        self.uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))

        self.cacheType = CacheType(rawValue: try UInt64(parsingLittleEndian: &input)) ?? .development

        // Branch pools (skip)
        _ = try UInt32(parsingLittleEndian: &input) // branchPoolsOffset
        _ = try UInt32(parsingLittleEndian: &input) // branchPoolsCount

        // Dyld in cache (skip)
        _ = try UInt64(parsingLittleEndian: &input) // dyldInCacheMH
        _ = try UInt64(parsingLittleEndian: &input) // dyldInCacheEntry

        self.imagesTextOffset = try UInt64(parsingLittleEndian: &input)
        self.imagesTextCount = try UInt64(parsingLittleEndian: &input)

        // Patch info (skip)
        _ = try UInt64(parsingLittleEndian: &input) // patchInfoAddr
        _ = try UInt64(parsingLittleEndian: &input) // patchInfoSize

        // Other image group unused (skip)
        _ = try UInt64(parsingLittleEndian: &input)
        _ = try UInt64(parsingLittleEndian: &input)

        // Program closures (skip)
        _ = try UInt64(parsingLittleEndian: &input) // progClosuresAddr
        _ = try UInt64(parsingLittleEndian: &input) // progClosuresSize
        _ = try UInt64(parsingLittleEndian: &input) // progClosuresTrieAddr
        _ = try UInt64(parsingLittleEndian: &input) // progClosuresTrieSize

        let platformRaw = try UInt32(parsingLittleEndian: &input)
        self.platform = CachePlatform(rawValue: platformRaw) ?? .unknown

        let flagsRaw = try UInt32(parsingLittleEndian: &input)
        self.flags = HeaderFlags(rawValue: flagsRaw)

        self.sharedRegionStart = try UInt64(parsingLittleEndian: &input)
        self.sharedRegionSize = try UInt64(parsingLittleEndian: &input)
        self.maxSlide = try UInt64(parsingLittleEndian: &input)

        // Dylibs image array (skip)
        _ = try UInt64(parsingLittleEndian: &input) // dylibsImageArrayAddr
        _ = try UInt64(parsingLittleEndian: &input) // dylibsImageArraySize

        self.dylibsTrieAddr = try UInt64(parsingLittleEndian: &input)
        self.dylibsTrieSize = try UInt64(parsingLittleEndian: &input)

        // Other image array (skip)
        _ = try UInt64(parsingLittleEndian: &input) // otherImageArrayAddr
        _ = try UInt64(parsingLittleEndian: &input) // otherImageArraySize
        _ = try UInt64(parsingLittleEndian: &input) // otherTrieAddr
        _ = try UInt64(parsingLittleEndian: &input) // otherTrieSize

        self.mappingWithSlideOffset = try UInt32(parsingLittleEndian: &input)
        self.mappingWithSlideCount = try UInt32(parsingLittleEndian: &input)

        // Skip unused and PBL fields
        _ = try UInt64(parsingLittleEndian: &input) // dylibsPBLStateArrayAddrUnused
        _ = try UInt64(parsingLittleEndian: &input) // dylibsPBLSetAddr
        _ = try UInt64(parsingLittleEndian: &input) // programsPBLSetPoolAddr
        _ = try UInt64(parsingLittleEndian: &input) // programsPBLSetPoolSize
        _ = try UInt64(parsingLittleEndian: &input) // programTrieAddr
        _ = try UInt32(parsingLittleEndian: &input) // programTrieSize

        self.osVersion = try UInt32(parsingLittleEndian: &input)
        self.altPlatform = try UInt32(parsingLittleEndian: &input)
        self.altOsVersion = try UInt32(parsingLittleEndian: &input)

        // Swift opts (skip)
        _ = try UInt64(parsingLittleEndian: &input) // swiftOptsOffset
        _ = try UInt64(parsingLittleEndian: &input) // swiftOptsSize

        self.subCacheArrayOffset = try UInt32(parsingLittleEndian: &input)
        self.subCacheArrayCount = try UInt32(parsingLittleEndian: &input)

        // Symbol file UUID (16 bytes)
        let symbolUuidBytes = try Array<UInt8>(parsing: &input, byteCount: 16)
        self.symbolFileUUID = UUID(uuid: (
            symbolUuidBytes[0], symbolUuidBytes[1], symbolUuidBytes[2], symbolUuidBytes[3],
            symbolUuidBytes[4], symbolUuidBytes[5], symbolUuidBytes[6], symbolUuidBytes[7],
            symbolUuidBytes[8], symbolUuidBytes[9], symbolUuidBytes[10], symbolUuidBytes[11],
            symbolUuidBytes[12], symbolUuidBytes[13], symbolUuidBytes[14], symbolUuidBytes[15]
        ))

        // Rosetta fields (skip)
        _ = try UInt64(parsingLittleEndian: &input) // rosettaReadOnlyAddr
        _ = try UInt64(parsingLittleEndian: &input) // rosettaReadOnlySize
        _ = try UInt64(parsingLittleEndian: &input) // rosettaReadWriteAddr
        _ = try UInt64(parsingLittleEndian: &input) // rosettaReadWriteSize

        self.imagesOffset = try UInt32(parsingLittleEndian: &input)
        self.imagesCount = try UInt32(parsingLittleEndian: &input)
        self.cacheSubType = try UInt32(parsingLittleEndian: &input)

        // Skip remaining optional fields - they may not exist in older caches
        // objcOptsOffset, objcOptsSize, cacheAtlasOffset, cacheAtlasSize,
        // dynamicDataOffset, dynamicDataMaxSize, tproMappingsOffset, tproMappingsCount, etc.

        // Try to parse TPRO mappings if available
        var tproOffset: UInt32 = 0
        var tproCount: UInt32 = 0

        if let parsed = try? Self.parseTproMappings(&input) {
            tproOffset = parsed.offset
            tproCount = parsed.count
        }

        self.tproMappingsOffset = tproOffset
        self.tproMappingsCount = tproCount
    }

    private static func parseTproMappings(_ input: inout ParserSpan) throws -> (offset: UInt32, count: UInt32) {
        _ = try UInt64(parsingLittleEndian: &input) // objcOptsOffset
        _ = try UInt64(parsingLittleEndian: &input) // objcOptsSize
        _ = try UInt64(parsingLittleEndian: &input) // cacheAtlasOffset
        _ = try UInt64(parsingLittleEndian: &input) // cacheAtlasSize
        _ = try UInt64(parsingLittleEndian: &input) // dynamicDataOffset
        _ = try UInt64(parsingLittleEndian: &input) // dynamicDataMaxSize
        let offset = try UInt32(parsingLittleEndian: &input)
        let count = try UInt32(parsingLittleEndian: &input)
        return (offset, count)
    }
}
