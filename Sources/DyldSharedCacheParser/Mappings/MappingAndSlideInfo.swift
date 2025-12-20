import BinaryParsing

/// Flags for dyld_cache_mapping_and_slide_info.
public struct MappingFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// Contains authenticated pointers (arm64e PAC).
    public static let authData = MappingFlags(rawValue: 1 << 0)

    /// Contains dirty (writable) data.
    public static let dirtyData = MappingFlags(rawValue: 1 << 1)

    /// Contains constant (read-only after fixups) data.
    public static let constData = MappingFlags(rawValue: 1 << 2)

    /// Contains TEXT stubs.
    public static let textStubs = MappingFlags(rawValue: 1 << 3)

    /// Contains dynamic config data.
    public static let dynamicConfigData = MappingFlags(rawValue: 1 << 4)

    /// Contains read-only data.
    public static let readOnlyData = MappingFlags(rawValue: 1 << 5)

    /// Contains constant TPRO data.
    public static let constTPROData = MappingFlags(rawValue: 1 << 6)
}

extension MappingFlags: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        if contains(.authData) { parts.append("auth") }
        if contains(.dirtyData) { parts.append("dirty") }
        if contains(.constData) { parts.append("const") }
        if contains(.textStubs) { parts.append("stubs") }
        if contains(.dynamicConfigData) { parts.append("dynamic") }
        if contains(.readOnlyData) { parts.append("ro") }
        if contains(.constTPROData) { parts.append("tpro") }
        return parts.isEmpty ? "none" : parts.joined(separator: "|")
    }
}

/// Extended mapping information including slide info for ASLR support.
///
/// This structure includes file offsets to slide information that
/// describes which pointers in this mapping need to be rebased
/// when the cache is loaded at a non-default address.
public struct MappingAndSlideInfo: Sendable, Hashable {
    /// Virtual memory address where this region is mapped.
    public let address: UInt64

    /// Size of the mapping in bytes.
    public let size: UInt64

    /// Offset in the cache file where this region's data starts.
    public let fileOffset: UInt64

    /// File offset to the slide info for this mapping.
    public let slideInfoFileOffset: UInt64

    /// Size of the slide info for this mapping.
    public let slideInfoFileSize: UInt64

    /// Mapping flags indicating the type of data.
    public let flags: MappingFlags

    /// Maximum protection flags (r/w/x).
    public let maxProt: VMProtection

    /// Initial protection flags (r/w/x).
    public let initProt: VMProtection

    public init(
        address: UInt64,
        size: UInt64,
        fileOffset: UInt64,
        slideInfoFileOffset: UInt64,
        slideInfoFileSize: UInt64,
        flags: MappingFlags,
        maxProt: VMProtection,
        initProt: VMProtection
    ) {
        self.address = address
        self.size = size
        self.fileOffset = fileOffset
        self.slideInfoFileOffset = slideInfoFileOffset
        self.slideInfoFileSize = slideInfoFileSize
        self.flags = flags
        self.maxProt = maxProt
        self.initProt = initProt
    }

    /// Whether this mapping has slide information.
    public var hasSlideInfo: Bool {
        slideInfoFileSize > 0
    }
}

extension MappingAndSlideInfo {
    /// Size of this structure in bytes.
    public static let size = 56

    /// Parse a MappingAndSlideInfo from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.address = try UInt64(parsingLittleEndian: &input)
        self.size = try UInt64(parsingLittleEndian: &input)
        self.fileOffset = try UInt64(parsingLittleEndian: &input)
        self.slideInfoFileOffset = try UInt64(parsingLittleEndian: &input)
        self.slideInfoFileSize = try UInt64(parsingLittleEndian: &input)
        self.flags = MappingFlags(rawValue: try UInt64(parsingLittleEndian: &input))
        self.maxProt = VMProtection(rawValue: try UInt32(parsingLittleEndian: &input))
        self.initProt = VMProtection(rawValue: try UInt32(parsingLittleEndian: &input))
    }
}

extension MappingAndSlideInfo: CustomStringConvertible {
    public var description: String {
        let addrHex = String(format: "0x%016llx", address)
        let sizeHex = String(format: "0x%llx", size)
        return "MappingAndSlideInfo(addr: \(addrHex), size: \(sizeHex), flags: \(flags), prot: \(initProt))"
    }
}

/// TPRO (Temporal Property Oriented) mapping information.
public struct TPROMappingInfo: Sendable, Hashable {
    /// Unslid virtual address of this region.
    public let unslidAddress: UInt64

    /// Size of this region.
    public let size: UInt64

    public init(unslidAddress: UInt64, size: UInt64) {
        self.unslidAddress = unslidAddress
        self.size = size
    }
}

extension TPROMappingInfo {
    /// Size of this structure in bytes.
    public static let size = 16

    /// Parse a TPROMappingInfo from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.unslidAddress = try UInt64(parsingLittleEndian: &input)
        self.size = try UInt64(parsingLittleEndian: &input)
    }
}
